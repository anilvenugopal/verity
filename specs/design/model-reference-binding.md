# Model Reference Binding — Design Input

**Status:** Design input for spec/ADR update  
**Scope:** Harness execution engine (Feature #008) + entity registry (Feature #005)  
**Author:** Derived from v1 `ExecutionEngine` review + cross-provider fallback analysis

---

## Background

The schema already implements model decoupling via design decision D10:

- `core.model_reference` — a stable logical alias (e.g. `reasoning-primary`) that executable versions point at instead of a concrete model string
- `core.model_reference_binding` — SCD-2 effective-dated table that maps an alias to an actual model; swapping the underlying model = close old binding + open new one, no package re-promotion required
- `core.inference_config` — holds inference parameters (temperature, max_tokens, etc.); deliberately holds NO model id
- `core.inference_config_model` — ordered list of `model_reference_id` entries with `priority` (1 = primary, 2+ = fallbacks); the harness is expected to try them in order

**What is missing** is:
1. The **engine behavior** that actually walks the `inference_config_model` chain — i.e. `gateway_llm_call` trying priority-1, failing over to priority-2, etc.
2. The **audit record** of whether a fallback fired on a given invocation — `audit.model_invocation_log` has `model_id` (which model was called) but no `was_fallback` flag and no pointer to which `model_reference` position was used.

This document specifies those two additions.

---

## v1 Engine Review: Re-authoring Feasibility

All harness engine features are re-authorable from v1. The seams in `ExecutionEngine` (3009 lines, `verity_legacy/verity/src/verity/runtime/engine.py`) are clean.

| Feature | v1 Location | v2 Status |
|---|---|---|
| Agent loop (10-turn ceiling) | `run_agent()` lines 657–1248 | Direct port; max_turns becomes config |
| Task execution (single-turn) | `run_task()` lines 1254–1589 | Direct port |
| MCP client | `mcp_client.py` — `MCPClient` class | Port; add `sse`/`http` transport (v1 stubs only) |
| Tool dispatch | `_gateway_tool_call()` → `_execute_real_tool()` | Three-branch: python, mcp, builtin |
| Tool binder | `ToolAuthorization` model + DB lookup | Map to `executable_tool_assignment` + `executable_mcp_assignment` |
| Decision writer | `DecisionsWriter` (84 lines) | Port; target `audit.decision_log` |
| Run writer | `RunsWriter` (200+ lines) | Port; target `core.execution_run_status` + `harness_dispatch` |
| Output suppression | `_write_targets()` with `effective_mode` | Maps to v2 shadow/challenger run modes |
| Input redaction | `_redact_input_for_log()` (8 KB threshold) | Port; threshold becomes config |
| Logging | `_log_decision()` (31 cols) + `_log_model_invocation()` | Wire to v2 audit schema |
| Retry + fallback | `_gateway_llm_call()` — 3 retries, 2^n backoff | Re-author with model_reference chain walk |

**One net-new item:** v1 MCP supports `stdio` only. ADR-0016 §4 requires `sse` and `http` for cluster-deployed MCP servers. This is new work, not a port.

---

## Model Reference Chain Resolution

### Concept

At claim time, the coordinator resolves the `inference_config_model` rows for the assigned executable version, ordered by `priority`. The worker holds this ordered list for the run. `gateway_llm_call` walks the list: try priority-1, on transient failure retry with backoff, on exhaustion try priority-2, and so on. If all candidates fail, raise.

This is entirely encapsulated in `gateway_llm_call` — callers pass a resolved `ModelChain` and get back `(response, model_used, was_fallback)`. No caller needs to know the chain logic.

### Schema additions

`audit.model_invocation_log` needs two new columns to make fallback auditable:

```sql
-- Add to audit.model_invocation_log (migration 0007)
alter table audit.model_invocation_log
    add column model_reference_id  uuid,       -- soft ref: which reference position fired
    add column was_fallback        boolean not null default false;

comment on column audit.model_invocation_log.model_reference_id is
    'The model_reference that resolved to the called model. Soft ref — no FK (log is append-only). '
    'Null for legacy rows. @ref core.model_reference soft';

comment on column audit.model_invocation_log.was_fallback is
    'True when this call used a fallback (priority > 1) rather than the primary reference.';
```

No new tables. No changes to `core.model_reference`, `core.model_reference_binding`, `core.inference_config`, or `core.inference_config_model` — the schema already covers the structure.

### Harness Engine: gateway\_llm\_call

Replaces `_gateway_llm_call` in v1. The only place where fallback logic lives.

```python
# harness/src/verity/harness/engine/llm_gateway.py

from dataclasses import dataclass
from typing import Optional
import asyncio
import anthropic

TRANSIENT_CODES: frozenset[int] = frozenset({429, 500, 502, 503, 529})

@dataclass(frozen=True)
class ModelCandidate:
    model_reference_id: str   # UUID of core.model_reference row
    model_id: str             # UUID of core.model row (resolved via binding as-of run time)
    model_api_name: str       # Actual API string, e.g. 'claude-opus-4-8'
    priority: int             # 1 = primary, 2+ = fallback


@dataclass(frozen=True)
class InvocationResult:
    response: anthropic.types.Message
    candidate: ModelCandidate
    was_fallback: bool


async def gateway_llm_call(
    client: anthropic.AsyncAnthropic,
    api_params: dict,
    chain: list[ModelCandidate],    # ordered by priority ascending; must not be empty
    *,
    max_retries: int = 3,
) -> InvocationResult:
    """
    Invoke Claude, walking the model reference chain on exhausted retries.

    Returns InvocationResult with the response plus which candidate was used and
    whether it was a fallback. Callers must log candidate.model_reference_id and
    was_fallback so the invocation record reflects which chain position fired.
    """
    last_exc: Exception | None = None

    for candidate in chain:
        params = {**api_params, "model": candidate.model_api_name}
        for attempt in range(max_retries + 1):
            try:
                response = await client.messages.create(**params)
                return InvocationResult(
                    response=response,
                    candidate=candidate,
                    was_fallback=(candidate.priority > 1),
                )
            except anthropic.APIStatusError as exc:
                if exc.status_code in TRANSIENT_CODES and attempt < max_retries:
                    await asyncio.sleep(2.0 * (2 ** attempt))
                    last_exc = exc
                    continue
                last_exc = exc
                break  # non-retryable or retries exhausted — try next candidate
            except anthropic.APIConnectionError as exc:
                if attempt < max_retries:
                    await asyncio.sleep(2.0 * (2 ** attempt))
                    last_exc = exc
                    continue
                last_exc = exc
                break

    raise last_exc
```

### Invocation log write (updated)

```python
result = await gateway_llm_call(client, api_params, chain)

await decisions.log_invocation(
    decision_log_id=decision_log_id,
    model_id=result.candidate.model_id,                   # which core.model row
    model_reference_id=result.candidate.model_reference_id,  # which chain position
    was_fallback=result.was_fallback,
    invocation_status="complete",
    input_tokens=total_input_tokens,
    output_tokens=total_output_tokens,
    duration_ms=duration_ms,
)
```

---

## What Needs Updating

### ADRs

| ADR | Change needed |
|---|---|
| ADR-0016 (tool invocation + image composition) | Add model reference chain resolver to §5 Framework Layer. Note MCP `sse`/`http` transport as net-new (not in v1). |
| New ADR-0019 | **Model Reference Chain Resolution** — captures the engine behavior (walk priority chain), governance rationale (fallback audit), and the decision to encapsulate entirely in `gateway_llm_call`. |

### Schema

| File | Change needed |
|---|---|
| `specs/schema/verity_schema.sql` | No structural changes — `core.model_reference`, `core.model_reference_binding`, `core.inference_config`, `core.inference_config_model` already exist. Only audit additions below. |
| `specs/schema/audit/model_invocation_log.sql` | Add `model_reference_id uuid` (soft ref) and `was_fallback boolean not null default false`. |
| New migration `hub/db/migrations/0007_model_reference_fallback.sql` | DDL for the two new columns on `audit.model_invocation_log`. |

### Seed files

| File | Change needed |
|---|---|
| `specs/schema/seed/core_seed.sql` | Add seed rows for `core.model_reference` (standard reference codes) and `core.model_reference_binding` (point each reference at a current model). Use SCD-2 pattern: `valid_from = now()`, `valid_to = '2099-12-31'`. |

### Feature Roadmap

| File | Change needed |
|---|---|
| `specs/features/feature-roadmap.md` | Feature #008 (Harness Runtime) — add model reference chain resolution as a deliverable: `gateway_llm_call` walks `inference_config_model` by priority; `was_fallback` + `model_reference_id` logged on `model_invocation_log`. Note MCP `sse`/`http` as net-new scope. |

### Entity Registry (Feature 005)

| File | Change needed |
|---|---|
| `specs/005-entity-registry/plan.md` | `core.model_reference` is a governed entity — CRUD + list, same pattern as MCP server. Operators bind a reference to an actual model via `model_reference_binding` (close old + open new). Add to the phase covering inference config management. |
| `specs/005-entity-registry/data-model.md` | Add `model_reference` entity with its fields. Add `model_reference_binding` (SCD-2) with its fields. Note relationship to `inference_config_model` (the per-executable priority chain). |

---

## Standard Reference Codes (seed)

| Reference code | Suggested initial binding | Use case |
|---|---|---|
| `reasoning-primary` | `claude-opus-4-8` | Default for agentic / assessment tasks |
| `reasoning-fallback` | `claude-sonnet-4-6` | Fallback for reasoning tasks |
| `extraction-primary` | `claude-sonnet-4-6` | Lighter tasks, higher throughput |
| `extraction-fallback` | `claude-haiku-4-5` | Fallback for extraction tasks |
| `classification-primary` | `claude-haiku-4-5` | Classification, low-latency |

A standard agentic executable would have an `inference_config_model` with two rows: `reasoning-primary` at priority 1, `reasoning-fallback` at priority 2.

---

## Governance Note

When `was_fallback = true` on an invocation log row, the governed decision was produced by a non-primary model. The `model_reference_id` column identifies which fallback position fired. Compliance reviewers can filter on `was_fallback = true` to find decisions warranting additional scrutiny.

A future obligation rule could require human review of decisions where fallback fired — these columns are the prerequisite.

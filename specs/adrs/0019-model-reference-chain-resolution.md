# ADR-0019 — Model reference chain resolution

- **Status:** Accepted
- **Date:** 2026-06-11
- **Deciders:** Product Owner (Anil)
- **Related:** [[0016-tool-invocation-harness-image-composition]],
  [[0010-harness-runtime-federated-coordinator]],
  [[0006-packages-and-governed-deployment]]

---

## Context

Design decision D10 (schema hardening) introduced three tables that decouple the
executing model from the entity version that declares it:

- `core.model_reference` — a stable logical alias (e.g. `reasoning-primary`) that
  executable versions reference instead of a concrete model string.
- `core.model_reference_binding` — SCD-2 effective-dated table mapping an alias to an
  actual `core.model` row. Swapping the underlying model = close old binding + open new
  one; no package re-promotion required.
- `core.inference_config_model` — an ordered list of `model_reference_id` entries with
  a `priority` integer (1 = primary, 2+ = fallbacks) attached to an `inference_config`.

These tables exist in the `0001_baseline` schema. What the schema does **not** specify is
the **engine behaviour** that walks `inference_config_model` at claim time and retries
across chain positions on transient failure — that is the gap this ADR closes.

A second gap: `audit.model_invocation_log` has a `model_id` column (which concrete model
was called) but no record of which chain position fired or whether a fallback was used.
Compliance reviewers cannot identify governed decisions produced by a non-primary model
without this information.

---

## Decision

### 1. Chain walk is encapsulated entirely in `gateway_llm_call`

The coordinator resolves the `inference_config_model` rows (ordered by `priority`) at
claim time via `get_inference_config_chain`. The resulting ordered list (`ModelChain`) is
held for the duration of the run.

`gateway_llm_call` (in `harness/src/verity/harness/engine/llm_gateway.py`) owns the
chain walk exclusively:

1. Try `priority-1` candidate. On transient error (HTTP 429/500/502/503/529 or
   `APIConnectionError`), retry with exponential backoff (`2.0 × 2ⁿ` seconds,
   `max_retries=3`).
2. On exhausted retries, **try the next candidate** (`priority-2`, etc.) — do not raise.
3. If all candidates fail, raise the last exception.
4. On success, return `InvocationResult(response, candidate, was_fallback)` where
   `was_fallback = (candidate.priority > 1)`.

**Callers are unaware of the chain logic.** They pass a resolved `ModelChain` and receive
back a response plus metadata about which candidate fired. The caller's only responsibility
is to log `candidate.model_reference_id` and `was_fallback` on the invocation record.

### 2. Fallback is made auditable via two new columns on model_invocation_log

Migration 0007 adds to `audit.model_invocation_log`:

- `model_reference_id uuid` — soft reference to `core.model_reference`; records which
  chain position resolved to the called model. Null for legacy rows.
- `was_fallback boolean not null default false` — true when `priority > 1` fired.

No new tables. No changes to `core.model_reference`, `core.model_reference_binding`,
`core.inference_config`, or `core.inference_config_model`.

### 3. Governance rationale: fallback decisions require heightened scrutiny

When `was_fallback = true`, the governed decision was produced by a non-primary model
(the primary was unavailable or transiently failing at the time of the run). The
`model_reference_id` column identifies which fallback position fired. Compliance reviewers
can filter on `was_fallback = true` to find decisions that warrant additional scrutiny.

A future obligation rule could require human review of any decision where fallback fired.
The two new columns are the prerequisite for that rule.

### 4. Chain resolution query is a cross-feature contract

`get_inference_config_chain(inference_config_id)` — defined in
`hub/db/queries/registry_model_catalog.sql` (Feature 005) — returns the full ordered
chain: `priority`, `model_reference_id`, `reference_code`, and the resolved `model_code`
(joined via the current open `model_reference_binding` row). Feature 008's
`gateway_llm_call` depends on this query at claim time. Changing its return shape is a
cross-feature breaking change.

---

## Consequences

**Positive**
- Callers of `gateway_llm_call` are completely isolated from chain logic — no caller
  change is needed when the chain depth changes (e.g. adding a third fallback).
- `was_fallback = true` on any invocation log row is a queryable governance signal:
  compliance reports can highlight decisions produced outside the primary path.
- Swapping the underlying model for a reference (close old binding + open new) takes
  effect for all executables using that reference at the next run — no re-promotion.
- The chain walk is deterministic: the coordinator resolves the chain once at claim time;
  mid-run changes to model_reference_binding do not affect a running job.

**Negative / costs**
- `gateway_llm_call` must be tested for all paths: primary success, primary-exhausted →
  fallback success, all-exhausted → raise, non-retryable error on primary.
- The claim-time chain resolution adds one DB read (`get_inference_config_chain`) per
  claim. This is acceptable — claims are infrequent relative to tool calls.
- Compliance tooling must be taught to interpret `was_fallback = true` rows; a naive
  cost report that joins only on `model_id` is still correct, but a review dashboard
  that ignores `was_fallback` will miss the signal.

---

## Alternatives Considered

**Environment-variable model override (e.g. `VERITY_MODEL=claude-opus-4-8`).**
Would allow operators to pin a model without touching the registry. *Rejected*: env-var
overrides bypass the governance record entirely — the model actually used would not match
the `model_reference` the package was promoted against. Non-auditable and non-reproducible.

**Per-deployment config (model specified in the Helm values or deployment manifest).**
Would make the model a deployment-time concern rather than a registry concern. *Rejected*:
the entity registry is the governed source of truth for what a package runs with; pushing
model selection to deployment config splits that truth and makes replay impossible.

**Provider-agnostic SDK (LiteLLM or equivalent).**
Would abstract over multiple LLM providers and handle retries/fallback internally.
*Rejected*: introduces a non-trivial third-party dependency in the harness critical path;
LiteLLM's fallback semantics are not auditable at the level Verity requires (we need per-
call `model_reference_id` and `was_fallback` written to our own audit schema, not a
generic retry counter). The Anthropic SDK is already the declared harness dependency
(ADR-0016 §5); a second SDK abstraction layer adds surface area without governance gain.

**Priority chain per run-mode (different chain for shadow vs live).**
Would allow operators to use cheaper fallbacks in shadow mode. *Rejected* for now:
the chain is a property of the inference config, which is a property of the entity
version — not the run-mode. Introducing run-mode awareness into the chain would require
schema changes and a new axis of governance. Deferred; the current design allows it to
be added additively.

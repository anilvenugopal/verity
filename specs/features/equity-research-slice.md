# Feature Spec — Equity Research vertical slice

- **Status:** Draft
- **Date:** 2026-05-29
- **Related:** [[0001-rebuild-vs-refactor]], [[0002-execution-model]],
  [[0003-harness-governance-api]], [[binding-grammar]]
- **Purpose:** The first end-to-end vertical slice that proves the v2 model. It is a
  *reference solution*, not the product. Business scope is deliberately tiny; the point
  is to exercise the platform's governed lifecycle on a real, legible workflow.

---

## User story

> As an analyst, I enter a stock ticker. The application finds any filings for that
> ticker in the vault and extracts the key numbers; pulls live market data; forms a
> rated investment opinion that I can review and adjust; and then writes a research
> report. If there is no filing on file, it still proceeds using market data alone.

## Domain

Financial services / equity research. The business-context key is the **ticker**
(e.g. `AAPL`), which links every step and every governed run in the workflow.

## Entities (governed by Verity)

Binding terminology follows [[binding-grammar]]: **Source Binding** (declarative input)
and **Target Binding** (declarative output) apply identically to tasks and agents.
**Tools and MCP are agent-only** — tasks have neither.

### 1. Task `extract_filing_metrics`  *(conditional)*
- **Source Binding:** the latest filing PDF for the ticker, fetched from the vault via
  the Vault API (vision input). Looked up by ticker.
- **Target Binding:** `{ ticker, period, revenue, eps, guidance }` (structured).
- **Tools / MCP:** none (it is a task).
- **Notes:** Skipped by the application when no filing exists for the ticker.

### 2. Agent `assess_equity`  *(the reasoning core; this entity gets the change round)*
- **Source Binding:** the `extract_filing_metrics` output — **nullable**. When no
  filing exists, this is null and the agent reasons from market data alone.
- **MCP:** AlphaVantage — `GLOBAL_QUOTE` (live price) and `OVERVIEW` (fundamentals),
  keyed by ticker. This is the "use AlphaVantage when there's no extracted data" path.
- **Tool call:** `compute_upside(target_price, current_price)` — a local (non-MCP) tool.
- **Target Binding:** `{ rating, target_price, rationale }` (structured payload).
- **HITL:** a human reviews and may edit `rating` and `target_price` on **this
  structured output**, before any report is generated. The edit is recorded as a
  per-field **HITL override** sent to Verity (see HITL note below).

### 3. Task `write_research_report`
- **Source Binding:** the **possibly HITL-edited** `assess_equity` output.
- **Target Binding:** renders a narrative report and writes `research_note.pdf` to the
  vault via the Vault API. (This is an LLM task — it writes the prose — not a
  deterministic template.)
- **Tools / MCP:** none (it is a task).

## Orchestration (owned by the application, not Verity)

Per [[0002-execution-model]], the application owns the sequence and all branching;
Verity governs each individual invocation. The harness reaches governance **only via
the governance API** ([[0003-harness-governance-api]]); the vault is reached **via the
Vault API** (decoupled; Vault 2.0 integrates here later). Pseudocode:

```
web page: analyst enters ticker
app: search Vault API for filings matching ticker
  if filing found:
      run extract_filing_metrics   -> show extracted metrics on screen
  else:
      skip (metrics = null)
app: run assess_equity            (input: metrics-or-null + AlphaVantage + tool)
  HITL: analyst reviews {rating, target_price}; may edit
        -> if edited, app POSTs a per-field HITL override to the governance API
app: run write_research_report    (input: approved/edited opinion)
app: show research_note.pdf + the run ids
```

Every `run ...` is a governed execution with its own **execution run id**; all three
share the same **ticker** business-context key so the runs can be viewed as one
workflow.

### HITL override mechanism (carried from v1, verified)

The human edit is recorded as a **per-field HITL override** anchored to the
`assess_equity` decision: `(decision_log_id, output_path)` plus business identity
`(application, entity_type, entity_reference, fact_type)`, with `ai_value`, `ai_found`,
`hitl_value`, `created_by`, and `reason`. The app sends it to Verity via
`POST /api/v1/runs/{decision_log_id}/overrides` (the v1 contract). This is the existing
`hitl_override` mechanism — distinct from the decision-level `override_log` — carried
forward, not reinvented.

## Capability coverage (why this slice exists)

| Capability | Where it shows up |
|---|---|
| Vault input (via Vault API) | `extract_filing_metrics` Source Binding |
| Vault output (via Vault API) | `write_research_report` Target Binding |
| Structured payload in/out | all three entities |
| Business-context key linking | ticker threads all three runs |
| Execution run id (single-run view) | each governed run |
| MCP integration | AlphaVantage on `assess_equity` |
| Tool call | `compute_upside` on `assess_equity` |
| HITL edit(s) | on `assess_equity` structured output |
| Full intake → execution, task **and** agent | yes |
| One round of change | on the `assess_equity` agent (see below) |
| Agent Source/Target Binding parity with tasks | demonstrated minimally here; full matrix covered by tests (below) |
| HITL override sent to governance | per-field override on `assess_equity` (carried from v1) |

## The "round of change"

After the slice works end to end, change the `assess_equity` agent — e.g. adjust its
rating methodology via prompt/config — and re-promote it draft → champion. Re-running
the same ticker produces a different opinion from the new champion, demonstrating the
governed change loop and artifact re-deployment.

## Agent binder parity (tests, not demo)

v2 gives **agents** the same **Source Binding / Target Binding** grammar as **tasks**
(see [[binding-grammar]]). Tools and MCP remain agent-only. The demo exercises binding
parity only lightly (the agent has a Source Binding and a Target Binding). The **full
matrix** — every source type and every target type, applied to an agent — is proven by
**built-in project tests**, not demo surface. Verbally: "agents bind exactly like
tasks."

## Acceptance criteria

1. **Happy path (filing present):** enter a ticker with a vault filing → metrics
   extracted and shown → opinion formed using metrics + AlphaVantage → analyst edits the
   target price → report PDF written to vault reflecting the edited value → all three run
   ids share the ticker key and are individually viewable.
2. **No-document path:** enter a ticker with no vault filing → `extract_filing_metrics`
   is skipped → `assess_equity` produces an opinion from AlphaVantage alone, flagged as
   market-data-only / lower-confidence → report still produced.
3. **HITL override is honored:** the value the analyst sets on `assess_equity` output is
   the value `write_research_report` consumes; an un-edited run uses the agent's original
   values.
4. **Tool + MCP recorded:** the AlphaVantage MCP calls and the `compute_upside` tool call
   appear in the agent's decision log for the run.
5. **Round of change:** after re-promoting `assess_equity`, the same ticker yields an
   opinion consistent with the new champion, and the decision logs show different
   champion versions across the two runs.
6. **Agent binder parity tests pass:** tests prove an agent can bind from each supported
   source and write to each supported target.

## Out of scope for this slice (sequenced per ADR-0001)

Out of scope **for this slice**, each a committed later phase:

- **Full 195-operation API surface** — committed goal ([[0001-rebuild-vs-refactor]]),
  built out after the slice proves the model. The slice implements only the handful of
  endpoints it needs (register/compose/promote/run/override).
- **Tier-2 bulk log store** (Iceberg/DuckDB) — the slice runs **Postgres-only**; the
  bulk store is a dedicated phase ([[0004-storage-architecture]]). Insert-only modeling
  applies from day one regardless.
- **Vault 2.0** — the slice consumes a decoupled **Vault API**; the real Vault 2.0
  integration plugs in behind that API later.

Still deferred (not committed to a near-term phase): Kubernetes, Helm, NATS, HA
Postgres, authentication/RBAC, and Prometheus/OTEL/Grafana. The slice runs on **local
Docker** with the simplest dispatch first.

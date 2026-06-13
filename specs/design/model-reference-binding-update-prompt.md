Read specs/design/model-reference-binding.md in full before doing anything else.

That document is a design input. Your job is to propagate it into the live specs and ADRs. Work through each item in the "What Needs Updating" section in order. For each file:

1. Read the current file first.
2. Make the minimum change that integrates the design — do not refactor or restructure unrelated content.
3. If creating a new file (ADR-0019, migration), follow the conventions of the nearest existing file in that directory.

Work to do, in order:

## 1. New ADR: specs/adrs/0019-model-reference-binding.md

Create this ADR. Follow the structure of specs/adrs/0016-tool-invocation-harness-image-composition.md as a template (sections: Status, Context, Decision, Consequences, Alternatives Considered). Cover:
- The schema already has core.model_reference + core.model_reference_binding (SCD-2) + core.inference_config_model (priority chain) from design decision D10 — the ADR is about the ENGINE behavior that walks this chain, not a new schema concept
- gateway_llm_call walks inference_config_model by priority; on exhausted retries against priority-N, it tries priority-N+1
- Governance rationale: when fallback fires (priority > 1), the invocation log records was_fallback=true and model_reference_id so compliance reviewers can identify decisions produced by non-primary models
- The decision to encapsulate the chain walk entirely in gateway_llm_call (callers are unaware)
- Alternatives: env-var override, per-deploy config, provider-agnostic SDK (LiteLLM) — and why each was rejected

## 2. Update ADR-0016: specs/adrs/0016-tool-invocation-harness-image-composition.md

Find the section listing Framework Layer components (§5 or equivalent table). Add one line alongside the Anthropic SDK entry:
"Model reference chain resolver | Walks inference_config_model by priority at run time; see ADR-0019"

Also add a note under the MCP Protocol Client entry: stdio is the v1-ported transport; sse and http are net-new scope required for cluster-deployed MCP servers per the ADR-0016 §4 topology.

## 3. Schema: specs/schema/audit/model_invocation_log.sql

Read this file first. Add two columns after the existing `model_id` column:
- `model_reference_id uuid` — soft ref to core.model_reference (no FK, log is append-only); null for legacy rows
- `was_fallback boolean not null default false` — true when priority > 1 fired

Add COMMENT ON COLUMN for each using the exact wording from specs/design/model-reference-binding.md §Schema additions.

Do NOT touch core.model_reference, core.model_reference_binding, core.inference_config, or core.inference_config_model — they already exist and are correct.

## 4. Update specs/schema/verity_schema.sql

The verity_schema.sql uses \i includes. The audit/model_invocation_log.sql file is already included. No structural changes needed — the file does not need to be modified unless you find that the include is missing.

## 5. New migration: hub/db/migrations/0007_model_reference_fallback.sql

Migrations live at hub/db/migrations/ (NOT specs/schema/migrations/). The last migration is 0005. Migration 0006 is reserved for entity registry (Feature 005). This migration is 0007.

Read hub/db/migrations/0005_change_proposal_asset.sql for format conventions. The migration must add only:
- model_reference_id uuid to audit.model_invocation_log
- was_fallback boolean not null default false to audit.model_invocation_log

## 6. Seed file: specs/schema/seed/core_seed.sql

Read this file first. Add seed rows for:
- core.model_reference — five rows using the reference codes from the "Standard Reference Codes" table in the design doc
- core.model_reference_binding — one row per reference, pointing at the suggested initial binding (actual model API name resolves via core.model; find or insert the relevant model rows if they exist in the seed)

Use the SCD-2 pattern: valid_from = now(), valid_to = '2099-12-31 00:00:00+00'. Look at how other SCD-2 seed rows are written in this file; if none, follow the column order in specs/schema/core/model_reference_binding.sql exactly.

## 7. Feature roadmap: specs/features/feature-roadmap.md

Find the ### 008 · Harness runtime section. In the "What it delivers" bullet list, add:
- Model reference chain resolution: gateway_llm_call walks inference_config_model by priority (1=primary, 2+=fallbacks); was_fallback + model_reference_id logged on model_invocation_log on each invocation

Also add a note that MCP sse/http transport is net-new scope (not ported from v1 which had stdio only).

Do not touch the Key FRs, Depends on, Blocks, or ADRs fields unless the ADR-0019 reference needs to be added to the ADRs field.

## 8. Entity registry plan: specs/005-entity-registry/plan.md

Read this file in full before editing. The plan already covers model_reference CRUD in Phase 6 and the portal priority list in Phase 10 step 5 — do not add those again. The impacts below are surgical additions to existing phases only; do not restructure or rewrite the plan.

**Impact 1 — Phase 1, step 4 (registry_model_catalog.sql)**
Confirm this step explicitly lists a query named `get_inference_config_chain(inference_config_id)` that returns the full ordered chain: priority, model_reference_id, reference_code, and the resolved model_code (joined via model_reference_binding → model, using the current open binding). This is the cross-feature contract that Feature 008's gateway_llm_call depends on at claim time. If it is not listed, add it to step 4.

**Impact 2 — Phase 1, add seed step**
After the existing steps in Phase 1, add: "Seed standard model_reference and model_reference_binding rows in specs/schema/seed/core_seed.sql — five reference codes from specs/design/model-reference-binding.md §Standard Reference Codes, each with one open model_reference_binding row (valid_to = '2099-12-31 00:00:00+00'). This gives Feature 008 working references at first run."

**Impact 3 — Phase 6, step 1**
Confirm `get_inference_config` returns the full chain (not just the inference_config row alone) so `GET /api/registry/inference-configs/:id` exposes the priority list. If not explicit, add it.

**Impact 4 — Phase 9, tests**
Add two test cases to the existing test list:
- `get_inference_config_chain` returns rows in priority order and resolves the correct model_code via the current open binding
- SCD-2 rebinding a model_reference (close old + open new) causes `get_inference_config_chain` to return the updated model_code — no package re-promotion needed

**Impact 5 — Phase 11, step 2 (inference config inline editor)**
The current text says "model reference priority list (add/remove/reorder)". Clarify that this operates on `core.inference_config_model` rows — adding/removing model_reference entries by reference_code, reordering by priority integer. It does NOT operate on `core.model_reference_binding`. The binding swap is a separate action from `ModelDetail.tsx` (`POST /api/registry/model-references/:id/bind`), not from the version detail page.

No other phases need changes. Do not touch Phases 2, 3, 4, 5, 7, 8, or 10.

## 9. Entity registry data model: specs/005-entity-registry/data-model.md

Read this file in full before editing. core.model_reference and core.model_reference_binding are already documented in §10. core.inference_config_model is already documented in §7. Two surgical additions only — do not rewrite any existing section.

**Addition 1 — §7 inference_config_model table**
After the existing core.inference_config_model table, add a note:
"The priority chain in this table is walked by gateway_llm_call in Feature 008 (Harness Runtime): priority 1 is tried first; on exhausted retries against a transient error, priority 2+ is tried in order. The chain is resolved at claim time via get_inference_config_chain — see Feature 008 / ADR-0019."

**Addition 2 — §10 model_reference_binding table**
After the existing core.model_reference_binding table, add a note:
"Swapping the underlying model (close old binding + open new) takes effect for all executables using that reference at the next run — no package re-promotion required (D10). Migration 0007 adds was_fallback and model_reference_id to audit.model_invocation_log so each governed decision records which chain position fired."

Do not modify §11 (Required migration). It covers only migration 0006 and must not reference migration 0007.

---

After all changes: grep for any spec prose that says "model_name on executable_version" or "inference_config embeds a model" — these are stale descriptions that predate D10. Do not fix them in this pass; list the file paths and line numbers so they can be addressed separately.

Do not update CLAUDE.md. Do not touch hub/ source code or harness/ source code — this pass is spec and migration only. The migration file at hub/db/migrations/0007_model_reference_fallback.sql is the only hub/ file to create.

# Implementation Plan: Entity Model & Registry

**Branch**: `005-entity-registry` | **Date**: 2026-06-11 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/005-entity-registry/spec.md`

---

## Summary

Feature 005 delivers the full entity registry API layer for Verity's AI governance platform — the CRUD, composition, champion lifecycle, source/target bindings, model catalog, and YAML portability endpoints that sit on top of the hardened schema already in the 0001 baseline. One new migration (0006) adds `data_classification_code` to `core.tool_version`. Everything else is new SQL query files and extensions to the existing `registry` FastAPI module.

The existing `hub/src/verity/hub/registry/` module (from feature 003) covers executables, lifecycle events, and intake links. Feature 005 extends it with: components (prompts, tools, MCP, connectors, inference configs), composition assignments, bindings, model catalog, and YAML I/O.

---

## Technical Context

**Language/Version**: Python 3.12

**Primary Dependencies**: FastAPI, psycopg v3 (async), aiosql, Pydantic v2, pyyaml

**Storage**: PostgreSQL 18 — all tables already in `0001_baseline`; migration `0006` adds one column.

**Testing**: pytest + psycopg v3; existing test infrastructure in `hub/tests/`

**Target Platform**: Linux/K8s (Helm); local dev via Docker Compose convenience runner

**Project Type**: REST API service — new endpoints on existing `verity-governance` FastAPI app

**Performance Goals**: All registry read operations <500ms at hundreds-of-versions scale (SC-002). Where-used lookup <200ms for ≤50 executable versions per component (SC-005).

**Constraints**: Raw SQL only (no ORM — ADR-0012). Pydantic v2 models. Auth via existing `require_action` dependency. No new roles introduced.

**Scale/Scope**: Single-application registry (hundreds of entities/versions). Horizontal scale via existing governance API replicas.

---

## Constitution Check

### Pre-design gate (against constitution v1.3.0)

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec Precedes Implementation | PASS | spec.md written and committed before any code |
| II. Schema Is the Hardened Foundation | PASS | All tables from hardened `verity_schema.sql` baseline; migration 0006 adds a nullable column to `tool_version` (additive only) |
| III. Legacy Is Reference, Never Source | PASS | No imports from `../verity_legacy/` |
| IV. API-Only Governance Boundary | PASS | All registry access through governance API; harness reads champion via API |
| V. Uniform Bindings, Agent-Only Tools | PASS | Source/target bindings apply uniformly to agents and tasks; tool/MCP assignments are agent-only (DB-enforced composite FK + CHECK) |
| VI. Equity-Research Slice First | PASS | Registry/compose phase in the PCR §6 roadmap — correct sequencing |
| VII. Governed Deployment & Reproducible Execution | PASS | Champion promotion via API; append-only champion_assignment provides full audit trail |
| VIII. Continuous Compliance | PASS | `data_classification_code` on tool versions enables data sensitivity tracking (FR-RG-018) |

**Naming gate**: All API fields use v2 binding grammar (`source_binding`/`target_binding`). No v1 names. ✓

**Schema gate**: `0001_baseline` is the foundation; migration `0006` is additive (nullable column). ✓

No violations — no Complexity Tracking entries required.

---

## Project Structure

### Documentation (this feature)

```text
specs/005-entity-registry/
├── plan.md                          # This file
├── spec.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── registry-api.yaml
└── tasks.md                         # Phase 2 output (/speckit-tasks — not yet created)
```

### Source Code

```text
hub/
├── db/
│   ├── migrations/
│   │   └── 0006_tool_data_classification.sql
│   └── queries/
│       ├── registry.sql                       # EXTEND: version detail, champion resolve+as-of, where-used, atomic promote
│       ├── registry_components.sql            # NEW: prompts, tools, mcp, connectors, inference configs
│       ├── registry_bindings.sql              # NEW: source/target bindings
│       └── registry_model_catalog.sql         # NEW: models, prices, model references, ref bindings
└── src/verity/hub/
    └── registry/
        ├── models.py                          # EXTEND: new Pydantic models for all components
        ├── router.py                          # EXTEND: ~35 new route handlers
        ├── service.py                         # EXTEND: business logic for new entities
        └── yaml_io.py                         # NEW: YAML export / dry-run import / apply import

hub/tests/
└── test_registry_005.py                       # NEW: pytest suite for all new endpoints

hub/portal/src/
├── App.tsx                                    # EXTEND: add /registry/* sub-routes
├── pages/registry/
│   ├── RegistryList.tsx                       # REPLACE: section shell with entity-type navigation + <Outlet />
│   ├── agents/
│   │   ├── AgentList.tsx                      # NEW: agent list with champion badge
│   │   ├── AgentDetail.tsx                    # NEW: versions list, champion badge, intake link
│   │   └── AgentVersionDetail.tsx             # NEW: composition + bindings + inline inference config
│   ├── tasks/
│   │   ├── TaskList.tsx                       # NEW
│   │   ├── TaskDetail.tsx                     # NEW
│   │   └── TaskVersionDetail.tsx              # NEW: composition manifest (no tools/MCP section)
│   ├── prompts/
│   │   ├── PromptList.tsx                     # NEW
│   │   └── PromptDetail.tsx                   # NEW: versions + where-used
│   ├── tools/
│   │   ├── ToolList.tsx                       # NEW
│   │   └── ToolDetail.tsx                     # NEW: versions + where-used + data classification
│   └── models/
│       ├── ModelList.tsx                      # NEW: model catalog with current price
│       └── ModelDetail.tsx                    # NEW: price history + reference bindings
├── shell/
│   └── CommandPalette.tsx                     # EXTEND: add agents/tasks/prompts/tools OBJECT_SOURCES
└── help/
    ├── pages.ts                               # EXTEND: 4 new registry help page entries
    ├── registry-entity-types.tsx             # NEW: reference — agent vs task vs prompt vs tool
    ├── registry-compose.tsx                  # NEW: forms — composing a version
    ├── registry-full-lifecycle.tsx           # NEW: workflows — register → compose → promote → run
    └── registry-navigate.tsx                 # NEW: how-to — navigating connected assets
```

---

## Implementation Phases

### Phase 1 — Foundation: migration + SQL queries

Write the migration and all SQL query files. No service code yet.

1. Write `hub/db/migrations/0006_tool_data_classification.sql` — additive `ALTER TABLE core.tool_version ADD COLUMN IF NOT EXISTS data_classification_code text` + FK constraint
2. Write `hub/db/queries/registry_components.sql` — CRUD for prompts, prompt_versions, tools, tool_versions, mcp_server_versions, data_connectors, data_connector_versions, inference_configs, inference_config_models
3. Write `hub/db/queries/registry_bindings.sql` — CRUD for source_binding, target_binding
4. Write `hub/db/queries/registry_model_catalog.sql` — CRUD for model, model_price (SCD-2 close+insert), model_reference, model_reference_binding (SCD-2 close+insert); include `get_inference_config_chain(inference_config_id)` returning the full ordered chain (priority, model_reference_id, reference_code, resolved model_code joined via the current open model_reference_binding row) — this is the cross-feature contract that Feature 008's `gateway_llm_call` depends on at claim time (ADR-0019)
5. Extend `hub/db/queries/registry.sql`:
   - `get_version_detail` — full version row including governance fields
   - `champion_current` — resolves via `entity_champion_current` view
   - `champion_as_of` — window query on `champion_assignment.created_at` (see research.md Finding 6)
   - `promote_champion` — atomic revocation of old champion + insert new (research.md Finding 2)
   - `where_used_prompt_version`, `where_used_tool_version`, `where_used_mcp_version`
6. Wire new SQL query files to the aiosql loader in `hub/src/verity/hub/db.py`
7. Seed standard `model_reference` and `model_reference_binding` rows in `specs/schema/seed/core_seed.sql` — five reference codes from `specs/design/model-reference-binding.md` §Standard Reference Codes, each with one open `model_reference_binding` row (`valid_to = '2099-12-31 00:00:00+00'`). This gives Feature 008 working references at first run

### Phase 2 — Component CRUD (US1)

Register and version prompts, tools, MCP servers, connectors, and inference configs.

1. Extend `registry/models.py` with Pydantic models matching `contracts/registry-api.yaml`
2. Extend `registry/service.py` with: `create_prompt`, `list_prompts`, `create_prompt_version`, `list_prompt_versions`, `create_tool`, `create_tool_version`, `create_mcp_server_version`, `list_mcp_servers`, `create_connector`, `create_connector_version`, `create_inference_config`, `get_inference_config`
3. Extend `registry/router.py` with routes for `/registry/prompts*`, `/registry/tools*`, `/registry/mcp-servers*`, `/registry/connectors*`, `/registry/inference-configs*`
4. Extend existing `create_version` to accept all governance classification fields from `CreateExecutableVersion`
5. Extend existing `list_executables` / `get_version` to include `champion_semver`, governance fields

### Phase 3 — Composition assignments (US2)

Assign/remove prompts, tools, and MCP servers to/from executable versions.

1. Add service functions: `add_prompt_assignment`, `list_prompt_assignments`, `remove_prompt_assignment`, `add_tool_assignment`, `list_tool_assignments`, `remove_tool_assignment`, `add_mcp_assignment`, `list_mcp_assignments`, `remove_mcp_assignment`
2. Agent-only enforcement: the DB CHECK raises `psycopg.errors.CheckViolation`; catch and re-raise as HTTP 409 with message "tools are agent-only"
3. Add route handlers: all `/registry/versions/{id}/prompt-assignments*`, `tool-assignments*`, `mcp-assignments*`

### Phase 4 — Champion promotion (US3)

Fix champion atomicity; add champion resolution with as-of.

1. Replace bare `insert_champion` call in `advance_lifecycle` with the two-step atomic pattern from research.md Finding 2
2. Add `promote` service function with precondition: at least one prompt assignment must exist
3. Add `GET /registry/executables/{id}/champion` route with optional `?as_of=` query param
4. Add `POST /registry/versions/{id}/promote` route (keeps existing `lifecycle` route for non-champion stages)

### Phase 5 — Source and target bindings (US4)

1. Add service functions: `create_source_binding`, `list_source_bindings`, `delete_source_binding`, `create_target_binding`, `list_target_bindings`, `delete_target_binding`
2. Service-layer validation: reject `storage_object` source/target without `data_connector_version_id`; reject `storage_object` target without `write_mode_code` (mirrors DB CHECK, catches earlier)
3. Add route handlers: `/registry/versions/{id}/source-bindings*`, `/registry/versions/{id}/target-bindings*`

### Phase 6 — Model catalog (US6)

1. Add service functions: `create_model`, `list_models`, `add_model_price`, `list_model_prices`, `create_model_reference`, `list_model_references`, `bind_model_reference`, `list_model_reference_bindings`; update `get_inference_config` (introduced in Phase 2) to call `get_inference_config_chain` so that `GET /api/registry/inference-configs/:id` returns the full ordered priority list (model_reference entries with resolved model_code) — required for Feature 008 claim-time resolution and for the portal inference config editor
2. SCD-2 close pattern for prices: `UPDATE ... SET valid_to = now() WHERE valid_to = '2099-12-31...'` + INSERT in same tx (SQL in `registry_model_catalog.sql`)
3. Same pattern for reference bindings
4. Add route handlers: `/registry/models*`, `/registry/model-references*`

### Phase 7 — Where-used (FR-RG-019)

1. Add service functions: `where_used_prompt_version`, `where_used_tool_version`, `where_used_mcp_version`
2. Add routes: `/registry/prompt-versions/{id}/used-by`, `/registry/tool-versions/{id}/used-by`, `/registry/mcp-versions/{id}/used-by`

### Phase 8 — YAML I/O (US5)

1. Create `hub/src/verity/hub/registry/yaml_io.py`:
   - `export_version(conn, version_id) -> dict`
   - `bundle_to_yaml(data) -> str`
   - `parse_bundle(yaml_str) -> dict`
   - `import_bundle(conn, bundle, dry_run) -> ImportReport`
2. Idempotency keys: executables by `(kind_code, name)`; prompt versions by `content_hash`; others by `(name, semver)`
3. Add routes: `GET /registry/versions/{id}/export`, `POST /registry/import/dry-run`, `POST /registry/import`
4. Add `pyyaml` to `hub/pyproject.toml` if not already present

### Phase 9 — Tests

1. Create `hub/tests/test_registry_005.py` with scenarios listed in quickstart.md:
   - Registration + duplicate rejection
   - Prompt version content hash
   - Agent composition + agent-only enforcement
   - Champion atomic swap (no dual-champion window)
   - Champion as-of resolution
   - Binding storage_object validation
   - Where-used lookups
   - Model price + reference binding SCD-2 atomicity
   - YAML round-trip (all no-ops on re-import)
   - `get_inference_config_chain` returns rows in priority order and resolves the correct model_code via the current open model_reference_binding
   - SCD-2 rebinding a model_reference (close old + open new) causes `get_inference_config_chain` to return the updated model_code — no package re-promotion needed
2. Run full pytest suite to confirm no regressions (SC-007)

### Phase 10 — Portal: Registry browse pages (US7)

Implement read-only registry portal pages — multi-entity list pages, detail pages, version detail with composition manifest, bindings, inference config display, and connected-asset navigation.

1. Update `hub/portal/src/App.tsx`: add nested `<Route>` entries under `/registry/*` covering `/agents`, `/agents/:id`, `/agents/:id/:vid`, `/tasks`, `/tasks/:id`, `/tasks/:id/:vid`, `/prompts`, `/prompts/:id`, `/tools`, `/tools/:id`, `/models`, `/model-references/:id`; replace direct `<RegistryList />` mount with a nested `<Routes>` + `<Outlet />`
2. Replace `hub/portal/src/pages/registry/RegistryList.tsx` with a registry section shell: entity-type left-navigation (Agents | Tasks | Prompts | Tools | Models) and `<Outlet />` centre; default redirect to `/registry/agents`
3. Create `agents/AgentList.tsx` — `GET /api/registry/executables?kind=agent`; columns: name, champion semver badge, lifecycle stage; click → `/registry/agents/:id`
4. Create `agents/AgentDetail.tsx` — `GET /api/registry/executables/:id`; versions table (semver, stage, champion badge); intake chip if linked; click version row → `/registry/agents/:id/:vid`
5. Create `agents/AgentVersionDetail.tsx` — three read-only sections: (a) Composition manifest with prompt assignments linked to `/registry/prompts/:id` and tool assignments linked to `/registry/tools/:id`; (b) Source/target bindings table; (c) Inference config — max_tokens, temperature, model reference priority list
6. Mirror the agent pages under `tasks/` — same structure; `TaskVersionDetail.tsx` omits the tool and MCP sections
7. Create `prompts/PromptList.tsx` and `PromptDetail.tsx` — `PromptDetail` shows version table (semver, content hash truncated) and "Used by" section from `GET /api/registry/prompt-versions/:vid/used-by` linked to agent/task version pages
8. Create `tools/ToolList.tsx` and `ToolDetail.tsx` — `ToolDetail` shows version table with data classification badge and "Used by" section
9. Create `models/ModelList.tsx` and `ModelDetail.tsx` — `ModelList` shows model code, provider, current price; `ModelDetail` shows price history table and "Bound references" section (which model references currently point to this model)

### Phase 11 — Portal: Write actions + Ctrl+J + Help (US8, FR-UI-010, FR-UI-011)

Add write actions to version detail pages, extend the command palette with registry entries, and add help corpus pages.

1. Add compose write actions to `AgentVersionDetail.tsx`: inline "Assign Prompt" form (prompt search, role selector, ordinal field); remove-assignment button per manifest row; "Assign Tool" inline form; each write calls `POST`/`DELETE` endpoint and refreshes local state with toast notification
2. Add inference config inline editor to `AgentVersionDetail.tsx` and `TaskVersionDetail.tsx`: editable `max_tokens` and `temperature` fields; model reference priority list — this operates on `core.inference_config_model` rows (adding/removing model_reference entries by reference_code, reordering by priority integer); submits to `POST /api/registry/inference-configs`; does NOT operate on `core.model_reference_binding` — the binding swap (which underlying model a reference resolves to) is a separate action on `ModelDetail.tsx` via `POST /api/registry/model-references/:id/bind`, not from the version detail page
3. Add champion promotion to `AgentVersionDetail.tsx` and `TaskVersionDetail.tsx`: "Promote to champion" button (shown when `lifecycle_stage !== 'champion'`); confirm dialog; calls `POST /api/registry/versions/:vid/promote`; success/failure toast; champion badge reflects new state
4. Extend `hub/portal/src/shell/CommandPalette.tsx` `OBJECT_SOURCES`: add agents entry (`hint` = champion semver), tasks entry, prompts entry (`hint` = version count), tools entry (`hint` = transport_code); use `i-app-registry` sprite if entity-specific icons are not yet present in `sprite.svg`
5. Create `hub/portal/src/help/registry-entity-types.tsx`, `registry-compose.tsx`, `registry-full-lifecycle.tsx`, `registry-navigate.tsx`; add four entries to `hub/portal/src/help/pages.ts` HELP_PAGES array (groups: `reference`, `forms`, `workflows`, `how-to`)

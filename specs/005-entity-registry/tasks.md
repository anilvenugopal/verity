# Tasks: Entity Model & Registry

**Input**: Design documents from `specs/005-entity-registry/`

**Feature**: 005-entity-registry — full entity registry API on top of the hardened schema
**Branch**: `005-entity-registry`

**No tests requested in spec** — test tasks in Phase 9 cover integration verification only.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel with other [P] tasks in the same phase (different files, no dependencies)
- **[Story]**: User story this task serves
- All file paths are relative to the repo root

---

## Phase 1: Setup

**Purpose**: Migration in place; new SQL query files registered in aiosql loader.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T00X Write `hub/db/migrations/0006_tool_data_classification.sql` — `ALTER TABLE core.tool_version ADD COLUMN IF NOT EXISTS data_classification_code text` + DO-block FK constraint to `reference.data_classification`; idempotent (`IF NOT EXISTS` / `DO IF NOT EXISTS`)
- [X] T00X [P] Write `hub/db/queries/registry_components.sql` — aiosql queries: `create_prompt^`, `get_prompt^`, `list_prompts`, `create_prompt_version^`, `get_prompt_version^`, `list_prompt_versions`, `create_tool^`, `get_tool^`, `list_tools`, `create_tool_version^`, `list_tool_versions`, `create_mcp_server_version^`, `list_mcp_servers`, `create_connector^`, `list_connectors`, `create_connector_version^`, `list_connector_versions`, `create_inference_config^`, `get_inference_config^`, `add_inference_config_model!`, `list_inference_config_models`
- [X] T00X [P] Write `hub/db/queries/registry_bindings.sql` — aiosql queries: `create_source_binding^`, `list_source_bindings`, `delete_source_binding!`, `create_target_binding^`, `list_target_bindings`, `delete_target_binding!`
- [X] T00X [P] Write `hub/db/queries/registry_model_catalog.sql` — aiosql queries: `create_model^`, `get_model_by_code^`, `list_models`, `add_model_price^`, `close_current_model_price!`, `list_model_prices`, `create_model_reference^`, `list_model_references`, `bind_model_reference^`, `close_current_reference_binding!`, `list_model_reference_bindings`; also write `get_inference_config_chain` — returns ordered rows `(priority, model_reference_id, reference_code, resolved model_code)` joined via the current open `model_reference_binding` row; this is the cross-feature contract that Feature 008's `gateway_llm_call` depends on at claim time (ADR-0019 §4 — changing the return shape is a breaking change)
- [X] T00X [P] Extend `hub/db/queries/registry.sql` — add: `get_version_detail^` (full version row + governance fields), `champion_current^` (via `entity_champion_current` view), `champion_as_of^` (window query on `champion_assignment.created_at`), `revoke_champion!` (INSERT revocation row for current champion), `insert_champion_promotion!` (INSERT new champion with lifecycle_event_id), `where_used_prompt_version`, `where_used_tool_version`, `where_used_mcp_version`
- [X] T00X Wire new SQL query files into `hub/src/verity/hub/db.py` aiosql loader — add `registry_components`, `registry_bindings`, `registry_model_catalog` alongside existing `registry` driver load

**Checkpoint**: Migration written; all SQL query files present; aiosql loader updated. Run `./dev migrate` to verify 0006 applies cleanly.

---

## Phase 2: User Story 1 — Register and manage registry entities (P1)

**Goal**: List, create, and version all registry entities — executables, prompts, tools, MCP servers, data connectors, inference configs. Where-used reverse lookup.

**Independent Test**: Register an agent, a prompt, create versions of each, list them back via the API, and call `/registry/prompt-versions/{id}/used-by` — fully testable without composition or promotion.

- [X] T00X [US1] Extend `hub/src/verity/hub/registry/models.py` — add: `CreateExecutableVersion` (with semver, governance_tier_code, capability_type_code, trust_level_code, data_classification_code, inference_config_id, input_schema, output_schema, version_change_type_code, cloned_from_version_id), `ExecutableVersionDetail` (extends summary with all classification fields), `ExecutableDetail` (with versions list), update `ExecutableSummary` to include `champion_semver`; add `PromptSummary`, `CreatePrompt`, `PromptVersionSummary`, `CreatePromptVersion`; add `ToolSummary`, `CreateTool`, `ToolVersionSummary`, `CreateToolVersion`; add `McpServerVersionSummary`, `CreateMcpServerVersion`; add `ConnectorSummary`, `CreateConnector`, `ConnectorVersionSummary`, `CreateConnectorVersion`; add `InferenceConfigDetail`, `CreateInferenceConfig`; add `UsedByEntry`
- [X] T00X [US1] Extend `hub/src/verity/hub/registry/service.py` — (a) update `create_version` to accept all `CreateExecutableVersion` fields and pass to SQL; (b) update `list_executables` / `get_version` queries to include `champion_semver` via subquery on `entity_champion_current`; (c) add prompt functions: `create_prompt`, `list_prompts`, `create_prompt_version` (computes SHA-256 content hash from rendered blocks before INSERT), `list_prompt_versions`; (d) add tool functions: `create_tool`, `list_tools`, `create_tool_version`, `list_tool_versions`; (e) add MCP functions: `create_mcp_server_version`, `list_mcp_servers`; (f) add connector functions: `create_connector`, `create_connector_version`; (g) add inference config functions: `create_inference_config` (creates config row + inserts inference_config_model rows in one tx), `get_inference_config`; (h) add where-used: `where_used_prompt_version`, `where_used_tool_version`, `where_used_mcp_version`
- [X] T00X [US1] Extend `hub/src/verity/hub/registry/router.py` — add route handlers for: `GET/POST /registry/prompts`, `GET/POST /registry/prompts/{id}/versions`, `GET /registry/prompt-versions/{id}/used-by`; `GET/POST /registry/tools`, `GET/POST /registry/tools/{id}/versions`, `GET /registry/tool-versions/{id}/used-by`; `GET/POST /registry/mcp-servers`, `GET /registry/mcp-versions/{id}/used-by`; `GET/POST /registry/connectors`, `GET/POST /registry/connectors/{id}/versions`; `POST /registry/inference-configs`, `GET /registry/inference-configs/{id}`; update `GET /registry/executables/{id}` to return `ExecutableDetail`; update `POST /registry/executables/{id}/versions` to accept `CreateExecutableVersion`

**Checkpoint**: All component list/create/version endpoints return correct responses. Duplicate name returns 409. Content hash is present on prompt versions. Where-used returns empty list for unused versions and correct entries once composition is done.

---

## Phase 3: User Story 2 — Compose an agent version with its components (P2)

**Goal**: Assign/remove prompt versions, tool versions, and MCP server versions to/from an executable version. Tools and MCP servers are agent-only.

**Independent Test**: Create an agent version, assign a prompt to `system` role, assign a tool, retrieve the composition manifest — fully testable without champion promotion.

- [X] T010 [US2] Extend `hub/src/verity/hub/registry/models.py` — add `PromptAssignment`, `CreatePromptAssignment`, `ToolAssignment`, `CreateToolAssignment`, `McpAssignment`, `CreateMcpAssignment`
- [X] T011 [US2] Extend `hub/src/verity/hub/registry/service.py` — add: `add_prompt_assignment`, `list_prompt_assignments`, `remove_prompt_assignment`; `add_tool_assignment` (catch `psycopg.errors.CheckViolation` and raise `HTTPException(409, "tools are agent-only")`), `list_tool_assignments`, `remove_tool_assignment`; `add_mcp_assignment` (same agent-only check), `list_mcp_assignments`, `remove_mcp_assignment`
- [X] T012 [US2] Extend `hub/src/verity/hub/registry/router.py` — add route handlers for: `GET/POST /registry/versions/{id}/prompt-assignments`, `DELETE /registry/versions/{id}/prompt-assignments/{prompt_version_id}/{api_role}`; `GET/POST /registry/versions/{id}/tool-assignments`, `DELETE /registry/versions/{id}/tool-assignments/{tool_version_id}`; `GET/POST /registry/versions/{id}/mcp-assignments`, `DELETE /registry/versions/{id}/mcp-assignments/{mcp_version_id}`

**Checkpoint**: Prompt, tool, MCP assignment CRUD works. Task version rejects tool/MCP assignment with 409. Removing an assignment removes it from the list only. Assigning same prompt+role twice is idempotent (or returns 409 on true duplicate PK).

---

## Phase 4: User Story 3 — Promote a version to champion (P3)

**Goal**: Atomic champion promotion with SCD-2 semantics via append-only champion_assignment. Champion resolution by name (current and as-of timestamp).

**Independent Test**: Register an agent, create two versions, promote v1, confirm it's champion, promote v2, confirm v1 is retired and v2 is champion — testable without bindings.

- [X] T013 [US3] Verify that `hub/db/queries/registry.sql` contains `revoke_champion!`, `insert_champion_promotion!`, `champion_current^`, and `champion_as_of^` written in T005 — these are prerequisites for T014's service logic. **No new SQL is written in this task.** If any query is missing, that is a T005 defect to fix before proceeding.
- [X] T014 [US3] Extend `hub/src/verity/hub/registry/service.py` — add `promote(conn, version_id, reason, ctx)` function: (1) verify version exists; (2) check at least one prompt assignment exists (else raise `HTTPException(422, "version has no prompt assignments — cannot promote")`); (3) in one transaction: insert lifecycle_event for `champion` state, call `revoke_champion` (no-op if no current champion), call `insert_champion_promotion`; (4) return updated version; update `advance_lifecycle` so `to_stage == "champion"` delegates to `promote`; add `resolve_champion(conn, executable_id, as_of=None)` using `champion_current` or `champion_as_of`
- [X] T015 [US3] Extend `hub/src/verity/hub/registry/router.py` — add `GET /registry/executables/{id}/champion` (with optional `?as_of=` datetime param, returns 404 "no champion" if unset); add `POST /registry/versions/{id}/promote` (accepts optional `{"reason": "..."}` body, returns updated version); update existing `POST /versions/{id}/lifecycle` to block `to_stage = "champion"` and redirect caller to the new promote endpoint

**Checkpoint**: Promote v1 → champion. Promote v2 → v1 retired, v2 champion (no dual-champion). `GET champion` returns v2. `GET champion?as_of=<before v2 promotion>` returns v1.

---

## Phase 5: User Story 4 — Define Source and Target data bindings (P4)

**Goal**: CRUD for source_binding and target_binding on executable versions. Structured fields (source_kind + locator), not a DSL string. Storage-object bindings validated at service layer.

**Independent Test**: Create source and target bindings on a version, list them back, delete one — testable without champion promotion.

- [X] T016 [US4] Extend `hub/src/verity/hub/registry/models.py` — add `SourceBinding`, `CreateSourceBinding`, `TargetBinding`, `CreateTargetBinding` (fields per `contracts/registry-api.yaml` schemas)
- [X] T017 [US4] Extend `hub/src/verity/hub/registry/service.py` — add `create_source_binding(conn, version_id, body, ctx)`: reject if `source_kind_code == "storage_object"` and `data_connector_version_id` is None (422); call `queries.create_source_binding`; add `list_source_bindings`, `delete_source_binding`; add `create_target_binding(conn, version_id, body, ctx)`: reject if `target_kind_code == "storage_object"` and (`data_connector_version_id` is None or `write_mode_code` is None) (422); add `list_target_bindings`, `delete_target_binding`
- [X] T018 [US4] Extend `hub/src/verity/hub/registry/router.py` — add route handlers for: `GET/POST /registry/versions/{id}/source-bindings`, `DELETE /registry/versions/{id}/source-bindings/{binding_id}`; `GET/POST /registry/versions/{id}/target-bindings`, `DELETE /registry/versions/{id}/target-bindings/{binding_id}`

**Checkpoint**: Source/target bindings CRUD works. `storage_object` without connector_version_id returns 422. Deleting a binding removes it. Binding names are unique per version (409 on duplicate).

---

## Phase 6: User Story 6 — Manage the model catalog and pricing (P6)

**Goal**: Register provider models; SCD-2 price windows; stable model references; SCD-2 reference-to-model bindings.

**Independent Test**: Register a model, set a price, register a reference, bind the reference, rebind to a different model — all independently testable.

- [X] T019 [US6] Extend `hub/src/verity/hub/registry/models.py` — add `ModelSummary`, `CreateModel`, `ModelPrice`, `CreateModelPrice`, `ModelReferenceSummary`, `CreateModelReference`, `ModelReferenceBinding`, `CreateModelReferenceBinding` (fields per `contracts/registry-api.yaml` schemas)
- [X] T020 [US6] Extend `hub/src/verity/hub/registry/service.py` — add `create_model` (409 on duplicate `model_code`), `list_models` (include current_price subquery); add `add_model_price(conn, model_id, body, ctx)`: in one tx call `close_current_model_price` then INSERT new row via `add_model_price` query; add `list_model_prices`; add `create_model_reference` (409 on duplicate `reference_code`), `list_model_references` (include `current_model_code` via join to open binding); add `bind_model_reference(conn, ref_id, body, ctx)`: in one tx call `close_current_reference_binding` then INSERT new binding row; add `list_model_reference_bindings`; also update `get_inference_config` (introduced in T008) to call `get_inference_config_chain` so that `GET /api/registry/inference-configs/:id` returns the full ordered model reference priority list with resolved `model_code` — required for the portal inference config editor and for Feature 008 claim-time resolution (plan Phase 6 step 1)
- [X] T021 [US6] Extend `hub/src/verity/hub/registry/router.py` — add route handlers for: `GET/POST /registry/models`, `GET/POST /registry/models/{id}/prices`; `GET/POST /registry/model-references`, `GET/POST /registry/model-references/{id}/bindings`

**Checkpoint**: Register model → set price → list models shows current_price. Set new price → old window closed, new window open. Register reference → bind to model → rebind to different model → old binding closed. Deletion of a model referenced by an active inference config returns 409 (DB FK constraint).

---

## Phase 7: User Story 5 — Export and import registry bundles as YAML (P5)

**Goal**: Export a version + full composition as YAML. Dry-run and apply import with idempotency by content hash / (name, semver).

**Independent Test**: Export the US1 agent version as YAML, re-import it, verify dry-run reports all no-ops.

- [X] T022 [US5] Add `pyyaml` to `hub/pyproject.toml` dependencies if not already present (check with `grep -r pyyaml hub/pyproject.toml`)
- [X] T023 [US5] Extend `hub/src/verity/hub/registry/models.py` — add `ImportReportEntry`, `ImportReport` (fields per `contracts/registry-api.yaml` ImportReport schema)
- [X] T024 [US5] Create `hub/src/verity/hub/registry/yaml_io.py` — implement: `export_version(conn, version_id) -> dict`: collects executable, version detail, prompt/tool/mcp assignments (with their component content), source/target bindings, inference config; returns nested dict matching bundle structure from research.md Finding 7; `bundle_to_yaml(data: dict) -> str`: serializes with `yaml.safe_dump`; `parse_bundle(yaml_str: str) -> dict`: parses YAML, validates top-level `verity_registry_bundle` key (raises ValueError on malformed); `import_bundle(conn, bundle: dict, dry_run: bool) -> ImportReport`: for each entity type — prompts by content_hash, executables by (kind_code, name), versions by (name, semver), tools/connectors by (name, semver) — query for existence and emit action `created`/`no_op`; if `dry_run=False` INSERT missing entities; return `ImportReport` with totals
- [X] T025 [US5] Extend `hub/src/verity/hub/registry/router.py` — add: `GET /registry/versions/{id}/export` (returns YAML via `Response(content=..., media_type="application/x-yaml")`); `POST /registry/import/dry-run` (reads `application/x-yaml` body, calls `import_bundle(dry_run=True)`); `POST /registry/import` (calls `import_bundle(dry_run=False)`)

**Checkpoint**: Export version → YAML contains all assignments and bindings. Dry-run import of same YAML → all no-ops. Apply import after deleting a prompt → prompt is re-created. Name/kind conflict returns 422.

---

## Phase 8: Tests & Polish

**Purpose**: Integration verification and quickstart walkthrough.

- [X] T026 Create `hub/tests/test_registry_005.py` with pytest cases covering: (1) register executable + duplicate name rejection; (2) create prompt version + content hash present; (3) create agent version with governance fields; (4) assign tool to agent version succeeds; (5) assign tool to task version returns 409; (6) promote v1 to champion; (7) promote v2 to champion atomically — verify `entity_champion_current` shows v2 only; (8) `GET champion?as_of=<before v2 promote>` returns v1; (9) create storage_object source binding without connector_version_id returns 422; (10) register model + set price + rebind model reference; (11) YAML round-trip: export → dry-run import → all entries are no_op; (12) where-used returns correct executable_version entries after assignment
- [X] T027 Run `./dev test` and verify all tests pass (67+ existing + new T026 tests); run `./dev migrate` to confirm 0006 applies cleanly. **Performance gate (SC-002, SC-005)**: against the running dev instance with ≥10 seeded versions, time `GET /api/registry/executables?kind=agent` (must be <500ms) and `GET /api/registry/prompt-versions/{id}/used-by` (must be <200ms) using `curl -s -o /dev/null -w "%{time_total}"` or browser DevTools; record results in the `specs/005-entity-registry/quickstart.md` Deviations table.
- [ ] T028 Run quickstart.md flows 1–6 end-to-end against a running dev instance; record any deviations in the Deviations table in `specs/005-entity-registry/quickstart.md`

---

## Phase 9: Portal — Registry Browse (US7)

**Goal**: Read-only portal pages for agents, tasks, prompts, tools, and model catalog. Connected-asset navigation links. Where-used sections on component pages.

**Independent Test**: Navigate to `/registry/agents`, open an agent version, follow a link to an assigned prompt — all navigable without any write actions.

**Prerequisites**: Phase 2 (US1) backend endpoints must exist.

- [X] T029 [US7] Update `hub/portal/src/App.tsx` — add nested `<Route>` entries under `/registry`: `/agents`, `/agents/:id`, `/agents/:id/:vid`, `/tasks`, `/tasks/:id`, `/tasks/:id/:vid`, `/prompts`, `/prompts/:id`, `/tools`, `/tools/:id`, `/models`, `/model-references/:id`; replace direct `<RegistryList />` mount with `<Outlet />`
- [X] T030 [P] [US7] Replace `hub/portal/src/pages/registry/RegistryList.tsx` — convert to registry section shell: entity-type left-nav (Agents | Tasks | Prompts | Tools | Models) + `<Outlet />` centre; default redirect to `/registry/agents`
- [X] T031 [P] [US7] Create `hub/portal/src/pages/registry/agents/AgentList.tsx` — fetches `GET /api/registry/executables?kind=agent`; shows name, champion semver badge, lifecycle stage; click → `/registry/agents/:id`
- [X] T032 [P] [US7] Create `hub/portal/src/pages/registry/agents/AgentDetail.tsx` — fetches executable detail; renders versions table (semver, stage, champion badge); intake chip if linked; click version row → `/registry/agents/:id/:vid`
- [X] T033 [US7] Create `hub/portal/src/pages/registry/agents/AgentVersionDetail.tsx` — three read-only sections: (a) Composition manifest — prompt assignments linked to `/registry/prompts/:id`, tool assignments linked to `/registry/tools/:id`, MCP assignments by name; (b) source/target bindings table; (c) Inference config — max_tokens, temperature, model reference priority list (read-only in this phase)
- [X] T034 [P] [US7] Create `hub/portal/src/pages/registry/tasks/TaskList.tsx`, `TaskDetail.tsx`, `TaskVersionDetail.tsx` — same structure as agent pages; `TaskVersionDetail` omits tool and MCP sections
- [X] T035 [P] [US7] Create `hub/portal/src/pages/registry/prompts/PromptList.tsx` and `PromptDetail.tsx` — `PromptDetail` shows versions table (semver, content hash truncated) and "Used by" section from `GET /api/registry/prompt-versions/:vid/used-by` linked to agent/task version pages
- [X] T036 [P] [US7] Create `hub/portal/src/pages/registry/tools/ToolList.tsx` and `ToolDetail.tsx` — `ToolDetail` shows versions table with data classification badge and "Used by" section from `GET /api/registry/tool-versions/:vid/used-by`
- [X] T037 [P] [US7] Create `hub/portal/src/pages/registry/models/ModelList.tsx` and `ModelDetail.tsx` — `ModelList` shows model code, provider, current price; `ModelDetail` shows price history table and "Bound references" section (reverse lookup: which model references currently point to this model)

**Checkpoint**: Navigate the full browse flow in a browser: agent list → detail → version → click prompt link → prompt detail with "Used by" section back-linking to the agent version. `tsc` and `vite build` clean.

---

## Phase 10: Portal — Write Actions + Ctrl+J + Help (US8, FR-UI-010, FR-UI-011)

**Goal**: Composition write actions (assign/remove prompts and tools), inline inference config editor, champion promotion button. Extend Ctrl+J with registry entries. Add four help corpus pages.

**Prerequisites**: Phase 9 complete (version detail page exists before write actions are layered on).

- [X] T038 [US8] Add compose write actions to `hub/portal/src/pages/registry/agents/AgentVersionDetail.tsx` — inline "Assign Prompt" form (prompt version search field, role selector, ordinal input); remove-assignment button per manifest row; "Assign Tool" inline form; each action calls `POST`/`DELETE /api/registry/versions/:vid/prompt-assignments` or `tool-assignments` and refreshes manifest state with success/error toast. Also add prompt-assignment write actions (only) to `hub/portal/src/pages/registry/tasks/TaskVersionDetail.tsx` — same "Assign Prompt" form and per-row remove button; **omit** the tool/MCP assignment section entirely on task pages (FR-UI-007)
- [X] T039 [US8] Add inline inference config editor to `AgentVersionDetail.tsx` and `TaskVersionDetail.tsx` — editable `max_tokens` and `temperature` fields; model reference priority list with add/remove/reorder; saves via `POST /api/registry/inference-configs` (always POST — no PATCH endpoint exists; the version's `inference_config_id` is updated to point at the newly created config row)
- [X] T040 [US8] Add champion promotion to `AgentVersionDetail.tsx` and `TaskVersionDetail.tsx` — "Promote to champion" button (hidden when `lifecycle_stage === 'champion'`); confirm dialog; calls `POST /api/registry/versions/:vid/promote`; success/failure toast; parent detail page champion badge updates. Also add model-reference rebind write action to `hub/portal/src/pages/registry/models/ModelDetail.tsx` — "Rebind" button on the "Bound references" section; model_code selector; calls `POST /api/registry/model-references/:id/bind`; success toast; bound-references section refreshes (plan Phase 11 step 2)
- [X] T041 [P] [US8] Extend `hub/portal/src/shell/CommandPalette.tsx` `OBJECT_SOURCES` — add four entries: agents (`GET /api/registry/executables?kind=agent`, hint = champion semver), tasks (`kind=task`), prompts (hint = semver of latest version), tools (hint = transport_code); use `i-app-registry` sprite until entity-specific icons land in sprite.svg
- [X] T042 [P] [US8] Create four help pages in `hub/portal/src/help/`: `registry-entity-types.tsx` (group `reference`), `registry-compose.tsx` (group `forms`), `registry-full-lifecycle.tsx` (group `workflows`), `registry-navigate.tsx` (group `how-to`); add four entries to `hub/portal/src/help/pages.ts` HELP_PAGES array

**Checkpoint**: Assign and remove a prompt from an agent version in the browser; configure inference config and save; promote a version to champion; verify old champion badge clears. Ctrl+J surfaces agent and prompt results. Help drawer shows four new registry pages. `tsc`, `vite build`, `./dev test` all clean.

---

## Phase 11: Schema & Backend Gaps (prerequisite for detail screens)

**Purpose**: Migration adds two schema columns + the delegation table. Backend wires new routes and extends
existing models so detail screens have everything they need.

**Prerequisites**: Phases 1–10 done (all checked above).

- [X] T043 Write `hub/db/migrations/0009_schema_additions.sql` — three changes, all idempotent:
  (a) `ALTER TABLE core.model ADD COLUMN IF NOT EXISTS context_window integer`;
  (b) `ALTER TABLE core.tool ADD COLUMN IF NOT EXISTS is_write_operation boolean NOT NULL DEFAULT false`;
  (c) CREATE TABLE `core.executable_version_delegation` with columns:
      `delegation_id UUID PK DEFAULT gen_random_uuid()`,
      `parent_version_id UUID NOT NULL REFERENCES core.executable_version(executable_version_id)`,
      `child_executable_id UUID REFERENCES core.executable(executable_id)` (champion-tracking),
      `child_version_id UUID REFERENCES core.executable_version(executable_version_id)` (pinned),
      `scope JSONB NOT NULL DEFAULT '{}'`,
      `rationale TEXT`,
      `notes TEXT`,
      `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`,
      CHECK: exactly one of `child_executable_id` / `child_version_id` is set;
      INDEX on `parent_version_id`, INDEX on `child_executable_id`.
  Apply migration to dev DB via `psql`.
  Update `specs/schema/verity_schema.sql` with the delegation table DDL.
  Update `specs/schema/core/model.sql` and `specs/schema/core/tool.sql` with the new columns.

- [X] T044 Add SQL queries to `hub/db/queries/registry_components.sql`:
  (a) `get_tool_version_detail^` — SELECT `tv.tool_version_id, tv.tool_id, t.name, t.transport_code, t.description, tv.semver, tv.input_schema, tv.data_classification_code` FROM `core.tool_version tv JOIN core.tool t ON t.tool_id = tv.tool_id` WHERE `tv.tool_version_id = %(tool_version_id)s`.
  Add SQL queries to `hub/db/queries/registry.sql`:
  (b) `list_delegations_for_parent` — SELECT `d.delegation_id, d.parent_version_id, d.child_executable_id, e.name AS child_name, e.kind_code AS child_kind, d.child_version_id, d.scope, d.rationale, d.notes, d.created_at` FROM `core.executable_version_delegation d LEFT JOIN core.executable e ON e.executable_id = d.child_executable_id` WHERE `d.parent_version_id = %(parent_version_id)s` ORDER BY `d.created_at`;
  (c) `insert_delegation^` — INSERT INTO `core.executable_version_delegation` RETURNING `delegation_id, created_at`;
  (d) `delete_delegation!` — DELETE WHERE `delegation_id = %(delegation_id)s AND parent_version_id = %(parent_version_id)s`;
  (e) Update `list_executables_filtered` — add two subqueries to pull `governance_tier_code` and `capability_type_code` from the champion version (via `entity_champion_current` view JOIN `executable_version`).

- [X] T045 Extend `hub/src/verity/hub/registry/models.py`:
  (a) Add `PromptVersionDetail(BaseModel)` — `prompt_version_id: UUID, prompt_id: UUID, semver: str, content_hash: str, blocks: list[dict[str, Any]]`;
  (b) Add `ToolVersionDetail(BaseModel)` — `tool_version_id: UUID, tool_id: UUID, tool_name: str, transport_code: str, description: str | None, semver: str, input_schema: dict[str, Any] | None, data_classification_code: str | None`;
  (c) Add `DelegationSummary(BaseModel)` — `delegation_id: UUID, parent_version_id: UUID, child_executable_id: UUID | None, child_name: str | None, child_kind: str | None, child_version_id: UUID | None, scope: dict, rationale: str | None, notes: str | None, created_at: str`;
  (d) Add `CreateDelegation(BaseModel)` — `child_executable_id: UUID | None = None, child_version_id: UUID | None = None, scope: dict = {}, rationale: str | None = None, notes: str | None = None` with validator: exactly one of child_executable_id / child_version_id;
  (e) Add `context_window: int | None = None` to `ModelSummary`;
  (f) Add `is_write_operation: bool = False` to `ToolSummary`;
  (g) Add `governance_tier_code: str | None = None` and `capability_type_code: str | None = None` to `ExecutableSummary`.

- [X] T046 Extend `hub/src/verity/hub/registry/service.py` + `router.py`:
  Service: add `get_prompt_version_detail(conn, prompt_version_id) -> PromptVersionDetail | None` — calls `queries.get_prompt_version`; raise 404 if missing.
  Service: add `get_tool_version_detail(conn, tool_version_id) -> ToolVersionDetail | None` — calls `queries.get_tool_version_detail`; raise 404 if missing.
  Service: add `list_delegations(conn, version_id)`, `create_delegation(conn, version_id, body, ctx)` — validates parent is `kind_code=agent` (raise 422 for tasks: "tasks cannot delegate"), INSERTs row; `delete_delegation(conn, version_id, delegation_id, ctx)`.
  Service: update `list_models` SQL to include `context_window` from schema.
  Service: update `list_tools` SQL to include `is_write_operation` from schema.
  Router: add `GET /prompt-versions/{prompt_version_id}` → `PromptVersionDetail`.
  Router: add `GET /tool-versions/{tool_version_id}` → `ToolVersionDetail`.
  Router: add `GET /versions/{version_id}/delegations` → `list[DelegationSummary]`.
  Router: add `POST /versions/{version_id}/delegations` → `DelegationSummary` status 201.
  Router: add `DELETE /versions/{version_id}/delegations/{delegation_id}` → 204.
  Router: update `GET /models` → include `context_window`.
  Router: update `GET /tools` → include `is_write_operation`.

**Checkpoint**: `GET /api/prompt-versions/{id}` returns `blocks`. `GET /api/tool-versions/{id}` returns `input_schema`. `GET /api/versions/{id}/delegations` returns `[]`. `GET /api/models` includes `context_window`. `GET /api/tools` includes `is_write_operation`. All 67+ pytest pass.

---

## Phase 12: Portal — Detail Screen Rebuilds

**Purpose**: Replace the stub detail screens with production-quality screens matching and exceeding the legacy registry. This is the highest-value phase — the list screens exist and work; the detail screens have almost nothing.

**Prerequisites**: Phase 11 complete (all new API routes must exist before frontend calls them).

- [X] T047 Rebuild `hub/portal/src/pages/registry/agents/AgentDetail.tsx`:
  Fetch `GET /api/executables/{id}` for entity metadata.
  Page head: entity name, kind chip, champion semver badge (if set).
  **Metadata section** (`.kv` grid): description, version count.
  **Version history section** (`.log-table`, `.log-row`): columns = semver | stage badge | governance_tier chip | capability_type chip | created date. Each row is clickable → `/registry/agents/:id/:vid`. Champion row has champion badge. Empty state when no versions.
  **Champion snapshot section**: if champion exists, fetch `GET /api/executables/{id}/champion` and render inline summary (governance_tier, capability_type, trust_level) — this is a read-only preview, not a full version page.

- [X] T048 Rebuild `hub/portal/src/pages/registry/agents/AgentVersionDetail.tsx`:
  Fetch: `GET /api/versions/{vid}` (metadata), `GET /api/versions/{vid}/prompt-assignments`, `GET /api/versions/{vid}/tool-assignments`, `GET /api/versions/{vid}/source-bindings`, `GET /api/versions/{vid}/target-bindings`, `GET /api/versions/{vid}/delegations`. If `inference_config_id` present: `GET /api/inference-configs/{id}`.
  Page head: agent name · vX.Y.Z, stage badge.
  **Metadata `.kv`**: governance_tier, capability_type, trust_level, data_classification.
  **Inference config section**: if present — render `max_tokens`, `temperature`; render model reference priority list as a `.log-table` (priority | reference_code | resolved model_code); if absent show "No inference config assigned".
  **Prompts section** (`.log-table`): columns = ordinal | role badge | prompt name (link to `/registry/prompts/:id`) | semver. Empty state if none.
  **Authorized Tools section** (`.log-table`): columns = tool name (link to `/registry/tools/:id`) | transport chip. Empty state if none.
  **Sub-agent Delegations section** (`.log-table`): columns = child name (link to `/registry/agents/:id` if kind=agent) | tracking mode chip (`champion` vs `pinned`) | rationale (truncated). Empty state "No delegations — this agent runs without sub-agent calls."
  **Source Bindings section** (`.log-table`): name | kind chip | delivery mode. Empty state.
  **Target Bindings section** (`.log-table`): name | kind chip | write mode. Empty state.

- [X] T049 Rebuild `hub/portal/src/pages/registry/tasks/TaskDetail.tsx` and `TaskVersionDetail.tsx` — identical structure to T047/T048 with two suppressions: (a) no "Authorized Tools" section (tasks are single-call, no tool use); (b) no "Sub-agent Delegations" section (tasks cannot delegate). Everything else identical.

- [X] T050 Rebuild `hub/portal/src/pages/registry/prompts/PromptDetail.tsx`:
  Fetch `GET /api/prompts/{id}` for entity metadata.
  Fetch `GET /api/prompts/{id}/versions` for version list.
  Page head: prompt name.
  **Metadata**: description.
  **Versions** — render each version as a collapsible section card:
    - Section header: semver chip + content hash (first 8 chars) + "Used by N executables" summary (lazy-fetch `GET /api/prompt-versions/{vid}/used-by`, display count inline).
    - **Content block**: fetch `GET /api/prompt-versions/{vid}` (returns blocks); render `blocks[0].text` (and any subsequent blocks) inside `<pre className="code-block">`. Handle multi-block: render each block in its own `<pre>`.
    - **Used by table** (`.log-table`, lazy-loaded on expand): columns = executable name (link) | version | role. Empty state "Not used by any executable versions."
  First version is expanded by default; rest collapsed.

- [X] T051 Rebuild `hub/portal/src/pages/registry/tools/ToolDetail.tsx`:
  Fetch `GET /api/tools/{id}`, `GET /api/tools/{id}/versions`.
  Page head: tool name, transport chip.
  **Metadata `.kv`**: description, transport.
  **Versions** — each version as a section card:
    - Header: semver chip + data_classification badge.
    - **Input schema block**: fetch `GET /api/tool-versions/{vid}` (returns `input_schema`); render `JSON.stringify(input_schema, null, 2)` in `<pre className="code-block">`. If no schema: "No input schema defined."
    - **Used by table** (`.log-table`, lazy-loaded): same as T050 used-by.

- [X] T052 Update `hub/portal/src/pages/registry/models/ModelDetail.tsx`:
  (a) Add `context_window` to the metadata `.kv` grid — formatted as "200,000 tokens" (toLocaleString + " tokens").
  (b) Add `description` field to metadata grid (currently not shown).
  (c) Add **Used by** section: to determine which agents/tasks use this model, we need agents/tasks whose champion version's inference config resolves to this model. Backend query for this doesn't exist — fetch `GET /api/executables` (all agents+tasks), for each fetch their champion → check `inference_config_id` → fetch config chain. This is expensive client-side; instead, add a new backend query `list_executables_by_model(model_id)` that joins `executable_version.inference_config_id → inference_config_model → model_reference_binding → model` filtered by `model_id` and `entity_champion_current`. Add SQL query, service function, and `GET /api/models/{id}/executables` route. Frontend renders result as a `.log-table`: name | kind chip | version.
  Wire all three changes to the existing `ModelDetail.tsx`.

**Checkpoint**: Navigate to agent → version → see prompts/tools/delegations/bindings/inference config sections all populated. Navigate to prompt → see full text content in `<pre>`. Navigate to tool → see input_schema code block. Navigate to model → see context_window, description, and which agents use it. `tsc` and `vite build` clean.

---

## Phase 13: List Screen Polish

**Purpose**: Add the missing columns to the three list screens that have new data available from Phase 11.

**Prerequisites**: Phase 11 (backend must return new fields).

- [X] T053 [P] Update `hub/portal/src/pages/registry/agents/AgentList.tsx` and `TaskList.tsx`:
  Add `governance_tier_code` and `capability_type_code` columns (from denormalized `ExecutableSummary`, Phase 11 T045g).
  Update grid template in `hub/portal/src/pages/registry/RegistryLists.css`: `.exe-grid` from `1fr 100px 70px` → `1fr 110px 120px 90px 60px` (name | champion | tier | capability | count).
  Render tier and capability as `<span className="chip chip--static">` (not badge — no lifecycle meaning).
  Handle null (no champion yet → show dashes for tier and capability).

- [X] T054 [P] Update `hub/portal/src/pages/registry/models/ModelList.tsx`:
  Change pricing display: multiply stored per-1k value × 1000 → display as per-1M. Column header: "In / 1M" and "Out / 1M".
  Add `context_window` column: render as `200k` (Math.round(context_window / 1000) + 'k') or `—` if null.
  Update `.model-grid` in `RegistryLists.css`: `1fr 100px 90px 90px 80px` (model | status | in | out | ctx).

- [X] T055 [P] Update `hub/portal/src/pages/registry/tools/ToolList.tsx`:
  Add `is_write_operation` column: render as `<span className="chip chip--warn">Write</span>` if true, `—` if false.
  Update `.tool-grid` in `RegistryLists.css`: `1fr 150px 60px`.

**Checkpoint**: Agent list shows tier + capability columns. Model list shows per-1M prices. Tool list shows write-op indicator. `tsc` clean.

---

## Phase 14: Seed Data Enrichment

**Purpose**: Enrich demo_seed.py with inference configs, delegation authorizations, is_write_operation, context_window, and richer prompt content so the detail screens have real data to show.

**Prerequisites**: Phase 11 (schema changes must be applied to dev DB).

- [X] T056 Enrich `tools/demo_seed.py` — inference configs + wire to versions:
  Add three inference configs (idempotent, using deterministic UUIDs):
  - `triage_balanced`: temperature=0.2, max_tokens=4096
  - `classification_strict`: temperature=0.0, max_tokens=512
  - `extraction_deterministic`: temperature=0.0, max_tokens=2048
  For each, INSERT into `core.inference_config` + `core.inference_config_model` linking to the correct model reference (`reasoning-primary`, `classification-primary`, `extraction-primary`).
  UPDATE the seeded agent/task champion versions to set `inference_config_id` to the appropriate config.
  Add `teardown()` cleanup for inference configs.

- [X] T057 Enrich `tools/demo_seed.py` — delegation seed data:
  Add one delegation: `triage-agent v1.0.0` → `appetite-agent` (champion-tracking).
  INSERT into `core.executable_version_delegation` with rationale copied from legacy seed.
  Add `teardown()` cleanup.

- [X] T058 Enrich `tools/demo_seed.py` — schema columns:
  (a) UPDATE `core.model SET context_window = 200000 WHERE model_code IN (...)` for the three seeded models.
  (b) UPDATE `core.tool SET is_write_operation = true WHERE name = 'store-extraction-result'`.

- [ ] T059 Enrich `tools/demo_seed.py` — richer prompt content:
  Replace the current minimal single-sentence prompt text with production-grade blocks modelled after legacy.
  Each prompt should have a detailed system block (200–400 words) that reflects real underwriting / insurance governance intent:
  - `triage-system`: classify submission, identify risk tier, flag edge cases
  - `appetite-system`: evaluate against underwriting guidelines (GL, WC, BOP)
  - `extraction-gl-acord125`: extract ACORD 125 fields into structured JSON
  - `risk-assessment-system`: synthesize multiple signals into risk score + narrative
  - `classification-lob`: classify line of business from submission text
  - `compliance-check-system`: check submission against active regulatory obligations

**Checkpoint**: Run `./dev demo` — triage agent detail shows inference config chain (reasoning-primary → claude-opus-4-8). triage-agent version detail shows delegation to appetite-agent. Model list shows 200k context window. store-extraction-result shows "Write" chip. Prompt detail shows full production-grade prompt text in `<pre>`.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (US1)**: Depends on Phase 1 completion (SQL queries must exist before service code)
- **Phase 3 (US2)**: Depends on Phase 2 — composition requires component registration endpoints and their SQL
- **Phase 4 (US3)**: Depends on Phase 3 — promote endpoint requires composition check (prompt assignment exists)
- **Phase 5 (US4)**: Depends on Phase 2 — bindings need version_id and connector_version_id lookups; independent of US2/US3
- **Phase 6 (US6)**: Depends on Phase 1 SQL only — independent of US1–US4
- **Phase 7 (US5)**: Depends on Phases 2–6 — YAML export/import touches all entity types
- **Phase 8 (Backend Tests)**: Depends on Phases 1–7; backend-only (pytest suite)
- **Phase 9 (Portal Browse)**: Depends on Phase 2 (US1 API endpoints must exist); can run in parallel with Phases 3–7
- **Phase 10 (Portal Write + Shell)**: Depends on Phase 9 (write actions layer on top of browse pages)
- Final browser verification in Phase 10 checkpoint requires Phases 3–4 (compose + champion) backend complete

### User Story Dependencies

```
Phase 1 (SQL foundation)
  └─ Phase 2 (US1: register entities)
       ├─ Phase 3 (US2: composition) ──> Phase 4 (US3: champion)
       ├─ Phase 5 (US4: bindings)     [independent of US2/US3]
       ├─ Phase 6 (US6: model catalog) [independent of US1 beyond Phase 1]
       │    └─ Phase 7 (US5: YAML I/O)  [needs all above]
       │         └─ Phase 8 (backend tests)
       └─ Phase 9 (US7: portal browse)   [can start after Phase 2; runs in parallel with 3–7]
            └─ Phase 10 (US8: portal write + shell)  [final browser check needs Phases 3–4]
```

### Within Each Phase

- T007 (models) → T008 (service) → T009 (router) in each user story phase — always sequential
- T002/T003/T004/T005 in Phase 1 are all [P] — different SQL files, write independently

### Parallel Opportunities

**Phase 1**: T002, T003, T004, T005 can all be written simultaneously (different files).

**Phase 6 (US6)**: Can start in parallel with Phase 3 (US2) once Phase 1 is complete, since the model catalog has no dependency on composition.

---

## Parallel Example: Phase 1 SQL files

```bash
# All four SQL files can be written simultaneously:
Task: "Write hub/db/queries/registry_components.sql"   # T002
Task: "Write hub/db/queries/registry_bindings.sql"     # T003
Task: "Write hub/db/queries/registry_model_catalog.sql" # T004
Task: "Extend hub/db/queries/registry.sql"              # T005
```

---

## Implementation Strategy

### MVP (Phase 1 + Phase 2 only — US1)

1. Complete Phase 1 (SQL foundation)
2. Complete Phase 2 (US1 register entities)
3. Validate: register agent + prompt + tool, create versions, list them, verify where-used
4. **STOP and demonstrate** before moving to composition/champion

### Full Delivery Order

1. Phase 1 → Phase 2 (US1) — foundation + entity registration
2. Phase 3 (US2) → Phase 4 (US3) — composition then champion
3. Phase 5 (US4) — bindings (can start after Phase 2)
4. Phase 6 (US6) — model catalog (can start after Phase 1)
5. Phase 7 (US5) — YAML I/O (needs everything above)
6. Phase 8 — backend tests and quickstart walkthrough
7. Phase 9 (US7) — portal browse pages (can start in parallel with steps 2–5 once Phase 2 is done)
8. Phase 10 (US8) — portal write actions + Ctrl+J + help (after Phase 9, with Phases 3–4 complete)

---

## Notes

- All service functions must use `async with conn.transaction()` for multi-step writes
- `champion_assignment` is append-only — never UPDATE or DELETE rows; only INSERT
- SCD-2 closes (model_price, model_reference_binding) use `UPDATE ... SET valid_to = now() WHERE valid_to = '2099-12-31 00:00:00+00'` — always inside a transaction with the INSERT of the new row
- `psycopg.errors.CheckViolation` is the DB signal for agent-only violation — catch in service, raise as HTTP 409
- content_hash for prompt versions: `hashlib.sha256(json.dumps(blocks, sort_keys=True).encode()).hexdigest()` using Python stdlib
- YAML import idempotency: check existence by natural key before INSERT; `dry_run=True` skips all writes, still reports what would happen

# Research: Entity Model & Registry

**Feature**: 005-entity-registry
**Phase**: Phase 0 — resolves all technical unknowns before design

---

## Finding 1 — Schema is already fully defined in the 0001 baseline

**Decision**: No new migration is required for schema structure.

**Rationale**: The migration runner (`hub/src/verity/hub/migrate.py`) loads `specs/schema/verity_schema.sql` as migration `0001_baseline`. All tables this feature needs already exist:
- `core.prompt`, `core.prompt_version`
- `core.tool`, `core.tool_version`
- `core.mcp_server_version`
- `core.data_connector`, `core.data_connector_version`
- `core.inference_config`, `core.inference_config_model`
- `core.source_binding`, `core.target_binding`
- `core.model`, `core.model_price`
- `core.model_reference`, `core.model_reference_binding`
- `core.executable_prompt_assignment`, `core.executable_tool_assignment`, `core.executable_mcp_assignment`

**Implication for implementation**: Feature 005 adds only SQL queries and API/service layer on top of the existing schema. No `hub/db/migrations/0006_*.sql` file is needed.

---

## Finding 2 — Champion is append-only, not SCD-2

**Decision**: Atomic champion swap is implemented as: INSERT revocation row for old champion + INSERT new champion row — both in one transaction.

**Rationale**: `core.champion_assignment` is append-only with an `is_revocation` boolean (schema comment: "Champion = the latest non-revoked assignment"). The current champion is resolved via the `entity_champion_current` view (latest non-revoked assignment per executable). This differs from what the spec implied ("close the previous champion's validity window") — there is no `valid_from`/`valid_to` on champion_assignment. The semantics are equivalent: inserting a revocation record atomically with a new promotion record produces the same non-overlapping guarantee.

**SQL pattern**:
```sql
-- atomic swap: revoke old champion, insert new one
INSERT INTO core.champion_assignment (executable_version_id, is_revocation, reason, actor_id, acting_role_code)
SELECT ca.executable_version_id, true, 'superseded', %(actor_id)s, %(acting_role_code)s
FROM core.entity_champion_current ca
WHERE ca.executable_id = %(executable_id)s;  -- revoke if exists (0 or 1 row)

INSERT INTO core.champion_assignment (executable_version_id, lifecycle_event_id, is_revocation, reason, actor_id, acting_role_code)
VALUES (%(version_id)s, %(lifecycle_event_id)s, false, 'promoted', %(actor_id)s, %(acting_role_code)s);
```

**Existing gap**: The current `insert_champion` query in `hub/db/queries/registry.sql` does NOT revoke the old champion before inserting the new one. Feature 005 must replace it with the atomic two-insert pattern.

---

## Finding 3 — Binding schema is structured, not a string DSL

**Decision**: Source and target bindings are created via structured fields (`source_kind_code`, `delivery_mode_code`, `locator` JSONB, etc.), not a parsed string expression. The abstract DSL in the spec is a conceptual description of the `locator` + `kind` combination.

**Rationale**: Reading `core.source_binding`:
- `source_kind_code` ∈ `{storage_object, task_output, structured, inline_content}`
- `locator` JSONB holds the variable config (path template, query, business keys)
- `delivery_mode_code` ∈ `{inline, reference, download, extracted}` — how content reaches the model
- A `storage_object` source MUST reference a `data_connector_version_id` (DB CHECK constraint)

Reading `core.target_binding`:
- `target_kind_code` ∈ `{storage_object, task_output, structured}`
- `write_mode_code` ∈ `{create, overwrite, create_or_version}` — required for storage_object targets
- `target_payload_field` — which output field feeds this write

**Implication**: The API does not need to parse a DSL string. Instead, it accepts structured fields matching the schema columns. Validation is: (a) reject `storage_object` source/target without a `data_connector_version_id`; (b) reject `storage_object` target without `write_mode_code` — both already enforced as DB CHECK constraints that will raise at INSERT time.

---

## Finding 4 — Existing registry module is thin; feature 005 extends it

**Decision**: Feature 005 extends the existing `hub/src/verity/hub/registry/` module (models, router, service) and adds new SQL query files.

**Rationale**: The existing module (`hub/db/queries/registry.sql`, `registry/models.py`, `router.py`, `service.py`) covers:
- Executable CRUD + lifecycle advance + champion insert (missing revocation)
- Intake↔asset linking and the promotion gate

Everything else (prompts, tools, MCP servers, data connectors, inference configs, composition assignments, source/target bindings, model catalog, YAML I/O) is absent and must be added.

**New SQL query files**:
- `hub/db/queries/registry_components.sql` — CRUD for prompts, tools, MCP servers, connectors, inference configs
- `hub/db/queries/registry_bindings.sql` — CRUD for source/target bindings
- `hub/db/queries/registry_model_catalog.sql` — models, prices, model references, reference bindings
- Extend `hub/db/queries/registry.sql` — version detail, champion resolution (by name + as-of), where-used reverse lookup

**New service file**:
- `hub/src/verity/hub/registry/yaml_io.py` — YAML export/import using PyYAML (already in hub's dependencies via `aiosql` chain; if absent, add to `pyproject.toml`)

---

## Finding 5 — Where-used reverse lookup requires join across three assignment tables

**Decision**: Implement as a single SQL query using UNION across all three assignment tables.

**Rationale**: Component versions (prompts, tools, MCP) each appear in separate assignment tables. A where-used query joins back via `executable_prompt_assignment`, `executable_tool_assignment`, or `executable_mcp_assignment` respectively to `executable_version` and `executable`. The three variants share the same shape (return executable_id, name, kind, version_id, semver) and are exposed as:
- `GET /registry/prompt-versions/{id}/used-by`
- `GET /registry/tool-versions/{id}/used-by`
- `GET /registry/mcp-versions/{id}/used-by`

**SQL pattern** (prompt example):
```sql
SELECT e.executable_id, e.name, e.kind_code, ev.executable_version_id, ev.semver
FROM core.executable_prompt_assignment epa
JOIN core.executable_version ev ON ev.executable_version_id = epa.executable_version_id
JOIN core.executable e ON e.executable_id = ev.executable_id
WHERE epa.prompt_version_id = %(prompt_version_id)s
ORDER BY e.name, ev.semver;
```

---

## Finding 6 — Champion as-of timestamp resolution

**Decision**: Historical champion resolution queries `core.champion_assignment` as-of a timestamp by finding the most-recent non-revocation row created before or at the target timestamp.

**Rationale**: Champion assignment rows have `created_at`. The champion as-of time T is: the `executable_version_id` of the latest `champion_assignment` row with `is_revocation = false` and `created_at <= T`, for which no revocation row exists with `created_at <= T` and `created_at > the assignment row's created_at`.

**SQL pattern**:
```sql
WITH ranked AS (
  SELECT ca.executable_version_id, ca.created_at,
         lead(ca.created_at) OVER (ORDER BY ca.created_at) AS next_event_at,
         ca.is_revocation
  FROM core.champion_assignment ca
  JOIN core.executable_version ev ON ev.executable_version_id = ca.executable_version_id
  WHERE ev.executable_id = %(executable_id)s
    AND ca.created_at <= %(as_of)s
)
SELECT r.executable_version_id
FROM ranked r
WHERE r.is_revocation = false
  AND (r.next_event_at IS NULL OR r.next_event_at > %(as_of)s)
ORDER BY r.created_at DESC
LIMIT 1;
```

---

## Finding 7 — YAML I/O library: PyYAML is already available

**Decision**: Use `pyyaml` (already transitively present via `aiosql` or directly installable); if absent, add to `hub/pyproject.toml`.

**Rationale**: The YAML export format is straightforward: serialize Python dicts/lists produced by the query layer into YAML. Import reads YAML, validates structure, then performs upsert-or-skip SQL operations. No streaming YAML parser is needed at the volumes this feature handles (hundreds of entities per bundle).

**YAML bundle structure**:
```yaml
verity_registry_bundle:
  version: "1"
  exported_at: "2026-06-11T12:00:00Z"
  executables:
    - id: <uuid>
      kind: agent
      name: underwriting-assistant
      versions:
        - semver: "1.0.0"
          governance_tier: tier_2
          capability_type: classification
          inference_config: { max_tokens: 2048, temperature: 0.1, model_references: [...] }
          prompt_assignments:
            - prompt_name: uw-system-prompt
              prompt_semver: "1.0.0"
              api_role: system
              ordinal: 1
          tool_assignments: []
          mcp_assignments: []
          source_bindings:
            - name: application_data
              source_kind: structured
              delivery_mode: inline
              locator: {}
          target_bindings: []
  prompts:
    - name: uw-system-prompt
      versions:
        - semver: "1.0.0"
          blocks: [...]
          content_hash: "sha256:..."
  tools: []
  connectors: []
```

---

## Alternatives Considered

| Question | Decision | Alternatives Rejected |
|----------|----------|-----------------------|
| New migration for binding tables | No migration — tables in 0001 baseline | Additive migration: unnecessary; tables exist |
| Champion swap mechanism | Append-only: revoke + promote in one tx | SCD-2 valid_to update: contradicts schema design (`champion_assignment` has no `valid_to`) |
| Binding API shape | Structured fields per schema columns | String DSL parsing: more complex, no benefit — the schema already structures the fields |
| YAML library | pyyaml | ruamel.yaml (heavier, not needed); tomllib (wrong format) |
| Where-used endpoint | Three separate endpoints per component type | Single endpoint with `component_type` param: less clear routing, harder to type |

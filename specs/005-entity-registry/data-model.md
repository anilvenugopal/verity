# Data Model: Entity Model & Registry

**Feature**: 005-entity-registry
**Phase**: Phase 1 — maps spec entities to the hardened schema

All tables are in the `0001_baseline` migration (loaded from `specs/schema/verity_schema.sql`).
No new tables are introduced by this feature. This document records key fields, relationships,
invariants, and state transitions relevant to the API layer.

---

## 1. Executables — the governed, runnable unit

### `core.executable`

| Column | Type | Notes |
|--------|------|-------|
| `executable_id` | uuid | PK, uuidv7 |
| `kind_code` | text | `agent` or `task` — FK to `reference.executable_kind` |
| `name` | text | Unique per kind (UNIQUE on `(kind_code, name)`) |
| `description` | text | nullable |
| `created_by_actor_id` | uuid | FK to `core.actor` |
| `created_role_code` | text | FK to `reference.role` |

### `core.executable_version`

| Column | Type | Notes |
|--------|------|-------|
| `executable_version_id` | uuid | PK, uuidv7 |
| `executable_id` | uuid | FK to `core.executable` |
| `kind_code` | text | Denormalized from executable — enables agent-only FK enforcement |
| `semver` | text | UNIQUE per `executable_id` |
| `version_change_type_code` | text | major/minor/patch — FK to `reference.version_change_type` |
| `cloned_from_version_id` | uuid | Lineage — nullable FK to self |
| `capability_type_code` | text | classification/extraction/etc. — FK to `reference.capability_type` |
| `trust_level_code` | text | FK to `reference.trust_level` |
| `governance_tier_code` | text | FK to `reference.governance_tier` |
| `data_classification_code` | text | FK to `reference.data_classification` |
| `inference_config_id` | uuid | FK to `core.inference_config` |
| `input_schema` | jsonb | Structured input payload schema |
| `output_schema` | jsonb | Structured output payload schema |
| `valid_from` | timestamptz | SCD-2 window start |
| `valid_to` | timestamptz | SCD-2 window end; `2099-12-31` = current |

**Key invariants**:
- `kind_code` is denormalized so agent-only assignment tables can enforce `kind_code = 'agent'` via composite FK + CHECK.
- UNIQUE `(executable_version_id, kind_code)` enables agent-only enforcement.

---

## 2. Champion lifecycle — append-only

### `core.champion_assignment`

| Column | Type | Notes |
|--------|------|-------|
| `champion_assignment_id` | uuid | PK |
| `executable_version_id` | uuid | FK to `core.executable_version` |
| `is_revocation` | boolean | `false` = promote; `true` = demote |
| `lifecycle_event_id` | uuid | FK to `core.lifecycle_event` (nullable) |
| `reason` | text | e.g. `promoted`, `superseded` |
| `actor_id` / `acting_role_code` | uuid/text | Who made the change |
| `created_at` | timestamptz | Append-only timestamp |

**Champion resolution**:
- Current champion: `entity_champion_current` view — latest `is_revocation = false` row per executable.
- As-of timestamp: window query on `champion_assignment` (see research.md Finding 6).

**Atomic swap pattern**: To promote version B while retiring version A (the current champion):
1. INSERT revocation row for A's version ID
2. INSERT new champion row for B's version ID
Both in one transaction — guaranteed no gap, no dual-champion.

---

## 3. Prompt component

### `core.prompt`

| Column | Type | Notes |
|--------|------|-------|
| `prompt_id` | uuid | PK |
| `name` | text | UNIQUE |
| `description` | text | nullable |

### `core.prompt_version`

| Column | Type | Notes |
|--------|------|-------|
| `prompt_version_id` | uuid | PK |
| `prompt_id` | uuid | FK to `core.prompt` |
| `semver` | text | UNIQUE per prompt |
| `blocks` | jsonb | Ordered typed prompt blocks |
| `content_hash` | text | SHA-256 of rendered content |
| `valid_from` / `valid_to` | timestamptz | SCD-2 window |

---

## 4. Tool component — agent-only

### `core.tool`

| Column | Type | Notes |
|--------|------|-------|
| `tool_id` | uuid | PK |
| `name` | text | UNIQUE |
| `transport_code` | text | FK to `reference.tool_transport` |

### `core.tool_version`

| Column | Type | Notes |
|--------|------|-------|
| `tool_version_id` | uuid | PK |
| `tool_id` | uuid | FK to `core.tool` |
| `semver` | text | UNIQUE per tool |
| `input_schema` | jsonb | Input argument schema |
| `config` | jsonb | Tool config for this version |
| `valid_from` / `valid_to` | timestamptz | SCD-2 window |
| `data_classification_code` | text | **Added by feature 005** (FR-RG-018): FK to `reference.data_classification` |

> Note: `data_classification_code` is not in the baseline `core.tool_version`. Feature 005 requires migration `0006` to add this column. All other fields are pre-existing.

---

## 5. MCP server component — agent-only

### `core.mcp_server_version`

(No header table — versions are the primary registration unit for MCP servers.)

| Column | Type | Notes |
|--------|------|-------|
| `mcp_server_version_id` | uuid | PK |
| `name` | text | UNIQUE per MCP server |
| `semver` | text | Version string |
| `config` | jsonb | Server configuration |

---

## 6. Data connector

### `core.data_connector`

| Column | Type | Notes |
|--------|------|-------|
| `data_connector_id` | uuid | PK |
| `name` | text | UNIQUE |
| `connector_type_code` | text | FK to `reference.connector_type` (vault/s3/azure_blob/gcs/sharepoint/filesystem/http/database) |

### `core.data_connector_version`

| Column | Type | Notes |
|--------|------|-------|
| `data_connector_version_id` | uuid | PK |
| `data_connector_id` | uuid | FK to `core.data_connector` |
| `semver` | text | UNIQUE per connector |
| `config` | jsonb | Backend config (bucket, path, auth ref) |
| `valid_from` / `valid_to` | timestamptz | SCD-2 window |

---

## 7. Inference config

### `core.inference_config`

| Column | Type | Notes |
|--------|------|-------|
| `inference_config_id` | uuid | PK |
| `max_tokens` | integer | nullable |
| `temperature` | numeric(4,3) | 0–2, nullable |
| `params` | jsonb | Extra params |

### `core.inference_config_model`

| Column | Type | Notes |
|--------|------|-------|
| `inference_config_id` | uuid | Part of PK |
| `model_reference_id` | uuid | FK to `core.model_reference` |
| `priority` | integer | 1 = primary; 2+ = fallbacks |

---

## 8. Composition assignments

### `core.executable_prompt_assignment`

| Column | Type | Notes |
|--------|------|-------|
| `executable_version_id` | uuid | Part of PK |
| `prompt_version_id` | uuid | Part of PK |
| `api_role_code` | text | Part of PK — FK to `reference.api_role` (system/user/assistant/…) |
| `ordinal` | integer | Order within the role |

**Note**: PK is `(executable_version_id, prompt_version_id, api_role_code)` — same prompt version CAN appear in multiple roles.

> The priority chain in `core.inference_config_model` is walked by `gateway_llm_call` in Feature 008 (Harness Runtime): priority 1 is tried first; on exhausted retries against a transient error, priority 2+ is tried in order. The chain is resolved at claim time via `get_inference_config_chain` — see Feature 008 / ADR-0019.

### `core.executable_tool_assignment`

| Column | Type | Notes |
|--------|------|-------|
| `executable_version_id` | uuid | Part of PK |
| `tool_version_id` | uuid | Part of PK |
| `executable_kind_code` | text | MUST be `agent` — enforced by CHECK |

### `core.executable_mcp_assignment`

| Column | Type | Notes |
|--------|------|-------|
| `executable_version_id` | uuid | Part of PK |
| `mcp_server_version_id` | uuid | Part of PK |
| `executable_kind_code` | text | MUST be `agent` — enforced by CHECK |

---

## 9. Source and target bindings

### `core.source_binding`

| Column | Type | Notes |
|--------|------|-------|
| `source_binding_id` | uuid | PK |
| `executable_version_id` | uuid | FK to `core.executable_version` |
| `name` | text | UNIQUE per version |
| `source_kind_code` | text | `storage_object` / `task_output` / `structured` / `inline_content` |
| `data_connector_version_id` | uuid | Required when `source_kind = storage_object` (DB CHECK) |
| `delivery_mode_code` | text | `inline` / `reference` / `download` / `extracted` |
| `media_type` | text | nullable |
| `locator` | jsonb | Path template, query, or business keys |
| `nullable` | boolean | Whether input may be absent at run time |
| `ordinal` | integer | Order among version's inputs |

### `core.target_binding`

| Column | Type | Notes |
|--------|------|-------|
| `target_binding_id` | uuid | PK |
| `executable_version_id` | uuid | FK to `core.executable_version` |
| `name` | text | UNIQUE per version |
| `target_kind_code` | text | `storage_object` / `task_output` / `structured` |
| `data_connector_version_id` | uuid | Required when `target_kind = storage_object` (DB CHECK) |
| `delivery_mode_code` | text | `write_file` for storage; `inline` for structured |
| `write_mode_code` | text | `create` / `overwrite` / `create_or_version` — required for storage_object |
| `target_payload_field` | text | Which output field feeds this write |
| `locator` | jsonb | Path template, naming config |
| `ordinal` | integer | Order among version's outputs |

---

## 10. Model catalog

### `core.model`

| Column | Type | Notes |
|--------|------|-------|
| `model_id` | uuid | PK |
| `model_code` | text | UNIQUE — e.g. `claude-sonnet-4-6` |
| `provider` | text | e.g. `anthropic` |
| `modality` | text | default `chat` |
| `model_status_code` | text | FK to `reference.model_status` |

### `core.model_price`

| Column | Type | Notes |
|--------|------|-------|
| `model_price_id` | uuid | PK |
| `model_id` | uuid | FK to `core.model` |
| `input_price_per_1k` | numeric(12,6) | Input token price |
| `output_price_per_1k` | numeric(12,6) | Output token price |
| `currency_code` | text | FK to `reference.currency` |
| `valid_from` / `valid_to` | timestamptz | SCD-2 window |

**UNIQUE partial index**: one open price per model (`WHERE valid_to = '2099-12-31...'`).

**Atomic price update**: close old window (`UPDATE valid_to = now()`) + INSERT new row in one tx.

### `core.model_reference`

| Column | Type | Notes |
|--------|------|-------|
| `model_reference_id` | uuid | PK |
| `reference_code` | text | UNIQUE — stable alias e.g. `reasoning-primary` |
| `name` | text | Human name |
| `description` | text | nullable |

### `core.model_reference_binding`

| Column | Type | Notes |
|--------|------|-------|
| `model_reference_binding_id` | uuid | PK |
| `model_reference_id` | uuid | FK to `core.model_reference` |
| `model_id` | uuid | FK to `core.model` |
| `valid_from` / `valid_to` | timestamptz | SCD-2 window |
| `reason` | text | Why the binding changed |
| `bound_by_actor_id` / `bound_role_code` | uuid/text | Who set it |

**UNIQUE partial index**: one open binding per reference (`WHERE valid_to = '2099-12-31...'`).

> Swapping the underlying model (close old binding + open new) takes effect for all executables using that reference at the next run — no package re-promotion required (design decision D10). Migration 0007 adds `was_fallback` and `model_reference_id` to `audit.model_invocation_log` so each governed decision records which chain position fired (ADR-0019).

---

## 11. Required migration — 0006

One new migration is needed to add `data_classification_code` to `core.tool_version` (FR-RG-018):

```sql
-- 0006_tool_data_classification.sql
ALTER TABLE core.tool_version
  ADD COLUMN IF NOT EXISTS data_classification_code text;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_tool_version_data_class') THEN
    ALTER TABLE core.tool_version
      ADD CONSTRAINT fk_tool_version_data_class
      FOREIGN KEY (data_classification_code)
      REFERENCES reference.data_classification (code) ON DELETE RESTRICT;
  END IF;
END $$;
```

All other tables are in the 0001 baseline with no structural changes needed.

---

## Entity Relationships (summary)

```
core.executable (1) ──< (N) core.executable_version
  executable_version ──> (0|1) core.inference_config
                      ──< (N) core.executable_prompt_assignment ──> core.prompt_version
                      ──< (N) core.executable_tool_assignment   ──> core.tool_version  [agent-only]
                      ──< (N) core.executable_mcp_assignment    ──> core.mcp_server_version  [agent-only]
                      ──< (N) core.source_binding
                      ──< (N) core.target_binding

core.champion_assignment (append-only) ──> core.executable_version

core.prompt (1) ──< (N) core.prompt_version
core.tool (1) ──< (N) core.tool_version
core.data_connector (1) ──< (N) core.data_connector_version

core.inference_config (1) ──< (N) core.inference_config_model ──> core.model_reference
core.model_reference (1) ──< (N) core.model_reference_binding ──> core.model
core.model (1) ──< (N) core.model_price
```

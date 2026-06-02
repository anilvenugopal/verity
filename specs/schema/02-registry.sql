-- =====================================================================
-- 02-registry.sql — Verity v2 hardened schema · core REGISTRY
-- The entity/composition model (D5): the `executable` supertype, its
-- immutable versions, the reusable component tables, and Source/Target
-- bindings. Re-applied per D1-D6.
-- =====================================================================

-- ┌───────────────────────────────────────────────────────────────────┐
-- │ THE `executable` SUPERTYPE — what it is and why (D5)                │
-- │                                                                     │
-- │ An "executable" is the GOVERNED, VERSIONED, PROMOTABLE unit that    │
-- │ the harness runs. Today there are two KINDS: `agent` and `task`.    │
-- │   • an AGENT  (kind='agent') = multi-step, may use tools + MCP      │
-- │   • a TASK    (kind='task')  = single LLM step, no tools/MCP        │
-- │ Both are *executables* — they are versioned, promoted draft→champion│
-- │ packaged, and deployed the SAME way. So lifecycle, champion,        │
-- │ bindings, packaging, and deployment all point at ONE thing:         │
-- │ `executable_version` — never at "agent OR task" separately.         │
-- │                                                                     │
-- │ WHY a supertype instead of two tables: it is EXTENSIBLE. A future   │
-- │ kind (say 'workflow') is added by INSERTing one row into            │
-- │ reference.executable_kind — no change to lifecycle/champion/deploy. │
-- │ The KIND is DATA (kind_code), not hardcoded structure.              │
-- │                                                                     │
-- │ WHAT is NOT an executable: prompts, tools, data connectors, MCP     │
-- │ servers. Those are reusable COMPONENTS used *inside* an executable  │
-- │ version (see assignments below). They are versioned (for exact      │
-- │ historic reproduction) but have NO lifecycle/champion of their own. │
-- │                                                                     │
-- │ Example: agent "underwriting-assistant" (executable, kind=agent)    │
-- │   ├─ executable_version 1.2.0  ── champion                          │
-- │   │     ├─ uses prompt_version "uw-system-prompt" 3.1 (role=system) │
-- │   │     ├─ uses tool_version "calc-ltv" 1.0      (agent-only)       │
-- │   │     ├─ Source Binding: latest filing PDF from the vault         │
-- │   │     └─ Target Binding: write the rated opinion (structured)     │
-- │   └─ packaged as .vax, deployed to prod (separate, see 08-…)        │
-- └───────────────────────────────────────────────────────────────────┘

-- ===== executable (supertype header) =================================
CREATE TABLE core.executable (
    executable_id       uuid        NOT NULL DEFAULT uuidv7(),
    kind_code           text        NOT NULL,                 -- agent | task | (future) -> reference.executable_kind
    name                text        NOT NULL,
    description         text,
    created_at          timestamptz  NOT NULL DEFAULT now(),
    updated_at          timestamptz  NOT NULL DEFAULT now(),
    created_by_actor_id uuid        NOT NULL,
    created_role_code   text        NOT NULL,                 -- acting capacity (D6)
    CONSTRAINT pk_executable PRIMARY KEY (executable_id),
    CONSTRAINT fk_executable_kind FOREIGN KEY (kind_code)
        REFERENCES reference.executable_kind (code) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_created_by FOREIGN KEY (created_by_actor_id)
        REFERENCES core.actor (actor_id) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_created_role FOREIGN KEY (created_role_code)
        REFERENCES reference.role (code) ON DELETE RESTRICT,
    CONSTRAINT uq_executable_kind_name UNIQUE (kind_code, name),
    -- composite unique so child tables can pin the kind via FK (agent-only enforcement)
    CONSTRAINT uq_executable_id_kind UNIQUE (executable_id, kind_code),
    CONSTRAINT ck_executable_name_not_blank CHECK (length(btrim(name)) > 0)
);
COMMENT ON TABLE core.executable IS 'tier:1. SUPERTYPE: the governed/versioned/promotable unit (agent, task, future kinds). kind_code discriminates; no mutable champion/lifecycle columns (event-sourced in 03-lifecycle). D5.';

-- ===== inference_config (model + params for a version) ===============
CREATE TABLE core.inference_config (
    inference_config_id uuid        NOT NULL DEFAULT uuidv7(),
    model_id            uuid,                                  -- FK -> core.model added in 06-decisions
    max_tokens          integer,
    temperature         numeric(4,3),
    params              jsonb        NOT NULL DEFAULT '{}'::jsonb,  -- additional model params (genuinely variable)
    created_at          timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_inference_config PRIMARY KEY (inference_config_id),
    CONSTRAINT ck_inference_config_temp CHECK (temperature IS NULL OR (temperature >= 0 AND temperature <= 2))
);
COMMENT ON TABLE core.inference_config IS 'tier:1. Model + inference parameters referenced by an executable_version. model_id FK wired in 06-decisions.';

-- ===== executable_version (immutable SCD-2 version) ==================
CREATE TABLE core.executable_version (
    executable_version_id uuid       NOT NULL DEFAULT uuidv7(),
    executable_id         uuid       NOT NULL,
    kind_code             text       NOT NULL,                 -- denormalized from executable (enables agent-only FKs)
    semver                text       NOT NULL,                 -- e.g. '1.2.0'
    version_change_type_code text,                              -- major|minor|patch -> reference
    change_summary        text,
    cloned_from_version_id uuid,                                -- lineage (nullable)
    capability_type_code  text,                                 -- classification|extraction|… (may change per version)
    trust_level_code      text,
    governance_tier_code  text,
    data_classification_code text,
    inference_config_id   uuid,
    input_schema          jsonb,                                -- structured input payload schema
    output_schema         jsonb,                                -- structured output payload schema
    valid_from            timestamptz,                          -- SCD-2 temporal window
    valid_to              timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id   uuid       NOT NULL,
    created_role_code     text       NOT NULL,
    CONSTRAINT pk_executable_version PRIMARY KEY (executable_version_id),
    CONSTRAINT fk_executable_version_executable
        FOREIGN KEY (executable_id, kind_code)
        REFERENCES core.executable (executable_id, kind_code) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_version_change_type FOREIGN KEY (version_change_type_code)
        REFERENCES reference.version_change_type (code) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_version_cloned_from FOREIGN KEY (cloned_from_version_id)
        REFERENCES core.executable_version (executable_version_id) ON DELETE SET NULL,
    CONSTRAINT fk_executable_version_capability FOREIGN KEY (capability_type_code)
        REFERENCES reference.capability_type (code) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_version_trust FOREIGN KEY (trust_level_code)
        REFERENCES reference.trust_level (code) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_version_gov_tier FOREIGN KEY (governance_tier_code)
        REFERENCES reference.governance_tier (code) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_version_data_class FOREIGN KEY (data_classification_code)
        REFERENCES reference.data_classification (code) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_version_inference FOREIGN KEY (inference_config_id)
        REFERENCES core.inference_config (inference_config_id) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_version_created_by FOREIGN KEY (created_by_actor_id)
        REFERENCES core.actor (actor_id) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_version_created_role FOREIGN KEY (created_role_code)
        REFERENCES reference.role (code) ON DELETE RESTRICT,
    CONSTRAINT uq_executable_version_semver UNIQUE (executable_id, semver),
    -- composite unique lets agent-only component assignments pin kind via FK
    CONSTRAINT uq_executable_version_id_kind UNIQUE (executable_version_id, kind_code)
);
COMMENT ON TABLE core.executable_version IS 'tier:1 immutable SCD-2 version of an executable (valid_from/valid_to). Lifecycle/champion/bindings/deployment all reference THIS. kind_code denormalized to enforce agent-only component rules. D5.';
CREATE INDEX ix_executable_version_executable ON core.executable_version (executable_id);

-- ===== COMPONENTS (versioned, NO lifecycle; used inside executable versions) =====
-- prompt
CREATE TABLE core.prompt (
    prompt_id uuid NOT NULL DEFAULT uuidv7(), name text NOT NULL, description text,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_prompt PRIMARY KEY (prompt_id),
    CONSTRAINT fk_prompt_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_prompt_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_prompt_name UNIQUE (name));
COMMENT ON TABLE core.prompt IS 'tier:1 component (no lifecycle). Reusable prompt; content lives in prompt_version. D5.';

CREATE TABLE core.prompt_version (
    prompt_version_id uuid NOT NULL DEFAULT uuidv7(), prompt_id uuid NOT NULL,
    semver text NOT NULL, blocks jsonb NOT NULL,            -- ordered typed blocks (prompt-editor)
    content_hash text NOT NULL,                              -- for blame/diff + reproduction
    valid_from timestamptz, valid_to timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(), created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_prompt_version PRIMARY KEY (prompt_version_id),
    CONSTRAINT fk_prompt_version_prompt FOREIGN KEY (prompt_id) REFERENCES core.prompt (prompt_id) ON DELETE RESTRICT,
    CONSTRAINT fk_prompt_version_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_prompt_version_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_prompt_version_semver UNIQUE (prompt_id, semver));
COMMENT ON TABLE core.prompt_version IS 'tier:1 immutable prompt version (full historic reproduction). No lifecycle — governed within the executable that uses it. D5.';

-- tool (agent-only at assignment time)
CREATE TABLE core.tool (
    tool_id uuid NOT NULL DEFAULT uuidv7(), name text NOT NULL, description text,
    transport_code text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_tool PRIMARY KEY (tool_id),
    CONSTRAINT fk_tool_transport FOREIGN KEY (transport_code) REFERENCES reference.tool_transport (code),
    CONSTRAINT fk_tool_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_tool_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_tool_name UNIQUE (name));
CREATE TABLE core.tool_version (
    tool_version_id uuid NOT NULL DEFAULT uuidv7(), tool_id uuid NOT NULL, semver text NOT NULL,
    input_schema jsonb, config jsonb NOT NULL DEFAULT '{}'::jsonb,
    valid_from timestamptz, valid_to timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_tool_version PRIMARY KEY (tool_version_id),
    CONSTRAINT fk_tool_version_tool FOREIGN KEY (tool_id) REFERENCES core.tool (tool_id) ON DELETE RESTRICT,
    CONSTRAINT fk_tool_version_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_tool_version_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_tool_version_semver UNIQUE (tool_id, semver));

-- data_connector
CREATE TABLE core.data_connector (
    data_connector_id uuid NOT NULL DEFAULT uuidv7(), name text NOT NULL,
    connector_type_code text NOT NULL,                       -- vault|s3|azure_blob|gcs|sharepoint|filesystem|http|database
    description text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_data_connector PRIMARY KEY (data_connector_id),
    CONSTRAINT fk_data_connector_type FOREIGN KEY (connector_type_code) REFERENCES reference.connector_type (code),
    CONSTRAINT fk_data_connector_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_data_connector_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_data_connector_name UNIQUE (name));
COMMENT ON TABLE core.data_connector IS 'tier:1 component. A configured connection to a storage/data backend (connector_type). Backend config (bucket/container/base path/auth ref) in the connector version. Source/Target bindings resolve files THROUGH a connector.';
CREATE TABLE core.data_connector_version (
    data_connector_version_id uuid NOT NULL DEFAULT uuidv7(), data_connector_id uuid NOT NULL, semver text NOT NULL,
    config jsonb NOT NULL DEFAULT '{}'::jsonb, valid_from timestamptz, valid_to timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(), created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_data_connector_version PRIMARY KEY (data_connector_version_id),
    CONSTRAINT fk_data_connector_version_connector FOREIGN KEY (data_connector_id) REFERENCES core.data_connector (data_connector_id) ON DELETE RESTRICT,
    CONSTRAINT uq_data_connector_version_semver UNIQUE (data_connector_id, semver));

-- mcp_server (agent-only at assignment time)
CREATE TABLE core.mcp_server (
    mcp_server_id uuid NOT NULL DEFAULT uuidv7(), name text NOT NULL, transport_code text NOT NULL,
    description text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_mcp_server PRIMARY KEY (mcp_server_id),
    CONSTRAINT fk_mcp_server_transport FOREIGN KEY (transport_code) REFERENCES reference.tool_transport (code),
    CONSTRAINT fk_mcp_server_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_mcp_server_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_mcp_server_name UNIQUE (name));
CREATE TABLE core.mcp_server_version (
    mcp_server_version_id uuid NOT NULL DEFAULT uuidv7(), mcp_server_id uuid NOT NULL, semver text NOT NULL,
    config jsonb NOT NULL DEFAULT '{}'::jsonb, valid_from timestamptz, valid_to timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(), created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_mcp_server_version PRIMARY KEY (mcp_server_version_id),
    CONSTRAINT fk_mcp_server_version_server FOREIGN KEY (mcp_server_id) REFERENCES core.mcp_server (mcp_server_id) ON DELETE RESTRICT,
    CONSTRAINT uq_mcp_server_version_semver UNIQUE (mcp_server_id, semver));

-- ===== COMPONENT ASSIGNMENTS (component_version -> executable_version) =====
-- Prompts: uniform for agent AND task (binding-grammar). Junction = composite NK (D2).
CREATE TABLE core.executable_prompt_assignment (
    executable_version_id uuid NOT NULL, prompt_version_id uuid NOT NULL, api_role_code text NOT NULL,
    ordinal integer NOT NULL DEFAULT 1,
    CONSTRAINT pk_executable_prompt_assignment PRIMARY KEY (executable_version_id, prompt_version_id, api_role_code),
    CONSTRAINT fk_epa_executable_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_epa_prompt_version FOREIGN KEY (prompt_version_id) REFERENCES core.prompt_version (prompt_version_id) ON DELETE RESTRICT,
    CONSTRAINT fk_epa_api_role FOREIGN KEY (api_role_code) REFERENCES reference.api_role (code));
COMMENT ON TABLE core.executable_prompt_assignment IS 'tier:1. A prompt_version used by an executable_version in an api_role. Uniform for agent+task. D5.';

-- Tools: AGENT-ONLY. Enforced at the DB by pinning kind via composite FK + CHECK.
CREATE TABLE core.executable_tool_assignment (
    executable_version_id uuid NOT NULL, tool_version_id uuid NOT NULL,
    executable_kind_code text NOT NULL,                       -- must be 'agent'
    CONSTRAINT pk_executable_tool_assignment PRIMARY KEY (executable_version_id, tool_version_id),
    CONSTRAINT fk_eta_executable_version FOREIGN KEY (executable_version_id, executable_kind_code)
        REFERENCES core.executable_version (executable_version_id, kind_code) ON DELETE CASCADE,
    CONSTRAINT fk_eta_tool_version FOREIGN KEY (tool_version_id) REFERENCES core.tool_version (tool_version_id) ON DELETE RESTRICT,
    CONSTRAINT ck_eta_agent_only CHECK (executable_kind_code = 'agent'));
COMMENT ON TABLE core.executable_tool_assignment IS 'tier:1. Tool attached to an AGENT version. agent-only enforced by composite FK to (executable_version_id, kind_code) + CHECK kind=agent (binding-grammar). D5.';

-- MCP: AGENT-ONLY (same enforcement).
CREATE TABLE core.executable_mcp_assignment (
    executable_version_id uuid NOT NULL, mcp_server_version_id uuid NOT NULL,
    executable_kind_code text NOT NULL,
    CONSTRAINT pk_executable_mcp_assignment PRIMARY KEY (executable_version_id, mcp_server_version_id),
    CONSTRAINT fk_ema_executable_version FOREIGN KEY (executable_version_id, executable_kind_code)
        REFERENCES core.executable_version (executable_version_id, kind_code) ON DELETE CASCADE,
    CONSTRAINT fk_ema_mcp_version FOREIGN KEY (mcp_server_version_id) REFERENCES core.mcp_server_version (mcp_server_version_id) ON DELETE RESTRICT,
    CONSTRAINT ck_ema_agent_only CHECK (executable_kind_code = 'agent'));

-- ===== BINDINGS (Source / Target) — uniform for agent + task (binding-grammar) =====
CREATE TABLE core.source_binding (
    source_binding_id uuid NOT NULL DEFAULT uuidv7(), executable_version_id uuid NOT NULL,
    name text NOT NULL,
    source_kind_code text NOT NULL,                           -- storage_object|task_output|structured|inline_content
    data_connector_version_id uuid,                           -- the storage backend (for storage_object)
    delivery_mode_code text NOT NULL DEFAULT 'inline',        -- inline|reference|download|extracted (the base64-only fix)
    media_type text,                                           -- e.g. application/pdf, text/csv
    locator jsonb NOT NULL DEFAULT '{}'::jsonb,               -- path_template / query / business_keys (variable config)
    nullable boolean NOT NULL DEFAULT false,                  -- input may be absent at run time
    ordinal integer NOT NULL DEFAULT 1,
    CONSTRAINT pk_source_binding PRIMARY KEY (source_binding_id),
    CONSTRAINT fk_source_binding_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_source_binding_kind FOREIGN KEY (source_kind_code) REFERENCES reference.source_kind (code),
    CONSTRAINT fk_source_binding_delivery FOREIGN KEY (delivery_mode_code) REFERENCES reference.binding_delivery_mode (code),
    CONSTRAINT fk_source_binding_connector FOREIGN KEY (data_connector_version_id) REFERENCES core.data_connector_version (data_connector_version_id) ON DELETE RESTRICT,
    -- a storage_object must name its backend connector
    CONSTRAINT ck_source_binding_storage_needs_connector
        CHECK (source_kind_code <> 'storage_object' OR data_connector_version_id IS NOT NULL),
    CONSTRAINT uq_source_binding_name UNIQUE (executable_version_id, name));
COMMENT ON TABLE core.source_binding IS 'tier:1. Declarative INPUT resolved before the executable runs (v1 source_binding renamed). Files-from-storage via connector + locator + delivery_mode (inline/reference/download/extracted). Uniform for agent+task. binding-grammar.';

CREATE TABLE core.target_binding (
    target_binding_id uuid NOT NULL DEFAULT uuidv7(), executable_version_id uuid NOT NULL,
    name text NOT NULL,
    target_kind_code text NOT NULL,                           -- storage_object|task_output|structured
    data_connector_version_id uuid,                           -- the storage backend (for storage_object)
    delivery_mode_code text NOT NULL DEFAULT 'write_file',    -- write_file (storage) | inline (structured)
    write_mode_code text,                                      -- create|overwrite|create_or_version
    media_type text,
    target_payload_field text,                                -- which output field this writes
    locator jsonb NOT NULL DEFAULT '{}'::jsonb,               -- path_template / naming (variable config)
    ordinal integer NOT NULL DEFAULT 1,
    CONSTRAINT pk_target_binding PRIMARY KEY (target_binding_id),
    CONSTRAINT fk_target_binding_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_target_binding_kind FOREIGN KEY (target_kind_code) REFERENCES reference.target_kind (code),
    CONSTRAINT fk_target_binding_delivery FOREIGN KEY (delivery_mode_code) REFERENCES reference.binding_delivery_mode (code),
    CONSTRAINT fk_target_binding_write_mode FOREIGN KEY (write_mode_code) REFERENCES reference.write_mode (code),
    CONSTRAINT fk_target_binding_connector FOREIGN KEY (data_connector_version_id) REFERENCES core.data_connector_version (data_connector_version_id) ON DELETE RESTRICT,
    CONSTRAINT ck_target_binding_storage_needs_connector
        CHECK (target_kind_code <> 'storage_object' OR (data_connector_version_id IS NOT NULL AND write_mode_code IS NOT NULL)),
    CONSTRAINT uq_target_binding_name UNIQUE (executable_version_id, name));
COMMENT ON TABLE core.target_binding IS 'tier:1. Declarative OUTPUT written after the executable runs (v1 write_target renamed). Files-to-storage via connector + locator + write_mode. Uniform for agent+task. binding-grammar.';

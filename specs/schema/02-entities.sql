-- 02-entities.sql — hardened v2 schema domain: entities
-- See ASSEMBLY-AND-VERIFICATION.md for cross-domain FKs & review items.

-- ============================================================================
-- Domain: REGISTRY ENTITY & VERSION MODEL (hardened, ADR-0005)
-- Schema: governance (Tier-1 system-of-record unless tagged Tier-2)
-- Keys: UUIDv7 surrogate PKs. uuidv7() is PG18+; on PG<18 install a uuidv7()
--       SQL/extension shim (e.g. pg_uuidv7) so this default resolves identically.
-- Naming per specs/schema/naming-conventions.md.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS governance;

-- ----------------------------------------------------------------------------
-- ENUMS (lifecycle states VERBATIM; controlled vocabularies preserved from v1)
-- ----------------------------------------------------------------------------

CREATE TYPE governance.lifecycle_state AS ENUM (
    'draft', 'candidate', 'staging', 'shadow', 'challenger', 'champion', 'deprecated'
);

CREATE TYPE governance.deployment_channel AS ENUM (
    'development', 'staging', 'shadow', 'evaluation', 'production'
);

CREATE TYPE governance.materiality_tier AS ENUM ('high', 'medium', 'low');

CREATE TYPE governance.capability_type AS ENUM (
    'classification', 'extraction', 'generation', 'summarisation', 'matching', 'validation'
);

CREATE TYPE governance.trust_level AS ENUM (
    'trusted', 'conditional', 'sandboxed', 'blocked'
);

CREATE TYPE governance.data_classification AS ENUM (
    'tier1_public', 'tier2_internal', 'tier3_confidential', 'tier4_pii_restricted'
);

-- v1 entity_type members agent/task/prompt/tool, extended by intake with
-- test_suite/ground_truth_dataset (carried forward, no silent loss).
CREATE TYPE governance.entity_type AS ENUM (
    'agent', 'task', 'prompt', 'tool', 'test_suite', 'ground_truth_dataset'
);

CREATE TYPE governance.governance_tier AS ENUM (
    'behavioural', 'contextual', 'formatting'
);

CREATE TYPE governance.api_role AS ENUM ('system', 'user', 'assistant_prefill');

CREATE TYPE governance.metric_type AS ENUM (
    'exact_match', 'schema_valid', 'field_accuracy',
    'classification_f1', 'semantic_similarity', 'human_rubric'
);

CREATE TYPE governance.run_purpose AS ENUM (
    'production', 'test', 'validation', 'audit_rerun'
);

-- v1 free-text columns promoted to enums (real closed value sets).
CREATE TYPE governance.version_change_type AS ENUM ('major', 'minor', 'patch');

CREATE TYPE governance.decision_log_detail AS ENUM ('minimal', 'standard', 'verbose');

CREATE TYPE governance.tool_transport AS ENUM (
    'python_inprocess', 'mcp', 'http'
);

-- Source/Target Binding kinds (binding-grammar.md + equity-research-slice).
-- source_kind: where an input is resolved from before the entity runs.
CREATE TYPE governance.source_kind AS ENUM (
    'vault', 'task_output', 'structured'
);
-- The v1 source_binding.binding_kind payload-shape vocabulary (text|content_blocks).
CREATE TYPE governance.source_payload_kind AS ENUM ('text', 'content_blocks');
-- target_kind: where an output is written after the entity runs.
CREATE TYPE governance.target_kind AS ENUM (
    'vault', 'task_output', 'structured'
);
CREATE TYPE governance.binding_owner_kind AS ENUM ('task_version', 'agent_version');

-- AUTH enums (user-authentication.md). platform_role = v1 studio_role VERBATIM.
CREATE TYPE governance.platform_role AS ENUM (
    'business_owner', 'compliance', 'legal', 'model_risk', 'ai_governance',
    'security', 'privacy', 'engineer', 'auditor', 'viewer'
);
CREATE TYPE governance.app_team_role AS ENUM (
    'app_demo_owner', 'app_demo_sre', 'app_demo_dev', 'app_demo_lead', 'app_demo_ops'
);

-- PACKAGES & DEPLOYMENT enums (ADR-0006).
CREATE TYPE governance.package_kind AS ENUM ('vtx', 'vax');   -- .vtx task / .vax agent
CREATE TYPE governance.deployment_action AS ENUM (
    'deploy_nonprod', 'deploy_prod', 'promote_champion',
    'lock_deprecated', 'cleanup_deprecated'
);
CREATE TYPE governance.deployment_outcome AS ENUM ('succeeded', 'failed', 'refused');
CREATE TYPE governance.deployment_run_mode AS ENUM ('live', 'read_only', 'ab_slice');

-- ============================================================================
-- MODEL REGISTRY (referenced by inference_config; included in this domain)
-- ============================================================================

CREATE TABLE governance.model (
    model_id        uuid        NOT NULL DEFAULT uuidv7(),
    provider        text        NOT NULL,
    provider_model_id text      NOT NULL,             -- v1 model.model_id (the vendor string)
    display_name    text        NOT NULL,
    modality        text        NOT NULL DEFAULT 'chat',
    context_window  integer,
    status          text        NOT NULL DEFAULT 'active',
    description     text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_model PRIMARY KEY (model_id),
    CONSTRAINT uq_model_provider_model UNIQUE (provider, provider_model_id),
    CONSTRAINT ck_model_status_known CHECK (status IN ('active', 'deprecated', 'retired'))
);
CREATE INDEX ix_model_provider ON governance.model (provider);
CREATE INDEX ix_model_status ON governance.model (status);
COMMENT ON TABLE governance.model IS 'tier:1 model registry (system-of-record)';

CREATE TABLE governance.model_price (
    model_price_id        uuid          NOT NULL DEFAULT uuidv7(),
    model_id              uuid          NOT NULL,
    input_price_per_1m    numeric(14,6) NOT NULL,
    output_price_per_1m   numeric(14,6) NOT NULL,
    cache_read_price_per_1m  numeric(14,6),
    cache_write_price_per_1m numeric(14,6),
    currency              text          NOT NULL DEFAULT 'USD',
    valid_from            timestamptz   NOT NULL,
    valid_to              timestamptz,
    notes                 text,
    created_at            timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_model_price PRIMARY KEY (model_price_id),
    CONSTRAINT fk_model_price_model
        FOREIGN KEY (model_id) REFERENCES governance.model (model_id) ON DELETE RESTRICT,
    CONSTRAINT ck_model_price_window CHECK (valid_to IS NULL OR valid_to >= valid_from)
);
CREATE INDEX ix_model_price_lookup ON governance.model_price (model_id, valid_from DESC);
CREATE UNIQUE INDEX uq_model_price_active
    ON governance.model_price (model_id) WHERE valid_to IS NULL;
COMMENT ON TABLE governance.model_price IS 'tier:1 price history; one open (valid_to NULL) row per model';

-- ============================================================================
-- INFERENCE CONFIG (single-row config registry)
-- ============================================================================

CREATE TABLE governance.inference_config (
    inference_config_id uuid        NOT NULL DEFAULT uuidv7(),
    name            text            NOT NULL,
    display_name    text            NOT NULL,
    description     text            NOT NULL,
    intended_use    text            NOT NULL,
    model_id        uuid,                            -- FK to model registry (v1 added post-create)
    model_name      text            NOT NULL DEFAULT 'claude-sonnet-4-20250514',
    temperature     numeric(4,3),
    max_tokens      integer,
    top_p           numeric(4,3),
    top_k           integer,
    stop_sequences  text[],
    extended_params jsonb           NOT NULL DEFAULT '{}'::jsonb,
    is_active       boolean         NOT NULL DEFAULT true,
    created_at      timestamptz     NOT NULL DEFAULT now(),
    updated_at      timestamptz     NOT NULL DEFAULT now(),
    CONSTRAINT pk_inference_config PRIMARY KEY (inference_config_id),
    CONSTRAINT uq_inference_config_name UNIQUE (name),
    CONSTRAINT fk_inference_config_model
        FOREIGN KEY (model_id) REFERENCES governance.model (model_id) ON DELETE RESTRICT,
    CONSTRAINT ck_inference_config_temperature CHECK (temperature IS NULL OR temperature BETWEEN 0 AND 2),
    CONSTRAINT ck_inference_config_top_p CHECK (top_p IS NULL OR top_p BETWEEN 0 AND 1),
    CONSTRAINT ck_inference_config_max_tokens CHECK (max_tokens IS NULL OR max_tokens > 0)
);
COMMENT ON TABLE governance.inference_config IS 'tier:1 inference config registry (mutable settings table)';

-- ============================================================================
-- ENTITY HEADERS: agent / task / prompt
-- ============================================================================

CREATE TABLE governance.agent (
    agent_id        uuid             NOT NULL DEFAULT uuidv7(),
    name            text             NOT NULL,
    display_name    text             NOT NULL,
    description     text             NOT NULL,
    description_embedding        vector(1536),
    description_embedding_model  text,
    last_similarity_check_at     timestamptz,
    similarity_flags jsonb           NOT NULL DEFAULT '[]'::jsonb,
    purpose         text             NOT NULL,
    domain          text             NOT NULL DEFAULT 'underwriting',
    materiality_tier governance.materiality_tier NOT NULL,
    owner_name      text             NOT NULL,
    owner_email     text,
    business_context text,
    known_limitations text,
    regulatory_notes text,
    current_champion_version_id uuid,               -- soft pointer; FK declared after agent_version
    created_at      timestamptz      NOT NULL DEFAULT now(),
    updated_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_agent PRIMARY KEY (agent_id),
    CONSTRAINT uq_agent_name UNIQUE (name)
);
CREATE INDEX ix_agent_materiality_tier ON governance.agent (materiality_tier);
COMMENT ON TABLE governance.agent IS 'tier:1 agent header (system-of-record)';

CREATE TABLE governance.task (
    task_id         uuid             NOT NULL DEFAULT uuidv7(),
    name            text             NOT NULL,
    display_name    text             NOT NULL,
    description     text             NOT NULL,
    description_embedding        vector(1536),
    description_embedding_model  text,
    last_similarity_check_at     timestamptz,
    similarity_flags jsonb           NOT NULL DEFAULT '[]'::jsonb,
    capability_type governance.capability_type NOT NULL,
    purpose         text             NOT NULL,
    domain          text             NOT NULL DEFAULT 'underwriting',
    materiality_tier governance.materiality_tier NOT NULL,
    input_schema    jsonb            NOT NULL,
    output_schema   jsonb            NOT NULL,
    owner_name      text             NOT NULL,
    owner_email     text,
    business_context text,
    known_limitations text,
    regulatory_notes text,
    current_champion_version_id uuid,               -- soft pointer; FK declared after task_version
    created_at      timestamptz      NOT NULL DEFAULT now(),
    updated_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_task PRIMARY KEY (task_id),
    CONSTRAINT uq_task_name UNIQUE (name)
);
CREATE INDEX ix_task_capability_type ON governance.task (capability_type);
COMMENT ON TABLE governance.task IS 'tier:1 task header (system-of-record)';

CREATE TABLE governance.prompt (
    prompt_id           uuid        NOT NULL DEFAULT uuidv7(),
    name                text        NOT NULL,
    display_name        text        NOT NULL,
    description         text        NOT NULL,
    primary_entity_type governance.entity_type,
    primary_entity_id   uuid,                        -- soft polymorphic pointer (app-validated)
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_prompt PRIMARY KEY (prompt_id),
    CONSTRAINT uq_prompt_name UNIQUE (name)
);
COMMENT ON TABLE governance.prompt IS 'tier:1 prompt header (system-of-record)';

-- ============================================================================
-- IMMUTABLE VERSIONS with SCD-2 temporal windows (valid_from/valid_to)
-- ============================================================================

CREATE TABLE governance.agent_version (
    agent_version_id uuid            NOT NULL DEFAULT uuidv7(),
    agent_id        uuid             NOT NULL,
    major_version   integer          NOT NULL DEFAULT 1,
    minor_version   integer          NOT NULL DEFAULT 0,
    patch_version   integer          NOT NULL DEFAULT 0,
    version_label   text             GENERATED ALWAYS AS
        (major_version || '.' || minor_version || '.' || patch_version) STORED,
    lifecycle_state governance.lifecycle_state   NOT NULL DEFAULT 'draft',
    channel         governance.deployment_channel NOT NULL DEFAULT 'development',
    inference_config_id uuid         NOT NULL,
    input_schema    jsonb            NOT NULL DEFAULT '{}'::jsonb,
    output_schema   jsonb,
    authority_thresholds jsonb       NOT NULL DEFAULT '{}'::jsonb,
    mock_mode_enabled boolean        NOT NULL DEFAULT false,
    decision_log_detail governance.decision_log_detail NOT NULL DEFAULT 'standard',
    shadow_traffic_pct      numeric(5,4) NOT NULL DEFAULT 0,
    challenger_traffic_pct  numeric(5,4) NOT NULL DEFAULT 0,
    staging_tests_passed    boolean,
    ground_truth_passed     boolean,
    fairness_passed         boolean,
    shadow_period_complete  boolean   NOT NULL DEFAULT false,
    challenger_period_complete boolean NOT NULL DEFAULT false,
    developer_name  text,
    change_summary  text,
    limitations_this_version text,
    change_type     governance.version_change_type,
    cloned_from_version_id uuid,
    valid_from      timestamptz,
    valid_to        timestamptz,
    created_at      timestamptz      NOT NULL DEFAULT now(),
    updated_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_agent_version PRIMARY KEY (agent_version_id),
    CONSTRAINT fk_agent_version_agent
        FOREIGN KEY (agent_id) REFERENCES governance.agent (agent_id) ON DELETE RESTRICT,
    CONSTRAINT fk_agent_version_inference_config
        FOREIGN KEY (inference_config_id) REFERENCES governance.inference_config (inference_config_id) ON DELETE RESTRICT,
    CONSTRAINT fk_agent_version_cloned_from
        FOREIGN KEY (cloned_from_version_id) REFERENCES governance.agent_version (agent_version_id) ON DELETE SET NULL,
    CONSTRAINT uq_agent_version_semver UNIQUE (agent_id, major_version, minor_version, patch_version),
    CONSTRAINT ck_agent_version_shadow_pct CHECK (shadow_traffic_pct BETWEEN 0 AND 1),
    CONSTRAINT ck_agent_version_challenger_pct CHECK (challenger_traffic_pct BETWEEN 0 AND 1),
    CONSTRAINT ck_agent_version_temporal CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);
CREATE INDEX ix_agent_version_agent_id ON governance.agent_version (agent_id);
CREATE INDEX ix_agent_version_lifecycle_state ON governance.agent_version (lifecycle_state);
COMMENT ON TABLE governance.agent_version IS 'tier:1 immutable agent version (SCD-2 valid_from/valid_to)';

ALTER TABLE governance.agent
    ADD CONSTRAINT fk_agent_current_champion
        FOREIGN KEY (current_champion_version_id)
        REFERENCES governance.agent_version (agent_version_id) ON DELETE SET NULL;

CREATE TABLE governance.task_version (
    task_version_id uuid             NOT NULL DEFAULT uuidv7(),
    task_id         uuid             NOT NULL,
    major_version   integer          NOT NULL DEFAULT 1,
    minor_version   integer          NOT NULL DEFAULT 0,
    patch_version   integer          NOT NULL DEFAULT 0,
    version_label   text             GENERATED ALWAYS AS
        (major_version || '.' || minor_version || '.' || patch_version) STORED,
    lifecycle_state governance.lifecycle_state   NOT NULL DEFAULT 'draft',
    channel         governance.deployment_channel NOT NULL DEFAULT 'development',
    inference_config_id uuid         NOT NULL,
    output_schema   jsonb,
    mock_mode_enabled boolean        NOT NULL DEFAULT false,
    decision_log_detail governance.decision_log_detail NOT NULL DEFAULT 'standard',
    shadow_traffic_pct      numeric(5,4) NOT NULL DEFAULT 0,
    challenger_traffic_pct  numeric(5,4) NOT NULL DEFAULT 0,
    staging_tests_passed    boolean,
    ground_truth_passed     boolean,
    fairness_passed         boolean,
    developer_name  text,
    change_summary  text,
    change_type     governance.version_change_type,
    cloned_from_version_id uuid,
    valid_from      timestamptz,
    valid_to        timestamptz,
    created_at      timestamptz      NOT NULL DEFAULT now(),
    updated_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_task_version PRIMARY KEY (task_version_id),
    CONSTRAINT fk_task_version_task
        FOREIGN KEY (task_id) REFERENCES governance.task (task_id) ON DELETE RESTRICT,
    CONSTRAINT fk_task_version_inference_config
        FOREIGN KEY (inference_config_id) REFERENCES governance.inference_config (inference_config_id) ON DELETE RESTRICT,
    CONSTRAINT fk_task_version_cloned_from
        FOREIGN KEY (cloned_from_version_id) REFERENCES governance.task_version (task_version_id) ON DELETE SET NULL,
    CONSTRAINT uq_task_version_semver UNIQUE (task_id, major_version, minor_version, patch_version),
    CONSTRAINT ck_task_version_shadow_pct CHECK (shadow_traffic_pct BETWEEN 0 AND 1),
    CONSTRAINT ck_task_version_challenger_pct CHECK (challenger_traffic_pct BETWEEN 0 AND 1),
    CONSTRAINT ck_task_version_temporal CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);
CREATE INDEX ix_task_version_task_id ON governance.task_version (task_id);
CREATE INDEX ix_task_version_lifecycle_state ON governance.task_version (lifecycle_state);
COMMENT ON TABLE governance.task_version IS 'tier:1 immutable task version (SCD-2 valid_from/valid_to)';

ALTER TABLE governance.task
    ADD CONSTRAINT fk_task_current_champion
        FOREIGN KEY (current_champion_version_id)
        REFERENCES governance.task_version (task_version_id) ON DELETE SET NULL;

CREATE TABLE governance.prompt_version (
    prompt_version_id uuid           NOT NULL DEFAULT uuidv7(),
    prompt_id       uuid             NOT NULL,
    major_version   integer          NOT NULL DEFAULT 1,
    minor_version   integer          NOT NULL DEFAULT 0,
    patch_version   integer          NOT NULL DEFAULT 0,
    version_label   text             GENERATED ALWAYS AS
        (major_version || '.' || minor_version || '.' || patch_version) STORED,
    content         text             NOT NULL,
    template_variables text[]        NOT NULL DEFAULT '{}',
    api_role        governance.api_role        NOT NULL DEFAULT 'system',
    governance_tier governance.governance_tier NOT NULL DEFAULT 'behavioural',
    content_embedding       vector(1536),
    content_embedding_model text,
    lifecycle_state governance.lifecycle_state NOT NULL DEFAULT 'draft',
    change_summary  text             NOT NULL,
    sensitivity_level text           NOT NULL DEFAULT 'high',
    author_name     text,
    approved_by     text,
    approved_at     timestamptz,
    test_required   boolean          GENERATED ALWAYS AS (governance_tier = 'behavioural') STORED,
    staging_tests_passed boolean,
    cloned_from_version_id uuid,
    valid_from      timestamptz,
    valid_to        timestamptz,
    created_at      timestamptz      NOT NULL DEFAULT now(),
    updated_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_prompt_version PRIMARY KEY (prompt_version_id),
    CONSTRAINT fk_prompt_version_prompt
        FOREIGN KEY (prompt_id) REFERENCES governance.prompt (prompt_id) ON DELETE RESTRICT,
    CONSTRAINT fk_prompt_version_cloned_from
        FOREIGN KEY (cloned_from_version_id) REFERENCES governance.prompt_version (prompt_version_id) ON DELETE SET NULL,
    CONSTRAINT uq_prompt_version_semver UNIQUE (prompt_id, major_version, minor_version, patch_version),
    CONSTRAINT ck_prompt_version_temporal CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);
CREATE INDEX ix_prompt_version_prompt_id ON governance.prompt_version (prompt_id);
CREATE INDEX ix_prompt_version_lifecycle_state ON governance.prompt_version (lifecycle_state);
CREATE INDEX ix_prompt_version_governance_tier ON governance.prompt_version (governance_tier);
COMMENT ON TABLE governance.prompt_version IS 'tier:1 immutable prompt version (SCD-2 valid_from/valid_to)';

-- ============================================================================
-- PROMPT ASSIGNMENT (entity_version <-> prompt_version)
-- ============================================================================

CREATE TABLE governance.entity_prompt_assignment (
    entity_prompt_assignment_id uuid NOT NULL DEFAULT uuidv7(),
    entity_type     governance.entity_type NOT NULL,
    entity_version_id uuid           NOT NULL,        -- soft polymorphic pointer to agent_version/task_version
    prompt_version_id uuid           NOT NULL,
    api_role        governance.api_role        NOT NULL,
    governance_tier governance.governance_tier NOT NULL,
    execution_order integer          NOT NULL DEFAULT 1,
    is_required     boolean          NOT NULL DEFAULT true,
    condition_logic jsonb,
    created_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_entity_prompt_assignment PRIMARY KEY (entity_prompt_assignment_id),
    CONSTRAINT fk_entity_prompt_assignment_prompt_version
        FOREIGN KEY (prompt_version_id) REFERENCES governance.prompt_version (prompt_version_id) ON DELETE RESTRICT,
    CONSTRAINT uq_entity_prompt_assignment UNIQUE (entity_type, entity_version_id, prompt_version_id, api_role),
    CONSTRAINT ck_entity_prompt_assignment_entity_kind CHECK (entity_type IN ('agent', 'task'))
);
CREATE INDEX ix_entity_prompt_assignment_entity ON governance.entity_prompt_assignment (entity_type, entity_version_id);
COMMENT ON TABLE governance.entity_prompt_assignment IS 'tier:1 prompt-to-entity-version assignment';

-- ============================================================================
-- MCP SERVERS, TOOLS, DATA CONNECTORS (single-row registries)
-- ============================================================================

CREATE TABLE governance.mcp_server (
    mcp_server_id   uuid        NOT NULL DEFAULT uuidv7(),
    name            text        NOT NULL,
    display_name    text        NOT NULL,
    description     text,
    transport       text        NOT NULL,
    command         text,
    args            text[]      NOT NULL DEFAULT '{}',
    url             text,
    env             jsonb       NOT NULL DEFAULT '{}'::jsonb,
    auth_config     jsonb       NOT NULL DEFAULT '{}'::jsonb,
    is_active       boolean     NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_mcp_server PRIMARY KEY (mcp_server_id),
    CONSTRAINT uq_mcp_server_name UNIQUE (name)
);
COMMENT ON TABLE governance.mcp_server IS 'tier:1 MCP server registry';

CREATE TABLE governance.tool (
    tool_id         uuid             NOT NULL DEFAULT uuidv7(),
    name            text             NOT NULL,
    display_name    text             NOT NULL,
    description     text             NOT NULL,
    description_embedding        vector(1536),
    description_embedding_model  text,
    last_similarity_check_at     timestamptz,
    similarity_flags jsonb           NOT NULL DEFAULT '[]'::jsonb,
    input_schema    jsonb            NOT NULL,
    output_schema   jsonb            NOT NULL,
    transport       governance.tool_transport NOT NULL DEFAULT 'python_inprocess',
    mcp_server_id   uuid,                            -- hardened: FK to mcp_server_id (v1 keyed on name)
    mcp_tool_name   text,
    implementation_path text         NOT NULL,
    mock_mode_enabled boolean        NOT NULL DEFAULT true,
    mock_response_key text,
    mock_responses  jsonb            NOT NULL DEFAULT '{}'::jsonb,
    data_classification_max governance.data_classification NOT NULL DEFAULT 'tier3_confidential',
    is_write_operation boolean       NOT NULL DEFAULT false,
    requires_confirmation boolean    NOT NULL DEFAULT false,
    tags            text[]           NOT NULL DEFAULT '{}',
    is_active       boolean          NOT NULL DEFAULT true,
    created_at      timestamptz      NOT NULL DEFAULT now(),
    updated_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_tool PRIMARY KEY (tool_id),
    CONSTRAINT uq_tool_name UNIQUE (name),
    CONSTRAINT fk_tool_mcp_server
        FOREIGN KEY (mcp_server_id) REFERENCES governance.mcp_server (mcp_server_id) ON DELETE RESTRICT,
    CONSTRAINT ck_tool_mcp_pairing
        CHECK (transport <> 'mcp' OR (mcp_server_id IS NOT NULL AND mcp_tool_name IS NOT NULL))
);
COMMENT ON TABLE governance.tool IS 'tier:1 tool registry (agent-only capability per binding-grammar)';

CREATE TABLE governance.data_connector (
    data_connector_id uuid        NOT NULL DEFAULT uuidv7(),
    name            text          NOT NULL,
    connector_type  text          NOT NULL,
    display_name    text          NOT NULL,
    description     text,
    config          jsonb         NOT NULL DEFAULT '{}'::jsonb,
    owner_name      text,
    created_at      timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_data_connector PRIMARY KEY (data_connector_id),
    CONSTRAINT uq_data_connector_name UNIQUE (name)
);
COMMENT ON TABLE governance.data_connector IS 'tier:1 data connector registry';

-- ============================================================================
-- VERSION->TOOL AUTHORIZATION (agent-only; task_version_tool kept for parity/no-loss)
-- ============================================================================

CREATE TABLE governance.agent_version_tool (
    agent_version_tool_id uuid       NOT NULL DEFAULT uuidv7(),
    agent_version_id uuid            NOT NULL,
    tool_id         uuid             NOT NULL,
    is_authorized   boolean          NOT NULL DEFAULT true,
    notes           text,
    created_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_agent_version_tool PRIMARY KEY (agent_version_tool_id),
    CONSTRAINT fk_agent_version_tool_version
        FOREIGN KEY (agent_version_id) REFERENCES governance.agent_version (agent_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_agent_version_tool_tool
        FOREIGN KEY (tool_id) REFERENCES governance.tool (tool_id) ON DELETE RESTRICT,
    CONSTRAINT uq_agent_version_tool UNIQUE (agent_version_id, tool_id)
);
CREATE INDEX ix_agent_version_tool_version ON governance.agent_version_tool (agent_version_id);
CREATE INDEX ix_agent_version_tool_tool ON governance.agent_version_tool (tool_id);
COMMENT ON TABLE governance.agent_version_tool IS 'tier:1 agent-version tool authorization';

CREATE TABLE governance.task_version_tool (
    task_version_tool_id uuid        NOT NULL DEFAULT uuidv7(),
    task_version_id uuid             NOT NULL,
    tool_id         uuid             NOT NULL,
    is_authorized   boolean          NOT NULL DEFAULT true,
    notes           text,
    created_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_task_version_tool PRIMARY KEY (task_version_tool_id),
    CONSTRAINT fk_task_version_tool_version
        FOREIGN KEY (task_version_id) REFERENCES governance.task_version (task_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_task_version_tool_tool
        FOREIGN KEY (tool_id) REFERENCES governance.tool (tool_id) ON DELETE RESTRICT,
    CONSTRAINT uq_task_version_tool UNIQUE (task_version_id, tool_id)
);
CREATE INDEX ix_task_version_tool_version ON governance.task_version_tool (task_version_id);
COMMENT ON TABLE governance.task_version_tool IS 'tier:1 KEPT for no-silent-loss; binding-grammar makes tools agent-only (DEFER deprecation)';

-- ============================================================================
-- SOURCE BINDING / TARGET BINDING (v2 grammar; retire v1 source_binding/write_target)
-- Apply uniformly to task_version and agent_version (agent binder parity).
-- ============================================================================

CREATE TABLE governance.source_binding (
    source_binding_id uuid          NOT NULL DEFAULT uuidv7(),
    owner_kind      governance.binding_owner_kind NOT NULL,
    owner_id        uuid            NOT NULL,         -- soft polymorphic to *_version (app-validated by owner_kind)
    template_var    text            NOT NULL,
    reference       text            NOT NULL,
    source_kind     governance.source_kind         NOT NULL DEFAULT 'structured',
    source_payload_kind governance.source_payload_kind NOT NULL DEFAULT 'text',
    is_required     boolean         NOT NULL DEFAULT true,
    execution_order integer         NOT NULL DEFAULT 1,
    description     text,
    created_at      timestamptz     NOT NULL DEFAULT now(),
    CONSTRAINT pk_source_binding PRIMARY KEY (source_binding_id),
    CONSTRAINT uq_source_binding_owner_var UNIQUE (owner_kind, owner_id, template_var)
);
CREATE INDEX ix_source_binding_owner ON governance.source_binding (owner_kind, owner_id);
COMMENT ON TABLE governance.source_binding IS 'tier:1 Source Binding (renamed from v1 source_binding); declarative input resolution; v1 binding_kind -> source_payload_kind, new source_kind enum';

CREATE TABLE governance.target_binding (
    target_binding_id uuid          NOT NULL DEFAULT uuidv7(),
    owner_kind      governance.binding_owner_kind NOT NULL,
    owner_id        uuid            NOT NULL,         -- soft polymorphic to *_version
    name            text            NOT NULL,
    target_kind     governance.target_kind NOT NULL DEFAULT 'structured',
    data_connector_id uuid,                           -- nullable: structured/task_output targets need no connector
    write_method    text,
    container       text,
    is_required     boolean         NOT NULL DEFAULT false,
    execution_order integer         NOT NULL DEFAULT 1,
    description     text,
    created_at      timestamptz     NOT NULL DEFAULT now(),
    CONSTRAINT pk_target_binding PRIMARY KEY (target_binding_id),
    CONSTRAINT fk_target_binding_data_connector
        FOREIGN KEY (data_connector_id) REFERENCES governance.data_connector (data_connector_id) ON DELETE RESTRICT,
    CONSTRAINT uq_target_binding_owner_name UNIQUE (owner_kind, owner_id, name),
    CONSTRAINT ck_target_binding_vault_connector
        CHECK (target_kind <> 'vault' OR data_connector_id IS NOT NULL)
);
CREATE INDEX ix_target_binding_owner ON governance.target_binding (owner_kind, owner_id);
COMMENT ON TABLE governance.target_binding IS 'tier:1 Target Binding (renamed from v1 write_target); declarative output write';

CREATE TABLE governance.target_payload_field (
    target_payload_field_id uuid    NOT NULL DEFAULT uuidv7(),
    target_binding_id uuid          NOT NULL,         -- renamed from v1 write_target_id
    payload_field   text            NOT NULL,
    reference       text            NOT NULL,
    is_required     boolean         NOT NULL DEFAULT true,
    execution_order integer         NOT NULL DEFAULT 1,
    description     text,
    created_at      timestamptz     NOT NULL DEFAULT now(),
    CONSTRAINT pk_target_payload_field PRIMARY KEY (target_payload_field_id),
    CONSTRAINT fk_target_payload_field_target_binding
        FOREIGN KEY (target_binding_id) REFERENCES governance.target_binding (target_binding_id) ON DELETE CASCADE,
    CONSTRAINT uq_target_payload_field UNIQUE (target_binding_id, payload_field)
);
CREATE INDEX ix_target_payload_field_target ON governance.target_payload_field (target_binding_id);
COMMENT ON TABLE governance.target_payload_field IS 'tier:1 per-field payload mapping for a Target Binding';

-- ============================================================================
-- LEGACY I/O GRAMMAR (task_version_source / task_version_target)
-- KEPT for no-silent-loss; superseded by source_binding/target_binding (DEFER retire).
-- ============================================================================

CREATE TABLE governance.task_version_source (
    task_version_source_id uuid     NOT NULL DEFAULT uuidv7(),
    task_version_id uuid            NOT NULL,
    input_field_name text           NOT NULL,
    data_connector_id uuid          NOT NULL,
    fetch_method    text            NOT NULL,
    maps_to_template_var text       NOT NULL,
    is_required     boolean         NOT NULL DEFAULT true,
    execution_order integer         NOT NULL DEFAULT 1,
    description     text,
    created_at      timestamptz     NOT NULL DEFAULT now(),
    CONSTRAINT pk_task_version_source PRIMARY KEY (task_version_source_id),
    CONSTRAINT fk_task_version_source_version
        FOREIGN KEY (task_version_id) REFERENCES governance.task_version (task_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_task_version_source_connector
        FOREIGN KEY (data_connector_id) REFERENCES governance.data_connector (data_connector_id) ON DELETE RESTRICT,
    CONSTRAINT uq_task_version_source_field UNIQUE (task_version_id, input_field_name),
    CONSTRAINT uq_task_version_source_var UNIQUE (task_version_id, maps_to_template_var)
);
CREATE INDEX ix_task_version_source_version ON governance.task_version_source (task_version_id);
COMMENT ON TABLE governance.task_version_source IS 'tier:1 KEPT for no-silent-loss; superseded by source_binding (DEFER retire after migration)';

CREATE TABLE governance.task_version_target (
    task_version_target_id uuid     NOT NULL DEFAULT uuidv7(),
    task_version_id uuid            NOT NULL,
    output_field_name text          NOT NULL,
    data_connector_id uuid          NOT NULL,
    write_method    text            NOT NULL,
    target_container text,
    is_required     boolean         NOT NULL DEFAULT false,
    execution_order integer         NOT NULL DEFAULT 1,
    description     text,
    created_at      timestamptz     NOT NULL DEFAULT now(),
    CONSTRAINT pk_task_version_target PRIMARY KEY (task_version_target_id),
    CONSTRAINT fk_task_version_target_version
        FOREIGN KEY (task_version_id) REFERENCES governance.task_version (task_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_task_version_target_connector
        FOREIGN KEY (data_connector_id) REFERENCES governance.data_connector (data_connector_id) ON DELETE RESTRICT,
    CONSTRAINT uq_task_version_target_field UNIQUE (task_version_id, output_field_name)
);
CREATE INDEX ix_task_version_target_version ON governance.task_version_target (task_version_id);
COMMENT ON TABLE governance.task_version_target IS 'tier:1 KEPT for no-silent-loss; superseded by target_binding (DEFER retire after migration)';

-- ============================================================================
-- DELEGATIONS (agent_version -> agent_version)
-- ============================================================================

CREATE TABLE governance.agent_version_delegation (
    agent_version_delegation_id uuid NOT NULL DEFAULT uuidv7(),
    parent_agent_version_id uuid     NOT NULL,
    child_agent_name text,
    child_agent_version_id uuid,
    scope           jsonb            NOT NULL DEFAULT '{}'::jsonb,
    is_authorized   boolean          NOT NULL DEFAULT true,
    rationale       text,
    notes           text,
    created_at      timestamptz      NOT NULL DEFAULT now(),
    updated_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_agent_version_delegation PRIMARY KEY (agent_version_delegation_id),
    CONSTRAINT fk_agent_version_delegation_parent
        FOREIGN KEY (parent_agent_version_id) REFERENCES governance.agent_version (agent_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_agent_version_delegation_child
        FOREIGN KEY (child_agent_version_id) REFERENCES governance.agent_version (agent_version_id) ON DELETE SET NULL,
    CONSTRAINT uq_agent_version_delegation UNIQUE (parent_agent_version_id, child_agent_name, child_agent_version_id),
    CONSTRAINT ck_agent_version_delegation_child_target
        CHECK ((child_agent_name IS NOT NULL) <> (child_agent_version_id IS NOT NULL))
);
CREATE INDEX ix_agent_version_delegation_parent ON governance.agent_version_delegation (parent_agent_version_id);
CREATE INDEX ix_agent_version_delegation_child_name ON governance.agent_version_delegation (child_agent_name);
CREATE INDEX ix_agent_version_delegation_child_version ON governance.agent_version_delegation (child_agent_version_id);
COMMENT ON TABLE governance.agent_version_delegation IS 'tier:1 agent-to-agent delegation grant';

-- ============================================================================
-- APPLICATION & APPLICATION_ENTITY (ownership grouping)
-- ============================================================================

CREATE TABLE governance.application (
    application_id  uuid        NOT NULL DEFAULT uuidv7(),
    name            text        NOT NULL,
    display_name    text        NOT NULL,
    description     text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_application PRIMARY KEY (application_id),
    CONSTRAINT uq_application_name UNIQUE (name)
);
COMMENT ON TABLE governance.application IS 'tier:1 application registry';

CREATE TABLE governance.application_entity (
    application_entity_id uuid      NOT NULL DEFAULT uuidv7(),
    application_id  uuid            NOT NULL,
    entity_type     governance.entity_type NOT NULL,
    entity_id       uuid            NOT NULL,          -- soft polymorphic pointer (app-validated)
    created_at      timestamptz     NOT NULL DEFAULT now(),
    CONSTRAINT pk_application_entity PRIMARY KEY (application_entity_id),
    CONSTRAINT fk_application_entity_application
        FOREIGN KEY (application_id) REFERENCES governance.application (application_id) ON DELETE CASCADE,
    CONSTRAINT uq_application_entity UNIQUE (application_id, entity_type, entity_id)
);
CREATE INDEX ix_application_entity_application ON governance.application_entity (application_id);
CREATE INDEX ix_application_entity_entity ON governance.application_entity (entity_type, entity_id);
COMMENT ON TABLE governance.application_entity IS 'tier:1 application-to-entity ownership';

-- ============================================================================
-- AUTH (v2-new; user-authentication.md). 'user' is reserved -> account_user.
-- ============================================================================

CREATE TABLE governance.account_user (
    account_user_id uuid        NOT NULL DEFAULT uuidv7(),
    tenant_id       uuid        NOT NULL,             -- Entra tid
    microsoft_oid   uuid        NOT NULL,             -- Entra oid (immutable per tenant)
    display_name    text        NOT NULL,
    email           text,
    upn             text,
    session_epoch   integer     NOT NULL DEFAULT 0,   -- bumped on any role change
    disabled_at     timestamptz,                       -- non-null => fail closed
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_account_user PRIMARY KEY (account_user_id),
    CONSTRAINT uq_account_user_tenant_oid UNIQUE (tenant_id, microsoft_oid)
);
COMMENT ON TABLE governance.account_user IS 'tier:1 identity principal; natural key (tenant_id, microsoft_oid)';

CREATE TABLE governance.platform_role_grant (
    platform_role_grant_id uuid     NOT NULL DEFAULT uuidv7(),
    account_user_id uuid            NOT NULL,
    role            governance.platform_role NOT NULL,
    is_revocation   boolean         NOT NULL DEFAULT false,
    granted_by      uuid            NOT NULL,          -- server-resolved actor
    reason          text,
    granted_at      timestamptz     NOT NULL DEFAULT now(),
    CONSTRAINT pk_platform_role_grant PRIMARY KEY (platform_role_grant_id),
    CONSTRAINT fk_platform_role_grant_user
        FOREIGN KEY (account_user_id) REFERENCES governance.account_user (account_user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_platform_role_grant_actor
        FOREIGN KEY (granted_by) REFERENCES governance.account_user (account_user_id) ON DELETE RESTRICT
);
CREATE INDEX ix_platform_role_grant_latest
    ON governance.platform_role_grant (account_user_id, role, granted_at DESC);
COMMENT ON TABLE governance.platform_role_grant IS 'tier:1 APPEND-ONLY platform role grant; revoke = new event; current = view over latest';

CREATE TABLE governance.app_team_role_grant (
    app_team_role_grant_id uuid     NOT NULL DEFAULT uuidv7(),
    account_user_id uuid            NOT NULL,
    application_id  uuid            NOT NULL,
    role            governance.app_team_role NOT NULL,
    is_revocation   boolean         NOT NULL DEFAULT false,
    granted_by      uuid            NOT NULL,
    reason          text,
    granted_at      timestamptz     NOT NULL DEFAULT now(),
    CONSTRAINT pk_app_team_role_grant PRIMARY KEY (app_team_role_grant_id),
    CONSTRAINT fk_app_team_role_grant_user
        FOREIGN KEY (account_user_id) REFERENCES governance.account_user (account_user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_app_team_role_grant_application
        FOREIGN KEY (application_id) REFERENCES governance.application (application_id) ON DELETE RESTRICT,
    CONSTRAINT fk_app_team_role_grant_actor
        FOREIGN KEY (granted_by) REFERENCES governance.account_user (account_user_id) ON DELETE RESTRICT
);
CREATE INDEX ix_app_team_role_grant_latest
    ON governance.app_team_role_grant (application_id, account_user_id, role, granted_at DESC);
COMMENT ON TABLE governance.app_team_role_grant IS 'tier:1 APPEND-ONLY per-application role grant';

-- auth_event: Tier-2, append-only, month-range-partitioned, BRIN on time.
-- No FK to account_user (cross-tier hot-path); integrity enforced at API layer.
CREATE TABLE governance.auth_event (
    auth_event_id   uuid        NOT NULL DEFAULT uuidv7(),
    event_type      text        NOT NULL,             -- login|logout|session_expiry|authz_denial
    outcome         text        NOT NULL,             -- success|failure|denied
    reason_code     text,
    account_user_id uuid,                              -- nullable for pre-identity failures
    action_code     text,
    resource        text,
    request_id      text        NOT NULL,
    ip              inet,
    created_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_auth_event PRIMARY KEY (auth_event_id, created_at)
) PARTITION BY RANGE (created_at);
CREATE TABLE governance.auth_event_2026_05 PARTITION OF governance.auth_event
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE governance.auth_event_2026_06 PARTITION OF governance.auth_event
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE INDEX ix_auth_event_user_time ON governance.auth_event (account_user_id, created_at DESC);
CREATE INDEX brin_auth_event_created_at ON governance.auth_event USING brin (created_at);
COMMENT ON TABLE governance.auth_event IS 'tier:2 bulk-log append-only; month-partitioned; BRIN on created_at';

-- Current-role projections (views over latest grant event; read from PRIMARY).
CREATE VIEW governance.current_platform_role AS
SELECT DISTINCT ON (account_user_id, role)
       account_user_id, role, is_revocation, granted_at
FROM   governance.platform_role_grant
ORDER  BY account_user_id, role, granted_at DESC;
COMMENT ON VIEW governance.current_platform_role IS 'effective roles = rows where is_revocation = false';

CREATE VIEW governance.current_app_team_role AS
SELECT DISTINCT ON (application_id, account_user_id, role)
       application_id, account_user_id, role, is_revocation, granted_at
FROM   governance.app_team_role_grant
ORDER  BY application_id, account_user_id, role, granted_at DESC;
COMMENT ON VIEW governance.current_app_team_role IS 'effective app-team roles = rows where is_revocation = false';

-- ============================================================================
-- PACKAGES & DEPLOYMENT (v2-new; ADR-0006)
-- ============================================================================

CREATE TABLE governance.harness_image (
    harness_image_id uuid        NOT NULL DEFAULT uuidv7(),
    repository      text          NOT NULL,            -- e.g. registry/verity-harness
    digest          text          NOT NULL,            -- immutable content digest (sha256:...)
    tag             text,                               -- advisory only; never used for compatibility
    description     text,
    created_at      timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_harness_image PRIMARY KEY (harness_image_id),
    CONSTRAINT uq_harness_image_digest UNIQUE (repository, digest)
);
COMMENT ON TABLE governance.harness_image IS 'tier:1 harness image registry; compatibility pinned by digest (ADR-0006)';

CREATE TABLE governance.package (
    package_id      uuid          NOT NULL DEFAULT uuidv7(),
    package_kind    governance.package_kind NOT NULL,   -- vtx (task) / vax (agent)
    entity_type     governance.entity_type NOT NULL,    -- agent|task
    entity_version_id uuid        NOT NULL,             -- the versioned artifact this package wraps
    digest          text          NOT NULL,             -- package content digest
    manifest        jsonb         NOT NULL DEFAULT '{}'::jsonb,
    created_at      timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_package PRIMARY KEY (package_id),
    CONSTRAINT uq_package_digest UNIQUE (digest),
    CONSTRAINT ck_package_kind_entity
        CHECK ((package_kind = 'vtx' AND entity_type = 'task')
            OR (package_kind = 'vax' AND entity_type = 'agent'))
);
CREATE INDEX ix_package_entity ON governance.package (entity_type, entity_version_id);
COMMENT ON TABLE governance.package IS 'tier:1 package inventory (.vtx/.vax); entity_version_id is a soft polymorphic pointer (app/API-validated by entity_type)';

CREATE TABLE governance.package_harness_compatibility (
    package_harness_compatibility_id uuid NOT NULL DEFAULT uuidv7(),
    package_id      uuid          NOT NULL,
    harness_image_id uuid         NOT NULL,
    created_at      timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_package_harness_compatibility PRIMARY KEY (package_harness_compatibility_id),
    CONSTRAINT fk_package_harness_compat_package
        FOREIGN KEY (package_id) REFERENCES governance.package (package_id) ON DELETE CASCADE,
    CONSTRAINT fk_package_harness_compat_image
        FOREIGN KEY (harness_image_id) REFERENCES governance.harness_image (harness_image_id) ON DELETE RESTRICT,
    CONSTRAINT uq_package_harness_compatibility UNIQUE (package_id, harness_image_id)
);
COMMENT ON TABLE governance.package_harness_compatibility IS 'tier:1 declared package x harness-image compatibility (digest-pinned, ADR-0006)';

-- deployment: append-only, lifecycle-gated, actor/target/outcome.
CREATE TABLE governance.deployment (
    deployment_id   uuid          NOT NULL DEFAULT uuidv7(),
    package_id      uuid          NOT NULL,
    harness_image_id uuid         NOT NULL,
    lifecycle_state governance.lifecycle_state   NOT NULL,  -- state at deploy time (gates placement)
    cluster         text          NOT NULL,
    environment     text          NOT NULL,             -- non_prod | prod (+ ephemeral)
    run_mode        governance.deployment_run_mode NOT NULL,
    action          governance.deployment_action NOT NULL,
    outcome         governance.deployment_outcome NOT NULL,
    actor_account_user_id uuid    NOT NULL,
    detail          jsonb         NOT NULL DEFAULT '{}'::jsonb,
    created_at      timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment PRIMARY KEY (deployment_id),
    CONSTRAINT fk_deployment_package
        FOREIGN KEY (package_id) REFERENCES governance.package (package_id) ON DELETE RESTRICT,
    CONSTRAINT fk_deployment_harness_image
        FOREIGN KEY (harness_image_id) REFERENCES governance.harness_image (harness_image_id) ON DELETE RESTRICT,
    CONSTRAINT fk_deployment_actor
        FOREIGN KEY (actor_account_user_id) REFERENCES governance.account_user (account_user_id) ON DELETE RESTRICT,
    CONSTRAINT ck_deployment_environment_known CHECK (environment IN ('non_prod', 'prod', 'ephemeral'))
);
CREATE INDEX ix_deployment_package ON governance.deployment (package_id, created_at DESC);
CREATE INDEX ix_deployment_cluster_env ON governance.deployment (cluster, environment, created_at DESC);
COMMENT ON TABLE governance.deployment IS 'tier:1 APPEND-ONLY deployment inventory; lifecycle-gated placement (ADR-0006)';

-- ============================================================================
-- DISPATCH (v2-new; PCR 3.3 transactional outbox)
-- ============================================================================

CREATE TABLE governance.run_dispatch_outbox (
    run_dispatch_outbox_id uuid    NOT NULL DEFAULT uuidv7(),
    execution_run_id uuid          NOT NULL,            -- FK target in runtime domain (declared cross-domain)
    subject         text           NOT NULL DEFAULT 'verity.runs.pending',
    payload         jsonb          NOT NULL,
    published_at    timestamptz,                         -- NULL = not yet relayed to NATS
    created_at      timestamptz    NOT NULL DEFAULT now(),
    CONSTRAINT pk_run_dispatch_outbox PRIMARY KEY (run_dispatch_outbox_id)
);
CREATE INDEX ix_run_dispatch_outbox_unpublished
    ON governance.run_dispatch_outbox (created_at) WHERE published_at IS NULL;
COMMENT ON TABLE governance.run_dispatch_outbox IS 'tier:1 APPEND-ONLY transactional outbox for run dispatch (PCR 3.3); inserted in same txn as execution_run; relay marks published_at. FK to runtime.execution_run added when runtime domain is hardened.';

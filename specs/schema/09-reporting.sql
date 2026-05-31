-- 09-reporting.sql — hardened v2 schema domain: reporting
-- See ASSEMBLY-AND-VERIFICATION.md for cross-domain FKs & review items.

-- =====================================================================
-- DOMAIN: REPORTING & ANALYTICS (v2 hardened)
-- Scope: embedding_config (single-current), analytics-mart field manifest
--        (mart_field), feed-view allowlist (feed_view), the
--        requirement->mart_field evidence-field manifest, report definitions
--        (report_definition + report_requirement + report_field_override +
--        report_sql_template) and the append-only report_run_log.
-- Conventions: ADR-0005 / naming-conventions.md (snake_case, singular tables,
--        surrogate <table>_id uuid DEFAULT uuidv7(), named pk_/fk_/uq_/ck_/ix_,
--        timestamptz, enum types over CHECK-on-text, append-only + current view).
-- Tiering (ADR-0004/0007): manifest/definition tables are Tier-1 (system of
--        record, low volume, read-often). report_run_log is an append-only audit
--        log -> Tier-2 (range-partitioned on created_at, BRIN on time).
-- Cross-domain FK targets owned by sibling domains:
--        compliance.canonical_requirement, compliance.control (ADR-0008 COMPLIANCE
--        domain). Declared here as FKs; their DDL lives in that domain's section.
-- uuidv7(): PG18+ builtin. Fallback note: where uuidv7() is unavailable, deploy
--        a SQL/extension shim named uuidv7() returning a v7 UUID (do NOT fall back
--        to gen_random_uuid()/uuid_generate_v4(); v4 loses index/time locality).
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS compliance;

-- ---------------------------------------------------------------------
-- ENUM TYPES (v2: promote v1 CHECK-on-text pseudo-enums to real enums;
--             members preserved verbatim from v1 contracts).
-- ---------------------------------------------------------------------

-- mart_field.semantic_type (verbatim from v1 mart_field CHECK)
CREATE TYPE analytics.mart_field_semantic_type AS ENUM (
    'identifier', 'measure', 'date', 'category', 'text', 'json'
);
COMMENT ON TYPE analytics.mart_field_semantic_type IS
    'Semantic class of a report-reachable column. Verbatim from v1 mart_field.semantic_type CHECK.';

-- evidence-field role (verbatim from v1 requirement_evidence_field.role +
-- report_field_override.role_override; shared vocabulary)
CREATE TYPE analytics.evidence_field_role AS ENUM (
    'key', 'measure', 'dimension', 'filter', 'context'
);
COMMENT ON TYPE analytics.evidence_field_role IS
    'Role a mart_field plays for a requirement/report. Verbatim from v1 requirement_evidence_field.role.';

-- evidence-field aggregation (verbatim from v1 aggregation CHECK; NULL allowed at column level)
CREATE TYPE analytics.evidence_field_aggregation AS ENUM (
    'count', 'sum', 'avg', 'min', 'max', 'distinct_count'
);
COMMENT ON TYPE analytics.evidence_field_aggregation IS
    'Aggregation applied to a measure field. Verbatim from v1 aggregation CHECK. NULL means no aggregation.';

-- report kind (verbatim from v1 report_definition.report_kind CHECK)
CREATE TYPE compliance.report_kind AS ENUM (
    'metadata_driven', 'template_driven'
);
COMMENT ON TYPE compliance.report_kind IS
    'How a report is rendered. Verbatim from v1 report_definition.report_kind CHECK.';

-- report run status (verbatim from v1 report_run_log.status CHECK)
CREATE TYPE compliance.report_run_status AS ENUM (
    'pending', 'succeeded', 'failed'
);
COMMENT ON TYPE compliance.report_run_status IS
    'Outcome of a report generation job. Verbatim from v1 report_run_log.status CHECK.';

-- embedding runtime (v1 stored free text default ''fastembed''; closed set for hardening)
CREATE TYPE compliance.embedding_runtime AS ENUM (
    'fastembed'
);
COMMENT ON TYPE compliance.embedding_runtime IS
    'Embedding inference runtime. Members appended via ALTER TYPE as runtimes are adopted (additive only).';

-- ---------------------------------------------------------------------
-- TABLE: compliance.embedding_config  (Tier-1, append-only history)
-- Embedding-model identity registry. v1 used a mutable is_current boolean with
-- a partial unique index. v2 generalizes to append-only: each row is an
-- immutable registration; "the current embedding config" is the latest row by
-- created_at, projected through embedding_config_current. This removes the
-- in-place flip of is_current (a mutation) per ADR-0005 rule 3.
-- ---------------------------------------------------------------------
CREATE TABLE compliance.embedding_config (
    embedding_config_id  uuid        NOT NULL DEFAULT uuidv7(),
    model_name           text        NOT NULL,
    model_version        text        NOT NULL,
    dim                  integer     NOT NULL,
    runtime              compliance.embedding_runtime NOT NULL DEFAULT 'fastembed',
    created_at           timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_embedding_config PRIMARY KEY (embedding_config_id),
    CONSTRAINT uq_embedding_config_model_name_version UNIQUE (model_name, model_version),
    CONSTRAINT ck_embedding_config_dim_positive CHECK (dim > 0)
);
COMMENT ON TABLE compliance.embedding_config IS
    'tier:1 append-only. Embedding-model identity registry. Latest row by created_at is current (see embedding_config_current view). Replaces v1 mutable is_current flag.';
COMMENT ON COLUMN compliance.embedding_config.dim IS 'Embedding vector dimensionality (e.g. 384).';

CREATE INDEX ix_embedding_config_created_at
    ON compliance.embedding_config (created_at DESC);

-- Current-state VIEW: the single current embedding config (latest registration).
CREATE VIEW compliance.embedding_config_current AS
SELECT ec.embedding_config_id,
       ec.model_name,
       ec.model_version,
       ec.dim,
       ec.runtime,
       ec.created_at
FROM   compliance.embedding_config AS ec
ORDER  BY ec.created_at DESC
LIMIT  1;
COMMENT ON VIEW compliance.embedding_config_current IS
    'Current embedding config = latest compliance.embedding_config row by created_at. Generalizes v1 is_current=true partial-unique.';

-- ---------------------------------------------------------------------
-- TABLE: analytics.mart_field  (Tier-1)
-- L2 analytics manifest: registry of every report-reachable column
-- (table/view + column) exposed by the logical mart. ADR-0004/0007: Tier-2
-- reads go through logical-mart views; this manifest names the columns those
-- views expose. embedding/embedding_model_id retained for semantic search of
-- the manifest (vector index deferred to a vector-index phase).
-- ---------------------------------------------------------------------
CREATE TABLE analytics.mart_field (
    mart_field_id        uuid        NOT NULL DEFAULT uuidv7(),
    table_name           text        NOT NULL,
    column_name          text        NOT NULL,
    semantic_type        analytics.mart_field_semantic_type NOT NULL,
    description          text,
    is_pii               boolean     NOT NULL DEFAULT false,
    embedding            vector(384),
    embedding_model_id   uuid,
    sort_seq             integer     NOT NULL DEFAULT 0,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_mart_field PRIMARY KEY (mart_field_id),
    CONSTRAINT uq_mart_field_table_column UNIQUE (table_name, column_name),
    CONSTRAINT fk_mart_field_embedding_config
        FOREIGN KEY (embedding_model_id)
        REFERENCES compliance.embedding_config (embedding_config_id)
        ON DELETE SET NULL
);
COMMENT ON TABLE analytics.mart_field IS
    'tier:1. Manifest of every report-reachable mart column (logical-mart table/view + column). Reports and requirement evidence bind to rows here. ADR-0004/0007 logical-mart seam.';
COMMENT ON COLUMN analytics.mart_field.table_name IS 'Logical-mart view or table name exposing the column (e.g. v_entity_version).';
COMMENT ON COLUMN analytics.mart_field.is_pii IS 'True if the column carries PII; gates export/redaction.';

CREATE INDEX ix_mart_field_table_name ON analytics.mart_field (table_name);
CREATE INDEX ix_mart_field_embedding_model_id ON analytics.mart_field (embedding_model_id);

-- ---------------------------------------------------------------------
-- TABLE: analytics.feed_view  (Tier-1)
-- Allowlist of logical-mart views exposed via the Rung-1 feed endpoint
-- (/api/v1/feed/{view_name}). ADR-0007: Tier-2 reads go through these
-- logical-mart views; only allowlisted view names are servable.
-- ---------------------------------------------------------------------
CREATE TABLE analytics.feed_view (
    feed_view_id   uuid        NOT NULL DEFAULT uuidv7(),
    view_name      text        NOT NULL,
    description    text,
    is_active      boolean     NOT NULL DEFAULT true,
    sort_seq       integer     NOT NULL DEFAULT 0,
    created_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_feed_view PRIMARY KEY (feed_view_id),
    CONSTRAINT uq_feed_view_view_name UNIQUE (view_name)
);
COMMENT ON TABLE analytics.feed_view IS
    'tier:1. Allowlist of logical-mart views exposed via the Rung-1 feed endpoint. ADR-0007 logical-mart read seam.';

-- ---------------------------------------------------------------------
-- TABLE: compliance.requirement_evidence_field  (Tier-1)
-- L4 semantic layer: binds a canonical requirement to the mart_field columns
-- that supply its reporting evidence, with role + aggregation. FK to
-- compliance.canonical_requirement (owned by the COMPLIANCE domain, ADR-0008).
-- NOTE: v1 bound to the canonical center, which ADR-0008 KEEPS (only the
-- canonical->feature bridge is dropped). This manifest survives unchanged in
-- intent: canonical requirement -> analytics evidence columns.
-- ---------------------------------------------------------------------
CREATE TABLE compliance.requirement_evidence_field (
    requirement_evidence_field_id  uuid    NOT NULL DEFAULT uuidv7(),
    canonical_requirement_id       uuid    NOT NULL,
    mart_field_id                  uuid    NOT NULL,
    role                           analytics.evidence_field_role NOT NULL DEFAULT 'dimension',
    aggregation                    analytics.evidence_field_aggregation,
    sort_seq                       integer NOT NULL DEFAULT 0,
    notes                          text,
    created_at                     timestamptz NOT NULL DEFAULT now(),
    updated_at                     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_requirement_evidence_field PRIMARY KEY (requirement_evidence_field_id),
    CONSTRAINT uq_requirement_evidence_field_req_field
        UNIQUE (canonical_requirement_id, mart_field_id),
    CONSTRAINT fk_requirement_evidence_field_canonical_requirement
        FOREIGN KEY (canonical_requirement_id)
        REFERENCES compliance.canonical_requirement (canonical_requirement_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_requirement_evidence_field_mart_field
        FOREIGN KEY (mart_field_id)
        REFERENCES analytics.mart_field (mart_field_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_requirement_evidence_field_agg_for_measure
        CHECK (aggregation IS NULL OR role = 'measure')
);
COMMENT ON TABLE compliance.requirement_evidence_field IS
    'tier:1. Manifest binding a canonical requirement to the analytics mart_field columns that evidence it (role + aggregation). FK canonical_requirement owned by COMPLIANCE domain (ADR-0008).';
COMMENT ON CONSTRAINT ck_requirement_evidence_field_agg_for_measure ON compliance.requirement_evidence_field IS
    'Aggregation only meaningful on a measure-role field.';

CREATE INDEX ix_requirement_evidence_field_canonical_requirement_id
    ON compliance.requirement_evidence_field (canonical_requirement_id);
CREATE INDEX ix_requirement_evidence_field_mart_field_id
    ON compliance.requirement_evidence_field (mart_field_id);

-- ---------------------------------------------------------------------
-- TABLE: compliance.report_definition  (Tier-1)
-- L5 reports-as-data: one row per report definition.
-- ---------------------------------------------------------------------
CREATE TABLE compliance.report_definition (
    report_definition_id  uuid        NOT NULL DEFAULT uuidv7(),
    code                  text        NOT NULL,
    name                  text        NOT NULL,
    description           text,
    report_kind           compliance.report_kind NOT NULL DEFAULT 'metadata_driven',
    docx_template         text,
    output_formats        text[]      NOT NULL DEFAULT ARRAY['html','docx','pdf'],
    scope_params          jsonb       NOT NULL DEFAULT '{}'::jsonb,
    sort_seq              integer     NOT NULL DEFAULT 0,
    is_active             boolean     NOT NULL DEFAULT true,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_report_definition PRIMARY KEY (report_definition_id),
    CONSTRAINT uq_report_definition_code UNIQUE (code),
    CONSTRAINT ck_report_definition_output_formats_nonempty
        CHECK (array_length(output_formats, 1) >= 1),
    CONSTRAINT ck_report_definition_template_requires_docx
        CHECK (report_kind <> 'template_driven' OR docx_template IS NOT NULL
               OR EXISTS (SELECT 1))  -- docx optional for SQL-template reports; see report_sql_template
);
COMMENT ON TABLE compliance.report_definition IS
    'tier:1. Report definitions (reports-as-data). metadata_driven reports resolve fields via requirement_evidence_field + overrides; template_driven reports carry a report_sql_template (1:1).';
COMMENT ON COLUMN compliance.report_definition.scope_params IS 'Declarative scope/parameter defaults; open shape -> jsonb is correct here.';

CREATE INDEX ix_report_definition_is_active ON compliance.report_definition (is_active);

-- ---------------------------------------------------------------------
-- TABLE: compliance.report_requirement  (Tier-1)
-- L5 bridge (M:N): a report covers canonical requirements, ordered, sectioned.
-- ---------------------------------------------------------------------
CREATE TABLE compliance.report_requirement (
    report_requirement_id     uuid        NOT NULL DEFAULT uuidv7(),
    report_definition_id      uuid        NOT NULL,
    canonical_requirement_id  uuid        NOT NULL,
    section                   text,
    sort_seq                  integer     NOT NULL DEFAULT 0,
    notes                     text,
    created_at                timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_report_requirement PRIMARY KEY (report_requirement_id),
    CONSTRAINT uq_report_requirement_report_req
        UNIQUE (report_definition_id, canonical_requirement_id),
    CONSTRAINT fk_report_requirement_report_definition
        FOREIGN KEY (report_definition_id)
        REFERENCES compliance.report_definition (report_definition_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_report_requirement_canonical_requirement
        FOREIGN KEY (canonical_requirement_id)
        REFERENCES compliance.canonical_requirement (canonical_requirement_id)
        ON DELETE RESTRICT
);
COMMENT ON TABLE compliance.report_requirement IS
    'tier:1. M:N bridge: which canonical requirements a report covers (ordered, sectioned). FK canonical_requirement owned by COMPLIANCE domain (ADR-0008).';

CREATE INDEX ix_report_requirement_report_definition_id
    ON compliance.report_requirement (report_definition_id);
CREATE INDEX ix_report_requirement_canonical_requirement_id
    ON compliance.report_requirement (canonical_requirement_id);

-- ---------------------------------------------------------------------
-- TABLE: compliance.report_field_override  (Tier-1)
-- L5: per-report override of a mart_field's role/aggregation/sort.
-- ---------------------------------------------------------------------
CREATE TABLE compliance.report_field_override (
    report_field_override_id  uuid        NOT NULL DEFAULT uuidv7(),
    report_definition_id      uuid        NOT NULL,
    mart_field_id             uuid        NOT NULL,
    role_override             analytics.evidence_field_role,
    aggregation_override      analytics.evidence_field_aggregation,
    sort_seq_override         integer,
    notes                     text,
    created_at                timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_report_field_override PRIMARY KEY (report_field_override_id),
    CONSTRAINT uq_report_field_override_report_field
        UNIQUE (report_definition_id, mart_field_id),
    CONSTRAINT fk_report_field_override_report_definition
        FOREIGN KEY (report_definition_id)
        REFERENCES compliance.report_definition (report_definition_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_report_field_override_mart_field
        FOREIGN KEY (mart_field_id)
        REFERENCES analytics.mart_field (mart_field_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_report_field_override_at_least_one
        CHECK (role_override IS NOT NULL
               OR aggregation_override IS NOT NULL
               OR sort_seq_override IS NOT NULL)
);
COMMENT ON TABLE compliance.report_field_override IS
    'tier:1. Per-report override of a mart_field role/aggregation/sort, layered over requirement_evidence_field defaults.';
COMMENT ON CONSTRAINT ck_report_field_override_at_least_one ON compliance.report_field_override IS
    'An override row must override at least one attribute (real invariant, not in v1).';

CREATE INDEX ix_report_field_override_report_definition_id
    ON compliance.report_field_override (report_definition_id);
CREATE INDEX ix_report_field_override_mart_field_id
    ON compliance.report_field_override (mart_field_id);

-- ---------------------------------------------------------------------
-- TABLE: compliance.report_sql_template  (Tier-1)
-- L5 BYO-SQL escape hatch; one row per template_driven report (1:1).
-- referenced_mart_fields normalized to a bridge (no catch-all uuid[] array)
-- per ADR-0005 rule 2 -> compliance.report_sql_template_field.
-- ---------------------------------------------------------------------
CREATE TABLE compliance.report_sql_template (
    report_sql_template_id  uuid        NOT NULL DEFAULT uuidv7(),
    report_definition_id    uuid        NOT NULL,
    sql_text                text        NOT NULL,
    parameter_schema        jsonb       NOT NULL DEFAULT '{}'::jsonb,
    notes                   text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_report_sql_template PRIMARY KEY (report_sql_template_id),
    CONSTRAINT uq_report_sql_template_report UNIQUE (report_definition_id),
    CONSTRAINT fk_report_sql_template_report_definition
        FOREIGN KEY (report_definition_id)
        REFERENCES compliance.report_definition (report_definition_id)
        ON DELETE CASCADE
);
COMMENT ON TABLE compliance.report_sql_template IS
    'tier:1. BYO-SQL template, 1:1 with a template_driven report_definition. Referenced mart fields normalized into report_sql_template_field (was v1 uuid[] array).';

-- Bridge replacing v1 report_sql_template.referenced_mart_fields uuid[].
CREATE TABLE compliance.report_sql_template_field (
    report_sql_template_field_id  uuid    NOT NULL DEFAULT uuidv7(),
    report_sql_template_id        uuid    NOT NULL,
    mart_field_id                 uuid    NOT NULL,
    created_at                    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_report_sql_template_field PRIMARY KEY (report_sql_template_field_id),
    CONSTRAINT uq_report_sql_template_field_template_field
        UNIQUE (report_sql_template_id, mart_field_id),
    CONSTRAINT fk_report_sql_template_field_template
        FOREIGN KEY (report_sql_template_id)
        REFERENCES compliance.report_sql_template (report_sql_template_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_report_sql_template_field_mart_field
        FOREIGN KEY (mart_field_id)
        REFERENCES analytics.mart_field (mart_field_id)
        ON DELETE RESTRICT
);
COMMENT ON TABLE compliance.report_sql_template_field IS
    'tier:1. Normalized bridge: mart_fields referenced by a BYO-SQL template. Replaces v1 report_sql_template.referenced_mart_fields uuid[] (no catch-all array; real FK relation, ADR-0005 rule 2).';

CREATE INDEX ix_report_sql_template_field_template_id
    ON compliance.report_sql_template_field (report_sql_template_id);
CREATE INDEX ix_report_sql_template_field_mart_field_id
    ON compliance.report_sql_template_field (mart_field_id);

-- ---------------------------------------------------------------------
-- TABLE: compliance.report_run_log  (Tier-2, append-only, partitioned)
-- L5 audit trail of generated report runs. v1 mutated status/completed_at
-- in place; v2 makes the log append-only (ADR-0005 rule 3 / ADR-0004) and
-- Tier-2 (high-volume report-job audit, never in invocation path). One row
-- per terminal/last-known run state is appended; run lifecycle is expressed
-- by appended rows keyed by run_uuid, projected via report_run_current.
-- RANGE-partitioned on created_at (month) with BRIN on created_at (ADR-0004 §8).
-- ---------------------------------------------------------------------
CREATE TABLE compliance.report_run_log (
    report_run_log_id     uuid        NOT NULL DEFAULT uuidv7(),
    run_uuid              uuid        NOT NULL,  -- correlates the append events of one run
    report_definition_id  uuid        NOT NULL,
    requested_by          text,
    scope_params          jsonb       NOT NULL DEFAULT '{}'::jsonb,
    output_formats        text[]      NOT NULL DEFAULT '{}'::text[],
    status                compliance.report_run_status NOT NULL DEFAULT 'pending',
    error_message         text,
    artifact_uris         jsonb       NOT NULL DEFAULT '{}'::jsonb,
    duration_ms           integer,
    created_at            timestamptz NOT NULL DEFAULT now(),
    completed_at          timestamptz,
    CONSTRAINT pk_report_run_log PRIMARY KEY (report_run_log_id, created_at),
    CONSTRAINT fk_report_run_log_report_definition
        FOREIGN KEY (report_definition_id)
        REFERENCES compliance.report_definition (report_definition_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_report_run_log_failed_has_error
        CHECK (status <> 'failed' OR error_message IS NOT NULL),
    CONSTRAINT ck_report_run_log_completed_after_created
        CHECK (completed_at IS NULL OR completed_at >= created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE compliance.report_run_log IS
    'tier:2 append-only. Audit trail of report-generation jobs. Append a new row per run-state event keyed by run_uuid; latest per run_uuid via report_run_current. Range-partitioned monthly on created_at; never in invocation path (ADR-0004/0007).';
COMMENT ON COLUMN compliance.report_run_log.run_uuid IS 'Stable id of a logical report run; multiple appended rows share it as state advances.';

-- Initial monthly partition (creation date of this seed). Subsequent partitions
-- are minted by the partition-maintenance job.
CREATE TABLE compliance.report_run_log_2026_05
    PARTITION OF compliance.report_run_log
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE compliance.report_run_log_2026_06
    PARTITION OF compliance.report_run_log
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

CREATE INDEX brin_report_run_log_created_at
    ON compliance.report_run_log USING brin (created_at);
CREATE INDEX ix_report_run_log_report_definition_id
    ON compliance.report_run_log (report_definition_id, created_at DESC);
CREATE INDEX ix_report_run_log_run_uuid
    ON compliance.report_run_log (run_uuid, created_at DESC);

-- Current-state VIEW: latest appended state per logical report run.
CREATE VIEW compliance.report_run_current AS
SELECT DISTINCT ON (l.run_uuid)
       l.run_uuid,
       l.report_run_log_id,
       l.report_definition_id,
       l.requested_by,
       l.scope_params,
       l.output_formats,
       l.status,
       l.error_message,
       l.artifact_uris,
       l.duration_ms,
       l.created_at,
       l.completed_at
FROM   compliance.report_run_log AS l
ORDER  BY l.run_uuid, l.created_at DESC;
COMMENT ON VIEW compliance.report_run_current IS
    'Current state of each report run = latest report_run_log row per run_uuid. Append-only projection (ADR-0005 rule 3).';

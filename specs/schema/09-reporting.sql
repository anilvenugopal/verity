-- =====================================================================
-- 09-reporting.sql — Verity v2 hardened schema · REPORTING & ANALYTICS
-- Report DEFINITIONS + embedding config live in core; report RUN logs are Tier-2
-- (audit). Per ADR-0007 the canonical ANALYTICS tier is EXTERNAL (Iceberg/Parquet
-- on object storage, customer-portable) — it is NOT a Postgres schema here; these
-- tables are the definitions + the local run log, not the analytical store.
-- =====================================================================

-- ===== embedding_config (single current; effective-dated) =============
CREATE TABLE core.embedding_config (
    embedding_config_id  uuid        NOT NULL DEFAULT uuidv7(),
    embedding_runtime_code text      NOT NULL,                  -- fastembed | …
    model_ref            text        NOT NULL,                  -- embedding model identifier
    dimension            integer      NOT NULL,                  -- vector dim (source of truth for the vector(N) columns)
    effective_start_date date        NOT NULL DEFAULT current_date,
    effective_end_date   date,                                   -- NULL = current
    created_at           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_embedding_config PRIMARY KEY (embedding_config_id),
    CONSTRAINT fk_embedding_config_runtime FOREIGN KEY (embedding_runtime_code) REFERENCES reference.embedding_runtime (code),
    CONSTRAINT ck_embedding_config_dim CHECK (dimension > 0));
COMMENT ON TABLE core.embedding_config IS 'tier:1. The active embedding runtime + dimension used for similarity (intake_requirement/canonical_requirement embeddings). One current row (effective-dated).';
CREATE UNIQUE INDEX uq_embedding_config_current ON core.embedding_config (model_ref) WHERE effective_end_date IS NULL;

-- ===== report definitions ============================================
CREATE TABLE core.report_definition (
    report_definition_id uuid        NOT NULL DEFAULT uuidv7(),
    name                 text        NOT NULL,
    report_kind_code     text        NOT NULL,                  -- metadata_driven | template_driven
    description          text,
    sql_template         text,                                   -- for template_driven
    spec                 jsonb       NOT NULL DEFAULT '{}'::jsonb,-- for metadata_driven (fields, filters, grouping)
    created_at           timestamptz  NOT NULL DEFAULT now(),
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    created_by_actor_id  uuid        NOT NULL,
    created_role_code    text        NOT NULL,
    CONSTRAINT pk_report_definition PRIMARY KEY (report_definition_id),
    CONSTRAINT fk_report_definition_kind FOREIGN KEY (report_kind_code) REFERENCES reference.report_kind (code),
    CONSTRAINT fk_report_definition_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_report_definition_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_report_definition_name UNIQUE (name),
    CONSTRAINT ck_report_definition_template CHECK (report_kind_code <> 'template_driven' OR sql_template IS NOT NULL));
COMMENT ON TABLE core.report_definition IS 'tier:1. A report definition (metadata- or template-driven). Reports run as async jobs against the analytics tier (ADR-0007), never on the status path.';

CREATE TABLE core.report_field (
    report_field_id      uuid        NOT NULL DEFAULT uuidv7(),
    report_definition_id uuid        NOT NULL,
    field_name           text        NOT NULL,
    expression           text,
    ordinal              integer      NOT NULL DEFAULT 1,
    CONSTRAINT pk_report_field PRIMARY KEY (report_field_id),
    CONSTRAINT fk_report_field_definition FOREIGN KEY (report_definition_id) REFERENCES core.report_definition (report_definition_id) ON DELETE CASCADE,
    CONSTRAINT uq_report_field_name UNIQUE (report_definition_id, field_name));

-- ===== AUDIT (Tier-2): report run log =================================
CREATE TABLE audit.report_run_log (
    report_run_log_id    uuid        NOT NULL DEFAULT uuidv7(),
    report_definition_id uuid,                                   -- soft ref -> core.report_definition
    report_run_status_code text      NOT NULL,                  -- pending|succeeded|failed
    requested_by_actor_id uuid       NOT NULL,
    parameters           jsonb,
    output_ref           jsonb,                                  -- where the rendered report landed (storage)
    error                text,
    started_at           timestamptz,
    finished_at          timestamptz,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_report_run_log PRIMARY KEY (report_run_log_id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE audit.report_run_log IS 'tier:2 append-only (partitioned). Async report-job runs. The canonical analytics store is EXTERNAL (Iceberg/Parquet, customer-portable) — ADR-0007.';
CREATE INDEX ix_report_run_log_definition_time ON audit.report_run_log (report_definition_id, created_at DESC);
CREATE TABLE audit.report_run_log_2026_06 PARTITION OF audit.report_run_log FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.report_run_log_2026_07 PARTITION OF audit.report_run_log FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');

-- NOTE (ADR-0007): the customer-portable ANALYTICS tier (Iceberg/Parquet on object
-- storage + export to a customer warehouse) is external infrastructure, not modeled as
-- Postgres tables. The decision/invocation/evidence logs (audit, 06) are its source.

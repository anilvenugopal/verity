-- core.embedding_config  ·  subject: reporting  ·  (table)

-- 09-reporting.sql — Verity v2 hardened schema · REPORTING & ANALYTICS
-- Report DEFINITIONS + embedding config live in core; report RUN logs are Tier-2
-- (audit). Per ADR-0007 the canonical ANALYTICS tier is EXTERNAL (Iceberg/Parquet
-- on object storage, customer-portable) — it is NOT a Postgres schema here; these
-- tables are the definitions + the local run log, not the analytical store.
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

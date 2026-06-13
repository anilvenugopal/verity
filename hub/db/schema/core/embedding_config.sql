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
    effective_end_date   date NOT NULL DEFAULT '2099-12-31',                                   -- 2099-12-31 = open (current)
    created_at           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_embedding_config PRIMARY KEY (embedding_config_id),
    CONSTRAINT fk_embedding_config_runtime FOREIGN KEY (embedding_runtime_code) REFERENCES reference.embedding_runtime (code),
    CONSTRAINT ck_embedding_config_dim CHECK (dimension > 0));
COMMENT ON TABLE core.embedding_config IS
'The active embedding runtime and vector dimension used for similarity (the requirement embeddings). The dimension is the source of truth for the vector(N) columns. Effective-dated with one current row, so the embedding model can change over time without losing which config produced an old vector.

@tier 1
@lifecycle mutable
@subject reporting
@status reference.embedding_runtime';
CREATE UNIQUE INDEX uq_embedding_config_current ON core.embedding_config (model_ref) WHERE effective_end_date = '2099-12-31';
COMMENT ON COLUMN core.embedding_config.embedding_config_id IS
'Identity of the config.';
COMMENT ON COLUMN core.embedding_config.embedding_runtime_code IS
'The embedding runtime, e.g. fastembed. @status reference.embedding_runtime';
COMMENT ON COLUMN core.embedding_config.model_ref IS
'The embedding model identifier.';
COMMENT ON COLUMN core.embedding_config.dimension IS
'Vector dimension; the source of truth for the vector(N) columns. Greater than 0.';
COMMENT ON COLUMN core.embedding_config.effective_start_date IS
'Start of the validity window.';
COMMENT ON COLUMN core.embedding_config.effective_end_date IS
'End of the window; the open end (2099-12-31) is the current config.';
COMMENT ON COLUMN core.embedding_config.created_at IS
'When recorded.';

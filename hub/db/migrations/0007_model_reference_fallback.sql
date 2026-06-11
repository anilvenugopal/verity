-- 0007_model_reference_fallback.sql — feature 005/008 cross-feature contract (ADR-0019).
-- Adds fallback-audit columns to audit.model_invocation_log so each governed invocation
-- records which model_reference chain position fired and whether it was a fallback.
-- Additive (Principle II). model_invocation_log is append-only; existing rows get
-- was_fallback = false (the default) and model_reference_id = null.
ALTER TABLE audit.model_invocation_log
    ADD COLUMN IF NOT EXISTS model_reference_id uuid,
    ADD COLUMN IF NOT EXISTS was_fallback       boolean NOT NULL DEFAULT false;

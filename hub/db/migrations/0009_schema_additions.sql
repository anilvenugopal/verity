-- 0009_schema_additions: context_window on model, is_write_operation on tool,
-- and the executable_version_delegation table for sub-agent authorization.
-- Idempotent: IF NOT EXISTS / DO $$ checks throughout.

-- (a) context_window on core.model
ALTER TABLE core.model ADD COLUMN IF NOT EXISTS context_window integer;

-- (b) is_write_operation on core.tool
ALTER TABLE core.tool ADD COLUMN IF NOT EXISTS is_write_operation boolean NOT NULL DEFAULT false;

-- (c) Sub-agent delegation authorization table.
-- Each row authorizes ONE parent agent_version to delegate to ONE child.
-- child_executable_id = champion-tracking (delegation follows whoever is promoted champion).
-- child_version_id    = pinned to a specific version.
-- Exactly one must be set — enforced by the CHECK constraint below.
CREATE TABLE IF NOT EXISTS core.executable_version_delegation (
    delegation_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_version_id       UUID NOT NULL REFERENCES core.executable_version(executable_version_id),
    child_executable_id     UUID REFERENCES core.executable(executable_id),
    child_version_id        UUID REFERENCES core.executable_version(executable_version_id),
    scope                   JSONB NOT NULL DEFAULT '{}',
    rationale               TEXT,
    notes                   TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_delegation_child_exclusive CHECK (
        (child_executable_id IS NOT NULL)::int + (child_version_id IS NOT NULL)::int = 1
    )
);

CREATE INDEX IF NOT EXISTS idx_evd_parent ON core.executable_version_delegation(parent_version_id);
CREATE INDEX IF NOT EXISTS idx_evd_child_exe ON core.executable_version_delegation(child_executable_id);


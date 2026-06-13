-- core.executable_version_delegation  ·  subject: registry  ·  (table)

CREATE TABLE core.executable_version_delegation (
    delegation_id       uuid        NOT NULL DEFAULT gen_random_uuid(),
    parent_version_id   uuid        NOT NULL,
    child_executable_id uuid,
    child_version_id    uuid,
    scope               jsonb       NOT NULL DEFAULT '{}',
    rationale           text,
    notes               text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_executable_version_delegation PRIMARY KEY (delegation_id),
    CONSTRAINT fk_evd_parent FOREIGN KEY (parent_version_id)
        REFERENCES core.executable_version (executable_version_id),
    CONSTRAINT fk_evd_child_exe FOREIGN KEY (child_executable_id)
        REFERENCES core.executable (executable_id),
    CONSTRAINT fk_evd_child_version FOREIGN KEY (child_version_id)
        REFERENCES core.executable_version (executable_version_id),
    CONSTRAINT chk_delegation_child_exclusive CHECK (
        (child_executable_id IS NOT NULL)::int + (child_version_id IS NOT NULL)::int = 1
    ));
CREATE INDEX idx_evd_parent ON core.executable_version_delegation (parent_version_id);
CREATE INDEX idx_evd_child_exe ON core.executable_version_delegation (child_executable_id);
COMMENT ON TABLE core.executable_version_delegation IS
'Authorises a parent executable_version to delegate to a child. Exactly one of child_executable_id (champion-tracking) or child_version_id (pinned) must be set — enforced by the CHECK constraint.

@tier 1
@lifecycle mutable
@subject registry
@decision D5';
COMMENT ON COLUMN core.executable_version_delegation.delegation_id IS
'Identity of the delegation authorisation.';
COMMENT ON COLUMN core.executable_version_delegation.parent_version_id IS
'The version authorised to delegate. @ref core.executable_version hard';
COMMENT ON COLUMN core.executable_version_delegation.child_executable_id IS
'Champion-tracking delegation target — always resolves to the current champion of this executable. Mutually exclusive with child_version_id. @ref core.executable hard';
COMMENT ON COLUMN core.executable_version_delegation.child_version_id IS
'Pinned delegation target — locked to this exact version. Mutually exclusive with child_executable_id. @ref core.executable_version hard';
COMMENT ON COLUMN core.executable_version_delegation.scope IS
'Optional JSON scope constraints on the delegation.';
COMMENT ON COLUMN core.executable_version_delegation.rationale IS
'Why this delegation is authorised.';
COMMENT ON COLUMN core.executable_version_delegation.notes IS
'Implementation notes.';
COMMENT ON COLUMN core.executable_version_delegation.created_at IS
'When the delegation was authorised.';

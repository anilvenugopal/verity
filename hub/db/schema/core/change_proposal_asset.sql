-- core.change_proposal_asset  ·  subject: governance  ·  (table)

CREATE TABLE core.change_proposal_asset (
    change_proposal_asset_id uuid        NOT NULL DEFAULT uuidv7(),
    approval_request_id      uuid        NOT NULL,
    executable_id            uuid        NOT NULL,
    created_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_change_proposal_asset PRIMARY KEY (change_proposal_asset_id),
    CONSTRAINT fk_cpa_approval FOREIGN KEY (approval_request_id)
        REFERENCES core.approval_request (approval_request_id) ON DELETE CASCADE,
    CONSTRAINT fk_cpa_executable FOREIGN KEY (executable_id)
        REFERENCES core.executable (executable_id) ON DELETE RESTRICT,
    CONSTRAINT uq_cpa UNIQUE (approval_request_id, executable_id));
COMMENT ON TABLE core.change_proposal_asset IS
'Links a change proposal (approval_request of kind risk_reclassification or business_change) to the registry assets it impacts. On approval each impacted asset is forked to a new draft.

@tier 1
@lifecycle mutable
@subject governance';
COMMENT ON COLUMN core.change_proposal_asset.change_proposal_asset_id IS
'Identity of the link.';
COMMENT ON COLUMN core.change_proposal_asset.approval_request_id IS
'The change proposal. Must be kind risk_reclassification or business_change. @ref core.approval_request hard';
COMMENT ON COLUMN core.change_proposal_asset.executable_id IS
'The impacted executable. @ref core.executable hard';
COMMENT ON COLUMN core.change_proposal_asset.created_at IS
'When the link was created.';

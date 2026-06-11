-- 0005_change_proposal_asset.sql — feature 003 (US3). The small grouping table the 001 design note
-- anticipated: which registry assets a change proposal (an approval_request of kind
-- risk_reclassification | business_change) impacts. On approval each impacted asset is forked to a new
-- draft. Additive (Principle II). The approval kinds are already seeded in reference.approval_request_kind.
CREATE TABLE IF NOT EXISTS core.change_proposal_asset (
    change_proposal_asset_id uuid        NOT NULL DEFAULT uuidv7(),
    approval_request_id      uuid        NOT NULL,
    executable_id            uuid        NOT NULL,
    created_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_change_proposal_asset PRIMARY KEY (change_proposal_asset_id),
    CONSTRAINT fk_cpa_approval FOREIGN KEY (approval_request_id) REFERENCES core.approval_request (approval_request_id) ON DELETE CASCADE,
    CONSTRAINT fk_cpa_executable FOREIGN KEY (executable_id) REFERENCES core.executable (executable_id) ON DELETE RESTRICT,
    CONSTRAINT uq_cpa UNIQUE (approval_request_id, executable_id));

-- core.approval_signoff  ·  subject: lifecycle  ·  (table)

-- One immutable per-approver sign-off. signed_as_role_code = the capacity signed in
-- (must be an approval role the approver actually holds; enforced server-side).
CREATE TABLE core.approval_signoff (
    approval_signoff_id uuid        NOT NULL DEFAULT uuidv7(),
    approval_request_id uuid        NOT NULL,
    approver_actor_id   uuid        NOT NULL,
    signed_as_role_code text        NOT NULL,                   -- reference.role; must be is_approval_role (app-enforced)
    decision_code       text        NOT NULL,
    comment             text,
    created_at          timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_approval_signoff PRIMARY KEY (approval_signoff_id),
    CONSTRAINT fk_approval_signoff_request FOREIGN KEY (approval_request_id)
        REFERENCES core.approval_request (approval_request_id) ON DELETE RESTRICT,
    CONSTRAINT fk_approval_signoff_approver FOREIGN KEY (approver_actor_id)
        REFERENCES core.actor (actor_id) ON DELETE RESTRICT,
    CONSTRAINT fk_approval_signoff_role FOREIGN KEY (signed_as_role_code)
        REFERENCES reference.role (code) ON DELETE RESTRICT,
    CONSTRAINT fk_approval_signoff_decision FOREIGN KEY (decision_code)
        REFERENCES reference.approval_decision (code) ON DELETE RESTRICT,
    CONSTRAINT uq_approval_signoff_request_role UNIQUE (approval_request_id, signed_as_role_code)
);
COMMENT ON TABLE core.approval_signoff IS 'tier:1 append-only audit fact. Per-approver sign-off keyed by the required role filled (signed_as_role_code), by a real actor (FR-018/D6). One sign-off per required role per request.';
CREATE INDEX ix_approval_signoff_request ON core.approval_signoff (approval_request_id);

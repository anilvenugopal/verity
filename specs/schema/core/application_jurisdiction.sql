-- core.application_jurisdiction  ·  subject: intake  ·  (table)

-- The jurisdictions an application declares operation in. At least one is required (FR-IN-017).
-- Determines which state/regional regimes apply (e.g. CO -> SB21-169, NY -> NYDFS).
CREATE TABLE core.application_jurisdiction (
    application_id     uuid NOT NULL,
    jurisdiction_code  text NOT NULL,
    created_at         timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id uuid NOT NULL,
    CONSTRAINT pk_application_jurisdiction PRIMARY KEY (application_id, jurisdiction_code),
    CONSTRAINT fk_app_jurisdiction_application FOREIGN KEY (application_id) REFERENCES core.application (application_id) ON DELETE CASCADE,
    CONSTRAINT fk_app_jurisdiction_jurisdiction FOREIGN KEY (jurisdiction_code) REFERENCES reference.jurisdiction (code) ON DELETE RESTRICT,
    CONSTRAINT fk_app_jurisdiction_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id));
COMMENT ON TABLE core.application_jurisdiction IS
'The jurisdictions an application declares operation in (FR-IN-017). At least one is required; determines which state/regional regimes apply. Editable only via re-approval (FR-IN-013).

@tier 1
@lifecycle mutable
@subject intake
@status reference.jurisdiction
@decision D6';
CREATE INDEX ix_app_jurisdiction_jurisdiction ON core.application_jurisdiction (jurisdiction_code);
COMMENT ON COLUMN core.application_jurisdiction.application_id IS
'The application declaring operation in the jurisdiction. @ref core.application hard';
COMMENT ON COLUMN core.application_jurisdiction.jurisdiction_code IS
'The jurisdiction of operation. @status reference.jurisdiction';
COMMENT ON COLUMN core.application_jurisdiction.created_at IS
'When the jurisdiction was added to the perimeter.';
COMMENT ON COLUMN core.application_jurisdiction.created_by_actor_id IS
'Who added it. @ref core.actor hard';

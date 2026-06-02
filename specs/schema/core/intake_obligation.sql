-- core.intake_obligation  ·  subject: intake  ·  (table)

-- the resolved obligations: canonical requirement + target tier (+ domain). FKs to compliance deferred to 05.
CREATE TABLE core.intake_obligation (
    intake_obligation_id   uuid      NOT NULL DEFAULT uuidv7(),
    intake_obligation_resolution_id uuid NOT NULL,
    canonical_requirement_id uuid    NOT NULL,                        -- FK -> compliance.canonical_requirement (05)
    governance_domain_code text,                                      -- FK -> reference/compliance domain (05)
    target_requirement_tier_id uuid,                                  -- FK -> compliance.requirement_tier (05)
    created_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_obligation PRIMARY KEY (intake_obligation_id),
    CONSTRAINT fk_intake_obligation_resolution FOREIGN KEY (intake_obligation_resolution_id)
        REFERENCES core.intake_obligation_resolution (intake_obligation_resolution_id) ON DELETE CASCADE);
COMMENT ON TABLE core.intake_obligation IS 'tier:1. A resolved obligation (canonical_requirement + target tier) this intake must satisfy. Compliance FKs wired in 05-compliance (deferred). FR-IN-014.';

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
COMMENT ON TABLE core.intake_obligation IS
'A single resolved obligation an intake must satisfy: a canonical requirement at a target tier (plus its governance domain). This is the hand-off from the intake''s risk/materiality into the compliance metamodel; the compliance FKs are wired in the compliance domain (FR-IN-014).

@tier 1
@lifecycle insert-only
@subject intake
@status reference.governance_domain';
COMMENT ON COLUMN core.intake_obligation.intake_obligation_id IS
'Identity of the obligation.';
COMMENT ON COLUMN core.intake_obligation.intake_obligation_resolution_id IS
'The resolution event that produced this obligation. @ref core.intake_obligation_resolution hard';
COMMENT ON COLUMN core.intake_obligation.canonical_requirement_id IS
'The canonical requirement this obligation maps to. @ref core.canonical_requirement hard';
COMMENT ON COLUMN core.intake_obligation.governance_domain_code IS
'The governance domain of the obligation. @status reference.governance_domain';
COMMENT ON COLUMN core.intake_obligation.target_requirement_tier_id IS
'The tier on the requirements ladder the intake must reach. @ref core.requirement_tier hard';
COMMENT ON COLUMN core.intake_obligation.created_at IS
'When the obligation was recorded (with its resolution).';

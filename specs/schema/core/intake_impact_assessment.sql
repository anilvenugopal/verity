-- core.intake_impact_assessment  ·  subject: intake  ·  (table)

CREATE TABLE core.intake_impact_assessment (
    intake_impact_assessment_id uuid NOT NULL DEFAULT uuidv7(),
    intake_id            uuid       NOT NULL,
    revision             integer     NOT NULL,                      -- 1,2,3… immutable revisions
    assessment           jsonb       NOT NULL,                      -- the impact write-up (structured)
    valid_from           timestamptz NOT NULL DEFAULT now(),        -- SCD-2 window
    valid_to             timestamptz,                                -- NULL = current revision
    created_at           timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id  uuid       NOT NULL,
    created_role_code    text       NOT NULL,
    CONSTRAINT pk_intake_impact_assessment PRIMARY KEY (intake_impact_assessment_id),
    CONSTRAINT fk_intake_impact_intake FOREIGN KEY (intake_id) REFERENCES core.intake (intake_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_impact_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_intake_impact_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_intake_impact_revision UNIQUE (intake_id, revision));
COMMENT ON TABLE core.intake_impact_assessment IS 'tier:1 SCD-2 versioned. The audit-sensitive figure that KEEPS full history (D4 exception): immutable revisions, current = valid_to IS NULL.';

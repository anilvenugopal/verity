-- core.requirement_tier  ·  subject: compliance  ·  (table)

CREATE TABLE core.requirement_tier (
    requirement_tier_id   uuid       NOT NULL DEFAULT uuidv7(),
    requirement_id        uuid       NOT NULL,                    -- the requirement version this tier belongs to
    tier_level            integer     NOT NULL,                   -- 1..N cumulative (tier N implies 1..N)
    title                 text       NOT NULL,
    criteria              text       NOT NULL,
    valid_from            timestamptz NOT NULL DEFAULT now(),
    valid_to              timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_requirement_tier PRIMARY KEY (requirement_tier_id),
    CONSTRAINT fk_requirement_tier_requirement FOREIGN KEY (requirement_id)
        REFERENCES core.canonical_requirement (requirement_id) ON DELETE RESTRICT,
    CONSTRAINT ck_requirement_tier_level_positive CHECK (tier_level >= 1));
COMMENT ON TABLE core.requirement_tier IS 'tier:1 SCD-2. Cumulative tier ladder per canonical requirement (tier N implies all below). Variable depth per requirement. ADR-0008.';
CREATE UNIQUE INDEX uq_requirement_tier_current ON core.requirement_tier (requirement_id, tier_level) WHERE valid_to IS NULL;

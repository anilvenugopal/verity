-- core.requirement_tier  ·  subject: compliance  ·  (table)

CREATE TABLE core.requirement_tier (
    requirement_tier_id   uuid       NOT NULL DEFAULT uuidv7(),
    requirement_id        uuid       NOT NULL,                    -- the requirement version this tier belongs to
    tier_level            integer     NOT NULL,                   -- 1..N cumulative (tier N implies 1..N)
    title                 text       NOT NULL,
    criteria              text       NOT NULL,
    valid_from            timestamptz NOT NULL DEFAULT now(),
    valid_to              timestamptz NOT NULL DEFAULT '2099-12-31 00:00:00+00',
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_requirement_tier PRIMARY KEY (requirement_tier_id),
    CONSTRAINT fk_requirement_tier_requirement FOREIGN KEY (requirement_id)
        REFERENCES core.canonical_requirement (requirement_id) ON DELETE RESTRICT,
    CONSTRAINT ck_requirement_tier_level_positive CHECK (tier_level >= 1));
COMMENT ON TABLE core.requirement_tier IS
'The cumulative tier ladder for a canonical requirement: tier N implies every tier below it, and depth varies per requirement. An obligation targets a tier, and controls satisfy a requirement AT a tier (ADR-0008).

@tier 1
@lifecycle scd2
@subject compliance
@adr 0008';
CREATE UNIQUE INDEX uq_requirement_tier_current ON core.requirement_tier (requirement_id, tier_level) WHERE valid_to = '2099-12-31 00:00:00+00';
COMMENT ON COLUMN core.requirement_tier.requirement_tier_id IS
'Identity of this VERSION of the tier.';
COMMENT ON COLUMN core.requirement_tier.requirement_id IS
'The requirement version this tier belongs to. @ref core.canonical_requirement hard';
COMMENT ON COLUMN core.requirement_tier.tier_level IS
'Cumulative level (1..N); tier N implies 1..N. At least 1.';
COMMENT ON COLUMN core.requirement_tier.title IS
'Short title of the tier.';
COMMENT ON COLUMN core.requirement_tier.criteria IS
'What must be true to meet this tier.';
COMMENT ON COLUMN core.requirement_tier.valid_from IS
'Start of the SCD-2 validity window.';
COMMENT ON COLUMN core.requirement_tier.valid_to IS
'End of the window; the open row (2099-12-31) is the current version.';
COMMENT ON COLUMN core.requirement_tier.created_at IS
'When this version was recorded.';

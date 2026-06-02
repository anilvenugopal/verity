-- core.requirement_control  ·  subject: compliance  ·  (table)

CREATE TABLE core.requirement_control (
    requirement_control_id uuid      NOT NULL DEFAULT uuidv7(),
    requirement_tier_id   uuid       NOT NULL,                    -- which tier of which requirement
    control_id            uuid       NOT NULL,                    -- which control (phase derived from control)
    derivation_method_code text      NOT NULL DEFAULT 'manual',
    valid_from            timestamptz NOT NULL DEFAULT now(),
    valid_to              timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_requirement_control PRIMARY KEY (requirement_control_id),
    CONSTRAINT fk_reqctrl_tier FOREIGN KEY (requirement_tier_id) REFERENCES core.requirement_tier (requirement_tier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_reqctrl_control FOREIGN KEY (control_id) REFERENCES core.control (control_id) ON DELETE RESTRICT,
    CONSTRAINT fk_reqctrl_method FOREIGN KEY (derivation_method_code) REFERENCES reference.derivation_method (code));
COMMENT ON TABLE core.requirement_control IS 'tier:1 SCD-2. Bridge 2: which controls satisfy a requirement at a tier (phase derived from control, not stored — resolves verification S4). Effective-dated.';

-- core.requirement_control  ·  subject: compliance  ·  (table)

CREATE TABLE core.requirement_control (
    requirement_control_id uuid      NOT NULL DEFAULT uuidv7(),
    requirement_tier_id   uuid       NOT NULL,                    -- which tier of which requirement
    control_id            uuid       NOT NULL,                    -- which control (phase derived from control)
    derivation_method_code text      NOT NULL DEFAULT 'manual',
    valid_from            timestamptz NOT NULL DEFAULT now(),
    valid_to              timestamptz NOT NULL DEFAULT '2099-12-31 00:00:00+00',
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_requirement_control PRIMARY KEY (requirement_control_id),
    CONSTRAINT fk_reqctrl_tier FOREIGN KEY (requirement_tier_id) REFERENCES core.requirement_tier (requirement_tier_id) ON DELETE RESTRICT,
    CONSTRAINT fk_reqctrl_control FOREIGN KEY (control_id) REFERENCES core.control (control_id) ON DELETE RESTRICT,
    CONSTRAINT fk_reqctrl_method FOREIGN KEY (derivation_method_code) REFERENCES reference.derivation_method (code));
COMMENT ON TABLE core.requirement_control IS
'Bridge 2: which controls satisfy a requirement AT a given tier. The control''s phase is derived from the control, not stored here (resolves verification S4). Effective-dated, with the same derivation provenance as Bridge 1 (ADR-0008, ADR-0009).

@tier 1
@lifecycle scd2
@subject compliance
@status reference.derivation_method
@adr 0008';
COMMENT ON COLUMN core.requirement_control.requirement_control_id IS
'Identity of this VERSION of the mapping.';
COMMENT ON COLUMN core.requirement_control.requirement_tier_id IS
'The requirement tier being satisfied. @ref core.requirement_tier hard';
COMMENT ON COLUMN core.requirement_control.control_id IS
'The control that satisfies it; its phase is derived from the control. @ref core.control hard';
COMMENT ON COLUMN core.requirement_control.derivation_method_code IS
'How the mapping was established (D9). @status reference.derivation_method';
COMMENT ON COLUMN core.requirement_control.valid_from IS
'Start of the SCD-2 validity window.';
COMMENT ON COLUMN core.requirement_control.valid_to IS
'End of the window; the open row (2099-12-31) is the current version.';
COMMENT ON COLUMN core.requirement_control.created_at IS
'When this version was recorded.';

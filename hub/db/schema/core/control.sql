-- core.control  ·  subject: compliance  ·  (table)

CREATE TABLE core.control (
    control_id            uuid       NOT NULL DEFAULT uuidv7(),   -- a VERSION
    control_code          text       NOT NULL,                    -- stable logical key
    title                 text       NOT NULL,
    control_phase_code    text       NOT NULL,                    -- design_time|deploy_time|static_model|execution
    control_type_code     text       NOT NULL,                    -- preventive|detective|corrective|directive
    enforcement_action_code text     NOT NULL,                    -- block|refuse|suppress_write|warn|log_only
    description           text,
    valid_from            timestamptz NOT NULL DEFAULT now(),
    valid_to              timestamptz NOT NULL DEFAULT '2099-12-31 00:00:00+00',
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_control PRIMARY KEY (control_id),
    CONSTRAINT fk_control_phase FOREIGN KEY (control_phase_code) REFERENCES reference.control_phase (code),
    CONSTRAINT fk_control_type FOREIGN KEY (control_type_code) REFERENCES reference.control_type (code),
    CONSTRAINT fk_control_enforcement FOREIGN KEY (enforcement_action_code) REFERENCES reference.enforcement_action (code));
COMMENT ON TABLE core.control IS
'Right axis: an enforcement control bound to a lifecycle phase (design_time/deploy_time/static_model/execution) with a type and a concrete enforcement_action (block/refuse/suppress_write/warn/log_only). Versioned as controls mature. The phase lives HERE so requirement_control derives it rather than storing it (resolves verification S4) (ADR-0008, D7).

@tier 1
@lifecycle scd2
@subject compliance
@status reference.control_phase
@status reference.control_type
@status reference.enforcement_action
@adr 0008';
CREATE UNIQUE INDEX uq_control_current ON core.control (control_code) WHERE valid_to = '2099-12-31 00:00:00+00';
COMMENT ON COLUMN core.control.control_id IS
'Identity of this VERSION of the control.';
COMMENT ON COLUMN core.control.control_code IS
'Stable logical key shared across versions.';
COMMENT ON COLUMN core.control.title IS
'Short title of the control.';
COMMENT ON COLUMN core.control.control_phase_code IS
'The lifecycle phase the control acts at — design/deploy/static_model/execution. @status reference.control_phase';
COMMENT ON COLUMN core.control.control_type_code IS
'preventive/detective/corrective/directive. @status reference.control_type';
COMMENT ON COLUMN core.control.enforcement_action_code IS
'What the control does when it fires — block/refuse/suppress_write/warn/log_only. @status reference.enforcement_action';
COMMENT ON COLUMN core.control.description IS
'What the control checks or enforces.';
COMMENT ON COLUMN core.control.valid_from IS
'Start of the SCD-2 validity window.';
COMMENT ON COLUMN core.control.valid_to IS
'End of the window; the open row (2099-12-31) is the current version.';
COMMENT ON COLUMN core.control.created_at IS
'When this version was recorded.';

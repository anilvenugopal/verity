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
    valid_to              timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_control PRIMARY KEY (control_id),
    CONSTRAINT fk_control_phase FOREIGN KEY (control_phase_code) REFERENCES reference.control_phase (code),
    CONSTRAINT fk_control_type FOREIGN KEY (control_type_code) REFERENCES reference.control_type (code),
    CONSTRAINT fk_control_enforcement FOREIGN KEY (enforcement_action_code) REFERENCES reference.enforcement_action (code));
COMMENT ON TABLE core.control IS 'tier:1 SCD-2. Right axis: an enforcement control at a lifecycle phase. Versions as controls mature (D7). phase lives here (requirement_control derives it — resolves verification S4).';
CREATE UNIQUE INDEX uq_control_current ON core.control (control_code) WHERE valid_to IS NULL;

-- core.evidence_specification  ·  subject: compliance  ·  (table)

CREATE TABLE core.evidence_specification (
    evidence_specification_id uuid   NOT NULL DEFAULT uuidv7(),
    control_id            uuid       NOT NULL,
    evidence_artifact_type_code text NOT NULL,                    -- config_snapshot|model_card|…
    produced_by           text,                                   -- what produces it
    citable_as            text,                                   -- how it is cited in a dossier
    valid_from            timestamptz NOT NULL DEFAULT now(),
    valid_to              timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_evidence_specification PRIMARY KEY (evidence_specification_id),
    CONSTRAINT fk_evidence_spec_control FOREIGN KEY (control_id) REFERENCES core.control (control_id) ON DELETE RESTRICT,
    CONSTRAINT fk_evidence_spec_artifact_type FOREIGN KEY (evidence_artifact_type_code) REFERENCES reference.evidence_artifact_type (code));
COMMENT ON TABLE core.evidence_specification IS 'tier:1 SCD-2. The evidence a control must produce (artifact_type/produced_by/citable_as). The actual evidence facts are Tier-2 (audit.evidence, 06). ADR-0008.';

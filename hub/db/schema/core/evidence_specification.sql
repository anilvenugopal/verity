-- core.evidence_specification  ·  subject: compliance  ·  (table)

CREATE TABLE core.evidence_specification (
    evidence_specification_id uuid   NOT NULL DEFAULT uuidv7(),
    control_id            uuid       NOT NULL,
    evidence_artifact_type_code text NOT NULL,                    -- config_snapshot|model_card|…
    produced_by           text,                                   -- what produces it
    citable_as            text,                                   -- how it is cited in a dossier
    valid_from            timestamptz NOT NULL DEFAULT now(),
    valid_to              timestamptz NOT NULL DEFAULT '2099-12-31 00:00:00+00',
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_evidence_specification PRIMARY KEY (evidence_specification_id),
    CONSTRAINT fk_evidence_spec_control FOREIGN KEY (control_id) REFERENCES core.control (control_id) ON DELETE RESTRICT,
    CONSTRAINT fk_evidence_spec_artifact_type FOREIGN KEY (evidence_artifact_type_code) REFERENCES reference.evidence_artifact_type (code));
COMMENT ON TABLE core.evidence_specification IS
'The evidence a control must produce — artifact type, what produces it, and how it is cited in a dossier. This is the SPEC; the actual evidence facts are the Tier-2 audit.evidence stream (ADR-0008).

@tier 1
@lifecycle scd2
@subject compliance
@status reference.evidence_artifact_type
@adr 0008';
COMMENT ON COLUMN core.evidence_specification.evidence_specification_id IS
'Identity of this VERSION of the spec.';
COMMENT ON COLUMN core.evidence_specification.control_id IS
'The control this evidence supports. @ref core.control hard';
COMMENT ON COLUMN core.evidence_specification.evidence_artifact_type_code IS
'The kind of artifact — config_snapshot/model_card/... @status reference.evidence_artifact_type';
COMMENT ON COLUMN core.evidence_specification.produced_by IS
'What produces the evidence.';
COMMENT ON COLUMN core.evidence_specification.citable_as IS
'How the evidence is cited in a compliance dossier.';
COMMENT ON COLUMN core.evidence_specification.valid_from IS
'Start of the SCD-2 validity window.';
COMMENT ON COLUMN core.evidence_specification.valid_to IS
'End of the window; the open row (2099-12-31) is the current version.';
COMMENT ON COLUMN core.evidence_specification.created_at IS
'When this version was recorded.';

-- reference.evidence_artifact_type  ·  subject: compliance  ·  (table)

CREATE TABLE reference.evidence_artifact_type (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_evidence_artifact_type PRIMARY KEY (code), CONSTRAINT uq_evidence_artifact_type_sort UNIQUE (sort_order));
INSERT INTO reference.evidence_artifact_type (code, label, sort_order) VALUES
    ('config_snapshot',1),('model_card',2),('package_manifest',3),('approval_record',4),('test_result',5),
    ('validation_report',6),('decision_log',7),('binding_resolution',8),('deployment_record',9),('document',10);
COMMENT ON TABLE reference.evidence_artifact_type IS
'The kind of compliance evidence artifact (config_snapshot/model_card/...).

@lifecycle reference
@subject compliance';

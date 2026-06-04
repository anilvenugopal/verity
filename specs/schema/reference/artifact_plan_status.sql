-- reference.artifact_plan_status  ·  subject: intake  ·  (table)

CREATE TABLE reference.artifact_plan_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_artifact_plan_status PRIMARY KEY (code), CONSTRAINT uq_artifact_plan_status_sort UNIQUE (sort_order));
INSERT INTO reference.artifact_plan_status (code, label, sort_order) VALUES
    ('proposed',1),('in_progress',2),('realized',3),('cancelled',4);
COMMENT ON TABLE reference.artifact_plan_status IS
'Status of an intake artifact plan as it moves toward a realized executable.

@lifecycle reference
@subject intake';

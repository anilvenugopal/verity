-- reference.control_phase  ·  subject: compliance  ·  (table)

CREATE TABLE reference.control_phase (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_control_phase PRIMARY KEY (code), CONSTRAINT uq_control_phase_sort UNIQUE (sort_order));
INSERT INTO reference.control_phase (code, label, sort_order, description) VALUES
    ('design_time','Design-time',1,'when an asset/schema/pipeline is defined'),
    ('deploy_time','Deploy-time',2,'when promoting to production'),
    ('static_model','Static / model',3,'continuous on the model/artifact (AI analog of data-at-rest)'),
    ('execution','Execution',4,'during runtime (AI analog of data-in-motion)');
COMMENT ON TABLE reference.control_phase IS
'The lifecycle phase a compliance control acts at (design_time/deploy_time/static_model/execution).

@lifecycle reference
@subject compliance';

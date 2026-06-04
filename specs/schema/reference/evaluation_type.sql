-- reference.evaluation_type  ·  subject: validation  ·  (table)

CREATE TABLE reference.evaluation_type (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_evaluation_type PRIMARY KEY (code), CONSTRAINT uq_evaluation_type_sort UNIQUE (sort_order));
INSERT INTO reference.evaluation_type (code,label,sort_order) VALUES ('shadow',1),('challenger',2),('periodic',3),('drift_check',4);
COMMENT ON TABLE reference.evaluation_type IS
'The kind of evaluation_run (shadow/challenger/periodic/drift_check).

@lifecycle reference
@subject validation';

-- reference.intake_status  ·  subject: intake  ·  (table)

CREATE TABLE reference.intake_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_status PRIMARY KEY (code), CONSTRAINT uq_intake_status_sort UNIQUE (sort_order));
INSERT INTO reference.intake_status (code, label, sort_order) VALUES
    ('proposed',1),('in_review',2),('impact_assessment',3),('approved',4),('in_build',5),('live',6),('rejected',7),('retired',8);

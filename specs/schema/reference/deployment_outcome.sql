-- reference.deployment_outcome  ·  subject: deploy  ·  (table)

CREATE TABLE reference.deployment_outcome (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_outcome PRIMARY KEY (code), CONSTRAINT uq_deployment_outcome_sort UNIQUE (sort_order));
INSERT INTO reference.deployment_outcome (code, label, sort_order) VALUES
    ('requested',1),('rejected_incompatible',2),('rejected_lifecycle',3),('rejected_unauthorized',4),('succeeded',5),('failed',6),('superseded',7);

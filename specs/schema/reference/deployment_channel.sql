-- reference.deployment_channel  ·  subject: deploy  ·  (table)

CREATE TABLE reference.deployment_channel (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_channel PRIMARY KEY (code), CONSTRAINT uq_deployment_channel_sort UNIQUE (sort_order));
INSERT INTO reference.deployment_channel (code, label, sort_order) VALUES
    ('development',1),('staging',2),('evaluation',3),('production',4);

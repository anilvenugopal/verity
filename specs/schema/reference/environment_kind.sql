-- reference.environment_kind  ·  subject: deploy  ·  (table)

CREATE TABLE reference.environment_kind (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_environment_kind PRIMARY KEY (code), CONSTRAINT uq_environment_kind_sort UNIQUE (sort_order));
INSERT INTO reference.environment_kind (code, label, sort_order) VALUES ('non_prod',1),('prod',2),('ephemeral',3);

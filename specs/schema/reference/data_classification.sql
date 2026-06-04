-- reference.data_classification  ·  subject: registry  ·  (table)

CREATE TABLE reference.data_classification (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_data_classification PRIMARY KEY (code), CONSTRAINT uq_data_classification_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.data_classification IS
'Sensitivity class of the data an executable handles (public/internal/confidential/pii_restricted), enforced pre-dispatch.

@lifecycle reference
@subject registry';

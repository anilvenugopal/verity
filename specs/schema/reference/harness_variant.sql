-- reference.harness_variant  ·  subject: deploy  ·  (table)

CREATE TABLE reference.harness_variant (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_harness_variant PRIMARY KEY (code), CONSTRAINT uq_harness_variant_sort UNIQUE (sort_order));
COMMENT ON TABLE reference.harness_variant IS
'The harness execution-engine variant — the kind of container/runtime an image implements.

@lifecycle reference
@subject deploy';

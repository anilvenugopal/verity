-- reference.derivation_method  ·  subject: intake  ·  (table)

-- derivation_method: provenance of a resolved obligation / mapping (D9; generalizes v1 mapping_source).
CREATE TABLE reference.derivation_method (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_derivation_method PRIMARY KEY (code), CONSTRAINT uq_derivation_method_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.derivation_method IS
'Provenance of a resolved mapping or obligation (manual/reasoner_recommended/human_validated) — the D9 reasoning audit.

@lifecycle reference
@subject intake';

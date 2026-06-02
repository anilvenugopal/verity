-- reference.derivation_method  ·  subject: intake  ·  (table)

-- derivation_method: provenance of a resolved obligation / mapping (D9; generalizes v1 mapping_source).
CREATE TABLE reference.derivation_method (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_derivation_method PRIMARY KEY (code), CONSTRAINT uq_derivation_method_sort UNIQUE (sort_order));
INSERT INTO reference.derivation_method (code, label, sort_order, description) VALUES
    ('manual','Manual',1,'authored by a human directly'),
    ('reasoner_recommended','Reasoner-recommended',2,'inferred by the ontology/reasoner; pending validation (ADR-0009)'),
    ('human_validated','Human-validated',3,'reasoner/LLM recommendation reviewed & accepted by a human');

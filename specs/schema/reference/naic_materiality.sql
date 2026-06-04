-- reference.naic_materiality  ·  subject: intake  ·  (table)

CREATE TABLE reference.naic_materiality (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_naic_materiality PRIMARY KEY (code), CONSTRAINT uq_naic_materiality_sort UNIQUE (sort_order));
INSERT INTO reference.naic_materiality (code, label, sort_order) VALUES ('material','Material',1),('non_material','Non Material',2);
COMMENT ON TABLE reference.naic_materiality IS
'NAIC materiality classification (material/non_material) feeding obligations.

@lifecycle reference
@subject intake';

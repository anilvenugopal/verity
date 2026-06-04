-- reference.coverage_level  ·  subject: compliance  ·  (table)

CREATE TABLE reference.coverage_level (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_coverage_level PRIMARY KEY (code), CONSTRAINT uq_coverage_level_sort UNIQUE (sort_order));
INSERT INTO reference.coverage_level (code, label, sort_order) VALUES
    ('full',1),('substantial',2),('partial',3),('gap',4);
COMMENT ON TABLE reference.coverage_level IS
'Coverage classification attached to a governance-domain maturity score.

@lifecycle reference
@subject compliance';

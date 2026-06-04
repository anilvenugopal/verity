-- reference.extraction_match_type  ·  subject: validation  ·  (table)

CREATE TABLE reference.extraction_match_type (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_extraction_match_type PRIMARY KEY (code), CONSTRAINT uq_extraction_match_type_sort UNIQUE (sort_order));
INSERT INTO reference.extraction_match_type (code,label,sort_order) VALUES ('exact',1),('numeric_tolerance',2),('case_insensitive',3),('contains',4);
COMMENT ON TABLE reference.extraction_match_type IS
'How an extraction field is matched in validation (exact/numeric_tolerance/case_insensitive/contains).

@lifecycle reference
@subject validation';

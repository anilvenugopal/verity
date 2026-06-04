-- reference.validation_match_type  ·  subject: validation  ·  (table)

CREATE TABLE reference.validation_match_type (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_validation_match_type PRIMARY KEY (code), CONSTRAINT uq_validation_match_type_sort UNIQUE (sort_order));
INSERT INTO reference.validation_match_type (code,label,sort_order) VALUES ('exact',1),('partial',2),('fuzzy',3);
COMMENT ON TABLE reference.validation_match_type IS
'How a validation record result was judged (exact/partial/fuzzy).

@lifecycle reference
@subject validation';

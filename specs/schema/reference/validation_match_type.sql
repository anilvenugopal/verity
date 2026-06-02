-- reference.validation_match_type  ·  subject: validation  ·  (table)

CREATE TABLE reference.validation_match_type (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_validation_match_type PRIMARY KEY (code), CONSTRAINT uq_validation_match_type_sort UNIQUE (sort_order));
INSERT INTO reference.validation_match_type (code,label,sort_order) VALUES ('exact',1),('partial',2),('fuzzy',3);

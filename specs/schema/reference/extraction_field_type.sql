-- reference.extraction_field_type  ·  subject: validation  ·  (table)

CREATE TABLE reference.extraction_field_type (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_extraction_field_type PRIMARY KEY (code), CONSTRAINT uq_extraction_field_type_sort UNIQUE (sort_order));
INSERT INTO reference.extraction_field_type (code,label,sort_order) VALUES ('string',1),('numeric',2),('date',3),('boolean',4),('enum',5);
COMMENT ON TABLE reference.extraction_field_type IS
'Data type of an extraction output field (string/numeric/date/boolean/enum).

@lifecycle reference
@subject validation';

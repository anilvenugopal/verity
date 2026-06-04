-- reference.tolerance_unit  ·  subject: validation  ·  (table)

CREATE TABLE reference.tolerance_unit (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_tolerance_unit PRIMARY KEY (code), CONSTRAINT uq_tolerance_unit_sort UNIQUE (sort_order));
INSERT INTO reference.tolerance_unit (code,label,sort_order) VALUES ('percent',1),('absolute',2);
COMMENT ON TABLE reference.tolerance_unit IS
'Unit of an extraction tolerance (percent/absolute).

@lifecycle reference
@subject validation';

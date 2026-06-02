-- reference.setting_input_type  ·  subject: validation  ·  (table)

CREATE TABLE reference.setting_input_type (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_setting_input_type PRIMARY KEY (code), CONSTRAINT uq_setting_input_type_sort UNIQUE (sort_order));
INSERT INTO reference.setting_input_type (code,label,sort_order) VALUES ('text',1),('select',2),('number',3);

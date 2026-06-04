-- reference.setting_input_type  ·  subject: validation  ·  (table)

CREATE TABLE reference.setting_input_type (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_setting_input_type PRIMARY KEY (code), CONSTRAINT uq_setting_input_type_sort UNIQUE (sort_order));
INSERT INTO reference.setting_input_type (code,label,sort_order) VALUES ('text','Text',1),('select','Select',2),('number','Number',3);
COMMENT ON TABLE reference.setting_input_type IS
'The input/value type of a platform setting (text/select/number).

@lifecycle reference
@subject validation';

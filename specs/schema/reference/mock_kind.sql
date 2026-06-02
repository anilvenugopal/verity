-- reference.mock_kind  ·  subject: validation  ·  (table)

CREATE TABLE reference.mock_kind (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_mock_kind PRIMARY KEY (code), CONSTRAINT uq_mock_kind_sort UNIQUE (sort_order));
INSERT INTO reference.mock_kind (code,label,sort_order) VALUES ('tool',1),('source',2),('target',3);

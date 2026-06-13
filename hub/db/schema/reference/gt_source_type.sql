-- reference.gt_source_type  ·  subject: validation  ·  (table)

CREATE TABLE reference.gt_source_type (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_gt_source_type PRIMARY KEY (code), CONSTRAINT uq_gt_source_type_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.gt_source_type IS
'Where ground-truth labels came from (document/submission/synthetic).

@lifecycle reference
@subject validation';

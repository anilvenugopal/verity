-- reference.gt_dataset_status  ·  subject: validation  ·  (table)

-- compact: code/label/sort_order + standard columns (description/grouping/parent_code/
-- effective_*/is_active/metadata/created_at/updated_at), PK(code), UNIQUE(sort_order).
CREATE TABLE reference.gt_dataset_status (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_gt_dataset_status PRIMARY KEY (code), CONSTRAINT uq_gt_dataset_status_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.gt_dataset_status IS
'Collection/curation status of a ground-truth dataset (collecting/labeling/adjudicating/ready/deprecated).

@lifecycle reference
@subject validation';

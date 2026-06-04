-- reference.gt_annotator_type  ·  subject: validation  ·  (table)

CREATE TABLE reference.gt_annotator_type (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_gt_annotator_type PRIMARY KEY (code), CONSTRAINT uq_gt_annotator_type_sort UNIQUE (sort_order));
INSERT INTO reference.gt_annotator_type (code,label,sort_order) VALUES ('human_sme',1),('llm_judge',2),('adjudicator',3);
COMMENT ON TABLE reference.gt_annotator_type IS
'The kind of ground-truth annotator (human_sme/llm_judge/adjudicator).

@lifecycle reference
@subject validation';

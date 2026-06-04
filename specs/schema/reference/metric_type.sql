-- reference.metric_type  ·  subject: validation  ·  (table)

-- The grading metric a test_case / metric_threshold / test_execution_log uses.
CREATE TABLE reference.metric_type (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_metric_type PRIMARY KEY (code), CONSTRAINT uq_metric_type_sort UNIQUE (sort_order));
INSERT INTO reference.metric_type (code, label, sort_order) VALUES
    ('exact_match','Exact Match',1),('semantic_similarity','Semantic Similarity',2),
    ('json_schema_match','JSON Schema Match',3),('numeric_tolerance','Numeric Tolerance',4),
    ('f1_score','F1 Score',5),('accuracy','Accuracy',6),('llm_judge','LLM Judge',7),
    ('contains','Contains',8),('regex_match','Regex Match',9);
COMMENT ON TABLE reference.metric_type IS
'The grading metric a test case, metric threshold, or test-execution result uses (exact_match/semantic_similarity/llm_judge/...).

@lifecycle reference
@subject validation';

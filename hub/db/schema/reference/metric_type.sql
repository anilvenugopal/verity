-- reference.metric_type  ·  subject: validation  ·  (table)

-- The grading metric a test_case / metric_threshold / test_execution_log uses.
CREATE TABLE reference.metric_type (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_metric_type PRIMARY KEY (code), CONSTRAINT uq_metric_type_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.metric_type IS
'The grading metric a test case, metric threshold, or test-execution result uses (exact_match/semantic_similarity/llm_judge/...).

@lifecycle reference
@subject validation';

-- reference.harness_variant  ·  subject: deploy  ·  (table)

CREATE TABLE reference.harness_variant (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_harness_variant PRIMARY KEY (code), CONSTRAINT uq_harness_variant_sort UNIQUE (sort_order));
COMMENT ON TABLE reference.harness_variant IS 'Vocabulary: harness execution-engine variant (the kind of container/runtime). D8.';
INSERT INTO reference.harness_variant (code, label, sort_order, description) VALUES
    ('claude_agentic_loop','Claude agentic loop',1,'current default agent/task execution engine');

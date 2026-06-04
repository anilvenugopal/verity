-- reference.model_status  ·  subject: decisions  ·  (table)

-- (decision_status, invocation_status, auth_event_type/outcome stay NATIVE enums per D1 —
--  hot-path/Tier-2 internal; declared in 06-decisions. model_status + currency are vocab.)
CREATE TABLE reference.model_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_model_status PRIMARY KEY (code), CONSTRAINT uq_model_status_sort UNIQUE (sort_order));
INSERT INTO reference.model_status (code, label, sort_order) VALUES ('active',1),('deprecated',2),('retired',3);
COMMENT ON TABLE reference.model_status IS
'Registry status of a model (active/deprecated/retired).

@lifecycle reference
@subject decisions';

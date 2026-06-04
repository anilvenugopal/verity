-- reference.api_role  ·  subject: registry  ·  (table)

CREATE TABLE reference.api_role (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_api_role PRIMARY KEY (code), CONSTRAINT uq_api_role_sort UNIQUE (sort_order));
INSERT INTO reference.api_role (code, label, sort_order) VALUES
    ('system',1),('user',2),('assistant_prefill',3);
COMMENT ON TABLE reference.api_role IS
'The chat API role a prompt fills in a request (system/user/assistant), used by executable_prompt_assignment.

@lifecycle reference
@subject registry';

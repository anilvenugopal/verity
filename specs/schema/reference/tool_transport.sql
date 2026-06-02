-- reference.tool_transport  ·  subject: registry  ·  (table)

CREATE TABLE reference.tool_transport (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_tool_transport PRIMARY KEY (code), CONSTRAINT uq_tool_transport_sort UNIQUE (sort_order));
INSERT INTO reference.tool_transport (code, label, sort_order) VALUES
    ('python_inprocess',1),('mcp',2),('http',3);

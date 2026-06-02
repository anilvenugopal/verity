-- reference.source_kind  ·  subject: registry  ·  (table)

-- Source/Target Binding kinds (binding-grammar). `vault` is NO LONGER a kind — it is a
-- connector_type. A storage_object is a file in any backend, resolved via a connector.
CREATE TABLE reference.source_kind (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_source_kind PRIMARY KEY (code), CONSTRAINT uq_source_kind_sort UNIQUE (sort_order));
INSERT INTO reference.source_kind (code, label, sort_order) VALUES
    ('storage_object',1),  -- a file/object in a storage backend (via connector)
    ('task_output',2),     -- output of a prior task in the workflow
    ('structured',3),      -- a structured payload resolved from elsewhere
    ('inline_content',4);  -- literal inline content

CREATE TABLE reference.target_kind (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_target_kind PRIMARY KEY (code), CONSTRAINT uq_target_kind_sort UNIQUE (sort_order));

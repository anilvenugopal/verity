-- reference.embedding_runtime  ·  subject: reporting  ·  (table)

CREATE TABLE reference.embedding_runtime (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_embedding_runtime PRIMARY KEY (code), CONSTRAINT uq_embedding_runtime_sort UNIQUE (sort_order));
INSERT INTO reference.embedding_runtime (code, label, sort_order) VALUES ('fastembed','FastEmbed',1);

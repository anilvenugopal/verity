-- reference.capability_type  ·  subject: registry  ·  (table)

-- Compact vocab tables (standard pattern). code PK, sort_order unique, effective window.
CREATE TABLE reference.capability_type (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_capability_type PRIMARY KEY (code), CONSTRAINT uq_capability_type_sort UNIQUE (sort_order));
INSERT INTO reference.capability_type (code, label, sort_order) VALUES
    ('classification',1),('extraction',2),('generation',3),('summarisation',4),('matching',5),('validation',6);

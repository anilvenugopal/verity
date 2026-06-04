-- reference.capability_type  ·  subject: registry  ·  (table)

-- Compact vocab tables (standard pattern). code PK, sort_order unique, effective window.
CREATE TABLE reference.capability_type (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_capability_type PRIMARY KEY (code), CONSTRAINT uq_capability_type_sort UNIQUE (sort_order));
INSERT INTO reference.capability_type (code, label, sort_order) VALUES
    ('classification','Classification',1),('extraction','Extraction',2),('generation','Generation',3),('summarisation','Summarisation',4),('matching','Matching',5),('validation','Validation',6);
COMMENT ON TABLE reference.capability_type IS
'What an executable_version does (classification/extraction/...), a governance classification of capability.

@lifecycle reference
@subject registry';

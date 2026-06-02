-- reference.governance_tier  ·  subject: registry  ·  (table)

CREATE TABLE reference.governance_tier (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_governance_tier PRIMARY KEY (code), CONSTRAINT uq_governance_tier_sort UNIQUE (sort_order));
INSERT INTO reference.governance_tier (code, label, sort_order) VALUES
    ('behavioural',1),('contextual',2),('formatting',3);

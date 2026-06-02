-- reference.ai_risk_tier  ·  subject: intake  ·  (table)

-- ai_risk_tier: ordered classification (minimal < limited < high < unacceptable)
CREATE TABLE reference.ai_risk_tier (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_ai_risk_tier PRIMARY KEY (code), CONSTRAINT uq_ai_risk_tier_sort UNIQUE (sort_order));
INSERT INTO reference.ai_risk_tier (code, label, sort_order) VALUES
    ('minimal',1),('limited',2),('high',3),('unacceptable',4);

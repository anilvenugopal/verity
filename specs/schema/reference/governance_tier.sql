-- reference.governance_tier  ·  subject: registry  ·  (table)

CREATE TABLE reference.governance_tier (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_governance_tier PRIMARY KEY (code), CONSTRAINT uq_governance_tier_sort UNIQUE (sort_order));
INSERT INTO reference.governance_tier (code, label, sort_order) VALUES
    ('behavioural','Behavioural',1),('contextual','Contextual',2),('formatting','Formatting',3);
COMMENT ON TABLE reference.governance_tier IS
'Governance tier driving review and approval rigor for an executable version.

@lifecycle reference
@subject registry';

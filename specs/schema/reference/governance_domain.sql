-- reference.governance_domain  ·  subject: compliance  ·  (table)

-- governance_domain: the AI-governance areas (maturity is scored per domain). NOTE: confirm set vs v1.
CREATE TABLE reference.governance_domain (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_governance_domain PRIMARY KEY (code),
    CONSTRAINT fk_governance_domain_parent FOREIGN KEY (parent_code) REFERENCES reference.governance_domain (code),
    CONSTRAINT uq_governance_domain_sort UNIQUE (sort_order));
COMMENT ON TABLE reference.governance_domain IS
'The AI-governance areas — the center-axis grouping for canonical requirements and the unit maturity is scored on.

@lifecycle reference
@subject compliance';

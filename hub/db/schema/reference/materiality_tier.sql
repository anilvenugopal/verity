-- reference.materiality_tier  ·  subject: intake  ·  (table)

-- materiality_tier: ordered materiality scale. NOTE: confirm members against v1.
CREATE TABLE reference.materiality_tier (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_materiality_tier PRIMARY KEY (code), CONSTRAINT uq_materiality_tier_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.materiality_tier IS
'Ordered internal materiality scale (low/medium/high/critical).

@lifecycle reference
@subject intake';

-- reference.trust_level  ·  subject: registry  ·  (table)

CREATE TABLE reference.trust_level (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_trust_level PRIMARY KEY (code), CONSTRAINT uq_trust_level_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.trust_level IS
'Trust classification governing how an executable''s outputs may be used.

@lifecycle reference
@subject registry';

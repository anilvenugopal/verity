-- reference.jurisdiction  ·  subject: intake  ·  (table)

-- jurisdiction: the legal/regulatory geographies an application operates in. A controlled list
-- so the jurisdiction -> regulatory-regime mapping is tractable (e.g. CO -> SB21-169, NY -> NYDFS).
-- @grouping separates US-state from supra-national entries. The seed is representative and
-- extensible (the full US-state set + additional regions are completed as needed).
CREATE TABLE reference.jurisdiction (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_jurisdiction PRIMARY KEY (code), CONSTRAINT uq_jurisdiction_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.jurisdiction IS
'Legal/regulatory geographies an application declares operation in (FR-IN-017). Controlled so the jurisdiction->regime selection works; an application MUST declare at least one. @grouping = us_state | supranational.

@lifecycle reference
@subject intake';

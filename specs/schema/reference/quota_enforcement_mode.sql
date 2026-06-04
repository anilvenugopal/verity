-- reference.quota_enforcement_mode  ·  subject: runs  ·  (table)

-- enforcement is per-quota configurable: soft (warn, never refuse) default, or hard (refuse). D-clarify.
CREATE TABLE reference.quota_enforcement_mode (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_quota_enforcement_mode PRIMARY KEY (code), CONSTRAINT uq_quota_enforcement_mode_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.quota_enforcement_mode IS
'Whether a quota only warns (soft) or refuses the run (hard).

@lifecycle reference
@subject runs';

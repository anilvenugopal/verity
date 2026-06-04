-- reference.version_change_type  ·  subject: registry  ·  (table)

CREATE TABLE reference.version_change_type (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_version_change_type PRIMARY KEY (code), CONSTRAINT uq_version_change_type_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.version_change_type IS
'Semver bump class of a version (major/minor/patch).

@lifecycle reference
@subject registry';

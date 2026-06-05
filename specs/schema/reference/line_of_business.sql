-- reference.line_of_business  ·  subject: intake  ·  (table)

-- line_of_business: the insurance line an application serves. Optional organizational context for
-- reporting/routing (not a compliance driver). 'other' is the escape for an unlisted line.
CREATE TABLE reference.line_of_business (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_line_of_business PRIMARY KEY (code), CONSTRAINT uq_line_of_business_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.line_of_business IS
'Insurance line an application serves (reporting/routing context; optional, not a compliance driver). FR-IN-015.

@lifecycle reference
@subject intake';

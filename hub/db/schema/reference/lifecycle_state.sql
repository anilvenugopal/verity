-- reference.lifecycle_state  ·  subject: lifecycle  ·  (table)

-- lifecycle_state: the 7-state progression (sort_order = order). is_deployable /
-- is_terminal as typed flags; per-state deployment rules live in 08 (matrix).
CREATE TABLE reference.lifecycle_state (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    is_deployable boolean NOT NULL DEFAULT false, is_terminal boolean NOT NULL DEFAULT false,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_lifecycle_state PRIMARY KEY (code), CONSTRAINT uq_lifecycle_state_sort UNIQUE (sort_order));
COMMENT ON TABLE reference.lifecycle_state IS
'The executable lifecycle states (draft/candidate/staging/challenger/champion/deprecated); sort_order is the progression.

@lifecycle reference
@subject lifecycle';

CREATE TABLE reference.approval_request_kind (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_approval_request_kind PRIMARY KEY (code), CONSTRAINT uq_approval_request_kind_sort UNIQUE (sort_order));

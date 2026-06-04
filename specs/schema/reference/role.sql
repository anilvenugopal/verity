-- reference.role  ·  subject: identity  ·  (table)

-- Collapses v1 studio_role + platform_role (identical). approval_role becomes
-- the is_approval_role flag (the 7 that may sign off). D1 notable consequences.
CREATE TABLE reference.role (
    code                 text        NOT NULL,
    label                text        NOT NULL,
    description          text,
    sort_order           integer     NOT NULL,
    grouping             text,        -- governance | engineering | oversight
    parent_code          text,
    is_approval_role     boolean      NOT NULL DEFAULT false,  -- may sign off on approvals
    effective_start_date date        NOT NULL DEFAULT current_date,
    effective_end_date   date NOT NULL DEFAULT '2099-12-31',
    is_active            boolean      NOT NULL DEFAULT true,
    metadata             jsonb        NOT NULL DEFAULT '{}'::jsonb,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_role PRIMARY KEY (code),
    CONSTRAINT fk_role_parent FOREIGN KEY (parent_code)
        REFERENCES reference.role (code) ON DELETE RESTRICT,
    CONSTRAINT uq_role_sort UNIQUE (sort_order),
    CONSTRAINT ck_role_effective CHECK (effective_end_date >= effective_start_date)
);
COMMENT ON TABLE reference.role IS
'The unified platform role vocabulary (collapses v1 studio_role + platform_role); the acting_role_code paired with every actor.

@lifecycle reference
@subject identity';

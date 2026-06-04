-- reference.requirement_kind  ·  subject: intake  ·  (table)

CREATE TABLE reference.requirement_kind (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_requirement_kind PRIMARY KEY (code), CONSTRAINT uq_requirement_kind_sort UNIQUE (sort_order));
INSERT INTO reference.requirement_kind (code, label, sort_order) VALUES
    ('business','Business',1),('functional','Functional',2),('non_functional','Non Functional',3),('compliance','Compliance',4);
COMMENT ON TABLE reference.requirement_kind IS
'The kind of intake requirement.

@lifecycle reference
@subject intake';

-- reference.approval_decision  ·  subject: lifecycle  ·  (table)

CREATE TABLE reference.approval_decision (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_approval_decision PRIMARY KEY (code), CONSTRAINT uq_approval_decision_sort UNIQUE (sort_order));
INSERT INTO reference.approval_decision (code, label, sort_order) VALUES
    ('approved',1),('rejected',2),('requested_changes',3),('abstained',4);
COMMENT ON TABLE reference.approval_decision IS
'An individual approver''s decision on a sign-off (approve/reject/...), used by approval_signoff.

@lifecycle reference
@subject lifecycle';

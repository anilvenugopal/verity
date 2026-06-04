-- reference.outbox_status  ·  subject: runs  ·  (table)

-- Delivery state of a run_dispatch_outbox row (hub -> NATS handoff).
-- Converted from a native enum to reference vocab per the all-status-fields standard.
CREATE TABLE reference.outbox_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_outbox_status PRIMARY KEY (code), CONSTRAINT uq_outbox_status_sort UNIQUE (sort_order));
INSERT INTO reference.outbox_status (code, label, sort_order) VALUES
    ('pending','Pending',1),('published','Published',2),('claimed','Claimed',3),('failed','Failed',4);
COMMENT ON TABLE reference.outbox_status IS
'Delivery state of a run_dispatch_outbox row (pending/published/claimed/failed).

@lifecycle reference
@subject runs';

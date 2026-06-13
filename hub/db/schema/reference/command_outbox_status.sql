-- reference.command_outbox_status  ·  subject: deploy  ·  (table)

-- Delivery state of a harness_command_outbox row (hub -> coordinator handoff).
-- Distinct from reference.outbox_status: a command is 'acknowledged' (the coordinator
-- executed it) rather than 'claimed', and may 'expire' against its 24h TTL.
CREATE TABLE reference.command_outbox_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_command_outbox_status PRIMARY KEY (code), CONSTRAINT uq_command_outbox_status_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.command_outbox_status IS
'Delivery state of a harness_command_outbox row (pending/published/acknowledged/failed/expired).

@lifecycle reference
@subject deploy';

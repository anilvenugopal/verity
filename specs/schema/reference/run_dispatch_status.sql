-- reference.run_dispatch_status  ·  subject: runs  ·  (table)

-- Operational dispatch state of a run within a cluster (core.harness_dispatch).
-- Lifecycle names the hop along hub -> cluster -> worker: queued (hub) -> published
-- (relay -> NATS) -> claimed (coordinator) -> assigned (coordinator -> worker) ->
-- executing (worker) -> released (worker, terminal); requeued/cancelled are off-path.
CREATE TABLE reference.run_dispatch_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_run_dispatch_status PRIMARY KEY (code), CONSTRAINT uq_run_dispatch_status_sort UNIQUE (sort_order));
INSERT INTO reference.run_dispatch_status (code, label, sort_order) VALUES
    ('queued',1),('published',2),('claimed',3),('assigned',4),
    ('executing',5),('released',6),('requeued',7),('cancelled',8);
COMMENT ON TABLE reference.run_dispatch_status IS
'Operational dispatch state of a run within a cluster (queued/published/claimed/assigned/executing/released/requeued/cancelled).

@lifecycle reference
@subject runs';

-- reference.harness_node_status  ·  subject: deploy  ·  (table)

-- Lifecycle state of a coordinator-eligible runtime host (core.harness_node).
CREATE TABLE reference.harness_node_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_harness_node_status PRIMARY KEY (code), CONSTRAINT uq_harness_node_status_sort UNIQUE (sort_order));
INSERT INTO reference.harness_node_status (code, label, sort_order) VALUES
    ('active',1),('draining',2),('offline',3),('decommissioned',4);
COMMENT ON TABLE reference.harness_node_status IS
'Lifecycle state of a coordinator-eligible runtime host (active/draining/offline/decommissioned).

@lifecycle reference
@subject deploy';

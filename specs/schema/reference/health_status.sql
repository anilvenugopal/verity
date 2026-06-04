-- reference.health_status  ·  subject: deploy  ·  (table)

CREATE TABLE reference.health_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_health_status PRIMARY KEY (code), CONSTRAINT uq_health_status_sort UNIQUE (sort_order));
INSERT INTO reference.health_status (code, label, sort_order) VALUES ('healthy',1),('degraded',2),('down',3),('unknown',4);
COMMENT ON TABLE reference.health_status IS
'Reported instance health (healthy/degraded/down/unknown).

@lifecycle reference
@subject deploy';

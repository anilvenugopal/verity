-- reference.heartbeat_kind  ·  subject: deploy  ·  (table)

CREATE TABLE reference.heartbeat_kind (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_heartbeat_kind PRIMARY KEY (code), CONSTRAINT uq_heartbeat_kind_sort UNIQUE (sort_order));
INSERT INTO reference.heartbeat_kind (code, label, sort_order, description) VALUES
    ('minor','Minor',1,'frequent/light: alive + basic health'),('major','Major',2,'less frequent/full: running-package catalog + metrics');
COMMENT ON TABLE reference.heartbeat_kind IS
'Minor (liveness + lease refresh) vs major (running-package catalog) heartbeat.

@lifecycle reference
@subject deploy';

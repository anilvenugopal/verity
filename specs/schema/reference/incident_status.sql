-- reference.incident_status  ·  subject: validation  ·  (table)

CREATE TABLE reference.incident_status (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_incident_status PRIMARY KEY (code), CONSTRAINT uq_incident_status_sort UNIQUE (sort_order));
INSERT INTO reference.incident_status (code,label,sort_order) VALUES ('open','Open',1),('investigating','Investigating',2),('mitigated','Mitigated',3),('resolved','Resolved',4),('closed','Closed',5);
COMMENT ON TABLE reference.incident_status IS
'Lifecycle status of an incident (open/investigating/mitigated/resolved/closed).

@lifecycle reference
@subject validation';

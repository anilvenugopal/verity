-- reference.incident_status  ·  subject: validation  ·  (table)

CREATE TABLE reference.incident_status (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_incident_status PRIMARY KEY (code), CONSTRAINT uq_incident_status_sort UNIQUE (sort_order));
INSERT INTO reference.incident_status (code,label,sort_order) VALUES ('open',1),('investigating',2),('mitigated',3),('resolved',4),('closed',5);

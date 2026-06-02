-- core.incident  ·  subject: validation  ·  (table)

CREATE TABLE core.incident (
    incident_id uuid NOT NULL DEFAULT uuidv7(), executable_version_id uuid,
    incident_severity_code text NOT NULL, incident_status_code text NOT NULL DEFAULT 'open',
    title text NOT NULL, description text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    opened_by_actor_id uuid NOT NULL, opened_role_code text NOT NULL,
    CONSTRAINT pk_incident PRIMARY KEY (incident_id),
    CONSTRAINT fk_incident_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE SET NULL,
    CONSTRAINT fk_incident_severity FOREIGN KEY (incident_severity_code) REFERENCES reference.incident_severity (code),
    CONSTRAINT fk_incident_status FOREIGN KEY (incident_status_code) REFERENCES reference.incident_status (code),
    CONSTRAINT fk_incident_opened_by FOREIGN KEY (opened_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_incident_opened_role FOREIGN KEY (opened_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.incident IS 'tier:1. Governance incident; status mutable (D4). C9.';

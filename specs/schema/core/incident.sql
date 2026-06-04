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
COMMENT ON TABLE core.incident IS
'A governance incident, optionally tied to an executable_version, with a severity and a mutable status (open/...). The no-silent-loss record that something went wrong and how it was resolved (C9, D4).

@tier 1
@lifecycle mutable
@subject validation
@status reference.incident_severity
@status reference.incident_status
@decision D4';
COMMENT ON COLUMN core.incident.incident_id IS
'Identity of the incident.';
COMMENT ON COLUMN core.incident.executable_version_id IS
'The version implicated, if any; set null if it is purged. @ref core.executable_version hard';
COMMENT ON COLUMN core.incident.incident_severity_code IS
'Severity. @status reference.incident_severity';
COMMENT ON COLUMN core.incident.incident_status_code IS
'Mutable status; transitions audited in audit.status_transition. @status reference.incident_status';
COMMENT ON COLUMN core.incident.title IS
'Short title.';
COMMENT ON COLUMN core.incident.description IS
'What happened.';
COMMENT ON COLUMN core.incident.created_at IS
'When opened.';
COMMENT ON COLUMN core.incident.updated_at IS
'When last updated.';
COMMENT ON COLUMN core.incident.opened_by_actor_id IS
'Who opened it. @ref core.actor hard';
COMMENT ON COLUMN core.incident.opened_role_code IS
'The capacity they acted in. @status reference.role';

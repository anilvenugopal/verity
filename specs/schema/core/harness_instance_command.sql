-- core.harness_instance_command  ·  subject: deploy  ·  (table)

CREATE TABLE core.harness_instance_command (
    harness_instance_command_id uuid NOT NULL DEFAULT uuidv7(),
    harness_instance_id   uuid       NOT NULL,
    command_kind_code     text       NOT NULL,                  -- patch|restart|drain|enable|disable|reload_packages|collect_diagnostics
    params                jsonb      NOT NULL DEFAULT '{}'::jsonb,
    command_status_code   text       NOT NULL DEFAULT 'pending',-- pending|acknowledged|succeeded|failed
    issued_by_actor_id    uuid       NOT NULL,
    issued_role_code      text       NOT NULL,
    issued_at             timestamptz NOT NULL DEFAULT now(),
    acknowledged_at       timestamptz,
    completed_at          timestamptz,
    result                jsonb,                                  -- e.g. diagnostics pointer (logs in observability, not here)
    CONSTRAINT pk_harness_instance_command PRIMARY KEY (harness_instance_command_id),
    CONSTRAINT fk_hic_instance FOREIGN KEY (harness_instance_id) REFERENCES core.harness_instance (harness_instance_id) ON DELETE RESTRICT,
    CONSTRAINT fk_hic_kind FOREIGN KEY (command_kind_code) REFERENCES reference.command_kind (code),
    CONSTRAINT fk_hic_status FOREIGN KEY (command_status_code) REFERENCES reference.command_status (code),
    CONSTRAINT fk_hic_issued_by FOREIGN KEY (issued_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_hic_issued_role FOREIGN KEY (issued_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.harness_instance_command IS 'tier:1 append-only. Portal->agent control commands (patch/drain/enable/...). status pending->acknowledged->succeeded/failed. D8.';
CREATE INDEX ix_hic_instance_time ON core.harness_instance_command (harness_instance_id, issued_at DESC);

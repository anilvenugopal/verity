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
COMMENT ON TABLE core.harness_instance_command IS
'The append-only log of portal->agent control commands (patch, restart, drain, enable/disable, reload_packages, deploy_package, collect_diagnostics, patch_cert). Each command''s own lifecycle is pending->acknowledged->succeeded/failed; reliable delivery to the cluster is handled separately by the harness_command_outbox written in the same transaction (ADR-0010).

@tier 1
@lifecycle append-only
@subject deploy
@status reference.command_kind
@status reference.command_status
@decision D8
@adr 0010';
CREATE INDEX ix_hic_instance_time ON core.harness_instance_command (harness_instance_id, issued_at DESC);
COMMENT ON COLUMN core.harness_instance_command.harness_instance_command_id IS
'Identity of the command.';
COMMENT ON COLUMN core.harness_instance_command.harness_instance_id IS
'The instance the command targets. @ref core.harness_instance hard';
COMMENT ON COLUMN core.harness_instance_command.command_kind_code IS
'What to do. A patch (image) may carry a graceful-vs-force drain choice; deploy_package swaps the bundle without draining. @status reference.command_kind';
COMMENT ON COLUMN core.harness_instance_command.params IS
'Command arguments — e.g. target image, drain flag, diagnostics scope.';
COMMENT ON COLUMN core.harness_instance_command.command_status_code IS
'The commands own progress: pending->acknowledged->succeeded/failed. Distinct from its outbox delivery state. @status reference.command_status';
COMMENT ON COLUMN core.harness_instance_command.issued_by_actor_id IS
'Who issued the command. @ref core.actor hard';
COMMENT ON COLUMN core.harness_instance_command.issued_role_code IS
'The capacity they acted in. @status reference.role';
COMMENT ON COLUMN core.harness_instance_command.issued_at IS
'When the command was issued.';
COMMENT ON COLUMN core.harness_instance_command.acknowledged_at IS
'When the coordinator acknowledged receipt. @actor coordinator';
COMMENT ON COLUMN core.harness_instance_command.completed_at IS
'When the command finished, succeeded or failed. @actor coordinator';
COMMENT ON COLUMN core.harness_instance_command.result IS
'Execution result — e.g. a diagnostics pointer; bulk logs live in observability, not here.';

-- =====================================================================
-- 08-deploy.sql — Verity v2 hardened schema · PACKAGES, DEPLOYMENT, HARNESS CONTROL PLANE
-- Per D8 (BigID-style control plane): harness variant/image/instance, heartbeats
-- (minor/major + running-package catalog), portal->agent commands, packages +
-- digest-pinned compatibility, governed deployment, connection + binding overrides,
-- and the lifecycle->environment rule matrix. champion != deployed.
-- =====================================================================

-- ===== harness images (variant + version + digest) ===================
CREATE TABLE core.harness_image (
    harness_image_id  uuid        NOT NULL DEFAULT uuidv7(),
    variant_code      text        NOT NULL,                     -- reference.harness_variant
    harness_version   text        NOT NULL,                     -- semver/build of the harness
    image_digest      text        NOT NULL,                     -- immutable content fingerprint (sha256:...)
    registry_ref      text        NOT NULL,                     -- e.g. ghcr.io/verity/harness
    created_at        timestamptz  NOT NULL DEFAULT now(),
    created_by_actor_id uuid      NOT NULL,
    created_role_code text        NOT NULL,
    CONSTRAINT pk_harness_image PRIMARY KEY (harness_image_id),
    CONSTRAINT fk_harness_image_variant FOREIGN KEY (variant_code) REFERENCES reference.harness_variant (code),
    CONSTRAINT fk_harness_image_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_harness_image_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_harness_image_digest UNIQUE (image_digest),
    CONSTRAINT ck_harness_image_digest_format CHECK (image_digest ~ '^sha256:[0-9a-f]{64}$'));
COMMENT ON TABLE core.harness_image IS 'tier:1. A built harness container = variant + version + immutable image_digest (the identity; tags are advisory). ADR-0006/D8.';

-- ===== environments & clusters =======================================
CREATE TABLE core.deployment_environment (
    deployment_environment_id uuid  NOT NULL DEFAULT uuidv7(),
    name                  text       NOT NULL,
    environment_kind_code text       NOT NULL,                  -- non_prod | prod | ephemeral
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_environment PRIMARY KEY (deployment_environment_id),
    CONSTRAINT fk_deployment_environment_kind FOREIGN KEY (environment_kind_code) REFERENCES reference.environment_kind (code),
    CONSTRAINT uq_deployment_environment_name UNIQUE (name));

CREATE TABLE core.deployment_cluster (
    deployment_cluster_id uuid       NOT NULL DEFAULT uuidv7(),
    deployment_environment_id uuid   NOT NULL,
    name                  text       NOT NULL,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_cluster PRIMARY KEY (deployment_cluster_id),
    CONSTRAINT fk_deployment_cluster_environment FOREIGN KEY (deployment_environment_id) REFERENCES core.deployment_environment (deployment_environment_id) ON DELETE RESTRICT,
    CONSTRAINT uq_deployment_cluster_name UNIQUE (name));
COMMENT ON TABLE core.deployment_cluster IS 'tier:1. A cluster within an environment (multiple per env, incl. ephemeral/replay). D8.';

-- ===== harness_instance (the running harness "collector"; BigID-style) =
CREATE TABLE core.harness_instance (
    harness_instance_id   uuid       NOT NULL DEFAULT uuidv7(),
    deployment_cluster_id uuid       NOT NULL,
    current_image_id      uuid       NOT NULL,                  -- the image it is running
    desired_image_id      uuid,                                  -- patch target (desired-vs-current convergence)
    application_id        uuid,                                  -- owned (set) vs shared (NULL) fleet
    harness_instance_status_code text NOT NULL DEFAULT 'active',-- active | draining | disabled
    last_seen             timestamptz,                           -- denormalized from heartbeats (fast "who is down")
    registered_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_harness_instance PRIMARY KEY (harness_instance_id),
    CONSTRAINT fk_harness_instance_cluster FOREIGN KEY (deployment_cluster_id) REFERENCES core.deployment_cluster (deployment_cluster_id) ON DELETE RESTRICT,
    CONSTRAINT fk_harness_instance_current_image FOREIGN KEY (current_image_id) REFERENCES core.harness_image (harness_image_id) ON DELETE RESTRICT,
    CONSTRAINT fk_harness_instance_desired_image FOREIGN KEY (desired_image_id) REFERENCES core.harness_image (harness_image_id) ON DELETE RESTRICT,
    CONSTRAINT fk_harness_instance_application FOREIGN KEY (application_id) REFERENCES core.application (application_id) ON DELETE RESTRICT,
    CONSTRAINT fk_harness_instance_status FOREIGN KEY (harness_instance_status_code) REFERENCES reference.harness_instance_status (code));
COMMENT ON TABLE core.harness_instance IS 'tier:1. A running harness container on a cluster (the "collector"): current/desired image (patch via convergence), owned/shared scope, status, last_seen. D8.';
CREATE INDEX ix_harness_instance_cluster ON core.harness_instance (deployment_cluster_id);

-- ===== harness_instance_command (portal -> agent control channel) =====
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

-- ===== harness_heartbeat (agent -> portal; Tier-2, partitioned) =======
CREATE TABLE audit.harness_heartbeat (
    harness_heartbeat_id  uuid       NOT NULL DEFAULT uuidv7(),
    harness_instance_id   uuid       NOT NULL,                  -- soft ref -> core.harness_instance
    heartbeat_kind_code   text       NOT NULL,                  -- minor | major
    health_status_code    text       NOT NULL,                  -- healthy | degraded | down | unknown
    running_image_digest  text,                                  -- what version it is actually running
    running_packages      jsonb,                                 -- major: catalog of loaded packages (drift detection)
    metrics               jsonb,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_harness_heartbeat PRIMARY KEY (harness_heartbeat_id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE audit.harness_heartbeat IS 'tier:2 append-only (partitioned). Agent->portal heartbeats: minor (frequent/light) + major (running-package catalog -> drift detection). D8.';
CREATE INDEX ix_harness_heartbeat_instance_time ON audit.harness_heartbeat (harness_instance_id, created_at DESC);
CREATE TABLE audit.harness_heartbeat_2026_06 PARTITION OF audit.harness_heartbeat FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.harness_heartbeat_2026_07 PARTITION OF audit.harness_heartbeat FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');

CREATE VIEW audit.harness_instance_health_current AS
SELECT DISTINCT ON (harness_instance_id)
       harness_instance_id, health_status_code, running_image_digest, created_at AS last_seen
FROM   audit.harness_heartbeat
ORDER  BY harness_instance_id, created_at DESC;

CREATE VIEW audit.harness_running_package_current AS
SELECT DISTINCT ON (harness_instance_id)
       harness_instance_id, running_packages, created_at AS as_of
FROM   audit.harness_heartbeat
WHERE  heartbeat_kind_code = 'major'
ORDER  BY harness_instance_id, created_at DESC;
COMMENT ON VIEW audit.harness_running_package_current IS 'Latest reported running-package catalog per instance (from major heartbeats). Compare to deployments for drift. D8.';

-- ===== packages + compatibility ======================================
CREATE TABLE core.package (
    package_id            uuid       NOT NULL DEFAULT uuidv7(),
    executable_version_id uuid       NOT NULL,                  -- the champion version packaged
    package_kind_code     text       NOT NULL,                  -- vtx|vax (= executable_kind.package_format)
    package_digest        text       NOT NULL,                  -- immutable artifact fingerprint
    manifest              jsonb,                                 -- bundle manifest (config/bindings/connections snapshot)
    built_at              timestamptz NOT NULL DEFAULT now(),
    built_by_actor_id     uuid       NOT NULL,                  -- usually an automation actor
    built_role_code       text       NOT NULL,
    CONSTRAINT pk_package PRIMARY KEY (package_id),
    CONSTRAINT fk_package_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE RESTRICT,
    CONSTRAINT fk_package_kind FOREIGN KEY (package_kind_code) REFERENCES reference.executable_kind (code),
    CONSTRAINT fk_package_built_by FOREIGN KEY (built_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_package_built_role FOREIGN KEY (built_role_code) REFERENCES reference.role (code),
    CONSTRAINT uq_package_digest UNIQUE (package_digest));
COMMENT ON TABLE core.package IS 'tier:1 insert-only. The .vtx/.vax artifact built from a champion executable_version. D8/ADR-0006.';

CREATE TABLE core.package_harness_compatibility (
    package_id            uuid       NOT NULL,
    variant_code          text       NOT NULL,                  -- compatible harness variant
    min_harness_version   text,                                  -- declared loosely; deploy resolves+pins a digest
    max_harness_version   text,
    CONSTRAINT pk_package_harness_compatibility PRIMARY KEY (package_id, variant_code),
    CONSTRAINT fk_phc_package FOREIGN KEY (package_id) REFERENCES core.package (package_id) ON DELETE CASCADE,
    CONSTRAINT fk_phc_variant FOREIGN KEY (variant_code) REFERENCES reference.harness_variant (code));
COMMENT ON TABLE core.package_harness_compatibility IS 'tier:1. Package <-> harness variant + version range it can run on. Declared loosely; the deploy gate resolves & pins an exact image_digest. D8/ADR-0006.';

-- ===== deployment + governed-operation events ========================
CREATE TABLE core.deployment (
    deployment_id         uuid       NOT NULL DEFAULT uuidv7(),
    package_id            uuid       NOT NULL,
    harness_image_id      uuid       NOT NULL,                  -- the EXACT pinned image (resolved at deploy)
    deployment_cluster_id uuid       NOT NULL,
    deployment_run_mode_code text    NOT NULL,                  -- live|shadow|ab|locked
    deployment_status_code text      NOT NULL DEFAULT 'active', -- active|superseded|stopped (mutable; transitions -> audit.status_transition)
    deployed_by_actor_id  uuid       NOT NULL,
    deployed_role_code    text       NOT NULL,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment PRIMARY KEY (deployment_id),
    CONSTRAINT fk_deployment_package FOREIGN KEY (package_id) REFERENCES core.package (package_id) ON DELETE RESTRICT,
    CONSTRAINT fk_deployment_image FOREIGN KEY (harness_image_id) REFERENCES core.harness_image (harness_image_id) ON DELETE RESTRICT,
    CONSTRAINT fk_deployment_cluster FOREIGN KEY (deployment_cluster_id) REFERENCES core.deployment_cluster (deployment_cluster_id) ON DELETE RESTRICT,
    CONSTRAINT fk_deployment_run_mode FOREIGN KEY (deployment_run_mode_code) REFERENCES reference.deployment_run_mode (code),
    CONSTRAINT fk_deployment_status FOREIGN KEY (deployment_status_code) REFERENCES reference.deployment_status (code),
    CONSTRAINT fk_deployment_deployed_by FOREIGN KEY (deployed_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_deployment_deployed_role FOREIGN KEY (deployed_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.deployment IS 'tier:1. A package placed to run: pinned harness image (both package & image digests recorded), cluster, run_mode, status. champion!=deployed. D8/ADR-0006.';
CREATE INDEX ix_deployment_package ON core.deployment (package_id);
CREATE INDEX ix_deployment_cluster ON core.deployment (deployment_cluster_id);

CREATE TABLE core.deployment_event (
    deployment_event_id   uuid       NOT NULL DEFAULT uuidv7(),
    deployment_id         uuid,                                  -- nullable for a rejected request
    package_id            uuid       NOT NULL,
    deployment_operation_code text   NOT NULL,                  -- deploy_*|promote_champion|lock_deprecated|cleanup_deprecated|rollback
    deployment_outcome_code text     NOT NULL,                  -- requested|rejected_*|succeeded|failed|superseded
    detail                jsonb      NOT NULL DEFAULT '{}'::jsonb,
    actor_id              uuid       NOT NULL,
    acting_role_code      text       NOT NULL,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_event PRIMARY KEY (deployment_event_id),
    CONSTRAINT fk_deployment_event_deployment FOREIGN KEY (deployment_id) REFERENCES core.deployment (deployment_id) ON DELETE RESTRICT,
    CONSTRAINT fk_deployment_event_package FOREIGN KEY (package_id) REFERENCES core.package (package_id) ON DELETE RESTRICT,
    CONSTRAINT fk_deployment_event_operation FOREIGN KEY (deployment_operation_code) REFERENCES reference.deployment_operation (code),
    CONSTRAINT fk_deployment_event_outcome FOREIGN KEY (deployment_outcome_code) REFERENCES reference.deployment_outcome (code),
    CONSTRAINT fk_deployment_event_actor FOREIGN KEY (actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_deployment_event_acting_role FOREIGN KEY (acting_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.deployment_event IS 'tier:1 append-only. Governed deployment operations + outcome (the inventory/audit of deploy actions, incl. rejections). D8/ADR-0006.';
CREATE INDEX ix_deployment_event_deployment ON core.deployment_event (deployment_id, created_at DESC);

-- ===== per-deployment connections + binding overrides ================
CREATE TABLE core.deployment_connection (
    deployment_connection_id uuid    NOT NULL DEFAULT uuidv7(),
    deployment_id         uuid       NOT NULL,
    data_connector_version_id uuid   NOT NULL,                  -- the env-specific backend
    purpose               text,
    config                jsonb      NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT pk_deployment_connection PRIMARY KEY (deployment_connection_id),
    CONSTRAINT fk_deployment_connection_deployment FOREIGN KEY (deployment_id) REFERENCES core.deployment (deployment_id) ON DELETE CASCADE,
    CONSTRAINT fk_deployment_connection_connector FOREIGN KEY (data_connector_version_id) REFERENCES core.data_connector_version (data_connector_version_id) ON DELETE RESTRICT);
COMMENT ON TABLE core.deployment_connection IS 'tier:1. Env-specific connections for a deployment; also materialized into the package bundle so the harness is self-contained at runtime. D8.';

CREATE TABLE core.deployment_binding_override (
    deployment_binding_override_id uuid NOT NULL DEFAULT uuidv7(),
    deployment_id         uuid       NOT NULL,
    binding_kind          text       NOT NULL,                  -- 'source' | 'target'
    binding_name          text       NOT NULL,                  -- which binding (by name on the version)
    is_mocked             boolean     NOT NULL DEFAULT false,    -- real vs mocked
    mock_payload          jsonb,
    CONSTRAINT pk_deployment_binding_override PRIMARY KEY (deployment_binding_override_id),
    CONSTRAINT fk_dbo_deployment FOREIGN KEY (deployment_id) REFERENCES core.deployment (deployment_id) ON DELETE CASCADE,
    CONSTRAINT ck_dbo_binding_kind CHECK (binding_kind IN ('source','target')),
    CONSTRAINT uq_dbo_deployment_binding UNIQUE (deployment_id, binding_kind, binding_name));
COMMENT ON TABLE core.deployment_binding_override IS 'tier:1. Per-binding real|mock override for a deployment. NOTE: run_mode=shadow FORCIBLY suppresses/mocks ALL Target Bindings regardless of these rows (the shadow safety rail; enforced by the harness). D8.';

-- ===== lifecycle -> environment rule matrix (ADR-0006 as DATA) ========
CREATE TABLE core.lifecycle_deployment_rule (
    lifecycle_state_code  text       NOT NULL,
    environment_kind_code text       NOT NULL,
    allowed_run_modes     text[]     NOT NULL,                  -- subset of {live,shadow,ab,locked}
    output_suppressed     boolean     NOT NULL DEFAULT false,
    CONSTRAINT pk_lifecycle_deployment_rule PRIMARY KEY (lifecycle_state_code, environment_kind_code),
    CONSTRAINT fk_ldr_state FOREIGN KEY (lifecycle_state_code) REFERENCES reference.lifecycle_state (code),
    CONSTRAINT fk_ldr_env FOREIGN KEY (environment_kind_code) REFERENCES reference.environment_kind (code));
COMMENT ON TABLE core.lifecycle_deployment_rule IS 'tier:1. The ADR-0006 lifecycle->environment matrix as auditable DATA: which run-modes a state may use per environment, and whether outputs suppress. The deploy gate reads this. D8.';
-- seed the matrix (6-state; shadow/ab are challenger run-modes)
INSERT INTO core.lifecycle_deployment_rule (lifecycle_state_code, environment_kind_code, allowed_run_modes, output_suppressed) VALUES
    ('staging',   'non_prod',  ARRAY['live'],            false),
    ('challenger','prod',      ARRAY['shadow','ab'],     false),
    ('challenger','ephemeral', ARRAY['shadow','ab'],     false),
    ('champion',  'prod',      ARRAY['live'],            false),
    ('champion',  'non_prod',  ARRAY['live'],            false),
    ('champion',  'ephemeral', ARRAY['live','shadow'],   false),
    ('deprecated','prod',      ARRAY['locked'],          true),
    ('deprecated','ephemeral', ARRAY['locked','shadow'], true);

-- ===== wire deferred FK from 07-runs ==================================
ALTER TABLE runtime.execution_run
    ADD CONSTRAINT fk_execution_run_run_mode FOREIGN KEY (deployment_run_mode_code) REFERENCES reference.deployment_run_mode (code);

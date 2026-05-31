-- 08-packages_deploy.sql — hardened v2 schema domain: packages_deploy
-- See ASSEMBLY-AND-VERIFICATION.md for cross-domain FKs & review items.

-- ============================================================================
-- DOMAIN: PACKAGES & GOVERNED DEPLOYMENT  (v2-new; ADR-0006)
-- Schema: governance   |   Conventions: specs/schema/naming-conventions.md (ADR-0005)
-- Keys: uuidv7() (PG18+). FALLBACK on PG<18: define a uuidv7() SQL/PLpgSQL shim or
--   substitute gen_random_uuid() in the DEFAULT (time-ordering / BRIN locality lost).
-- All tables here are Tier-1 (system-of-record). Insert-only / append-only as noted.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ENUM TYPES
-- ----------------------------------------------------------------------------

-- package artifact kind: .vtx = task package, .vax = agent package (ADR-0006 §Context)
CREATE TYPE governance.package_kind AS ENUM (
    'vtx',
    'vax'
);
COMMENT ON TYPE governance.package_kind IS
    'Package artifact kind: vtx (.vtx task package) / vax (.vax agent package). ADR-0006.';

-- environment tier grouping clusters (ADR-0006 §1: non-prod / prod, incl. ephemeral)
CREATE TYPE governance.environment_kind AS ENUM (
    'non_prod',
    'prod',
    'ephemeral'
);
COMMENT ON TYPE governance.environment_kind IS
    'Environment classification for clusters: non_prod, prod, ephemeral (temp/replay). ADR-0006.';

-- lifecycle states verbatim from v1 governance.lifecycle_state (V2 NAMING/MODEL DELTAS).
-- Re-declared here as the canonical type; if the registry/lifecycle domain also emits
-- this type, keep ONE definition (see open issues).
CREATE TYPE governance.lifecycle_state AS ENUM (
    'draft',
    'candidate',
    'staging',
    'shadow',
    'challenger',
    'champion',
    'deprecated'
);
COMMENT ON TYPE governance.lifecycle_state IS
    'Verbatim v1 lifecycle states. Shared type; defined once across the schema. ADR-0006 §1.';

-- governed deployment operations (ADR-0006 §3 action-matrix verbs)
CREATE TYPE governance.deployment_operation AS ENUM (
    'deploy_nonprod',
    'deploy_prod',
    'promote_champion',
    'lock_deprecated',
    'cleanup_deprecated',
    'rollback'
);
COMMENT ON TYPE governance.deployment_operation IS
    'Governed deployment operations mediated by the control plane. ADR-0006 §3.';

-- run mode the harness executes a deployed package under (ADR-0006 §1 matrix)
CREATE TYPE governance.deployment_run_mode AS ENUM (
    'live',          -- target bindings (writes) enabled
    'read_only',     -- executes + writes decision log; target bindings suppressed
    'ab_slice',      -- challenger live on an A/B slice
    'locked'         -- deprecated: audit/replay only, no new placement
);
COMMENT ON TYPE governance.deployment_run_mode IS
    'Run mode: live / read_only (writes suppressed) / ab_slice / locked. ADR-0006 §1.';

-- outcome of a governed deployment request (append-only event)
CREATE TYPE governance.deployment_outcome AS ENUM (
    'requested',
    'rejected_incompatible',   -- package x image digest combination refused (ADR-0006 §2)
    'rejected_lifecycle',      -- state->environment matrix violated (ADR-0006 §1)
    'rejected_unauthorized',   -- action-matrix denied (ADR-0006 §3)
    'succeeded',
    'failed',
    'superseded'               -- replaced by a later deployment of same package on same target
);
COMMENT ON TYPE governance.deployment_outcome IS
    'Outcome recorded per governed deployment event. ADR-0006 §1-§3.';

-- ----------------------------------------------------------------------------
-- TABLE: harness_image  (Tier-1, INSERT-ONLY registry)
--   An immutable, digest-identified Verity harness image. ADR-0006 §2.
-- ----------------------------------------------------------------------------
CREATE TABLE governance.harness_image (
    harness_image_id  uuid        NOT NULL DEFAULT uuidv7(),
    -- registry reference + tag are descriptive; identity is the digest.
    registry_ref      text        NOT NULL,                 -- e.g. ghcr.io/verity/harness
    image_tag         text,                                 -- mutable tag, informational only
    image_digest      text        NOT NULL,                 -- immutable content digest (sha256:...)
    harness_version   text        NOT NULL,                 -- semver/build of the harness build
    notes             text,
    created_at        timestamptz NOT NULL DEFAULT now(),
    created_by        uuid,                                 -- FK -> governance.user (AUTH domain)
    CONSTRAINT pk_harness_image PRIMARY KEY (harness_image_id),
    CONSTRAINT uq_harness_image_digest UNIQUE (image_digest),
    CONSTRAINT ck_harness_image_digest_format
        CHECK (image_digest ~ '^sha256:[0-9a-f]{64}$')
    -- fk_harness_image_created_by added once governance.user exists (AUTH domain).
);
COMMENT ON TABLE governance.harness_image IS
    'tier:1 insert-only. Digest-identified Verity harness image registry. ADR-0006 §2. '
    'Rows are immutable facts; never updated/deleted.';
COMMENT ON COLUMN governance.harness_image.image_digest IS
    'Immutable content digest (sha256:<64hex>); the true identity. Tags are advisory (ADR-0006 §2).';

CREATE INDEX ix_harness_image_registry_ref
    ON governance.harness_image (registry_ref);

-- ----------------------------------------------------------------------------
-- TABLE: package  (Tier-1, INSERT-ONLY inventory)
--   A built, deployable .vtx/.vax package pinned to a source entity version.
--   ADR-0006 §Context (package is the unit of deployment).
-- ----------------------------------------------------------------------------
CREATE TABLE governance.package (
    package_id          uuid        NOT NULL DEFAULT uuidv7(),
    package_kind        governance.package_kind NOT NULL,    -- vtx | vax
    -- the governed source this package was built from. Polymorphic over
    -- agent_version / task_version in the REGISTRY domain; resolved by source_kind.
    source_kind         text        NOT NULL,                -- 'agent_version' | 'task_version'
    source_version_id   uuid        NOT NULL,                -- FK -> agent_version/task_version (REGISTRY)
    package_name        text        NOT NULL,                -- logical package name
    package_semver      text        NOT NULL,                -- built package version (semver)
    package_digest      text        NOT NULL,                -- immutable content digest of the artifact
    artifact_uri        text,                                -- where the .vtx/.vax bytes live (registry)
    built_at            timestamptz,                         -- when the artifact was produced
    created_at          timestamptz NOT NULL DEFAULT now(),
    created_by          uuid,                                -- FK -> governance.user (AUTH domain)
    CONSTRAINT pk_package PRIMARY KEY (package_id),
    CONSTRAINT uq_package_digest UNIQUE (package_digest),
    CONSTRAINT uq_package_name_semver UNIQUE (package_name, package_semver),
    CONSTRAINT ck_package_source_kind_known
        CHECK (source_kind IN ('agent_version', 'task_version')),
    -- a .vax must come from an agent_version, a .vtx from a task_version (ADR-0006).
    CONSTRAINT ck_package_kind_matches_source
        CHECK (
            (package_kind = 'vax' AND source_kind = 'agent_version')
            OR (package_kind = 'vtx' AND source_kind = 'task_version')
        ),
    CONSTRAINT ck_package_digest_format
        CHECK (package_digest ~ '^sha256:[0-9a-f]{64}$')
    -- fk_package_source_version is a polymorphic ref (source_kind + source_version_id);
    --   enforce in REGISTRY domain or app layer (see open issues).
);
COMMENT ON TABLE governance.package IS
    'tier:1 insert-only. Built .vtx/.vax package inventory pinned to a source entity '
    'version, identified by immutable digest. ADR-0006. Rows immutable; rebuild = new row.';
COMMENT ON COLUMN governance.package.source_version_id IS
    'Polymorphic FK to governance.agent_version / governance.task_version per source_kind (REGISTRY domain).';

CREATE INDEX ix_package_source_version_id
    ON governance.package (source_kind, source_version_id);

-- ----------------------------------------------------------------------------
-- TABLE: package_harness_image  (Tier-1, INSERT-ONLY compatibility bridge)
--   Declares the digest-pinned set of harness images a package may run on.
--   ADR-0006 §2: compatibility tracked by digest; deploy refuses incompatible combos.
-- ----------------------------------------------------------------------------
CREATE TABLE governance.package_harness_image (
    package_harness_image_id  uuid        NOT NULL DEFAULT uuidv7(),
    package_id                uuid        NOT NULL,
    harness_image_id          uuid        NOT NULL,
    declared_in_manifest      boolean     NOT NULL DEFAULT true,  -- from the package manifest
    created_at                timestamptz NOT NULL DEFAULT now(),
    created_by                uuid,                               -- FK -> governance.user (AUTH)
    CONSTRAINT pk_package_harness_image PRIMARY KEY (package_harness_image_id),
    CONSTRAINT uq_package_harness_image UNIQUE (package_id, harness_image_id),
    CONSTRAINT fk_package_harness_image_package
        FOREIGN KEY (package_id)
        REFERENCES governance.package (package_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_package_harness_image_image
        FOREIGN KEY (harness_image_id)
        REFERENCES governance.harness_image (harness_image_id)
        ON DELETE RESTRICT
);
COMMENT ON TABLE governance.package_harness_image IS
    'tier:1 insert-only. Digest-pinned package x harness-image compatibility set. '
    'The deploy path refuses a package on a non-listed image. ADR-0006 §2.';

CREATE INDEX ix_package_harness_image_image_id
    ON governance.package_harness_image (harness_image_id);

-- ----------------------------------------------------------------------------
-- TABLE: deployment_environment  (Tier-1 registry)
--   Named environment grouping clusters (non-prod / prod / ephemeral). ADR-0006 §1.
-- ----------------------------------------------------------------------------
CREATE TABLE governance.deployment_environment (
    deployment_environment_id  uuid        NOT NULL DEFAULT uuidv7(),
    environment_name           text        NOT NULL,
    environment_kind           governance.environment_kind NOT NULL,
    description                text,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_environment PRIMARY KEY (deployment_environment_id),
    CONSTRAINT uq_deployment_environment_name UNIQUE (environment_name)
);
COMMENT ON TABLE governance.deployment_environment IS
    'tier:1. Named environment (non_prod/prod/ephemeral) grouping clusters. ADR-0006 §1.';

-- ----------------------------------------------------------------------------
-- TABLE: deployment_cluster  (Tier-1 registry)
--   A target cluster within an environment (incl. ephemeral/replay clusters). ADR-0006 §1.
-- ----------------------------------------------------------------------------
CREATE TABLE governance.deployment_cluster (
    deployment_cluster_id      uuid        NOT NULL DEFAULT uuidv7(),
    deployment_environment_id  uuid        NOT NULL,
    cluster_name               text        NOT NULL,
    is_ephemeral               boolean     NOT NULL DEFAULT false,  -- temp/replay cluster
    description                text,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    decommissioned_at          timestamptz,                          -- soft retire of a cluster registration
    CONSTRAINT pk_deployment_cluster PRIMARY KEY (deployment_cluster_id),
    CONSTRAINT uq_deployment_cluster_name UNIQUE (cluster_name),
    CONSTRAINT fk_deployment_cluster_environment
        FOREIGN KEY (deployment_environment_id)
        REFERENCES governance.deployment_environment (deployment_environment_id)
        ON DELETE RESTRICT
);
COMMENT ON TABLE governance.deployment_cluster IS
    'tier:1. Target cluster within an environment, incl. ephemeral replay clusters. ADR-0006 §1.';

CREATE INDEX ix_deployment_cluster_environment_id
    ON governance.deployment_cluster (deployment_environment_id);

-- ----------------------------------------------------------------------------
-- TABLE: deployment  (Tier-1, APPEND-ONLY, lifecycle-gated event)
--   One immutable row per governed deployment request. ADR-0006 §1-§3.
--   Records: package, lifecycle state, target cluster/environment, image digest,
--   run mode, actor, operation, outcome. Never updated in place.
-- ----------------------------------------------------------------------------
CREATE TABLE governance.deployment (
    deployment_id              uuid        NOT NULL DEFAULT uuidv7(),
    package_id                 uuid        NOT NULL,
    harness_image_id           uuid        NOT NULL,             -- the digest-pinned image used
    deployment_cluster_id      uuid        NOT NULL,
    deployment_environment_id  uuid        NOT NULL,             -- denormalized for matrix CHECK + reporting
    lifecycle_state            governance.lifecycle_state    NOT NULL,
    deployment_operation       governance.deployment_operation NOT NULL,
    run_mode                   governance.deployment_run_mode  NOT NULL,
    outcome                    governance.deployment_outcome   NOT NULL DEFAULT 'requested',
    rejection_detail           text,                            -- why, when outcome is a reject/fail
    actor_user_id              uuid        NOT NULL,             -- FK -> governance.user (AUTH); server-resolved
    actor_role                 text        NOT NULL,            -- platform/app-team role exercised (AUTH)
    requested_at               timestamptz NOT NULL DEFAULT now(),
    completed_at               timestamptz,                     -- when outcome reached terminal
    CONSTRAINT pk_deployment PRIMARY KEY (deployment_id),
    CONSTRAINT fk_deployment_package
        FOREIGN KEY (package_id)
        REFERENCES governance.package (package_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_deployment_image
        FOREIGN KEY (harness_image_id)
        REFERENCES governance.harness_image (harness_image_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_deployment_cluster
        FOREIGN KEY (deployment_cluster_id)
        REFERENCES governance.deployment_cluster (deployment_cluster_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_deployment_environment
        FOREIGN KEY (deployment_environment_id)
        REFERENCES governance.deployment_environment (deployment_environment_id)
        ON DELETE RESTRICT,
    -- ADR-0006 §1 state->environment matrix (encoded as a real invariant):
    --   draft/candidate     : not deployable at all
    --   staging             : non_prod only
    --   shadow/challenger   : prod or any (read-only / A/B)
    --   champion/deprecated : any environment
    CONSTRAINT ck_deployment_state_environment_matrix
        CHECK (
            CASE lifecycle_state
                WHEN 'draft'      THEN false
                WHEN 'candidate'  THEN false
                WHEN 'staging'    THEN environment_kind_of = 'non_prod'
                ELSE true   -- shadow, challenger, champion, deprecated
            END
        ),
    -- ADR-0006 §1 run-mode gating per state:
    --   staging  -> live ; shadow -> read_only ; challenger -> read_only|ab_slice ;
    --   champion -> live ; deprecated -> locked
    CONSTRAINT ck_deployment_state_run_mode
        CHECK (
            CASE lifecycle_state
                WHEN 'staging'    THEN run_mode = 'live'
                WHEN 'shadow'     THEN run_mode = 'read_only'
                WHEN 'challenger' THEN run_mode IN ('read_only', 'ab_slice')
                WHEN 'champion'   THEN run_mode = 'live'
                WHEN 'deprecated' THEN run_mode = 'locked'
                ELSE false  -- draft/candidate never reach a deployment row
            END
        ),
    CONSTRAINT ck_deployment_completed_after_requested
        CHECK (completed_at IS NULL OR completed_at >= requested_at),
    CONSTRAINT ck_deployment_rejection_detail_present
        CHECK (
            outcome NOT IN ('rejected_incompatible','rejected_lifecycle',
                            'rejected_unauthorized','failed')
            OR rejection_detail IS NOT NULL
        )
    -- fk_deployment_actor added once governance.user exists (AUTH domain).
);
-- NOTE: ck_deployment_state_environment_matrix references environment_kind via a
--   generated helper column (below) so the matrix is enforceable without a subquery
--   (CHECK constraints cannot contain subqueries). environment_kind_of is kept in sync
--   to deployment_environment_id by the app/control plane at insert time.
ALTER TABLE governance.deployment
    ADD COLUMN environment_kind_of governance.environment_kind NOT NULL;
COMMENT ON COLUMN governance.deployment.environment_kind_of IS
    'Copy of the target environment_kind, set at insert from deployment_environment, so the '
    'state->environment matrix CHECK can be expressed without a subquery. Control plane keeps it consistent.';

COMMENT ON TABLE governance.deployment IS
    'tier:1 append-only. One immutable row per governed deployment request: package, '
    'lifecycle state, target cluster/environment, image digest, run mode, actor, '
    'operation, outcome. Lifecycle-gated (ADR-0006 §1) and digest-compatibility-gated '
    '(§2); deployment is mediated by the control plane (§3). Never updated in place; '
    'a state change is a new row. Out-of-band deploys are disallowed.';

CREATE INDEX ix_deployment_package_id
    ON governance.deployment (package_id, requested_at DESC);
CREATE INDEX ix_deployment_cluster_id
    ON governance.deployment (deployment_cluster_id, requested_at DESC);
CREATE INDEX ix_deployment_environment_id
    ON governance.deployment (deployment_environment_id);
CREATE INDEX ix_deployment_image_id
    ON governance.deployment (harness_image_id);
CREATE INDEX ix_deployment_actor_user_id
    ON governance.deployment (actor_user_id);

-- ----------------------------------------------------------------------------
-- VIEW: deployment_current  — latest successful deployment per (package, cluster)
--   "What is running where" single source of truth. ADR-0006 §3 / Consequences.
-- ----------------------------------------------------------------------------
CREATE VIEW governance.deployment_current AS
SELECT DISTINCT ON (d.package_id, d.deployment_cluster_id)
       d.deployment_id,
       d.package_id,
       d.harness_image_id,
       d.deployment_cluster_id,
       d.deployment_environment_id,
       d.lifecycle_state,
       d.run_mode,
       d.actor_user_id,
       d.requested_at,
       d.completed_at AS deployed_at
FROM   governance.deployment AS d
WHERE  d.outcome = 'succeeded'
ORDER  BY d.package_id, d.deployment_cluster_id, d.requested_at DESC;
COMMENT ON VIEW governance.deployment_current IS
    'Current placement: latest succeeded deployment per (package, cluster). Live projection '
    'over the append-only governance.deployment event log. ADR-0006 Consequences.';

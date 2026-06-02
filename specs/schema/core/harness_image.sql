-- core.harness_image  ·  subject: deploy  ·  (table)

-- 08-deploy.sql — Verity v2 hardened schema · PACKAGES, DEPLOYMENT, HARNESS CONTROL PLANE
-- Per D8 (BigID-style control plane): harness variant/image/instance, heartbeats
-- (minor/major + running-package catalog), portal->agent commands, packages +
-- digest-pinned compatibility, governed deployment, connection + binding overrides,
-- and the lifecycle->environment rule matrix. champion != deployed.
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

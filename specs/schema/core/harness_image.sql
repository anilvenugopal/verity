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
COMMENT ON TABLE core.harness_image IS
'A built harness container, identified by its immutable content digest rather than a tag. The digest is what package compatibility is declared against and what a deployment pins, so "the image that ran" is always reproducible for audit replay (ADR-0006). variant and version are descriptive; the digest is the identity.

@tier 1
@lifecycle insert-only
@subject deploy
@status reference.harness_variant
@decision D8
@adr 0006';
COMMENT ON COLUMN core.harness_image.harness_image_id IS
'Identity of the built image.';
COMMENT ON COLUMN core.harness_image.variant_code IS
'The execution-engine variant this image implements (which kind of harness runtime). @status reference.harness_variant';
COMMENT ON COLUMN core.harness_image.harness_version IS
'Semver/build of the harness; descriptive only — the digest, not this, is the identity.';
COMMENT ON COLUMN core.harness_image.image_digest IS
'Immutable sha256 content fingerprint; the real identity that compatibility and deployments pin to, which is what makes replay reproducible. Unique and format-checked.';
COMMENT ON COLUMN core.harness_image.registry_ref IS
'Where the image is pulled from — the central Verity registry, or a customer mirror of the same digest (ADR-0010).';
COMMENT ON COLUMN core.harness_image.created_at IS
'When the image was registered.';
COMMENT ON COLUMN core.harness_image.created_by_actor_id IS
'Who registered the image. @ref core.actor hard';
COMMENT ON COLUMN core.harness_image.created_role_code IS
'The capacity they acted in. @status reference.role';

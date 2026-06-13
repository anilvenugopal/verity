-- core.package  ·  subject: deploy  ·  (table)

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
COMMENT ON TABLE core.package IS
'The deployable .vtx (task) / .vax (agent) artifact built from a champion executable_version: the resolved composition the harness needs to run, fingerprinted by an immutable digest. The harness pulls it from object storage by digest and verifies the SHA-256 before any data is touched (ADR-0006, ADR-0010). Building a package is a separate, audited step — champion does not equal deployed.

@tier 1
@lifecycle insert-only
@subject deploy
@status reference.executable_kind
@decision D8
@adr 0006';
COMMENT ON COLUMN core.package.package_id IS
'Identity of the built artifact.';
COMMENT ON COLUMN core.package.executable_version_id IS
'The champion version that was packaged. @ref core.executable_version hard';
COMMENT ON COLUMN core.package.package_kind_code IS
'vtx (task) or vax (agent) — the bundle format, matching the executable kind. @status reference.executable_kind';
COMMENT ON COLUMN core.package.package_digest IS
'Immutable artifact fingerprint; the harness verifies it (SHA-256) before executing. Unique.';
COMMENT ON COLUMN core.package.manifest IS
'Snapshot of the bundle contents — config, bindings, connections — so the harness is self-contained at runtime.';
COMMENT ON COLUMN core.package.built_at IS
'When the package was built.';
COMMENT ON COLUMN core.package.built_by_actor_id IS
'Who or what built it — usually an automation actor. @ref core.actor hard';
COMMENT ON COLUMN core.package.built_role_code IS
'The capacity it was built under. @status reference.role';

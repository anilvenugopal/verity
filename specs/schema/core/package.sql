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
COMMENT ON TABLE core.package IS 'tier:1 insert-only. The .vtx/.vax artifact built from a champion executable_version. D8/ADR-0006.';

-- core.harness_app_credential  ·  subject: deploy  ·  (table)

-- Metadata-only registry of app data-source credentials (Model B). The hub stores the
-- credential's NAME, TYPE and verification result ONLY — never a value, never a vault
-- ref. The secret itself lives on the spoke (k8s Secret via External Secrets Operator;
-- or an encrypted config file on Linux) and is read in-memory by the worker at job time.
-- The coordinator test-connects and reports credential_verification_status via the
-- Harness Gateway API. The hub knows the credential exists and whether it works, never
-- what it is. Configured by the app lead (D6).
CREATE TABLE core.harness_app_credential (
    harness_app_credential_id           uuid        NOT NULL DEFAULT uuidv7(),
    application_id                      uuid        NOT NULL,
    deployment_cluster_id               uuid        NOT NULL,
    credential_name                     text        NOT NULL,                  -- referenced by source/target binding configs by name
    connector_type_code                 text        NOT NULL,                  -- reference.connector_type
    configured_by_actor_id              uuid        NOT NULL,
    configured_role_code                text        NOT NULL,                  -- reference.role (must be an app-lead capacity, D6)
    credential_verification_status_code text        NOT NULL DEFAULT 'unverified', -- reference.credential_verification_status
    last_verified_at                    timestamptz,
    verification_error                  text,
    is_active                           boolean     NOT NULL DEFAULT true,
    created_at                          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_harness_app_credential PRIMARY KEY (harness_app_credential_id),
    CONSTRAINT fk_hac_application FOREIGN KEY (application_id)
        REFERENCES core.application (application_id) ON DELETE RESTRICT,
    CONSTRAINT fk_hac_cluster FOREIGN KEY (deployment_cluster_id)
        REFERENCES core.deployment_cluster (deployment_cluster_id) ON DELETE RESTRICT,
    CONSTRAINT fk_hac_actor FOREIGN KEY (configured_by_actor_id)
        REFERENCES core.actor (actor_id) ON DELETE RESTRICT,
    CONSTRAINT fk_hac_role FOREIGN KEY (configured_role_code)
        REFERENCES reference.role (code),
    CONSTRAINT fk_hac_connector FOREIGN KEY (connector_type_code)
        REFERENCES reference.connector_type (code),
    CONSTRAINT fk_hac_verification FOREIGN KEY (credential_verification_status_code)
        REFERENCES reference.credential_verification_status (code),
    CONSTRAINT uq_hac_name UNIQUE (application_id, deployment_cluster_id, credential_name));
COMMENT ON TABLE core.harness_app_credential IS
'Metadata-only registry of app data-source credentials (Model B). The hub holds name,
type, and verification result ONLY — never a value, never a vault reference. The secret
lives on the spoke (k8s Secret via External Secrets Operator; or an encrypted file on
Linux) and is read in-memory by the worker at job time. The coordinator test-connects and
reports verification status. The hub knows the credential exists and whether it works,
never what it is.

@tier 1
@lifecycle mutable
@subject deploy
@status reference.credential_verification_status
@invariant hub stores no secret value and no vault reference (Model B)
@decision D6
@adr 0010';
COMMENT ON COLUMN core.harness_app_credential.harness_app_credential_id IS 'Surrogate key.';
COMMENT ON COLUMN core.harness_app_credential.application_id IS 'Owning application. @ref core.application hard';
COMMENT ON COLUMN core.harness_app_credential.deployment_cluster_id IS 'Cluster the credential is configured for. @ref core.deployment_cluster hard';
COMMENT ON COLUMN core.harness_app_credential.credential_name IS 'Logical name the Source/Target binding configs reference. Unique per (application, cluster).';
COMMENT ON COLUMN core.harness_app_credential.connector_type_code IS 'Backend the credential talks to. @status reference.connector_type';
COMMENT ON COLUMN core.harness_app_credential.configured_by_actor_id IS 'Who registered it. @ref core.actor hard';
COMMENT ON COLUMN core.harness_app_credential.configured_role_code IS 'Capacity it was registered under; must be an app-lead role. @status reference.role @decision D6';
COMMENT ON COLUMN core.harness_app_credential.credential_verification_status_code IS 'Result of the coordinator test-connection. @status reference.credential_verification_status';
COMMENT ON COLUMN core.harness_app_credential.last_verified_at IS 'When verification last succeeded. @nullable-when never verified';
COMMENT ON COLUMN core.harness_app_credential.verification_error IS 'Last verification failure detail. @nullable-when not failed';
COMMENT ON COLUMN core.harness_app_credential.is_active IS 'Whether the credential is in use. @default true';
COMMENT ON COLUMN core.harness_app_credential.created_at IS 'When the registry entry was created.';
CREATE INDEX ix_hac_cluster ON core.harness_app_credential (deployment_cluster_id);

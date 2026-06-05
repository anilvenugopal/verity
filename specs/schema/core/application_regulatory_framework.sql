-- core.application_regulatory_framework  ·  subject: intake  ·  (table)

-- The set of regulatory frameworks an application declares in scope (its legal surface). At least
-- one is required (FR-IN-017, enforced in the service). Selecting frameworks here bounds the
-- candidate regulatory_provisions that become per-intake obligations (FR-IN-018, FR-IN-014).
CREATE TABLE core.application_regulatory_framework (
    application_id  uuid NOT NULL,
    framework_code  text NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id uuid NOT NULL,
    CONSTRAINT pk_application_regulatory_framework PRIMARY KEY (application_id, framework_code),
    CONSTRAINT fk_app_framework_application FOREIGN KEY (application_id) REFERENCES core.application (application_id) ON DELETE CASCADE,
    CONSTRAINT fk_app_framework_framework FOREIGN KEY (framework_code) REFERENCES core.regulatory_framework (framework_code) ON DELETE RESTRICT,
    CONSTRAINT fk_app_framework_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id));
COMMENT ON TABLE core.application_regulatory_framework IS
'The regulatory frameworks an application declares in scope — its legal surface (FR-IN-017). At least one is required; the set bounds the candidate regulatory_provisions that become per-intake obligations (FR-IN-018). Editable only via re-approval (a change proposal, FR-IN-013).

@tier 1
@lifecycle mutable
@subject intake
@decision D6';
CREATE INDEX ix_app_framework_framework ON core.application_regulatory_framework (framework_code);
COMMENT ON COLUMN core.application_regulatory_framework.application_id IS
'The application declaring the framework in scope. @ref core.application hard';
COMMENT ON COLUMN core.application_regulatory_framework.framework_code IS
'The in-scope regulatory framework. @ref core.regulatory_framework hard';
COMMENT ON COLUMN core.application_regulatory_framework.created_at IS
'When the framework was added to the perimeter.';
COMMENT ON COLUMN core.application_regulatory_framework.created_by_actor_id IS
'Who added it. @ref core.actor hard';

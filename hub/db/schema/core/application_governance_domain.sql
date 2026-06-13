-- core.application_governance_domain  ·  subject: intake  ·  (table)

-- The governance domains an application declares in scope. At least one is required (FR-IN-017).
-- The in-scope domains define which domain_maturity the application must demonstrate (FR-RP-010).
CREATE TABLE core.application_governance_domain (
    application_id        uuid NOT NULL,
    governance_domain_code text NOT NULL,
    created_at            timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id   uuid NOT NULL,
    CONSTRAINT pk_application_governance_domain PRIMARY KEY (application_id, governance_domain_code),
    CONSTRAINT fk_app_domain_application FOREIGN KEY (application_id) REFERENCES core.application (application_id) ON DELETE CASCADE,
    CONSTRAINT fk_app_domain_domain FOREIGN KEY (governance_domain_code) REFERENCES reference.governance_domain (code) ON DELETE RESTRICT,
    CONSTRAINT fk_app_domain_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id));
COMMENT ON TABLE core.application_governance_domain IS
'The governance domains an application declares in scope (FR-IN-017). At least one is required; the set defines which domain_maturity the application must demonstrate (FR-RP-010). Editable only via re-approval (FR-IN-013).

@tier 1
@lifecycle mutable
@subject intake
@status reference.governance_domain
@decision D6';
CREATE INDEX ix_app_domain_domain ON core.application_governance_domain (governance_domain_code);
COMMENT ON COLUMN core.application_governance_domain.application_id IS
'The application declaring the domain in scope. @ref core.application hard';
COMMENT ON COLUMN core.application_governance_domain.governance_domain_code IS
'The in-scope governance domain. @status reference.governance_domain';
COMMENT ON COLUMN core.application_governance_domain.created_at IS
'When the domain was added to the perimeter.';
COMMENT ON COLUMN core.application_governance_domain.created_by_actor_id IS
'Who added it. @ref core.actor hard';

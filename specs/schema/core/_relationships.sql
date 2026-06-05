-- _relationships.sql — cross-domain FOREIGN KEYs, applied AFTER all tables load.

ALTER TABLE core.lifecycle_event
    ADD CONSTRAINT fk_lifecycle_event_approval_request
    FOREIGN KEY (approval_request_id) REFERENCES core.approval_request (approval_request_id) ON DELETE RESTRICT;
ALTER TABLE core.automation_actor
    ADD CONSTRAINT fk_automation_actor_application
    FOREIGN KEY (application_id) REFERENCES core.application (application_id) ON DELETE RESTRICT;
ALTER TABLE core.approval_request
    ADD CONSTRAINT fk_approval_request_target_intake
    FOREIGN KEY (target_intake_id) REFERENCES core.intake (intake_id) ON DELETE RESTRICT;
ALTER TABLE core.approval_request
    ADD CONSTRAINT fk_approval_request_target_application
    FOREIGN KEY (target_application_id) REFERENCES core.application (application_id) ON DELETE RESTRICT;
ALTER TABLE core.intake_obligation
    ADD CONSTRAINT fk_intake_obligation_requirement
    FOREIGN KEY (canonical_requirement_id) REFERENCES core.canonical_requirement (requirement_id) ON DELETE RESTRICT;
ALTER TABLE core.intake_obligation
    ADD CONSTRAINT fk_intake_obligation_domain
    FOREIGN KEY (governance_domain_code) REFERENCES reference.governance_domain (code) ON DELETE RESTRICT;
ALTER TABLE core.intake_obligation
    ADD CONSTRAINT fk_intake_obligation_target_tier
    FOREIGN KEY (target_requirement_tier_id) REFERENCES core.requirement_tier (requirement_tier_id) ON DELETE RESTRICT;
ALTER TABLE core.intake_artifact_plan_estimate
    ADD CONSTRAINT fk_intake_estimate_model FOREIGN KEY (model_id) REFERENCES core.model (model_id) ON DELETE RESTRICT;
ALTER TABLE core.intake_cost_envelope
    ADD CONSTRAINT fk_intake_cost_currency FOREIGN KEY (currency_code) REFERENCES reference.currency (code);
ALTER TABLE core.execution_run
    ADD CONSTRAINT fk_execution_run_run_mode FOREIGN KEY (deployment_run_mode_code) REFERENCES reference.deployment_run_mode (code);

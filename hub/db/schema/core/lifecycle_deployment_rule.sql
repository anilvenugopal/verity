-- core.lifecycle_deployment_rule  ·  subject: deploy  ·  (table)

CREATE TABLE core.lifecycle_deployment_rule (
    lifecycle_state_code  text       NOT NULL,
    environment_kind_code text       NOT NULL,
    allowed_run_modes     text[]     NOT NULL,                  -- subset of {live,shadow,ab,locked}
    output_suppressed     boolean     NOT NULL DEFAULT false,
    CONSTRAINT pk_lifecycle_deployment_rule PRIMARY KEY (lifecycle_state_code, environment_kind_code),
    CONSTRAINT fk_ldr_state FOREIGN KEY (lifecycle_state_code) REFERENCES reference.lifecycle_state (code),
    CONSTRAINT fk_ldr_env FOREIGN KEY (environment_kind_code) REFERENCES reference.environment_kind (code));
COMMENT ON TABLE core.lifecycle_deployment_rule IS
'The ADR-0006 lifecycle->environment matrix encoded as auditable data: for each (lifecycle_state, environment_kind) it states which run-modes are allowed and whether outputs are suppressed. The deploy gate reads this rather than hard-coding the policy, so safe progression (staging can''t reach prod; shadow/challenger can''t write to prod) is inspectable, governed data.

@tier 1
@lifecycle reference
@subject deploy
@status reference.lifecycle_state
@status reference.environment_kind
@decision D8
@adr 0006';

COMMENT ON COLUMN core.lifecycle_deployment_rule.lifecycle_state_code IS
'The version lifecycle state the rule applies to. @status reference.lifecycle_state';
COMMENT ON COLUMN core.lifecycle_deployment_rule.environment_kind_code IS
'The environment class the rule applies to. @status reference.environment_kind';
COMMENT ON COLUMN core.lifecycle_deployment_rule.allowed_run_modes IS
'The subset of {live,shadow,ab,locked} permitted for this state in this environment; the deploy gate refuses anything outside it. @values live|shadow|ab|locked';
COMMENT ON COLUMN core.lifecycle_deployment_rule.output_suppressed IS
'Whether Target Binding writes are suppressed for this cell (true for deprecated/locked) — audit and replay with no side effects.';

-- core.intake_cost_envelope  ·  subject: intake  ·  (table)

CREATE TABLE core.intake_cost_envelope (
    intake_cost_envelope_id uuid     NOT NULL DEFAULT uuidv7(),
    intake_id              uuid      NOT NULL,
    spend_cap              numeric(14,2) NOT NULL,
    currency_code          text      NOT NULL DEFAULT 'usd',         -- FK -> reference.currency (added in 06-decisions)
    locked                 boolean    NOT NULL DEFAULT false,
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    updated_by_actor_id    uuid,
    updated_role_code      text,
    CONSTRAINT pk_intake_cost_envelope PRIMARY KEY (intake_cost_envelope_id),
    CONSTRAINT fk_intake_cost_intake FOREIGN KEY (intake_id) REFERENCES core.intake (intake_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_cost_updated_by FOREIGN KEY (updated_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT uq_intake_cost_envelope_intake UNIQUE (intake_id));   -- one per intake
COMMENT ON TABLE core.intake_cost_envelope IS
'The single spend cap for an intake — the budget ceiling the build and run are expected to fit. locked freezes it (lock/unlock audited in audit.status_transition). One per intake (D4).

@tier 1
@lifecycle mutable
@subject intake
@status reference.currency
@decision D4';
COMMENT ON COLUMN core.intake_cost_envelope.intake_cost_envelope_id IS
'Identity of the envelope.';
COMMENT ON COLUMN core.intake_cost_envelope.intake_id IS
'The intake this caps; one envelope per intake. @ref core.intake hard';
COMMENT ON COLUMN core.intake_cost_envelope.spend_cap IS
'The budget ceiling for the intake. @units currency';
COMMENT ON COLUMN core.intake_cost_envelope.currency_code IS
'Currency of the cap. @status reference.currency';
COMMENT ON COLUMN core.intake_cost_envelope.locked IS
'Mutable flag freezing the envelope; transitions audited in audit.status_transition.';
COMMENT ON COLUMN core.intake_cost_envelope.created_at IS
'When created.';
COMMENT ON COLUMN core.intake_cost_envelope.updated_at IS
'When last updated.';
COMMENT ON COLUMN core.intake_cost_envelope.updated_by_actor_id IS
'Who last revised it. @ref core.actor hard';
COMMENT ON COLUMN core.intake_cost_envelope.updated_role_code IS
'The capacity they acted in. @status reference.role';

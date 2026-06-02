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
COMMENT ON TABLE core.intake_cost_envelope IS 'tier:1 mutable. One spend cap per intake; locked is a mutable flag (lock/unlock transitions -> audit.status_transition). D4.';

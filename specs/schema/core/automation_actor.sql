-- core.automation_actor  ·  subject: identity  ·  (table)

-- Named automated processes (the harness/runtime per app, named jobs).
CREATE TABLE core.automation_actor (
    actor_id          uuid       NOT NULL,           -- = core.actor.actor_id
    automation_name   text       NOT NULL,           -- e.g. 'equity-research-runner'
    application_id    uuid,                            -- optional: app it acts on behalf of
                                                       -- (FK -> core.application added in the intake domain)
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_automation_actor PRIMARY KEY (actor_id),
    CONSTRAINT fk_automation_actor_actor FOREIGN KEY (actor_id)
        REFERENCES core.actor (actor_id) ON DELETE RESTRICT,
    CONSTRAINT uq_automation_actor_name UNIQUE (automation_name)
);
COMMENT ON TABLE core.automation_actor IS 'tier:1. Automation actor subtype: named machine principal, optionally on behalf of an application. D6.';

-- core.intake_entity_link  ·  subject: intake  ·  (table)

CREATE TABLE core.intake_entity_link (
    intake_entity_link_id uuid       NOT NULL DEFAULT uuidv7(),
    intake_id             uuid       NOT NULL,
    intake_requirement_id uuid,                                       -- optional: link a specific requirement
    executable_id         uuid       NOT NULL,                        -- D5: a real FK, not polymorphic
    created_at            timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id   uuid       NOT NULL,
    created_role_code     text       NOT NULL,
    CONSTRAINT pk_intake_entity_link PRIMARY KEY (intake_entity_link_id),
    CONSTRAINT fk_intake_entity_link_intake FOREIGN KEY (intake_id) REFERENCES core.intake (intake_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_entity_link_requirement FOREIGN KEY (intake_requirement_id) REFERENCES core.intake_requirement (intake_requirement_id) ON DELETE SET NULL,
    CONSTRAINT fk_intake_entity_link_executable FOREIGN KEY (executable_id) REFERENCES core.executable (executable_id) ON DELETE RESTRICT,
    CONSTRAINT fk_intake_entity_link_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_intake_entity_link_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code));

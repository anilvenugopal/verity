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
COMMENT ON TABLE core.intake_entity_link IS
'Links an intake (optionally a specific requirement) to a realized executable — a real FK, not polymorphic (D5). This is how "what we asked for" connects to "what we built", for traceability and requirement verification before promotion.

@tier 1
@lifecycle mutable
@subject intake
@decision D5';
COMMENT ON COLUMN core.intake_entity_link.intake_entity_link_id IS
'Identity of the link.';
COMMENT ON COLUMN core.intake_entity_link.intake_id IS
'The intake. @ref core.intake hard';
COMMENT ON COLUMN core.intake_entity_link.intake_requirement_id IS
'The specific requirement this link satisfies, when scoped to one; set null if the requirement is removed. @ref core.intake_requirement hard';
COMMENT ON COLUMN core.intake_entity_link.executable_id IS
'The realized executable the intake produced. @ref core.executable hard';
COMMENT ON COLUMN core.intake_entity_link.created_at IS
'When linked.';
COMMENT ON COLUMN core.intake_entity_link.created_by_actor_id IS
'Who linked it. @ref core.actor hard';
COMMENT ON COLUMN core.intake_entity_link.created_role_code IS
'The capacity they acted in. @status reference.role';

-- core.intake_requirement  ·  subject: intake  ·  (table)

CREATE TABLE core.intake_requirement (
    intake_requirement_id uuid       NOT NULL DEFAULT uuidv7(),
    intake_id             uuid       NOT NULL,
    requirement_kind_code text       NOT NULL,
    requirement_status_code text     NOT NULL DEFAULT 'draft',     -- mutable (D4)
    title                 text       NOT NULL,
    body                  text       NOT NULL,
    embedding             vector(384),                              -- pgvector similarity (dim per embedding_config)
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id   uuid       NOT NULL,
    created_role_code     text       NOT NULL,
    CONSTRAINT pk_intake_requirement PRIMARY KEY (intake_requirement_id),
    CONSTRAINT fk_intake_requirement_intake FOREIGN KEY (intake_id) REFERENCES core.intake (intake_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_requirement_kind FOREIGN KEY (requirement_kind_code) REFERENCES reference.requirement_kind (code),
    CONSTRAINT fk_intake_requirement_status FOREIGN KEY (requirement_status_code) REFERENCES reference.requirement_status (code),
    CONSTRAINT fk_intake_requirement_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_intake_requirement_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code));
CREATE INDEX ix_intake_requirement_intake ON core.intake_requirement (intake_id);
COMMENT ON TABLE core.intake_requirement IS
'A typed, status-tracked requirement statement on an intake. It carries a pgvector embedding so requirements can be semantically de-duplicated and matched to realized entities before promotion. Status is mutable (D4).

@tier 1
@lifecycle mutable
@subject intake
@status reference.requirement_kind
@status reference.requirement_status
@decision D4';
COMMENT ON COLUMN core.intake_requirement.intake_requirement_id IS
'Identity of the requirement.';
COMMENT ON COLUMN core.intake_requirement.intake_id IS
'The intake it belongs to. @ref core.intake hard';
COMMENT ON COLUMN core.intake_requirement.requirement_kind_code IS
'The kind of requirement. @status reference.requirement_kind';
COMMENT ON COLUMN core.intake_requirement.requirement_status_code IS
'Mutable status (draft/...). @status reference.requirement_status';
COMMENT ON COLUMN core.intake_requirement.title IS
'Short title.';
COMMENT ON COLUMN core.intake_requirement.body IS
'Full requirement text.';
COMMENT ON COLUMN core.intake_requirement.embedding IS
'pgvector embedding of the requirement text for semantic de-duplication and matching; dimension per embedding_config.';
COMMENT ON COLUMN core.intake_requirement.created_at IS
'When created.';
COMMENT ON COLUMN core.intake_requirement.updated_at IS
'When last updated.';
COMMENT ON COLUMN core.intake_requirement.created_by_actor_id IS
'Who created it. @ref core.actor hard';
COMMENT ON COLUMN core.intake_requirement.created_role_code IS
'The capacity they acted in. @status reference.role';

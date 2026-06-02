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

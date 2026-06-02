-- core.intake_obligation_resolution  ·  subject: intake  ·  (table)

-- The resolution EVENT is append-only (auditors need "what was required as-of when").
-- Carries D9 provenance: how the obligation set was derived + ontology version + confidence.
CREATE TABLE core.intake_obligation_resolution (
    intake_obligation_resolution_id uuid NOT NULL DEFAULT uuidv7(),
    intake_id              uuid      NOT NULL,
    derivation_method_code text      NOT NULL DEFAULT 'manual',       -- manual|reasoner_recommended|human_validated (D9)
    ontology_version       text,                                      -- which axiom set produced it (D9; reproducibility)
    confidence             numeric(4,3),                              -- reasoner confidence (when applicable)
    resolved_by_actor_id   uuid      NOT NULL,
    resolved_role_code     text      NOT NULL,
    created_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_obligation_resolution PRIMARY KEY (intake_obligation_resolution_id),
    CONSTRAINT fk_intake_obl_res_intake FOREIGN KEY (intake_id) REFERENCES core.intake (intake_id) ON DELETE CASCADE,
    CONSTRAINT fk_intake_obl_res_method FOREIGN KEY (derivation_method_code) REFERENCES reference.derivation_method (code),
    CONSTRAINT fk_intake_obl_res_actor FOREIGN KEY (resolved_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_intake_obl_res_role FOREIGN KEY (resolved_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.intake_obligation_resolution IS 'tier:1 append-only. One obligation-set resolution per (re)classification; latest = current, history retained. D9 provenance (method/ontology_version/confidence).';
CREATE INDEX ix_intake_obl_res_intake_time ON core.intake_obligation_resolution (intake_id, created_at DESC);

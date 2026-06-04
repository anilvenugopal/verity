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
COMMENT ON TABLE core.intake_obligation_resolution IS
'The append-only record of resolving an intake''s obligation set at a (re)classification — auditors need "what was required as of when". Carries D9 provenance: how the set was derived (manual/reasoner/validated), the ontology version that produced it, and a reasoner confidence. Latest is current; history is retained.

@tier 1
@lifecycle append-only
@subject intake
@status reference.derivation_method
@decision D9';
CREATE INDEX ix_intake_obl_res_intake_time ON core.intake_obligation_resolution (intake_id, created_at DESC);
COMMENT ON COLUMN core.intake_obligation_resolution.intake_obligation_resolution_id IS
'Identity of the resolution event.';
COMMENT ON COLUMN core.intake_obligation_resolution.intake_id IS
'The intake whose obligations were resolved. @ref core.intake hard';
COMMENT ON COLUMN core.intake_obligation_resolution.derivation_method_code IS
'How the set was derived — manual/reasoner_recommended/human_validated (D9). @status reference.derivation_method';
COMMENT ON COLUMN core.intake_obligation_resolution.ontology_version IS
'Which axiom set produced the set, for reproducibility (D9).';
COMMENT ON COLUMN core.intake_obligation_resolution.confidence IS
'Reasoner confidence, when the set was machine-derived.';
COMMENT ON COLUMN core.intake_obligation_resolution.resolved_by_actor_id IS
'Who resolved the set. @ref core.actor hard';
COMMENT ON COLUMN core.intake_obligation_resolution.resolved_role_code IS
'The capacity they acted in. @status reference.role';
COMMENT ON COLUMN core.intake_obligation_resolution.created_at IS
'When the resolution occurred; latest is current.';

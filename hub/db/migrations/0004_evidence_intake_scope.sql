-- 0004_evidence_intake_scope.sql — feature 003 (US1). Scope evidence to an intake so an intake's
-- obligation can be marked satisfied. audit.evidence is keyed by requirement/control/spec but had no
-- intake link; this adds a nullable intake_id (the natural "evidence recorded for this intake's
-- obligation"). Additive + nullable (Principle II: hardened-schema change, additive only).
ALTER TABLE audit.evidence ADD COLUMN IF NOT EXISTS intake_id uuid;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_evidence_intake') THEN
    ALTER TABLE audit.evidence ADD CONSTRAINT fk_evidence_intake
      FOREIGN KEY (intake_id) REFERENCES core.intake (intake_id) ON DELETE CASCADE;
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS ix_evidence_intake ON audit.evidence (intake_id);

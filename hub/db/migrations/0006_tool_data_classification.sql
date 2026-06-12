-- 0006_tool_data_classification.sql — feature 005 (FR-RG-018).
-- Adds data_classification_code to core.tool_version so tool versions can declare
-- the sensitivity level of data they process. Additive (Principle II).
ALTER TABLE core.tool_version
    ADD COLUMN IF NOT EXISTS data_classification_code text;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_tool_version_data_class'
  ) THEN
    ALTER TABLE core.tool_version
      ADD CONSTRAINT fk_tool_version_data_class
      FOREIGN KEY (data_classification_code)
      REFERENCES reference.data_classification (code) ON DELETE RESTRICT;
  END IF;
END $$;

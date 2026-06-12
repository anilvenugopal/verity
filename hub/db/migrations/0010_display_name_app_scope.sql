-- 0010_display_name_app_scope.sql
-- Adds display_name and application_id to core.executable, core.prompt, core.tool.
-- display_name: human-readable label shown in the UI.
-- application_id: direct ownership FK — "every asset is scoped to an application".
-- Backfills display_name from existing name; backfills application_id from the
-- demo ZUW application where present. NOT NULL enforced at the app layer; DB
-- NOT NULL constraint follows once all data is clean.

ALTER TABLE core.executable
    ADD COLUMN IF NOT EXISTS display_name  text,
    ADD COLUMN IF NOT EXISTS application_id uuid REFERENCES core.application(application_id);

ALTER TABLE core.prompt
    ADD COLUMN IF NOT EXISTS display_name  text,
    ADD COLUMN IF NOT EXISTS application_id uuid REFERENCES core.application(application_id);

ALTER TABLE core.tool
    ADD COLUMN IF NOT EXISTS display_name  text,
    ADD COLUMN IF NOT EXISTS application_id uuid REFERENCES core.application(application_id);

-- Backfill display_name from tech name (will be replaced by demo re-seed for demo data)
UPDATE core.executable SET display_name = name  WHERE display_name IS NULL;
UPDATE core.prompt     SET display_name = name  WHERE display_name IS NULL;
UPDATE core.tool       SET display_name = name  WHERE display_name IS NULL;

-- Backfill application_id for existing demo assets using the ZUW app (if it exists)
DO $$
DECLARE zuw_id uuid;
BEGIN
    SELECT application_id INTO zuw_id FROM core.application WHERE code = 'ZUW' LIMIT 1;
    IF zuw_id IS NOT NULL THEN
        UPDATE core.executable SET application_id = zuw_id WHERE application_id IS NULL;
        UPDATE core.prompt     SET application_id = zuw_id WHERE application_id IS NULL;
        UPDATE core.tool       SET application_id = zuw_id WHERE application_id IS NULL;
    END IF;
END $$;

-- Partial unique index: display_name unique per application per kind (where app is known)
CREATE UNIQUE INDEX IF NOT EXISTS uq_executable_app_kind_display
    ON core.executable (application_id, kind_code, display_name)
    WHERE application_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_prompt_app_display
    ON core.prompt (application_id, display_name)
    WHERE application_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_tool_app_display
    ON core.tool (application_id, display_name)
    WHERE application_id IS NOT NULL;

-- core.platform_settings  ·  subject: validation  ·  (table)

CREATE TABLE core.platform_settings (
    setting_key text NOT NULL, setting_input_type_code text NOT NULL, value jsonb NOT NULL,
    description text, updated_at timestamptz NOT NULL DEFAULT now(), updated_by_actor_id uuid,
    CONSTRAINT pk_platform_settings PRIMARY KEY (setting_key),
    CONSTRAINT fk_platform_settings_input_type FOREIGN KEY (setting_input_type_code) REFERENCES reference.setting_input_type (code),
    CONSTRAINT fk_platform_settings_updated_by FOREIGN KEY (updated_by_actor_id) REFERENCES core.actor (actor_id));
COMMENT ON TABLE core.platform_settings IS
'Key/value platform configuration, typed by setting_input_type. The single place runtime-tunable platform settings live, with attribution of who last changed each.

@tier 1
@lifecycle mutable
@subject validation
@status reference.setting_input_type';
COMMENT ON COLUMN core.platform_settings.setting_key IS
'The setting name; primary key.';
COMMENT ON COLUMN core.platform_settings.setting_input_type_code IS
'The input/value type of the setting. @status reference.setting_input_type';
COMMENT ON COLUMN core.platform_settings.value IS
'The setting value.';
COMMENT ON COLUMN core.platform_settings.description IS
'What the setting controls.';
COMMENT ON COLUMN core.platform_settings.updated_at IS
'When last changed.';
COMMENT ON COLUMN core.platform_settings.updated_by_actor_id IS
'Who last changed it. @ref core.actor hard';

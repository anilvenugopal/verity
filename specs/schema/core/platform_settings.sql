-- core.platform_settings  ·  subject: validation  ·  (table)

CREATE TABLE core.platform_settings (
    setting_key text NOT NULL, setting_input_type_code text NOT NULL, value jsonb NOT NULL,
    description text, updated_at timestamptz NOT NULL DEFAULT now(), updated_by_actor_id uuid,
    CONSTRAINT pk_platform_settings PRIMARY KEY (setting_key),
    CONSTRAINT fk_platform_settings_input_type FOREIGN KEY (setting_input_type_code) REFERENCES reference.setting_input_type (code),
    CONSTRAINT fk_platform_settings_updated_by FOREIGN KEY (updated_by_actor_id) REFERENCES core.actor (actor_id));

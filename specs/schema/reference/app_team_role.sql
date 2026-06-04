-- reference.app_team_role  ·  subject: intake  ·  (table)

-- app_team_role: per-application team roles (D1; pairs with actor_app_role_grant). v2-new.
CREATE TABLE reference.app_team_role (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_app_team_role PRIMARY KEY (code), CONSTRAINT uq_app_team_role_sort UNIQUE (sort_order));
INSERT INTO reference.app_team_role (code, label, sort_order) VALUES
    ('app_demo_owner',1),('app_demo_lead',2),('app_demo_dev',3),('app_demo_sre',4),('app_demo_ops',5);
COMMENT ON TABLE reference.app_team_role IS
'Per-application app-team roles granted via actor_app_role_grant — the per-application authorization vocabulary.

@lifecycle reference
@subject intake';

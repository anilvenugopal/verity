-- core.test_suite  ·  subject: validation  ·  (table)

-- 10-validation.sql — Verity v2 hardened schema · TESTING / GROUND-TRUTH /
-- VALIDATION / EVALUATION / MODEL-CARDS / INCIDENTS / PLATFORM-SETTINGS.
-- Closes the C9 no-silent-loss gap. Definitions/state in core; execution logs Tier-2.
-- Status workflows use mutable *_status_code (D4); attribution via actor (D6).
CREATE TABLE core.test_suite (
    test_suite_id uuid NOT NULL DEFAULT uuidv7(), executable_id uuid NOT NULL,
    name text NOT NULL, description text, suite_type text NOT NULL, active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(), created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_test_suite PRIMARY KEY (test_suite_id),
    CONSTRAINT fk_test_suite_executable FOREIGN KEY (executable_id) REFERENCES core.executable (executable_id) ON DELETE RESTRICT,
    CONSTRAINT fk_test_suite_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_test_suite_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.test_suite IS 'tier:1. A test suite for an executable (agent/task). D5/C9.';

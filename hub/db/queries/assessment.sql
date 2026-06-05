-- core.intake_impact_assessment — the intake assessment as versioned jsonb (SCD-2). Raw SQL, no
-- ORM (ADR-0012). Each submit closes the open revision (valid_to = now()) and inserts the next
-- revision (valid_to = the 2099 sentinel = current). Reads use the _current view (D-ASM-1).

-- name: next_revision^
SELECT COALESCE(max(revision), 0) + 1 AS revision
FROM core.intake_impact_assessment WHERE intake_id = %(intake_id)s;

-- name: close_current_assessment!
UPDATE core.intake_impact_assessment SET valid_to = now()
WHERE intake_id = %(intake_id)s AND valid_to = '2099-12-31 00:00:00+00';

-- name: insert_assessment_revision^
INSERT INTO core.intake_impact_assessment
    (intake_id, revision, assessment, created_by_actor_id, created_role_code)
VALUES (%(intake_id)s, %(revision)s, %(assessment)s, %(created_by_actor_id)s, %(created_role_code)s)
RETURNING intake_id, revision, assessment, created_at;

-- name: get_current_assessment^
SELECT intake_id, revision, assessment, created_at
FROM core.intake_impact_assessment_current
WHERE intake_id = %(intake_id)s;

-- name: list_revisions
SELECT revision, valid_from, valid_to, created_by_actor_id
FROM core.intake_impact_assessment
WHERE intake_id = %(intake_id)s
ORDER BY revision;

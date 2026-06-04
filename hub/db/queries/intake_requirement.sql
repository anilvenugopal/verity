-- core.intake_requirement — add + list typed requirements on an intake (intake slice, US4).
-- Raw SQL, no ORM (ADR-0012). requirement_status_code defaults to 'draft'; embedding is left out
-- of the INSERT and so stays null — embedding generation + semantic dedup are deferred (D-INT-6).
-- Attribution (created_by_actor_id, created_role_code) is server-resolved (D6 / FR-018).

-- name: add_requirement^
-- A bad requirement_kind_code trips fk_intake_requirement_kind -> 400 (D-INT-7). The parent
-- intake's existence is checked by the router (404) before this runs.
INSERT INTO core.intake_requirement
    (intake_id, requirement_kind_code, title, body, created_by_actor_id, created_role_code)
VALUES
    (%(intake_id)s, %(requirement_kind_code)s, %(title)s, %(body)s,
     %(created_by_actor_id)s, %(created_role_code)s)
RETURNING intake_requirement_id, intake_id, requirement_kind_code, requirement_status_code,
          title, body, created_at;

-- name: list_requirements
SELECT intake_requirement_id, intake_id, requirement_kind_code, requirement_status_code,
       title, body, created_at
FROM core.intake_requirement
WHERE intake_id = %(intake_id)s
ORDER BY created_at;

-- core.intake — create + reads (intake slice, US1).
-- Raw SQL, no ORM (ADR-0012). intake_status_code defaults to 'proposed' (DB default); the
-- classification codes are left null here (set later via /classification, US2). Attribution is
-- server-resolved (D6 / FR-018). Classification + status-change statements arrive with US2/US3.

-- name: create_intake^
-- application_id is bound by the router after confirming the parent exists (404 otherwise); the
-- FK is the backstop. Returns the full API view of the new intake.
INSERT INTO core.intake (application_id, title, description, created_by_actor_id, created_role_code)
VALUES (%(application_id)s, %(title)s, %(description)s, %(created_by_actor_id)s, %(created_role_code)s)
RETURNING intake_id, application_id, title, description, intake_status_code,
          ai_risk_tier_code, naic_materiality_code, materiality_tier_code, created_at;

-- name: get_intake^
SELECT intake_id, application_id, title, description, intake_status_code,
       ai_risk_tier_code, naic_materiality_code, materiality_tier_code, created_at
FROM core.intake
WHERE intake_id = %(intake_id)s;

-- name: list_intakes_by_application
SELECT intake_id, application_id, title, description, intake_status_code,
       ai_risk_tier_code, naic_materiality_code, materiality_tier_code, created_at
FROM core.intake
WHERE application_id = %(application_id)s
ORDER BY created_at DESC;

-- name: list_all_intakes
-- Every intake (newest first) with its parent application's name (for display) and created_by (for
-- the MY USE CASES projection). Powers the top-level Use Cases list. Role gating is at the route
-- (require_action("view")); there is no per-intake RLS this slice.
SELECT i.intake_id, i.application_id, a.name AS application_name, i.title, i.description,
       i.intake_status_code, i.ai_risk_tier_code, i.naic_materiality_code, i.materiality_tier_code,
       i.created_by_actor_id, i.created_at
FROM core.intake i
JOIN core.application a ON a.application_id = i.application_id
ORDER BY i.created_at DESC;

-- name: get_intake_status^
-- The current status, read inside the status-change transaction to capture from_code (D-INT-1).
-- Null => the intake does not exist (-> 404).
SELECT intake_status_code FROM core.intake WHERE intake_id = %(intake_id)s;

-- name: update_intake_status^
-- Move the status. The to-code is validated by fk_intake_status -> reference.intake_status; an
-- invalid code raises a FK violation the router maps to 400 (before any audit row is written).
UPDATE core.intake SET intake_status_code = %(to_status_code)s, updated_at = now()
WHERE intake_id = %(intake_id)s
RETURNING intake_id, application_id, title, description, intake_status_code,
          ai_risk_tier_code, naic_materiality_code, materiality_tier_code, created_at;

-- name: classify_intake^
-- Set/refresh risk tier + materiality (US2). Any subset: COALESCE leaves an unspecified (null
-- param) code unchanged; a supplied code overwrites. An invalid code trips its reference FK
-- (fk_intake_risk_tier / _naic / _materiality) — the router maps that to 400 (D-INT-7). Returns
-- null if the intake does not exist (no row updated) -> 404.
UPDATE core.intake SET
    ai_risk_tier_code     = COALESCE(%(ai_risk_tier_code)s, ai_risk_tier_code),
    naic_materiality_code = COALESCE(%(naic_materiality_code)s, naic_materiality_code),
    materiality_tier_code = COALESCE(%(materiality_tier_code)s, materiality_tier_code),
    updated_at = now()
WHERE intake_id = %(intake_id)s
RETURNING intake_id, application_id, title, description, intake_status_code,
          ai_risk_tier_code, naic_materiality_code, materiality_tier_code, created_at;

-- ── Pre-approval lifecycle: edit / withdraw / hard-delete ────────────────────────────────────────
-- Mirrors the application onboarding lifecycle (PUT / withdraw / DELETE). A *revisable* intake is one
-- of the three pre-decision authoring states {proposed, in_review, impact_assessment}; everything
-- else is locked {approved, rejected, retired, in_build, live}. A quorum rejection leaves the status
-- at in_review (the approval *request* is what reads 'rejected'), so the remediation loop matches a
-- rejected application staying 'pending'. An explicit rejected/retired is a terminal governance kill.

-- name: update_intake^
-- Edit a still-revisable intake's title/description in place (pre-activation remediation). The status
-- guard means a locked (approved/rejected/retired/in_build/live) intake is never edited this way.
-- Returns the row, or nothing if it was locked / not found (the service distinguishes 404 from 409
-- via get_intake_status).
UPDATE core.intake SET
    title = %(title)s, description = %(description)s, updated_at = now()
WHERE intake_id = %(intake_id)s
  AND intake_status_code IN ('proposed', 'in_review', 'impact_assessment')
RETURNING intake_id, application_id, title, description, intake_status_code,
          ai_risk_tier_code, naic_materiality_code, materiality_tier_code, created_at;

-- name: get_pending_intake_approval^
-- The intake's open (pending) kind=intake approval, if any — used to confirm there is something to
-- cancel on withdraw (no open request => 409, nothing to cancel).
SELECT approval_request_id FROM core.approval_request
WHERE target_intake_id = %(intake_id)s AND request_kind_code = 'intake' AND status_code = 'pending'
ORDER BY created_at DESC LIMIT 1;

-- ── Hard delete (delete_intake action; revisable intakes only; API + UI maintenance) ──────────────
-- Run in FK order inside one transaction: sign-offs → approval requests → the intake row.
-- intake_requirement is ON DELETE CASCADE (auto-removed); audit.status_transition is a soft ref
-- (no FK) and is intentionally left intact (audit immutability).

-- name: delete_intake_signoffs!
DELETE FROM core.approval_signoff
WHERE approval_request_id IN (SELECT approval_request_id FROM core.approval_request
                              WHERE target_intake_id = %(intake_id)s);

-- name: delete_intake_approvals!
DELETE FROM core.approval_request WHERE target_intake_id = %(intake_id)s;

-- name: delete_intake!
DELETE FROM core.intake WHERE intake_id = %(intake_id)s;

-- Change-proposal queries (003 US3): the grouping table `change_proposal_asset` + the reads needed
-- to open a proposal, fork assets on approval, and list proposals on an intake. The approval request
-- rows themselves live in the shared approval.sql primitive. Raw SQL, no ORM (ADR-0012).

-- name: insert_change_proposal_asset!
INSERT INTO core.change_proposal_asset (approval_request_id, executable_id)
VALUES (%(approval_request_id)s, %(executable_id)s);

-- name: list_proposal_assets
-- The impacted executables for a change proposal (for forking + the portal view).
SELECT cpa.change_proposal_asset_id, cpa.executable_id, e.name, e.kind_code
FROM core.change_proposal_asset cpa
JOIN core.executable e ON e.executable_id = cpa.executable_id
WHERE cpa.approval_request_id = %(approval_request_id)s
ORDER BY e.name;

-- name: get_champion_version^
-- The current champion version for an executable (the source for forking). Null => no champion yet.
SELECT ca.executable_version_id
FROM core.champion_assignment ca
JOIN core.executable_version ev ON ev.executable_version_id = ca.executable_version_id
WHERE ev.executable_id = %(executable_id)s
ORDER BY ca.created_at DESC LIMIT 1;

-- name: get_best_version^
-- The most-advanced version for an executable (fallback when no champion: draft/candidate/staging).
-- Used as fork source when the champion is absent.
SELECT v.executable_version_id, v.semver, lc.lifecycle_state_code
FROM core.executable_version v
LEFT JOIN core.entity_lifecycle_current lc ON lc.executable_version_id = v.executable_version_id
WHERE v.executable_id = %(executable_id)s
ORDER BY array_position(
    ARRAY['champion','challenger','staging','candidate','draft'],
    lc.lifecycle_state_code
) NULLS LAST, v.created_at DESC
LIMIT 1;

-- name: has_open_change_proposal^
-- True if a pending risk_reclassification or business_change approval already exists for this intake.
SELECT EXISTS (
    SELECT 1 FROM core.approval_request
    WHERE target_intake_id = %(intake_id)s
      AND request_kind_code IN ('risk_reclassification', 'business_change')
      AND status_code = 'pending'
) AS present;

-- name: list_intake_change_proposals
-- All change proposals (any status) for an intake, newest first — powers the portal history list.
SELECT ar.approval_request_id, ar.request_kind_code, ar.status_code,
       ar.opened_by_actor_id, ar.created_at,
       coalesce(
           json_agg(json_build_object(
               'executable_id', cpa.executable_id,
               'name', e.name,
               'kind_code', e.kind_code
           ) ORDER BY e.name) FILTER (WHERE cpa.executable_id IS NOT NULL),
           '[]'
       ) AS assets
FROM core.approval_request ar
LEFT JOIN core.change_proposal_asset cpa ON cpa.approval_request_id = ar.approval_request_id
LEFT JOIN core.executable e ON e.executable_id = cpa.executable_id
WHERE ar.target_intake_id = %(intake_id)s
  AND ar.request_kind_code IN ('risk_reclassification', 'business_change')
GROUP BY ar.approval_request_id, ar.request_kind_code, ar.status_code,
         ar.opened_by_actor_id, ar.created_at
ORDER BY ar.created_at DESC;

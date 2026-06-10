-- core.intake_obligation(_resolution) + evidence/exceptions — resolve & track an intake's obligation
-- set from the metamodel (003 US1, FR-001..006). Status (satisfied/excepted/outstanding) is DERIVED
-- in the service from recorded evidence + valid exceptions, not stored. CUR = the 2099 SCD-2 sentinel.

-- name: resolve_applicable_requirements
-- D1: requirements applicable to an intake = tier × app governance-domains × app frameworks, each at
-- the target requirement_tier (clamped to the intake's tier, gated by the provision minimum tier).
WITH ctx AS (
  SELECT i.intake_id, a.application_id,
         CASE i.ai_risk_tier_code WHEN 'minimal' THEN 1 WHEN 'limited' THEN 2 WHEN 'high' THEN 3 ELSE 0 END AS lvl
  FROM core.intake i JOIN core.application a ON a.application_id = i.application_id
  WHERE i.intake_id = %(intake_id)s
)
SELECT cr.requirement_id, cr.governance_domain_code,
       (SELECT rt.requirement_tier_id FROM core.requirement_tier rt
          WHERE rt.requirement_id = cr.requirement_id AND rt.valid_to = '2099-12-31 00:00:00+00'
            AND rt.tier_level = LEAST((SELECT lvl FROM ctx),
                  (SELECT max(tier_level) FROM core.requirement_tier m
                     WHERE m.requirement_id = cr.requirement_id AND m.valid_to = '2099-12-31 00:00:00+00'))) AS target_requirement_tier_id
FROM core.canonical_requirement cr
WHERE cr.valid_to = '2099-12-31 00:00:00+00'
  AND (SELECT lvl FROM ctx) >= 1
  AND cr.governance_domain_code IN (SELECT governance_domain_code FROM core.application_governance_domain WHERE application_id = (SELECT application_id FROM ctx))
  AND EXISTS (
    SELECT 1 FROM core.provision_requirement pr
    JOIN core.regulatory_provision p ON p.provision_id = pr.provision_id AND p.valid_to = '2099-12-31 00:00:00+00'
    WHERE pr.requirement_id = cr.requirement_id AND pr.valid_to = '2099-12-31 00:00:00+00'
      AND p.framework_code IN (SELECT framework_code FROM core.application_regulatory_framework WHERE application_id = (SELECT application_id FROM ctx))
      AND pr.min_tier_level <= (SELECT lvl FROM ctx));

-- name: delete_intake_resolution!
-- Supersede the prior resolution on re-resolve (intake_obligation cascades). Evidence + exceptions are
-- keyed by intake and persist, so derived satisfied/excepted survives (FR-002).
DELETE FROM core.intake_obligation_resolution WHERE intake_id = %(intake_id)s;

-- name: insert_obligation_resolution^
INSERT INTO core.intake_obligation_resolution (intake_id, derivation_method_code, ontology_version, resolved_by_actor_id, resolved_role_code)
VALUES (%(intake_id)s, 'manual', %(ontology_version)s, %(resolved_by_actor_id)s, %(resolved_role_code)s)
RETURNING intake_obligation_resolution_id;

-- name: insert_obligation!
INSERT INTO core.intake_obligation (intake_obligation_resolution_id, canonical_requirement_id, governance_domain_code, target_requirement_tier_id)
VALUES (%(resolution_id)s, %(canonical_requirement_id)s, %(governance_domain_code)s, %(target_requirement_tier_id)s);

-- name: list_obligations
SELECT o.intake_obligation_id, cr.requirement_code, cr.title, o.governance_domain_code,
       rt.tier_level AS target_tier, o.canonical_requirement_id
FROM core.intake_obligation o
JOIN core.intake_obligation_resolution r ON r.intake_obligation_resolution_id = o.intake_obligation_resolution_id
JOIN core.canonical_requirement cr ON cr.requirement_id = o.canonical_requirement_id
JOIN core.requirement_tier rt ON rt.requirement_tier_id = o.target_requirement_tier_id
WHERE r.intake_id = %(intake_id)s
ORDER BY o.governance_domain_code, cr.requirement_code;

-- name: obligation_controls
-- Cumulative controls (tiers 1..target) for a requirement, with the evidence spec and whether THIS
-- intake has recorded evidence for the control.
SELECT c.control_code, c.title, c.control_phase_code, c.enforcement_action_code,
       es.evidence_artifact_type_code,
       EXISTS (SELECT 1 FROM audit.evidence e WHERE e.intake_id = %(intake_id)s AND e.control_id = c.control_id) AS evidenced
FROM core.requirement_tier rt
JOIN core.requirement_control rc ON rc.requirement_tier_id = rt.requirement_tier_id AND rc.valid_to = '2099-12-31 00:00:00+00'
JOIN core.control c ON c.control_id = rc.control_id AND c.valid_to = '2099-12-31 00:00:00+00'
LEFT JOIN core.evidence_specification es ON es.control_id = c.control_id AND es.valid_to = '2099-12-31 00:00:00+00'
WHERE rt.requirement_id = %(requirement_id)s AND rt.valid_to = '2099-12-31 00:00:00+00' AND rt.tier_level <= %(target_tier)s
ORDER BY rt.tier_level, c.control_code;

-- name: active_exception^
-- An approved, unexpired exception covering (intake, requirement, >= tier) → the obligation is excepted.
SELECT compliance_exception_id FROM core.compliance_exception
WHERE scope_intake_id = %(intake_id)s AND canonical_requirement_id = %(requirement_id)s
  AND exception_status_code = 'approved' AND waived_tier_level >= %(target_tier)s AND expires_at > now()
ORDER BY expires_at DESC LIMIT 1;

-- name: requirement_id_by_code^
SELECT requirement_id FROM core.canonical_requirement WHERE requirement_code = %(code)s AND valid_to = '2099-12-31 00:00:00+00';

-- name: control_for_evidence^
-- Resolve the metamodel refs for a control so recorded evidence binds them.
SELECT c.control_id, c.control_phase_code, rt.requirement_tier_id, rt.requirement_id,
       (SELECT es.evidence_specification_id FROM core.evidence_specification es WHERE es.control_id = c.control_id AND es.valid_to = '2099-12-31 00:00:00+00' LIMIT 1) AS evidence_specification_id,
       (SELECT es.evidence_artifact_type_code FROM core.evidence_specification es WHERE es.control_id = c.control_id AND es.valid_to = '2099-12-31 00:00:00+00' LIMIT 1) AS evidence_artifact_type_code
FROM core.control c
JOIN core.requirement_control rc ON rc.control_id = c.control_id AND rc.valid_to = '2099-12-31 00:00:00+00'
JOIN core.requirement_tier rt ON rt.requirement_tier_id = rc.requirement_tier_id AND rt.valid_to = '2099-12-31 00:00:00+00'
WHERE c.control_code = %(control_code)s AND c.valid_to = '2099-12-31 00:00:00+00' LIMIT 1;

-- name: record_evidence!
INSERT INTO audit.evidence (intake_id, canonical_requirement_id, requirement_tier_id, control_id, evidence_specification_id,
                            control_phase_code, evidence_artifact_type_code, storage_ref, produced_by_actor_id, produced_role_code)
VALUES (%(intake_id)s, %(canonical_requirement_id)s, %(requirement_tier_id)s, %(control_id)s, %(evidence_specification_id)s,
        %(control_phase_code)s, %(evidence_artifact_type_code)s, %(storage_ref)s, %(produced_by_actor_id)s, %(produced_role_code)s);

-- name: intake_for_obligation^
-- The intake an obligation belongs to (for evidence attribution + scoping).
SELECT r.intake_id, o.canonical_requirement_id, o.target_requirement_tier_id,
       (SELECT tier_level FROM core.requirement_tier rt WHERE rt.requirement_tier_id = o.target_requirement_tier_id) AS target_tier
FROM core.intake_obligation o
JOIN core.intake_obligation_resolution r ON r.intake_obligation_resolution_id = o.intake_obligation_resolution_id
WHERE o.intake_obligation_id = %(obligation_id)s;

-- ── Exceptions (compliance_exception is self-contained; approve_exception sign-off) ───────────────
-- name: insert_exception^
INSERT INTO core.compliance_exception (canonical_requirement_id, waived_tier_level, scope_intake_id,
            compensating_controls, rationale, expires_at, opened_by_actor_id, opened_role_code)
VALUES (%(canonical_requirement_id)s, %(waived_tier_level)s, %(scope_intake_id)s,
        %(compensating_controls)s, %(rationale)s, %(expires_at)s, %(opened_by_actor_id)s, %(opened_role_code)s)
RETURNING compliance_exception_id;

-- name: get_exception^
SELECT compliance_exception_id, canonical_requirement_id, waived_tier_level, scope_intake_id,
       exception_status_code, opened_by_actor_id, approver_actor_id, expires_at
FROM core.compliance_exception WHERE compliance_exception_id = %(exception_id)s;

-- name: set_exception_status!
UPDATE core.compliance_exception
SET exception_status_code = %(status)s, approver_actor_id = %(approver_actor_id)s, signed_as_role_code = %(signed_as_role_code)s, updated_at = now()
WHERE compliance_exception_id = %(exception_id)s;

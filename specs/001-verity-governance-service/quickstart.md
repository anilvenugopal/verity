# Quickstart — Intake Assessment slice (capture + tier + ceiling)

Run and verify the assessment locally. Prereqs: Docker, `uv`, the `hub` venv.

## 1. Substrate + clean DB

```bash
cd tools
dev stack up pg
dev db reset            # rebuild from canonical DDL + seeds (incl. intake.data_classification_code)
```

## 2. Run the hub (mock auth; a governance principal that can edit assessments)

```bash
cd hub
VERITY_ENV=local VERITY_AUTH_MODE=mock \
VERITY_MOCK_PLATFORM_ROLES=ai_governance,business_owner,compliance,viewer \
VERITY_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/verity \
.venv/bin/uvicorn verity.hub.app:app --reload
```

## 3. Exercise the flow (assumes an active application + an intake under it already exist)

```bash
# submit the assessment — the AI-Decision-Impact answers compute the inherent tier; the Data tab
# sets the intake's classification (checked against the app ceiling)
curl -s -XPUT localhost:8000/intakes/$intake/assessment -H 'content-type: application/json' -d '{
  "ai_decision_impact": {
    "decision_role":"recommends_with_signoff","decision_domain":"underwriting",
    "affected_population":"policyholders_consumers","adverse_impact":"coverage_or_claim_denial",
    "human_oversight":{"strategy":"in_the_loop","threshold":"all decisions reviewed"},
    "reversibility":"reversible_with_effort","gdpr_art22":false,"deployment_scale":"limited"
  },
  "data": {
    "description":"Submission documents + prior claims.","sources":["policy_admin","claims_db"],
    "data_classification_code":"tier3_confidential","pii_presence":"direct",
    "lawful_basis":"established","residency":"in_region","retention":"7y","use":"inference"
  },
  "rationale":"Underwriting recommendation affecting policyholders."
}' | jq '.computed'

# read the current assessment + computed tier
curl -s localhost:8000/intakes/$intake/assessment | jq '.computed'

# revision history (SCD-2)
curl -s localhost:8000/intakes/$intake/assessment/revisions | jq '.[].revision'
```

## 4. Run the tests (the real gate)

```bash
cd hub && pytest -q tests/verity/hub/assessment
```

## Acceptance (maps to the spec)

- Submitting the assessment stores a new **SCD-2 revision** on `intake_impact_assessment`; a
  resubmit creates revision 2 and closes revision 1 (FR-AS-010 history).
- The AI-Decision-Impact answers compute the intake's **inherent `ai_risk_tier` + `naic_materiality`**
  (FR-AS-002/008); an `unacceptable` pattern **auto-rejects** the intake with one
  `audit.status_transition` row (FR-IN-004).
- The Data tab sets the intake's **`data_classification_code`**, rejected (**400**) if it exceeds the
  application **ceiling** or if `pii_presence != none` without ≥ `tier3_confidential` (FR-IN-018 — closes T034).
- A `viewer`-only principal is **denied (403)** on PUT, allowed on GET (fail-closed).
- The **Security & Access** answers are captured in the stored assessment (for the later
  access/obligation slices) but are **not** resolved here.

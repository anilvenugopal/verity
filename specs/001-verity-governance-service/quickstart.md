# Quickstart — Application Onboarding slice

Run and verify onboarding locally. Prereqs: Docker, `uv`, the `hub` venv (`uv pip install -e ".[dev]"`).

## 1. Substrate + a clean, seeded DB (with the onboarding migration applied)

```bash
cd tools
dev stack up pg          # local Postgres 18 (pgvector)
dev db reset             # rebuild from canonical DDL + seeds (incl. the onboarding growth, ADR-0012)
```

## 2. Run the hub (mock auth; a principal that can onboard + a governance approver)

```bash
cd hub
VERITY_ENV=local VERITY_AUTH_MODE=mock \
VERITY_MOCK_PLATFORM_ROLES=business_owner,ai_governance,viewer \
VERITY_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/verity \
.venv/bin/uvicorn verity.hub.app:app --reload
```

## 3. Exercise the flow — propose → submit → approve → active

```bash
# propose an application (created pending, with its compliance perimeter)
app=$(curl -s -XPOST localhost:8000/applications -H 'content-type: application/json' -d '{
  "name":"Underwriting Copilot","code":"UWC","description":"Assists underwriters with submission triage.",
  "data_classification_code":"confidential",
  "regulatory_framework_codes":["naic_model_bulletin_ai"],
  "governance_domain_codes":["model_risk","fairness","human_oversight"],
  "jurisdiction_codes":["co","ny"],
  "business_owner_actor_id":"<actor-uuid>",
  "affects_consumers":true,"processes_pii":true,"consumer_facing":false,
  "justification":"Underwriting decisions affecting consumers — governed from intake."
}' | jq -r .application_id)

# submit for approval (opens the application_onboarding approval)
req=$(curl -s -XPOST localhost:8000/applications/$app/submit -H 'content-type: application/json' -d '{}' | jq -r .approval_request_id)

# AI Governance signs off → (business owner too, if they were not the proposer) → app goes active
curl -s -XPOST localhost:8000/approvals/$req/signoff -H 'content-type: application/json' \
  -d '{"decision_code":"approve","comment":"meets governance bar"}' | jq '.status_code'

curl -s localhost:8000/applications/$app | jq '.application_status_code'   # -> "active"
```

## 4. Run the tests (the real gate)

```bash
cd hub && pytest -q tests/verity/hub/application tests/verity/hub/approval   # PG18 testcontainer, e2e
```

## Acceptance (maps to the spec)

- Propose creates the app **`pending`** with a unique, well-formed TLA `code`, the perimeter rows
  (≥1 framework / domain / jurisdiction), the three explicit attestations, and the business owner —
  attribution server-set (D6, FR-IN-015).
- A `viewer`-only principal is **denied (403)** on propose; allowed on `GET` (fail-closed).
- Submit opens an `application_onboarding` approval whose **required roles are computed** =
  AI Governance **+ business owner when they were not the proposer** (D-ONB-1).
- The required sign-offs resolve the request and flip the app to **`active`**, writing the
  **`app_owner`** grant; an incomplete set leaves it `pending` (FR-IN-015).
- A non-`active` app **cannot own promotable intakes/assets**; an intake classification above the
  app **ceiling** is rejected (FR-IN-018).
- The TLA `code` is **immutable once active** (409 on change).
- Invalid reference codes / `<1` framework·domain·jurisdiction / a missing attestation → **400**.

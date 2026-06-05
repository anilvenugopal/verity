# Quickstart — Intake Approval slice

Run and verify intake approval locally. Prereqs: Docker, `uv`, the `hub` venv.

## 1. Substrate + clean DB

```bash
cd tools
dev stack up pg
dev db reset
```

## 2. Run the hub (mock auth; the tier quorum's roles + an author)

```bash
cd hub
VERITY_ENV=local VERITY_AUTH_MODE=mock \
VERITY_MOCK_PLATFORM_ROLES=business_owner,compliance,legal,model_risk,ai_governance,viewer \
VERITY_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/verity \
.venv/bin/uvicorn verity.hub.app:app --reload
```

## 3. Exercise the flow (assumes an active app + an assessed intake with a tier)

```bash
# submit the intake for approval — opens a kind=intake approval with the tier-based quorum
req=$(curl -s -XPOST localhost:8000/intakes/$intake/submit -H 'content-type: application/json' \
  -d '{}' | jq -r .approval_request_id)

# see the required roles (FR-IN-005, computed from the intake's tier)
curl -s localhost:8000/approvals/$req | jq '.required_roles'

# each required role signs off; when the quorum is complete the intake is approved
curl -s -XPOST localhost:8000/approvals/$req/signoff -H 'content-type: application/json' \
  -d '{"decision_code":"approved"}' | jq '.status_code'

# (repeat as the other required-role principals) … then:
curl -s localhost:8000/intakes/$intake | jq '.intake_status_code'   # -> "approved" when the quorum is met
```

## 4. Run the tests (the real gate)

```bash
cd hub && pytest -q tests/verity/hub/intake_approval
```

## Acceptance (maps to the spec)

- Submit opens a `kind=intake` `approval_request` whose **required roles are the tier quorum**
  (FR-IN-005): `high` → 5 roles, `limited` → 3, `minimal` → `business_owner`.
- Submit **requires a computed tier** (the Slice-3 assessment) — an unassessed intake → **400**.
- A **terminal** intake (`rejected`/`retired`) or an intake that already has an open approval → **409**.
- A sign-off requires the signer to **hold a required role** for the tier (else **403**); each role
  slot is filled once.
- When **every required role has an `approved` sign-off**, the intake moves to **`approved`** with one
  `audit.status_transition` row; any `rejected` sign-off → the request is `rejected`.
- A `viewer`-only principal is **denied (403)** on submit/sign-off.

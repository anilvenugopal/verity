# Quickstart — Intake slice

Run and verify the intake slice locally. Prereqs: Docker, `uv`, the `hub` and `tools` venvs
installed (`uv pip install -e ".[dev]"` in each).

## 1. Bring up the substrate + a clean, seeded DB

```bash
cd tools
dev stack up pg          # local Postgres 18 (pgvector) container
dev db reset             # drop + rebuild from the canonical DDL + seeds (ADR-0012)
```

## 2. Run the hub (mock auth, a principal that can author intakes)

```bash
cd hub
VERITY_ENV=local VERITY_AUTH_MODE=mock \
VERITY_MOCK_PLATFORM_ROLES=business_owner,ai_governance,compliance,viewer \
VERITY_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/verity \
.venv/bin/uvicorn verity.hub.app:app --reload
# or: cd tools && dev run    (then `dev logs` to tail it alongside the container)
```

## 3. Exercise the flow

```bash
# onboard an application
app=$(curl -s -XPOST localhost:8000/applications -H 'content-type: application/json' \
  -d '{"name":"Underwriting","description":"demo"}' | jq -r .application_id)

# create an intake under it
intake=$(curl -s -XPOST localhost:8000/applications/$app/intakes -H 'content-type: application/json' \
  -d '{"title":"Submission triage assistant"}' | jq -r .intake_id)

# classify (risk + materiality)
curl -s -XPOST localhost:8000/intakes/$intake/classification -H 'content-type: application/json' \
  -d '{"ai_risk_tier_code":"high","naic_materiality_code":"material"}' | jq .

# change status (audited, one transaction) — to_status_code must be a seeded reference.intake_status
curl -s -XPOST localhost:8000/intakes/$intake/status -H 'content-type: application/json' \
  -d '{"to_status_code":"in_review","reason":"meets criteria"}' | jq .

# add a requirement
curl -s -XPOST localhost:8000/intakes/$intake/requirements -H 'content-type: application/json' \
  -d '{"requirement_kind_code":"business","title":"Explainability","body":"Decisions must cite features"}' | jq .
```

Inspect the audit trail + reads via the dev console:

```bash
cd tools
dev db query intakes          # the intake(s)
dev db query status_history   # audit.status_transition rows for intakes
```

## 4. Run the tests (the real gate)

```bash
cd hub && pytest -q tests/verity/hub/intake     # PG18 testcontainer, end-to-end
```

## Acceptance (maps to the spec)

- A principal with an authoring role creates an application; a `viewer`-only principal is
  **denied (403)** on create, allowed on `GET` (FR-008, fail-closed).
- Create/edit/classify records `created_by_actor_id + acting_role` server-side (D6; never from
  the request body — FR-018).
- A status change updates `intake.intake_status_code` **and** appends exactly one
  `audit.status_transition` row with `from_code`/`to_code` (D4) — in one transaction.
- An invalid reference code (e.g. `ai_risk_tier_code:"bogus"`) returns **400**, not 500 (D-INT-7).
- A requirement is created with `embedding` null (deferred — D-INT-6).

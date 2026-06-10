# Quickstart: Intake Depth Loop (mock auth, end-to-end)

Demonstrates the full governance loop over the seeded metamodel, with **separation of duty** (the asset author / obligation raiser is not the exception approver). Builds on 002's portal + intake lifecycle.

**Pre-reqs**: the metamodel seed is applied (`hub` schema + `specs/schema/seed/` metamodel), and an **active application** with governance domains + frameworks exists (`./dev demo` seeds one — *Underwriting Workbench*).

## 1. Resolve obligations (P1)

Sign in (authoring role, e.g. `ai_governance`), open an assessed `high`-tier use case (e.g. *Auto claim severity estimator*) → **Risk & Obligations** tab. On assessment save the system has **resolved the obligation set** from the metamodel — each obligation shows its canonical requirement, target tier, source provision(s), required control(s) + phase, and the evidence specification, all `outstanding`.

Acid test (the directive):
```bash
curl -s "$HUB/api/requirements/eu-ai-act-data-governance/status?intake=$INTAKE&tier=2" | jq
# → { requirement_code, tier: 2, status: "outstanding", unmet_controls: [...] }   (metamodel query — no bespoke flag)
```

## 2. Satisfy / except

- **Satisfy**: record the specified evidence against an obligation's control → it flips to `satisfied` when every control for tiers ≤ target is evidenced.
- **Except**: where a control can't be met, raise a compliance exception (compensating controls, rationale, expiry). It is `requested` until a **different** principal holding `approve_exception` (sign in as `compliance` or `security`) signs it off → the obligation reads `excepted` until expiry.

When every obligation is `satisfied` or `excepted`, the intake's rollup reports `all_resolved = true`.

## 3. Approve the intake

Submit the intake and have the tier quorum approve it (002's shared sign-off gate). An approved intake with `all_resolved` obligations is the unit that unlocks promotion.

## 4. Link an asset + hit the promotion gate (P2)

As `engineer`/`ai_governance`:
```bash
EXE=$(curl -s -XPOST $HUB/api/executables -d '{"name":"Severity scorer","kind_code":"task"}' | jq -r .executable_id)
VER=$(curl -s -XPOST $HUB/api/executables/$EXE/versions | jq -r .executable_version_id)
curl -s -XPOST $HUB/api/intakes/$INTAKE/links -d "{\"executable_id\":\"$EXE\"}"      # link to the approved intake
curl -s -XPOST $HUB/api/versions/$VER/lifecycle -d '{"to_stage":"candidate"}'         # free (exempt)
curl -s -XPOST $HUB/api/versions/$VER/lifecycle -d '{"to_stage":"champion"}'          # GATED
# approved intake + all_resolved → 200 (promoted). Otherwise 409 GateBlock:
#   { code: "promotion_blocked", reason: "intake_not_approved" | "outstanding_obligation", requirement_code }
```
A `draft → candidate → staging` advance is never gated (free POC); `challenger`/`champion` (production-reaching) are.

## 5. Change proposal (P3)

The use case changes. As the owner, raise a change proposal selecting the impacted asset:
```bash
curl -s -XPOST $HUB/api/intakes/$INTAKE/change-proposals \
  -d "{\"kind\":\"risk_reclassification\",\"impacted_executable_ids\":[\"$EXE\"],\"rationale\":\"New geography\"}"
# → opens an approval_request; sign off via /approvals/{id}/signoff (tier quorum, separation of duty)
```
On approval: each impacted asset gets a **new `draft` forked from its champion** (production untouched), and a `risk_reclassification` **re-resolves** the obligations (back to P1). Promotion of the new draft re-enters the gate.

## What "done" looks like (maps to SC-001..007)

The loop runs end-to-end on seeded data — assess → resolve (metamodel query) → satisfy/except → approve → link → promote (gate passes) → change-propose → fork — with no hand-edited rows, and *"is requirement R at tier N met?"* answerable by a metamodel query throughout.

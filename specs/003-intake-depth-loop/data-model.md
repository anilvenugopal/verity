# Data Model: Intake Depth Loop

This feature is built over the **existing** hardened schema (Principle II) — entities below are already in `specs/schema/` unless marked **NEW**. The novelty is the *resolution algorithm*, the *derived states*, and a thin API surface — not table design.

## 1. Compliance metamodel (the source of truth — read-only at runtime, seeded)

```
regulatory_framework ─< regulatory_provision ─< provision_requirement >─ canonical_requirement
                                                                              │ (governance_domain_code)
                                                          requirement_tier (tier_level 1..N, cumulative) ─┘
                                                              │
                                                requirement_control >─ control (phase, type, enforcement_action)
                                                                          │
                                                              evidence_specification (artifact_type, citable_as)
```

- **canonical_requirement** — versioned (`requirement_code` stable); one `governance_domain`; the stable center axis.
- **requirement_tier** — the cumulative ladder for a requirement (`tier_level`, `criteria`); **tier N implies 1..N**.
- **provision_requirement** — many-to-many provisions↔requirements, by **minimum tier** (Principle VIII).
- **control** — phase ∈ {design_time, deploy_time, static_model, execution}; type ∈ {preventive,detective,corrective,directive}; `enforcement_action`.
- **evidence_specification** — what artifact proves a control (`evidence_artifact_type`, `citable_as`).

All seeded (D9). Validation: codes resolve by FK; `valid_to = 2099-sentinel` marks the current version.

## 2. Per-intake obligation resolution

- **intake_obligation_resolution** — one per resolution run for an intake: `derivation_method` (`manual` here), `ontology_version`, `confidence?`, `resolved_by_actor_id`/`role`. Replaced (new row) on re-resolution; supersedes prior.
- **intake_obligation** — one per applicable canonical requirement under a resolution: `canonical_requirement_id`, `governance_domain_code`, `target_requirement_tier_id`.
- **Derived status per obligation** (not stored — computed, D2): `outstanding | satisfied | excepted`.
  - `satisfied` ⇔ every control for tiers `1..target` has recorded evidence.
  - `excepted` ⇔ the residual controls are covered by an `approved`, unexpired `compliance_exception` with `waived_tier_level ≥ target`.
  - else `outstanding`.
- **Rollup** (intake-level): `all_resolved` ⇔ every obligation is `satisfied` or `excepted` ⇒ the promotion-gate condition.

### Resolution algorithm (compliance service)
```
inputs:  intake.ai_risk_tier_code, application.governance_domains, application.frameworks
tierLevel = {minimal:1, limited:2, high:3}[risk_tier]            # cumulative
reqs = canonical_requirement (current)
        where governance_domain ∈ app.domains
          and exists provision_requirement → provision (current) of a framework ∈ app.frameworks
for each req:
    target = clamp(tierLevel, floor = provision min tier, cap = req max tier_level)
    emit intake_obligation(req, target_requirement_tier_id = req tier @ target)
+ apply seeded signal→requirement triggers (D3) from the assessment answers (e.g. special_category, solely_automated)
persist one intake_obligation_resolution + its intake_obligation rows (supersede prior; preserve still-applicable satisfied/excepted)
```

## 3. Evidence & exceptions

- **evidence** (existing) — recorded against an obligation/control; moves the obligation toward `satisfied`. Append-only, attributed.
- **compliance_exception** (existing) — `canonical_requirement_id`, `waived_tier_level`, scope (`intake`/`application`), `compensating_controls`, `rationale`, `expires_at`, `exception_status` (`requested → approved/rejected`), `approver_actor_id`, `signed_as_role_code`. Self-contained sign-off (D6), status → `audit.status_transition`.

## 4. Registry asset (minimal primitive) + promotion gate

- **executable** (existing) — the governed unit; `kind_code` ∈ {agent, task}.
- **executable_version** (existing) — immutable SCD-2 version; lifecycle stage via `entity_lifecycle_current`.
- **champion_assignment** (existing) — append-only champion pointer; current via `entity_champion_current`.
- **Lifecycle ladder**: `draft → candidate → staging → challenger → champion → deprecated`.
- **Promotion gate** (D4): advancing to `challenger`/`champion` requires the executable be linked (via `intake_entity_link`) to an **approved** intake with `all_resolved` obligations; else blocked with `{reason: not_approved | outstanding_obligation, requirement?}`. `draft/candidate/staging` exempt.

## 5. Intake ↔ asset link

- **intake_entity_link** (existing) — `(intake_id, intake_requirement_id?, executable_id)`; an executable links to **at most one** intake, only while early-stage + not already linked (FR-008). Drives the intake's asset roll-up (each linked asset's most-advanced stage, lower-stage flag).

## 6. Change proposal (P3)

- **approval_request** (existing) with **NEW kinds** `risk_reclassification` / `business_change`, `target_intake_id`, FR-IN-005 quorum, shared sign-off gate.
- **change_proposal_asset** **(NEW, small grouping table — schema review)** — `(approval_request_id, executable_id)`: the impacted assets.
- On approval: fork each impacted asset → new `draft` `executable_version` from champion; `risk_reclassification` re-runs §2 resolution.

## 7. New auth-matrix actions (D8)

| Action | Allowed roles |
|---|---|
| `record_evidence` | the approval/governance roles |
| `approve_exception` | `compliance`, `security` |
| `link_asset` | `engineer`, `ai_governance` |
| `propose_change` | governance |
| (reuse) `author_registry` | create executables/versions |
| (reuse) `promote_registry` | lifecycle advance / gate |
| (reuse) `reclassify_risk` | change proposals |

Fail-closed matrix invariant preserved; `test_matrix_total_coverage` extended.

## 8. API surface (→ contracts/obligations-api.yaml)

`GET /intakes/{id}/obligations` · `POST /obligations/{id}/evidence` · `POST /intakes/{id}/exceptions` · `POST /exceptions/{id}/signoff` · `GET /requirements/{code}/status?intake&tier` · `POST /executables` · `POST /executables/{id}/versions` · `POST /versions/{id}/lifecycle` · `POST /intakes/{id}/links` · `DELETE /links/{id}` · `POST /intakes/{id}/change-proposals` (+ shared `/approvals/{id}/signoff`). Obligation resolution also runs internally on assessment save.

## State transitions

- **Obligation**: `outstanding → satisfied` (evidence) · `outstanding → excepted` (exception approved) · `excepted → outstanding` (exception expiry) · re-resolution may withdraw/add obligations.
- **Exception**: `requested → approved` (approve_exception) | `requested → rejected`; effective until `expires_at`.
- **Asset version (gate-relevant)**: `candidate → staging` (free) · `staging → challenger` / `→ champion` (**gated**) · `champion → deprecated`.
- **Change proposal**: reuses approval `pending → approved/rejected`; on `approved` → fork drafts.

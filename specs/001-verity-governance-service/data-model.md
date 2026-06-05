# Phase 1 — Data Model: Intake Assessment slice (capture + tier + ceiling)

Field names are schema column names verbatim (naming gate). This slice **reuses** the existing
assessment entity and adds **one column** to `core.intake`. Obligation-resolution entities are
**not** touched (deferred — unseeded metamodel).

## Grown: `core.intake` (one column)

| Column | Type | Notes |
|---|---|---|
| `data_classification_code` | text NULL | FK → `reference.data_classification`; the intake's actual sensitivity (set by the Data tab). MUST NOT exceed the owning application's ceiling (FR-IN-018, D-ASM-5). |

Existing intake columns reused: `ai_risk_tier_code`, `naic_materiality_code` (set by the computed
tier, D-ASM-3), `intake_status_code` (auto-reject path, D-ASM-4).

## Reused as-is: `core.intake_impact_assessment` (+ `_current` view)

| Column | Role this slice |
|---|---|
| `intake_id` | FK → `core.intake` (cascade) |
| `revision` | 1,2,3… immutable; new revision per submit; UNIQUE `(intake_id, revision)` |
| `assessment` | `jsonb` — the **four-tab structured answers** (AI Decision Impact · Data · Security & Access · captured) |
| `valid_from` / `valid_to` | SCD-2 window; `valid_to = '2099-12-31'` is the open/current revision |
| `created_by_actor_id` / `created_role_code` | attribution (D6) |

`core.intake_impact_assessment_current` (view, `valid_to = '2099-12-31'`) is the read path.

## The `assessment` jsonb shape (boundary-validated, D-ASM-2)

```
{
  "ai_decision_impact": { decision_role, decision_domain, affected_population, adverse_impact,
                          human_oversight: {strategy, threshold}, reversibility,
                          gdpr_art22, deployment_scale },
  "data":              { description, sources[], data_classification_code, pii_presence,
                         sensitive_categories[], lawful_basis, residency, retention, use },
  "security_access":   { sources[], targets[], tools[], credential_handling, egress },   # captured, not yet resolved
  "rationale":         "<free text>"
}
```

## Computation (read-only outputs)

- **Inherent tier** (D-ASM-3): `ai_decision_impact.*` → `ai_risk_tier_code` + `naic_materiality_code`
  (written to `core.intake` via `intake.service.classify_intake`).
- **Auto-reject** (D-ASM-4): `ai_risk_tier_code = 'unacceptable'` → `intake_status_code = 'rejected'`
  + one `audit.status_transition` row (via `intake.service.change_status`).
- **Ceiling** (D-ASM-5): `data.data_classification_code` rank ≤ `application.data_classification_code`
  rank (`tier1_public` < … < `tier4_pii_restricted`); `data.pii_presence != none` ⇒ ≥ `tier3_confidential`.

## Relationships

```
application (ceiling: data_classification_code)
     │ 1───* intake (data_classification_code ≤ app ceiling; ai_risk_tier/naic_materiality computed)
                   │ 1───* intake_impact_assessment (jsonb answers, SCD-2 revisions)
                   └── unacceptable tier ──> status=rejected + audit.status_transition
```

## Validation rules (FR-AS-002/003/008, FR-IN-004/018)

- The assessment body is Pydantic-validated (enumerated choices); stored as `jsonb`.
- Each submit creates a new revision (closes the prior open window); reads use the `_current` view.
- The computed tier is **inherent** and sets the intake's `*_code` columns.
- `unacceptable` → audited auto-reject (one transaction).
- Intake `data_classification_code` ≤ app ceiling; `processes_pii` ⇒ ≥ `tier3_confidential` (else 400).
- All writes record `created_by/role` server-side (D6).

## Deferred entities (NOT touched — unseeded metamodel)

`core.intake_obligation` / `intake_obligation_resolution`, `canonical_requirement`,
`regulatory_provision`, `control`, `evidence_specification`, `requirement_tier`, `domain_maturity` —
obligation resolution (FR-AS-001 / FR-IN-014) is a dedicated content slice. The Security & Access
answers are captured in `assessment` jsonb for that later slice; no approvable records / ITSM export
/ mitigations this slice (FR-AS-004/005/006/007).

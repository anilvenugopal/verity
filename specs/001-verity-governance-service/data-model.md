# Phase 1 — Data Model: Application Onboarding slice

Field names are schema column names verbatim (naming gate). This slice **grows** the canonical
schema (spec-covered: FR-IN-015…018) and **reuses** existing approval/compliance/app-team tables.
DDL changes are reviewed before service work (Principle II).

## Grown: `core.application` (new columns)

| Column | Type | Notes |
|---|---|---|
| `code` | text | TLA; `UNIQUE`, `CHECK (code ~ '^[A-Z]{3}$')`; immutable after `active` (service-enforced) |
| `application_status_code` | text | FK → `reference.application_status`; default `'pending'` |
| `data_classification_code` | text | FK → `reference.data_classification` (sensitivity ceiling; codes `tier1_public`…`tier4_pii_restricted`) |
| `line_of_business_code` | text NULL | FK → `reference.line_of_business` (optional) |
| `business_owner_actor_id` | uuid | FK → `core.actor`; the designated owner + approval-routing target (set at propose) |
| `affects_consumers` | boolean | NOT NULL, no default (explicit attestation) |
| `processes_pii` | boolean | NOT NULL, no default |
| `consumer_facing` | boolean | NOT NULL, no default |

Existing: `application_id`, `name` (unique, non-blank), `description`, `created_at`, `updated_at`,
`created_by_actor_id`, `created_role_code`.

## New join tables (the compliance perimeter, FR-IN-017)

- **`core.application_regulatory_framework`** — `(application_id → core.application, framework_code → core.regulatory_framework)`, PK both; ≥1 enforced in the service.
- **`core.application_governance_domain`** — `(application_id, governance_domain_code → reference.governance_domain)`, PK both; ≥1.
- **`core.application_jurisdiction`** — `(application_id, jurisdiction_code → reference.jurisdiction)`, PK both; ≥1.

## New reference vocabularies

- **`reference.application_status`** — `pending` · `active` · `suspended` · `retired`.
- **`reference.jurisdiction`** — controlled (US states + `eu` · `uk` · …).
- **`reference.line_of_business`** — `pc` · `life` · `health` · `annuities` · `commercial` · `reinsurance` · `other`.

## Grown: `core.approval_request` (one column)

| Column | Type | Notes |
|---|---|---|
| `target_application_id` | uuid NULL | FK → `core.application`; scopes onboarding approvals (joins existing `target_intake_id` / `target_executable_version_id`) |

`request_kind_code` gains the `application_onboarding` value (seed/validate per D-ONB-7).

## Reused as-is (no change)

- **`core.approval_request`** — `approval_request_id`, `request_kind_code`, `status_code` (default `pending`), `opened_by_actor_id`, `opened_role_code`.
- **`core.approval_signoff`** — `approval_request_id`, `approver_actor_id`, `signed_as_role_code`, `decision_code → reference.approval_decision`, `comment`.
- **`core.actor_app_role_grant`** (+ `current_actor_app_role` view) — business owner + initial app-team grants; the `app_owner` grant written on approval.
- **`reference.governance_domain`** (the 9), **`reference.data_classification`** (4 sensitivity codes — verify seed, D-ONB-3), **`core.regulatory_framework`**, **`reference.approval_decision`**, **`reference.approval_request_status`**, **`reference.app_team_role`** (renamed `app_*`, D-ONB-6).

## Relationships

```
actor ──proposes──> application (pending)
   │                     │ 1───* application_regulatory_framework ─> regulatory_framework
   │                     │ 1───* application_governance_domain ────> governance_domain
   │                     │ 1───* application_jurisdiction ─────────> jurisdiction
   │                     │ data_classification_code (ceiling) ─────> data_classification
   └──signs off──> approval_request (kind=application_onboarding, target_application_id)
                        │ 1───* approval_signoff (signed_as_role, decision)
                        └── resolved (approved) ──> application.status = active
                                                    + actor_app_role_grant (app_owner)
```

## Validation rules (from FR-IN-015…018)

- `code`: `^[A-Z]{3}$`, unique; immutable once `active`.
- Perimeter: ≥1 regulatory framework, ≥1 governance domain, ≥1 jurisdiction (else 400).
- Attestations: all three booleans required (no default; missing → 400/422).
- `data_classification_code` is the **ceiling**: an intake's actual classification MUST NOT exceed it; `processes_pii = true` ⇒ ceiling ≥ `confidential`. **[deferred — T034]**: `core.intake` has no `data_classification` column yet (intake classification = risk-tier/materiality only); ceiling enforcement requires an intake-schema addition in the next intake slice.
- Approval resolves only when every computed required role (AI Governance + business-owner-if-not-proposer) has an `approval` sign-off; any rejection blocks.
- A non-`active` application MUST NOT own promotable intakes/assets (FR-IN-015).
- All writes record `created_by/role` server-side (D6 / FR-018).

## State

`application_status`: `pending` --(approval)--> `active` --(governed)--> `suspended` / `retired`.
The compliance perimeter is editable only via re-approval (a change proposal — FR-IN-013); `code` is immutable once `active` (FR-IN-018).

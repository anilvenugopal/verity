# Data Model: UI Shell, Auth & Application Onboarding

**Date**: 2026-06-05  
**Source**: `spec.md` entities + backend models in `hub/src/verity/hub/`

This document defines the TypeScript types and React state shapes the portal uses. Field names mirror the backend Pydantic model names exactly (naming gate).

---

## 1. Session / Principal

Held in `SessionContext` (React context, in-memory only — never persisted).

```typescript
// Sourced from GET /me (extended response)
interface Principal {
  actor_id: string;               // UUID
  tenant_id: string;              // UUID
  display_name: string;
  email: string | null;
  platform_roles: string[];       // e.g. ["ai_governance", "viewer"]
  app_team_roles: AppTeamRole[];  // scoped per application
  session_epoch: number;
  is_mock: boolean;               // true when auth_mode=mock
}

interface AppTeamRole {
  application_id: string;         // UUID
  application_name: string;
  role_code: string;              // e.g. "app_demo_lead"
}
```

---

## 2. Auth state

Drives which full-screen surface is rendered (or nothing, if authenticated).

```typescript
type AuthState =
  | "loading"          // GET /me in flight on mount
  | "authenticated"    // principal loaded successfully
  | "unauthenticated"  // no session (401 from /me) → redirect to /signin
  | "session_expired"  // 401 mid-session (after initial load)
  | "forbidden"        // 403 on a route-level check
  | "disabled";        // account disabled (403 with code "account_disabled")
```

---

## 3. Application

Mirrors `hub/src/verity/hub/application/models.py::Application`.

```typescript
interface Application {
  application_id: string;           // UUID
  code: string;                     // TLA e.g. "UWD"
  name: string;
  description: string;
  application_status_code: string;  // "pending" | "pending_approval" | "active" | "suspended" | "retired"
  line_of_business_code: string | null;
  data_classification_code: string;
  business_owner_actor_id: string;  // UUID
  regulatory_framework_codes: string[];
  governance_domain_codes: string[];
  jurisdiction_codes: string[];
  affects_consumers: boolean;
  processes_pii: boolean;
  consumer_facing: boolean;
  created_at: string;               // ISO 8601
}

// POST /applications body — mirrors ApplicationPropose
interface ApplicationPropose {
  code: string;                           // /^[A-Z]{3}$/
  name: string;
  description: string;
  line_of_business_code: string | null;
  data_classification_code: string;
  regulatory_framework_codes: string[];
  governance_domain_codes: string[];
  jurisdiction_codes: string[];
  business_owner_actor_id: string;
  initial_app_team: AppTeamMember[];
  affects_consumers: boolean;
  processes_pii: boolean;
  consumer_facing: boolean;
  justification: string;
}

interface AppTeamMember {
  actor_id: string;
  app_team_role_code: string;
}
```

---

## 4. Approval request (shared — onboarding AND intake)

Mirrors `hub/src/verity/hub/approval/models.py::ApprovalRequest` exactly. **One kind-agnostic shape** is
returned for both `application_onboarding` and `intake` (dispatched on `request_kind_code`). There is
no `application_name`/`required_signoffs`/`recorded_signoffs` and **no `returned_for_revision`** — those
were an earlier draft that diverged from the backend.

```typescript
interface ApprovalRequest {
  approval_request_id: string;    // UUID
  request_kind_code: string;      // "application_onboarding" | "intake"
  status_code: string;            // "pending" | "approved" | "rejected" | "cancelled"
  target_intake_id: string | null;       // set when kind=intake
  target_application_id: string | null;   // set when kind=application_onboarding
  required_roles: string[];        // computed quorum (FR-IN-005 for intake)
  signoffs: SignoffRecord[];
  created_at: string;
}

interface SignoffRecord {
  approver_actor_id: string;      // UUID
  signed_as_role_code: string;
  decision_code: string;          // "approved" | "rejected" | "requested_changes" | "abstained"
  comment: string | null;
}

// POST /approvals/{id}/signoff body — reference.approval_decision vocabulary.
// Resolution terminates only on `rejected` (→ rejected) or full-quorum `approved` (→ approved);
// `requested_changes` / `abstained` leave the request `pending`.
// UI rule (not an API constraint): onboarding offers Approve / Return-for-revision (requested_changes);
// intake offers Approve / Reject only (rejected).
interface Signoff {
  decision_code: "approved" | "rejected" | "requested_changes" | "abstained";
  comment: string | null;
}
```

---

## 5. API error envelope

All API errors from the hub follow the same shape (from `app.py` `AuthError` handler and FastAPI default validation errors).

```typescript
interface ApiError {
  code: string;       // stable machine-readable code e.g. "unauthenticated", "action_denied"
  detail: string;     // human-readable, non-leaking
  request_id: string;
}
```

---

## 6. UI-only state shapes (not persisted, not sent to API)

```typescript
// Multi-step form progress
interface OnboardFormState {
  step: 1 | 2 | 3 | 4;                   // 1=identity, 2=ownership, 3=perimeter, 4=review
  dirty: boolean;                          // unsaved changes guard
  values: Partial<ApplicationPropose>;
  errors: Record<string, string>;
}

// Approval view scroll gate
interface ApprovalViewState {
  approval_request_id: string;
  scrolled_to_end: boolean;               // gates action buttons
  submitting: boolean;
}

// App launcher
interface AppLauncherState {
  open: boolean;
  search_query: string;
}
```

---

## 7. State transitions — Application status

Reflects the shipped backend (`application/service.py`). `POST /applications/{id}/submit` opens a
`kind=application_onboarding` approval but does **not** change the application status — the app stays
`pending` while the approval is open. Only a full-quorum `approved` activates it.

```
[pending]   (created by propose)
    │ POST /applications/{id}/submit  → opens approval (app stays pending)
    ▼
[pending] + open approval
    │ POST /approvals/{id}/signoff  decision_code=approved   (quorum satisfied)
    ▼
[active]

[pending] + open approval
    │ POST /approvals/{id}/signoff  decision_code=rejected   (any signer)
    ▼
approval → rejected;  app stays [pending]   (no auto return-to-draft is enforced today)
    # decision_code=requested_changes / abstained leave the approval `pending` (no terminal effect yet)

[active] ──POST /applications/{id}/lifecycle to_status=suspended──▶ [suspended]
[active] ──POST /applications/{id}/lifecycle to_status=retired────▶ [retired]
```

Status badge colour mapping (design system tokens):
- `pending` → `--color-warning` pill
- `active` → `--color-positive` pill
- `suspended` / `retired` → `--text-tertiary` pill (neutral)

---

# Milestone 4 — Intake lifecycle types

Field names mirror the backend models in `hub/src/verity/hub/intake/models.py` and
`hub/src/verity/hub/assessment/models.py` verbatim (naming gate).

## 8. Intake

```typescript
// GET /intakes/{intake_id}  &  rows in GET /applications/{application_id}/intakes
interface Intake {
  intake_id: string;                    // UUID
  application_id: string;               // UUID
  title: string;
  description: string | null;
  intake_status_code: string;           // "proposed" | "in_review" | "approved" | "rejected" | "retired"
  ai_risk_tier_code: string | null;     // computed by the assessment; null until assessed
  naic_materiality_code: string | null;
  materiality_tier_code: string | null; // intake-level materiality (distinct from agent-level)
  created_at: string;                   // ISO 8601
}

// POST /applications/{application_id}/intakes body — mirrors IntakeCreate
interface IntakeCreate {
  title: string;                        // min length 1
  description?: string | null;
}
```

## 9. Requirement

```typescript
interface Requirement {
  intake_requirement_id: string;        // UUID
  intake_id: string;                    // UUID
  requirement_kind_code: string;
  requirement_status_code: string;
  title: string;
  body: string;
  created_at: string;
}

// POST /intakes/{intake_id}/requirements body — mirrors RequirementCreate
interface RequirementCreate {
  requirement_kind_code: string;
  title: string;
  body: string;
}
```

## 10. Assessment (the two shipped tabs only)

```typescript
// PUT /intakes/{intake_id}/assessment body — mirrors AssessmentInput.
// NOTE: both shipped tabs are REQUIRED in one payload — there is no partial PUT.
// security_access stays null in M4 (that tab's backend is unbuilt → feature 003).
interface AssessmentInput {
  ai_decision_impact: AIDecisionImpact;   // tab 1 (required)
  data: DataTab;                          // tab 2 (required)
  security_access?: null;                 // M4: always null
  rationale?: string | null;
}

interface AIDecisionImpact {
  decision_role: "assists" | "recommends_with_signoff" | "autonomous";
  decision_domain: "underwriting" | "pricing" | "claims" | "fraud" | "marketing" | "servicing" | "internal_ops";
  affected_population: "internal_only" | "brokers_agents" | "policyholders_consumers" | "vulnerable";
  adverse_impact: "negligible" | "financial" | "coverage_or_claim_denial" | "unfair_discriminatory" | "safety";
  human_oversight: { strategy: "none" | "on_the_loop" | "in_the_loop"; threshold?: string | null };
  reversibility: "easily_reversible" | "reversible_with_effort" | "irreversible";
  gdpr_art22: boolean;
  deployment_scale: "pilot" | "limited" | "production_wide";
}

interface DataTab {
  description: string;                    // min length 1
  sources: string[];
  data_classification_code: string;       // tier1_public | tier2_internal | tier3_confidential | tier4_pii_restricted
  pii_presence: "none" | "direct" | "indirect" | "special_category";
  sensitive_categories: string[];
  lawful_basis?: string | null;
  residency?: string | null;
  retention?: string | null;
  use?: string | null;
}

// GET /intakes/{intake_id}/assessment — mirrors AssessmentView
interface AssessmentView {
  intake_id: string;
  revision: number;
  assessment: Record<string, unknown>;   // the captured AssessmentInput as stored
  computed: Computed | null;
  created_at: string;
}

interface Computed {
  ai_risk_tier_code: string | null;
  naic_materiality_code: string | null;
  data_classification_code: string | null;
  intake_status_code: string | null;
  auto_rejected: boolean;                 // true when the tier computed to unacceptable → intake auto-rejected
}

// GET /intakes/{intake_id}/assessment/revisions — mirrors RevisionMeta
interface RevisionMeta {
  revision: number;
  valid_from: string;
  valid_to: string;
  created_by_actor_id: string;
}
```

## 11. Intake approval request (kind=intake)

The intake approval reuses the shared approval entity. Shape per `hub/src/verity/hub/approval/models.py::ApprovalRequest` with `request_kind_code = "intake"` and `target_intake_id` set. `required_roles` is the FR-IN-005 tier quorum, computed from the intake's `ai_risk_tier_code` (not stored).

```typescript
// POST /intakes/{intake_id}/submit → ApprovalRequest (kind=intake)
// GET /approvals/{approval_request_id} → ApprovalRequest
// Reuses the shared ApprovalRequest type (§4). UI rule: for kind=intake the sign-off offers
// approve/reject ONLY (a UI narrowing of the shared Signoff vocabulary — not a separate API shape).
interface Signoff_Intake {
  decision_code: "approved" | "rejected";   // intake UI omits requested_changes/abstained
  comment: string | null;
}
```

## 12. UI-only state — intake (not persisted, not sent to API)

```typescript
// Assessment editor: both tabs held client-side; a per-tab Save PUTs the FULL snapshot.
// A save only succeeds once BOTH tabs' required fields are valid (backend requires both).
interface AssessmentEditorState {
  intake_id: string;
  ai_decision_impact: Partial<AIDecisionImpact>;
  data: Partial<DataTab>;
  active_tab: "ai_decision_impact" | "data";
  dirty: boolean;
  computed: Computed | null;              // last server-computed result
  approval_open: boolean;                 // true when intake is in_review → show the "re-save may change tier" banner
}
```

## 13. State transitions — Intake status

```
[proposed]
    │ PUT …/assessment  (tier computed)        │ assessment → unacceptable
    │ POST /intakes/{id}/submit                 ▼
    ▼                                       [rejected] (auto, terminal)
[in_review]
    │ POST /approvals/{id}/signoff  decision=approved  (full tier quorum)
    ▼
[approved]

[in_review]
    │ POST /approvals/{id}/signoff  decision=rejected  (any signer)
    ▼
[rejected] (terminal)
```

Intake status badge colours: `proposed` → `--color-warning`; `in_review` → `--color-info`/`--color-warning`; `approved` → `--color-positive`; `rejected` / `retired` → `--text-tertiary`.
Risk-tier badge: `high`/`unacceptable` → `--color-negative`; `limited` → `--color-warning`; `minimal` → `--color-positive`.

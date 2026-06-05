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

## 4. Approval request

Mirrors `hub/src/verity/hub/approval/models.py::ApprovalRequest`.

```typescript
interface ApprovalRequest {
  approval_request_id: string;    // UUID
  application_id: string;         // UUID
  application_name: string;
  status_code: string;            // "pending" | "approved" | "returned_for_revision"
  required_signoffs: RequiredSignoff[];
  recorded_signoffs: RecordedSignoff[];
  submitted_at: string;
  resolved_at: string | null;
}

interface RequiredSignoff {
  role_code: string;
  label: string;
}

interface RecordedSignoff {
  actor_id: string;
  display_name: string;
  role_code: string;
  decision_code: string;
  comment: string | null;
  recorded_at: string;
}

// POST /approvals/{id}/signoff body
interface Signoff {
  decision_code: "approved" | "returned_for_revision";
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

```
[proposed]
    │ POST /applications/{id}/submit
    ▼
[pending_approval]
    │ POST /approvals/{id}/signoff  decision_code=approved
    ▼                                (quorum met)
[active]

[pending_approval]
    │ POST /approvals/{id}/signoff  decision_code=returned_for_revision
    ▼
[pending]  (back to draft/editable)

[active] ──POST /applications/{id}/lifecycle to_status=suspended──▶ [suspended]
[active] ──POST /applications/{id}/lifecycle to_status=retired────▶ [retired]
```

Status badge colour mapping (design system tokens):
- `pending` / `pending_approval` → `--color-warning` pill
- `active` → `--color-positive` pill
- `suspended` / `retired` → `--text-tertiary` pill (neutral)

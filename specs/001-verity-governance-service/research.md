# Phase 0 — Research & Decisions: Application Onboarding slice

The stack/storage are fixed (constitution + ADRs). These decisions resolve the choices specific
to onboarding. Much of the infrastructure already exists in the canonical schema; several
decisions are about *reuse* vs *grow*.

## D-ONB-1 — Approval required-roles are computed, not stored
- **Decision**: `core.approval_request` has no `required_roles` column; for `kind=application_onboarding`
  the service **computes** the required set = `{ai_governance}` ∪ `{business_owner}` **iff** the
  proposer is not the named business owner. The request **resolves** (`approved`) when there is an
  `approval` sign-off from each required role (recorded in `core.approval_signoff`); any
  `rejected`/`changes_requested` sign-off blocks.
- **Rationale**: the conditional rule (FR-IN-015) is policy, best kept in code beside the matrix;
  the existing tables already carry the request + sign-offs. Avoids a schema change for roles.
- **Alternatives**: store `required_roles` on the request (rejected — duplicates policy, drifts);
  a DB trigger to resolve (rejected — hides attribution).

## D-ONB-2 — TLA `code` is the application identity key
- **Decision**: `core.application.code` is a 3-letter TLA — `CHECK (code ~ '^[A-Z]{3}$')`, `UNIQUE`,
  **immutable after approval** (enforced in the service: the column is settable while `pending`,
  rejected on change once `active`). It is the audit-correlation key (FR-IN-015) and the
  `application_code` resolution key referenced by FR-IN-001.
- **Rationale**: a stable short key removes ambiguity in evidence trails; FR-IN-001 already
  resolves intakes by `application_code`.
- **Alternatives**: longer slug (rejected — the TLA is the chosen product convention; 3-char space
  ~17.5k is sufficient for an app catalog); mutable code (rejected — breaks audit correlation).

## D-ONB-3 — Reuse `reference.data_classification` as the sensitivity ceiling
- **Decision**: the perimeter's data-classification **reuses** the existing
  `reference.data_classification` (its table comment defines it as the data-sensitivity vocab:
  `public`/`internal`/`confidential`/`pii_restricted`). `core.application.data_classification_code`
  FKs to it as the **ceiling**. An intake's actual classification MUST NOT exceed it;
  `processes_pii = true` implies a ceiling ≥ `confidential`.
- **Implementation check**: an early grep suggested the *seed* may hold environment-tier codes
  (`development/staging/…`) rather than the 4 sensitivity codes — **verify and repair the seed** to
  `{public, internal, confidential, pii_restricted}` during the migration task.
- **Alternatives**: a new `data_sensitivity` vocab (rejected — the existing table already *means*
  sensitivity per its contract; renaming/duplicating would churn references).

## D-ONB-4 — Compliance perimeter as join tables; domains/frameworks reused
- **Decision**: the multi-valued perimeter is three join tables —
  `core.application_regulatory_framework` (→ existing `core.regulatory_framework`),
  `core.application_governance_domain` (→ existing `reference.governance_domain`, the 9), and
  `core.application_jurisdiction` (→ new `reference.jurisdiction`). The three attestations
  (`affects_consumers`, `processes_pii`, `consumer_facing`) are NOT-NULL booleans on
  `core.application` (no default — explicit attestation, FR-IN-017).
- **Rationale**: governance domains + frameworks already exist; only jurisdictions/LOB are new.
  Booleans-without-default force a deliberate Yes/No (a default reads as a silent "No").
- **Alternatives**: a single jsonb perimeter blob (rejected — unqueryable, no FK integrity for the
  framework→provision→obligation chain).

## D-ONB-5 — Onboarding supersedes the Slice-1 instant create
- **Decision**: the shipped `POST /applications` (instant create, Slice 1) is **reworked** into
  *propose* → creates the application `pending` with identity + ownership + perimeter; a separate
  *submit* opens the approval; *sign-off* resolves it to `active`. Slice-1's create test is
  updated to assert `pending` + the perimeter.
- **Rationale**: FR-IN-015 makes onboarding a governed proposal; the thin create was a Slice-1
  placeholder.
- **Alternatives**: keep both paths (rejected — two create semantics is a footgun).

## D-ONB-6 — `app_team_role` renamed `app_demo_*` → `app_*`
- **Decision**: rename the seed vocab `app_demo_{owner,lead,dev,sre,ops}` →
  `app_{owner,lead,dev,sre,ops}`. The business owner + initial app-team write grants to the
  existing `core.actor_app_role_grant`; approval writes the `app_owner` grant.
- **Rationale**: the `*_demo_*` names leak demo semantics into the product vocab.
- **SC-004 note**: this touches the "vocabularies verbatim from v1" criterion — recorded as an
  **intentional v2 product rename** (never silent — Principle VI), to be reflected in the
  disposition table.

## D-ONB-7 — New vocabs: `application_status`, `jurisdiction`, `line_of_business`
- **Decision**: add `reference.application_status` (`pending` | `active` | `suspended` | `retired`),
  `reference.jurisdiction` (controlled — US states + EU/UK + …; "Other" is a non-driving free-text
  note, not a row), and `reference.line_of_business` (P&C · Life · Health · Annuities · Commercial ·
  Reinsurance · … + `other`). The `application_onboarding` value is added to the approval-request
  kind vocabulary (or validated by the service if the kind column is unconstrained).
- **Rationale**: status/jurisdiction/LOB are genuinely new; jurisdictions must be controlled so the
  jurisdiction→regime mapping works (FR-IN-017).
- **Alternatives**: free-text jurisdiction (rejected — breaks regime selection).

## Error model (slice)
- `401/403` → `AuthError` (unauthenticated / action denied), non-leaking JSON.
- `404` → unknown application / approval id.
- `409` → duplicate TLA; attempt to mutate an immutable `code`; submit on a non-`pending` app.
- `400` → invalid reference code (FK) with the field; perimeter cardinality (`<1` framework /
  domain / jurisdiction); a missing attestation; classification-ceiling violation.
- `422` → Pydantic request validation.

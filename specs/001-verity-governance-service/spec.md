# Feature Spec — verity-governance Service (umbrella)

- **Status:** Draft
- **Date:** 2026-05-30
- **Related:** [[verity_v2_pcr]], [[0003-harness-governance-api]],
  [[0004-storage-architecture]], [[0005-schema-hardening]],
  [[0006-packages-and-governed-deployment]], [[0007-decision-log-scale-and-portable-analytics]],
  [[0008-compliance-control-evidence-model]], [[binding-grammar]], [[user-authentication]],
  [[constitution]]
- **Purpose:** The umbrella feature specification for **`verity-governance`** — the
  Tier-1 system-of-record service that owns AI asset definitions, their 6-state
  lifecycle, the use-case intake/risk machine, the append-only decision and
  model-invocation audit trail, run/execution state, soft quotas, plan/cost/ROI
  business-case envelopes, testing/validation metadata, governed packaging and
  deployment, YAML portability, and reporting/compliance. It restates every v1
  governance capability as **observable behaviour** (inputs, outputs, contracts,
  state transitions, failure modes) and applies the v2 architecture deltas:
  **API-only boundary** (ADR-0003), **hardened schema + Source/Target Binding grammar**
  (ADR-0005, [[binding-grammar]]), **packages and governed deployment** (ADR-0006),
  **append-only logs with a portable analytics tier** (ADR-0004, ADR-0007), and
  **DB-managed authorization** ([[user-authentication]]). No silent capability loss
  ([[constitution]] Principle III): every v1 capability is explicitly
  KEEP / CHANGE / DROP-with-reason / DEFER-with-reason in the disposition table.
- **Traceability:** Honors Principle I (Spec Precedes Implementation). Intent traces
  to the PCR ([[verity_v2_pcr]]): governance becomes a network service behind a single
  API boundary (ADR-0003), the schema is hardened (ADR-0005), champion promotion
  produces deployable packages (ADR-0006), and the decision log scales into a portable
  analytics tier (ADR-0004/0007). The controlled vocabularies (lifecycle states, AI
  risk tiers, approval roles/decisions, capability types, run purposes, materiality
  tiers, metric types) are carried **verbatim** from v1 (`contracts/enums.py`,
  `models/intake.py`). Authorization composes with [[user-authentication]]: the action
  matrix and approval-by-risk-tier sets are the same; the **role source changes from
  cookie persona to DB-managed grants** and **every surface is gated**. The SQL shapes
  are illustrative; the canonical schema lives in `specs/schema/verity_schema.sql`
  (schema gate, Principle II) — this spec is the source of the observable contracts
  until that artifact is authored.

This is **platform plumbing**, not a product vertical slice; the equity-research slice
([[equity-research-slice]]) is the first consumer that exercises it end to end. It is a
**local-dev-first** spec; production deltas are called out explicitly throughout and
consolidated under *What changes for production*.

> **Spec tier & slicing.** 001 is the **component spec** for `verity-governance` (PCR §4
> hierarchy: ADRs → component specs → slices → implementation) and the behavioral source of
> truth for the whole service. The roadmap phases (Intake, Registry/Compose, Decision
> Logging, …) are **plan-driven delivery slices** of it — each is realized via
> `/speckit.plan` + `/speckit.tasks` scoped to the relevant `FR-*` ranges here (plus its
> UX wireframe and phase controls), and does **not** re-state these requirements as a
> separate spec. Capability shapes are defined once: here for behavior, in
> `specs/schema/verity_schema.sql` for data.

---

## Clarifications

### Session 2026-05-31

- Q: Minimum evidence set to promote a version to champion? → A: The **full validation set + design/static control evidence** — staging tests passed; ground-truth passed & reviewed; model card reviewed; challenger metrics reviewed; the risk-tier approval quorum + champion confirmation; impact assessment complete (limited/high); all linked functional & compliance requirements satisfied; and captured evidence for every design-time + static/model control required at the asset's tier (deploy/execution controls enforce at their own phases).
- Q: Who may approve a compliance exception (waiving a control tier)? → A: A dedicated `approve_exception` action (distinct from promotion sign-off), granted to the `compliance` and `security` roles.
- Q: Target latency for a decision-log record to become visible in the UI? → A: ≤ 20 seconds (p95), via async/batched ingest.
- Q: Quota enforcement posture in v2? → A: Per-quota configurable — soft (warn/breach, never refuse) by default, with an optional hard-stop that refuses the run when the budget is exceeded.

### Session 2026-06-04

*(Intake model simplification + assessment — guides the next slice; the shipped US1–US4 stays the thin CRUD foundation.)*

- Q: Is application onboarding in scope for intake, and how is it governed? → A: Yes. `onboard_application` is a documented v2 action (FR-AUTHZ-001 addition). **Any platform author** (`engineer`/`ai_governance`/`business_owner`) MAY propose onboarding; approval requires **AI Governance**, **plus the `business_owner` when they were not the proposer** (the business owner must be proposer or approver). A dedicated **Application Onboarding** screen is added (potentially the app's first screen). See FR-IN-015.
- Q: What does onboarding capture, and how are environments/harnesses handled? → A: Onboarding captures name, description, **business owner (required)**, **governance domains** (app defaults; intake refines — FR-IN-014), and **cost center/quota**; it creates the app `pending` → AI-Governance-approved (+ business_owner if not the proposer) → `active` (status set `{pending, active, suspended, retired}`), establishing the owner's `app_owner` grant (via `core.actor_app_role_grant`) and a unique application `code`. The application screen is **multi-tab** (Overview · Environments · Harnesses · Inventory). **Environments are defined here with no approval**; **harness provisioning happens elsewhere** and a harness is **tied to an environment**, after which **standard environment/deployment rules apply** (Principle VII / ADR-0006, ADR-0010). See FR-IN-015/FR-IN-016.
- Q: Onboarding field & compliance-perimeter design decisions? → A: Onboarding draws the **regulatory perimeter** (app level); intakes inherit and set act-level risk (FR-IN-017/018). (1) Compliance perimeter is **editable post-approval via re-approval** (change proposal — FR-IN-013); the **TLA/`code` is immutable**. (2) **≥1 regulatory framework mandatory** (explicit `internal_only`/`nist_ai_rmf` sentinel, never blank). (3) **jurisdictions = controlled `reference.jurisdiction`** ("Other" is a non-driving note). (4) **data classification: app = ceiling, intake = actual** (intake MUST NOT exceed; `processes_pii` ⇒ ceiling ≥ `confidential`). (5) **app-team roles renamed** `app_demo_*` → `app_{owner,lead,dev,sre,ops}` (intentional v2 rename). (6) **`line_of_business` = controlled `reference.line_of_business` + "Other"**. `application.code` = 3-char TLA; approval kind `application_onboarding`; grants in `core.actor_app_role_grant`. Implied schema growth (code, data_classification_code, the three booleans, the framework/domain/jurisdiction joins, `reference.jurisdiction`, `line_of_business`, `actor_app_role_grant`, `application_onboarding` kind) is deferred to `/plan`.
- Q: Does the intake itself carry `in_build`/`live` states? → A: No. The intake status set is `{proposed, in_review, impact_assessment, approved, rejected, retired}`. `in_build`/`live` are **asset** stages surfaced on the intake by linking, not intake attributes — revises FR-IN-011/FR-IN-012 and removes `in_build`/`live` from `reference.intake_status` for intake use.
- Q: How do assets relate to an intake, and what gates promotion? → A: Assets **link to an intake** at the **asset level (not asset-version)**. An asset MAY link to at most one intake, only while `draft`/`candidate` and not already linked. Moving an asset **beyond `candidate`** (→ `champion`) requires a link to an **approved** intake; **`draft` is exempt** (free POC). The intake page rolls up each linked asset's most-advanced stage and flags lower-stage versions. Elevates FR-IN-009 as the promotion gate.
- Q: Are approvals part of intake? → A: Yes — approval is **core** to intake (no longer deferred). The intake approval (`kind=intake`, FR-IN-001) uses the tier→required-roles mapping (FR-IN-005). An approved intake is the unit that unlocks asset promotion.
- Q: How are post-intake changes (risk reclassification, business changes) handled? → A: As **change proposals** — an `approval_request` of kind `risk_reclassification` (FR-IN-013) or `business_change`, scoped to the intake, selecting **impacted assets**. On approval each impacted asset gets a **new `draft` forked from its champion** (or most-advanced stage). Modeled as an **extension of intake** (reuse `approval_request` + intake↔asset links; at most one small grouping table) — no standalone screen.
- Q: Is there a structured risk/impact assessment at intake? → A: Yes — a mandatory **Intake Assessment Questionnaire** extending `intake_impact_assessment` (history-keeping), with tabs **AI Decision Impact**, **Data**, **Security & Access**, and a computed **Risk & Obligations** summary. Each answer links to **compliance canonical requirements**, so completing it resolves the **obligation set** (FR-IN-014), computes the **risk tier + NAIC materiality + rationale**, and is the **approval justification**. Required before approval; serves as the `impact_assessment` gate for limited/high tiers. See FR-AS-001..010.
- Q: Does the assessment cover PII and data sensitivity? → A: Yes — the Data tab captures PII presence (none/direct/indirect/special-category) and sensitive-insurance-data categories; special-category PII triggers DPIA/minimization obligations.
- Q: How are required system accesses handled? → A: The Security & Access tab enumerates **sources (read), targets (write/act), and tools** as approvable items. On intake approval each is **governance-approved** and exported as an **Access Approval Record** the builder submits to external **ITSM/IAM**. Verity records/approves the **intent**; it does **not** integrate IAM/ITSM directly.
- Q: Can risk **mitigations** be recorded? → A: Yes — any risk-flagged answer supports one or more **mitigation/risk-treatment** records (procedure, treatment type avoid/reduce/transfer/accept, addressed control, owner, status, residual risk). A mitigation satisfying a required control becomes **evidence**; an `accept` of an unmet required control routes to **`approve_exception`** (FR-RP-009), not a silent pass.
- Q: Do mitigations lower the risk tier? → A: No. The **inherent EU-AI-Act tier** is fixed by the use case and is not downgraded by mitigations; mitigations **satisfy obligations** and track **residual risk** separately. Both are recorded; classification uses the inherent tier.
- Q: Requirement field set — schema (`title`/`body`) vs FR-IN-007? → A: **FR-IN-007 is authoritative** — `core.intake_requirement` will **grow** to add `statement`, `acceptance_criteria`, `source`, optional `parent_requirement_id`, and a unique `code` within the intake (spec-then-schema; the shipped slice's `title`/`body` reconciles to this).
- Q: Is intake-level `materiality_tier` distinct from the agent-level one? → A: Yes — the intake carries its **own** `materiality_tier`, intentionally distinct from the agent/plan-row `materiality_tier` (FR-IN-006); it stays on intake classification.
- Q: Status-transition action vocabulary (shipped slice)? → A: Gate **initial** classification on `triage_intake` and reserve **`reclassify_risk`** for re-triage (a change proposal); the shipped slice's generic `triage_intake` status gate reconciles to the per-target lifecycle actions.
- Q: Confirm deferred-with-reason? → A: Deferred — **Plan / estimate / ROI / cost** (and the estimation features); `edit_intake` PATCH beyond create (next slice); requirement **embeddings / semantic dedup**.

---

## User Scenarios & Testing *(mandatory)*

User journeys are prioritized P1–P3. Each is independently testable and delivers value
on its own. P1 is the governed lifecycle of an AI asset (the core product loop); P2 is
the governance front-of-funnel (intake/risk/business-case) and the audit/run substrate
that makes any execution accountable; P3 is portability, packaging-driven deployment,
and compliance reporting.

### User Story 1 — Author, validate, and promote a governed AI asset (Priority: P1)

An engineer registers a task or agent, composes its bindings/prompts/tools, runs it
through the 6-state lifecycle (draft → candidate → staging → challenger →
champion), and promotes a champion that consumers resolve at runtime. The promotion to
champion produces a deployable **package** (see Story 3). This is the core governed
change loop the platform exists to provide.

**Why this priority**: Without a governed entity/version model and lifecycle, nothing
else has anything to govern. It is the minimum viable governance loop.

**Independent Test**: Register an agent + version via the API, attach a Source Binding /
Target Binding / prompt / tool, promote draft → candidate → … → champion with the gate
evidence, then resolve the champion config via the API and confirm it returns the frozen
inference snapshot, ordered prompts, and authorized tools.

**Acceptance Scenarios**:

1. **Given** a registered agent with one draft version carrying a non-empty
   `input_schema`, **When** the caller promotes `draft → candidate`, **Then** the
   version state advances, its `deployment_channel` becomes `development`, an
   `approval_record` audit event is appended, and `updated_at` bumps.
2. **Given** a `staging` version whose `staging_tests_passed` is false, **When** a caller
   attempts `staging → challenger`, **Then** the promotion is rejected (gate not met) with
   the reason `"Staging tests have not passed"` and the state is unchanged.
3. **Given** a `challenger` version with `ground_truth_passed=true` and all required
   approver review flags asserted, **When** the caller promotes `challenger → champion`,
   **Then** the prior champion (if any) is deprecated (its temporal window closes), the
   new version becomes champion with an open-ended validity window, the parent header
   champion pointer repoints, and a `.vtx`/`.vax` package is produced (Story 3).
4. **Given** a champion version, **When** a caller edits its composition (prompts/tools/
   inference/thresholds/schema) in place, **Then** the edit is refused because non-draft
   versions are immutable; the caller must clone-to-draft first.
5. **Given** a draft version a caller opened a moment ago, **When** the caller saves with
   a stale `expected_updated_at` concurrency stamp, **Then** the write is rejected as a
   stale-write conflict and the caller is told to reload.
6. **Given** an entity linked to an `approved`/`in_build`/`live` intake, **When** a caller
   promotes it, **Then** the intake promotion gate passes; **Given** the same entity
   linked to a `high`-risk intake targeting `champion` with no approved `promote_champion`
   approval request, **When** promotion is attempted, **Then** it is blocked with that
   reason.
7. **Given** any caller, **When** they attempt any write without an authorization for the
   corresponding action code, **Then** the request is denied (fail-closed) and no state
   changes.

### User Story 2 — Govern a use case from intake through approval, with full audit (Priority: P2)

A business owner files an intake; AI Governance triages and classifies its EU-AI-Act
risk tier and NAIC materiality; an impact assessment is completed for limited/high-risk
cases; the required-role quorum signs off; on approval the system auto-generates a build
plan and locks a cost envelope and ROI. Every AI invocation thereafter writes an
append-only decision and model-invocation log row, and overrides are recorded per field.

**Why this priority**: This is the governance front-of-funnel and the accountability
substrate. It gates what may be built and records what actually happened — the evidence
every compliance report and audit reconstruction depends on.

**Independent Test**: Create an intake via the API, triage it `high`, complete the impact
assessment, record the 5 required sign-offs, and confirm the intake flips to `approved`,
a plan is generated, and the cost envelope locks; separately, submit a run and confirm a
decision-log row and a model-invocation-log row are ingested and queryable.

**Acceptance Scenarios**:

1. **Given** a new intake, **When** it is created, **Then** its status is `proposed`, a
   `code` slug is derived and made unique within the application, and a `kind=intake`
   approval request opens with `required_roles=[business_owner, ai_governance]`.
2. **Given** a `proposed` intake, **When** AI Governance triages it as `unacceptable`,
   **Then** it is auto-rejected to status `rejected` with the EU-AI-Act prohibited-use
   note and the approval request's required roles are wiped to `[]` (no sign-off
   possible).
3. **Given** a `proposed` intake, **When** it is triaged `high`, **Then** status advances
   to `impact_assessment`, and the open intake approval's required roles are rewritten to
   `[business_owner, compliance, legal, model_risk, ai_governance]`.
4. **Given** a `limited`/`high` intake with no completed impact assessment, **When** a
   caller submits an impact assessment with malformed JSON in a list field, **Then** the
   write is rejected as invalid input with a field-labeled message and the assessment is
   not saved.
5. **Given** an intake approval whose every required role has at least one `approved`
   sign-off and no `rejected`, **When** the last required sign-off lands, **Then** the
   request flips to `approved`, the intake flips to `approved`, and (best-effort,
   non-fatal) plan generation, cost-envelope lock, and ROI lock fire.
6. **Given** a sign-off attempt, **When** the actor's resolved role is not in the
   request's required roles (or is `engineer`/`auditor`/`viewer`), **Then** the sign-off
   is denied fail-closed; the signing role is always derived from the authenticated
   principal, never from request input.
7. **Given** any AI invocation, **When** it executes, **Then** exactly one append-only
   decision-log row is ingested (with the frozen inference snapshot, source-resolution
   and target-write audit, and HITL flags) and one model-invocation-log row (token
   counts, timing), and neither can be mutated or deleted afterward.
8. **Given** a completed decision, **When** a human overrides a single output field,
   **Then** a per-field HITL override is recorded (anchored by `decision_log_id` +
   `output_path` and by the business axis), additively, with the override never mutating
   the decision row.

### User Story 3 — Package, deploy under lifecycle gates, export, and report (Priority: P3)

Champion promotion produces a `.vtx` (task) / `.vax` (agent) package pinned to a
harness-image digest. Deployment is governed and lifecycle-gated and recorded in an
insert-only inventory. Entities round-trip as portable YAML bundles for promotion across
environments. Compliance officers generate metadata-driven reports and pull an
incremental analytics feed.

**Why this priority**: Packaging/deployment, portability, and reporting are what make the
governed asset useful across environments and demonstrable to regulators — valuable, but
they presuppose Stories 1 and 2.

**Independent Test**: Promote a version to champion and confirm a package artifact with a
digest-pinned harness-image compatibility record is produced and an insert-only
deployment inventory row can be created under the gates; export the entity to a YAML
bundle, import it into a fresh store, and confirm the dependency graph reconstructs as
draft; generate a model-inventory report and page the analytics feed by cursor.

**Acceptance Scenarios**:

1. **Given** a version promoted to `champion`, **When** the package is built, **Then** a
   `.vtx`/`.vax` artifact is produced carrying the resolved composition and a
   digest-pinned compatible-harness-image reference, and the build is recorded in the
   insert-only package inventory.
2. **Given** a `staging` package, **When** a caller requests deployment to a `prod`
   target, **Then** it is refused (staging packages deploy to non-prod only); a
   `challenger` package deploys to prod in `shadow` or `ab` run-mode (switchable); a
   `champion` package deploys to any live target; a `deprecated` package is locked
   (but restorable via rollback).
3. **Given** a deployment request whose package harness-image digest does not match the
   target environment's harness-image digest, **When** it is evaluated, **Then** it is
   refused as incompatible and recorded as a rejected deployment attempt.
4. **Given** an entity and its dependency graph, **When** it is exported to a YAML bundle
   and re-imported into a fresh store, **Then** every dependency reconstructs, references
   resolve by name+version (never UUID), `lifecycle_state` is forced to `draft`, and
   existing headers/versions are skipped (idempotent); a dangling reference aborts the
   import with all errors reported at once.
5. **Given** a report definition, **When** a compliance officer generates it for a scope,
   **Then** a `report_run_log` row is recorded (`pending` → `succeeded`/`failed`), the
   requested output formats are produced, and an unknown report code or missing required
   scope parameter fails cleanly.
6. **Given** a customer analytics consumer, **When** it requests a feed view with a keyset
   cursor, **Then** rows are returned in stable `(ingest_ts, source_pk)` order with a
   `next_cursor` and a `complete` flag; a view not on the active allow-list is refused
   before any query runs.
7. **Given** a `high`-tier intake whose applicable canonical requirements demand a
   design-time control, **When** the realized entity is promoted toward a lifecycle state
   without that control's evidence on record, **Then** the promotion is blocked at the
   compliance gate; **and given** a registered, unexpired exception (waived tier, affected
   requirement, named approver, compensating controls, expiry), **When** promotion is
   retried, **Then** it proceeds and the exception is recorded as an append-only audit fact.

### Edge Cases

- **Quota breach:** spend crosses the budget threshold → a `quota_check` records
  `warning`/`breach` and surfaces on incidents. With **soft** enforcement (default) the
  invocation proceeds; with **hard-stop** enforcement the invocation is **refused** at
  execution time (FR-QT-004).
- **Run terminates without a decision row** (e.g. cancelled before claim): the run still
  resolves to a terminal envelope; telemetry/audit-derived fields are simply absent.
- **Concurrent workers** claim the queue: claims are atomic and contention-free so no two
  workers ever claim the same run, and contended runs are skipped without blocking (the v1
  mechanism is `SKIP LOCKED`); in-process (`inproc`) runs are excluded from the worker
  claim cycle.
- **Stuck claim:** a worker dies after claiming; heartbeats stop; a janitor re-releases
  the run after a threshold, making it re-claimable (idempotent).
- **Cancel of an already-terminal run:** treated as an idempotent no-op (uniqueness on the
  terminal row).
- **Champion fast-track:** `candidate → champion` is a legal edge; in v2 it MUST NOT be
  gate-free for production use (see FR-LC-004 — v1 demo-seeding gap closed).
- **Missing model price** for a model-invocation: the invocation is absent from cost
  reports (no covering price window); historical reports stay stable across price changes.
- **`decision_log_detail = none`:** no decision row is written at all (redaction policy);
  audit reconstruction must tolerate this.
- **Mock fixture miss:** a non-empty mock context with no matching key fails hard rather
  than silently calling the live model.

---

## Requirements *(mandatory)*

Functional requirements are grouped by capability area. All MUST statements. Every
operation is gated by the DB-managed action matrix and fails closed
([[user-authentication]]); this cross-cut is stated once in FR-AUTHZ and assumed
throughout.

### Cross-cutting: API boundary & authorization

- **FR-API-001**: `verity-governance` MUST be reachable **only via its API** (ADR-0003,
  [[0003-harness-governance-api]]). Harness, applications, Studio UI, and admin surfaces
  MUST NOT hold or use a governance DB credential; **governance owns all writes** to the
  Tier-1 system-of-record. No caller performs direct DB access.
- **FR-API-002**: The governance API MUST be the single enforcement point for
  authentication, input validation, and audit. Every write MUST be validated server-side
  and recorded with server-resolved actor attribution (never client-supplied).
- **FR-AUTHZ-001**: Every API operation MUST be gated by `is_action_allowed(role, action)`
  over the 21-action matrix carried verbatim from v1, resolved from DB-managed
  platform-role grants ([[user-authentication]]). The action-code vocabulary is
  `create_intake`, `edit_intake`, `triage_intake`, `reclassify_risk`, `edit_requirement`,
  `edit_impact_assessment`, `signoff`, `withdraw_approval`, `generate_plan`, `edit_plan`,
  `realize_plan`, `author_registry`, `promote_registry`, `view`, `export_yaml`,
  `import_yaml`, `view_reports`, `edit_plan_estimate`, `edit_roi_assessment`,
  `lock_envelope`, `delete` (the matrix cells and the 10-member `studio_role` set are
  authoritative in [[user-authentication]]). Unknown role, unknown action, or a route with
  no declared action MUST **deny** (fail-closed). The v1 cookie-persona source is replaced;
  the matrix and fail-closed behavior are unchanged. Beyond the v1 set, v2 adds explicit
  fail-closed action cells for governed deployment (`deploy_nonprod`, `deploy_prod`,
  `promote_champion`, `lock_deprecated`, `cleanup_deprecated`; ADR-0006), role mutation
  ([[user-authentication]]), and **`approve_exception`** (compliance exceptions, FR-RP-009;
  granted to `compliance`/`security`).
- **FR-AUTHZ-002**: Action attribution previously self-asserted via persona
  (`acting_as_role`, `opened_by_role`, signoff role, `locked_role`) MUST be derived from
  the authenticated principal. Sign-off role MUST be derived from the principal and MUST
  NOT be accepted from request input; only `business_owner, compliance, legal, model_risk,
  ai_governance, security, privacy` (the 7 `approval_role` members) may sign off.
- **FR-AUTHZ-003**: App-scoped operations MUST evaluate `app_team_role` grants against the
  `application_id` **derived server-side from the target resource**, never a client-
  supplied field ([[user-authentication]] FR-010).

### Capability area: Intake & AI-risk classification

- **FR-IN-001**: The system MUST create an intake in status `proposed`, resolving the
  owning application (by `application_code` or `application_id`; reject if neither resolves
  or the application is unregistered), deriving a unique `code` slug from the title within
  the application when not supplied. The intake `(application, code)` pair MUST be unique.
  **Revised 2026-06-05 (Slice 4):** the intake approval is **not** opened on create with a fixed
  `[business_owner, ai_governance]` set; per the clarified model it is opened on an explicit
  **submit** (`POST /intakes/{id}/submit`, requires a computed tier) with the **tier-based quorum**
  (FR-IN-005). The original on-create fixed-quorum wording is superseded.
- **FR-IN-002**: The system MUST expose intake retrieval by natural key `(application_code,
  code)` and by id, and listing with optional filters (status, `ai_risk_tier`,
  business-owner email, application). A missing intake MUST surface as not-found.
- **FR-IN-003**: The system MUST allow updating a defined set of mutable intake fields
  (title, problem statement, expected benefit, in/out-of-scope decisions, owner name/email,
  requesting team, notes, HITL strategy/threshold, affected populations), leaving omitted
  fields unchanged.
- **FR-IN-004**: Triage MUST set `ai_risk_tier` (`minimal` | `limited` | `high` |
  `unacceptable`), `naic_materiality` (`material` | `non_material`), and the risk
  classification rationale, and MUST advance status: `proposed → in_review`, and
  `in_review → impact_assessment` when the tier is `limited` or `high`. Status only moves
  forward. An `unacceptable` tier MUST auto-reject the intake to `rejected` with the note
  `"Auto-rejected: AI risk tier 'unacceptable' under EU AI Act framing — prohibited use
  case."`. **Clarified 2026-06-04:** the tier/materiality/rationale are produced by the intake
  assessment (FR-AS-002, the **inherent** tier — FR-AS-008); triage records them and advances
  intake status. `in_build`/`live` are not intake states (FR-IN-011/FR-IN-012).
- **FR-IN-005**: On triage, the system MUST rewrite each open intake approval's
  `required_roles` to the tier-specific set: `high → [business_owner, compliance, legal,
  model_risk, ai_governance]`; `limited → [business_owner, compliance, ai_governance]`;
  `minimal → [business_owner]`; `unacceptable → []`. These sets are carried verbatim from
  v1 `REQUIRED_ROLES_BY_RISK_TIER`.
- **FR-IN-006**: NAIC materiality MUST be recorded as an orthogonal classification (no
  automated gate) for compliance reporting; it MUST NOT be conflated with the agent-level
  `materiality_tier` (`high`|`medium`|`low`) nor the plan-row `proposed_materiality_tier`.
  **Clarified 2026-06-04:** the **intake** additionally carries its **own** `materiality_tier`,
  intentionally distinct from the agent/plan-row one — an intake-level classification that stays
  on intake classification.
- **FR-IN-007**: The system MUST support requirements on an intake: add, list, and update,
  each carrying `kind` (`business` | `functional` | `non_functional` | `compliance`),
  `status` (`draft` | `approved` | `implemented` | `verified` | `deprecated`), statement,
  acceptance criteria, source, and an optional parent. Requirement `code` MUST be unique
  within the intake.
- **FR-IN-008**: The system MUST support a **semantic redundancy check**: given candidate
  requirement text, return the top-N most-similar existing requirements above a similarity
  threshold (default top-5, min similarity 0.78). Embedding/compute failures MUST be
  non-fatal and return an empty result.
- **FR-IN-009**: The system MUST support linking registry entities (`agent` | `task` |
  `prompt` | `tool` | `test_suite` | `ground_truth_dataset`) to an intake and optionally a
  requirement, with a relationship (`implements` default | `tests` | `monitors` |
  `informs`); list and delete links; and reverse-lookup intakes for an entity (consumed by
  the promotion gate). A link edge MUST be unique on `(intake, requirement, entity_type,
  entity_id, relationship)`. **Clarified 2026-06-04 (promotion gate):** linking is at the
  **asset** level (not asset-version); an asset MAY link to at most one intake, only while
  `draft`/`candidate` and not already linked. Moving an asset **beyond `candidate`** (→
  `champion`) MUST require a link to an **approved** intake; `draft` is exempt (POC). The intake
  page MUST roll up each linked asset's most-advanced stage and flag lower-stage versions.
- **FR-IN-010**: The system MUST expose a governance dashboard aggregation: intake counts
  by status, counts by risk tier, pending approvals, and unlinked-entity counts.
- **FR-IN-011**: The intake lifecycle stepper MUST be a computed read over the flow
  `[proposed, in_review, impact_assessment, approved, in_build, live]` exposing per-step
  status (`complete`|`active`|`pending`|`skipped`|`failed`); `minimal`-tier intakes show
  `impact_assessment` as `skipped`; `rejected`/`retired` are terminal badges, not rail
  stops. **Revised 2026-06-04:** the intake's **own** status set is `{proposed, in_review,
  impact_assessment, approved, rejected, retired}`; the `in_build` and `live` steps are
  **derived from the stages of linked assets** (FR-IN-009), not intake attributes — the stepper
  rolls up the most-advanced linked-asset stage.
- **FR-IN-012**: The system MUST support intake status transitions `approve_intake`
  (`in_review`/`impact_assessment` → `approved`), `mark_intake_in_build` (`approved` →
  `in_build`), `mark_intake_live` (`approved`/`in_build` → `live`), and `retire_intake`
  (any → `retired`). **Revised 2026-06-04:** intake status transitions are `approve_intake`
  (→ `approved`) and `retire_intake` (any → `retired`); the former `mark_intake_in_build` /
  `mark_intake_live` are **not intake transitions** — `in_build`/`live` are properties of linked
  assets (FR-IN-009), surfaced on the intake by roll-up.
- **FR-IN-013**: The system MUST support **risk reclassification** of an already-triaged
  intake, authorized by the `reclassify_risk` action code: re-running triage rewrites the
  tier/materiality/rationale and the open intake approval's `required_roles` (FR-IN-005),
  and opens a `kind=risk_reclassification` approval request that blocks promotion until
  resolved (FR-AP-005). **Clarified 2026-06-04:** risk reclassification and **business-proposed
  changes** are modeled as **change proposals** — an `approval_request` (kind
  `risk_reclassification` or `business_change`) scoped to the intake that selects **impacted
  assets**; on approval each impacted asset gets a **new `draft` forked from its champion** (or
  most-advanced stage). Change proposals are an **extension of intake** (reuse `approval_request`
  + intake↔asset links), not a separate surface.
- **FR-IN-014**: On triage/risk-classification (and on reclassification, FR-IN-013), the
  system MUST resolve the **applicable canonical requirements** for the intake from its
  **governance domains** and risk/materiality tier, producing the **obligation set** — the
  controls (per lifecycle phase) and evidence specifications the realized entity MUST
  satisfy through its lifecycle ([[0008-compliance-control-evidence-model]]). The obligation
  set MUST be recorded against the intake and carried onto its realized entities, so that
  design-/deploy-/static-/execution-time controls (FR-RP-007) enforce it and evidence
  (FR-RP-008) accrues. This is what makes the product implement controls and capture
  evidence **starting from intake**.
- **FR-IN-015** *(v2-new — clarified 2026-06-04)*: The system MUST support **application
  onboarding** as a **governed proposal** (not an instant create) via the `onboard_application`
  action (a documented v2 addition to the FR-AUTHZ-001 matrix). **Identity:** `name` (unique,
  non-blank), a 3-letter **`code`** — the TLA, `^[A-Z]{3}$`, unique, **immutable after approval**,
  the audit-correlation key used in run IDs / breadcrumbs / the Application-Scope filter — a
  `description` (intended purpose, EU-AI-Act Art. 11 baseline), and optional `line_of_business`
  (a `reference.line_of_business` value with an "Other" escape). **Ownership:** a **designated
  business owner** (required; resolves to an actor) and an optional **initial app-team** (rows of
  person + `reference.app_team_role`), recorded as grants in `core.actor_app_role_grant`; the
  proposer is server-resolved (D6), never client-supplied. **Approval:** any platform author
  (`engineer` | `ai_governance` | `business_owner`) MAY propose; approval (an `approval_request`
  of kind **`application_onboarding`**) MUST require **AI Governance**, **plus the named business
  owner when they were not the proposer** (the business owner MUST be proposer or approver).
  **Lifecycle:** onboarding creates the application **`pending`**; approval transitions it to
  **`active`** and writes the owner's `app_owner` grant; status is `{pending, active, suspended,
  retired}`; a non-`active` application MUST NOT own promotable intakes/assets. An **Application
  Onboarding** UI surface is provided (potentially the application's first screen). The
  application's **compliance perimeter** is captured per FR-IN-017 and inherited by intakes per
  FR-IN-018.
- **FR-IN-016** *(v2-new — clarified 2026-06-04)*: Beyond onboarding, the application is managed
  via a multi-tab **application screen** (Overview · Environments · Harnesses · Inventory). The
  **Environments** tab lets the application owner **define** environments (definitions only —
  **no approval gate**). **Harness provisioning happens elsewhere** (infra / harness — ADR-0010);
  a **harness is tied to an environment**, and once bound the **standard environment/deployment
  governance rules apply** (governed deployment — Principle VII / ADR-0006; the concrete rules —
  allowed run modes, environment-kind gating, lifecycle state requirements — are specified in the
  deployment/harness slice and its ADR, not here). The **Harnesses** and **Inventory** tabs are
  read/maintenance references to those separately-governed concerns; their detail is out of scope
  for the onboarding screen.
- **FR-IN-017** *(v2-new — clarified 2026-06-04)*: Onboarding MUST capture the application's
  **compliance perimeter** (app-wide), which downstream intakes inherit (FR-IN-018): (a) a
  **data-classification ceiling** — `reference.data_classification` (`public` | `internal` |
  `confidential` | `pii_restricted`) — the maximum sensitivity any intake under the app may
  declare; (b) **regulatory frameworks in scope** — **at least one** `core.regulatory_framework`
  (an explicit `internal_only` / `nist_ai_rmf` sentinel where no external regime applies — never
  blank); (c) **governance domains in scope** — **at least one** `reference.governance_domain`
  (the 9: `model_risk`, `fairness`, `privacy`, `security`, `transparency`, `robustness`,
  `data_governance`, `human_oversight`, `accountability`); (d) **jurisdictions of operation** —
  **at least one** `reference.jurisdiction` (a controlled list; an "Other" free-text is a
  non-driving annotation only); and (e) three **explicit Yes/No attestations** (no silent
  default) — `affects_consumers`, `processes_pii`, `consumer_facing`. A **justification** is
  recorded as the approval rationale.
- **FR-IN-018** *(v2-new — clarified 2026-06-04)*: The application perimeter (FR-IN-017) is the
  boundary intakes **inherit and refine** per use-case — per-intake risk fields
  (`ai_risk_tier` / `naic_materiality`) stay **off** the onboarding screen. The selected
  **regulatory frameworks** bound the candidate `regulatory_provision`s that become per-intake
  obligations (FR-IN-014); the **governance domains** scope the app's `domain_maturity`; the
  **data classification** is a **ceiling** — an intake's actual classification MUST NOT exceed
  it, and `processes_pii = yes` implies a ceiling ≥ `confidential`. The compliance perimeter is
  **editable only via re-approval** (a change proposal — FR-IN-013); the application **`code`
  (TLA) is immutable** once approved.

### Capability area: Intake assessment, obligation elicitation & risk treatment *(v2-new — clarified 2026-06-04)*

The intake assessment is the structured front-end that drives risk classification and the
obligation set and produces the approval justification. It **extends** the history-keeping
`intake_impact_assessment` entity, MUST be completed before an intake is approved, and **is** the
`impact_assessment` gate for `limited`/`high` tiers (FR-IN-004).

- **FR-AS-001**: The system MUST present the assessment as four tabs — **AI Decision Impact**,
  **Data**, **Security & Access** (inputs), and a computed read-only **Risk & Obligations**
  summary. Each input answer MUST map to zero or more `canonical_requirement` codes so that
  completing the assessment **resolves the intake's obligation set** (FR-IN-014).
- **FR-AS-002**: The **AI Decision Impact** tab MUST capture at least: the AI's decision role
  (assists | recommends-with-sign-off | autonomous), decision domain, affected population,
  worst-case adverse impact, human-oversight (HITL) strategy + threshold, reversibility,
  GDPR-Art.22 automated-decision applicability, and deployment scale. These MUST drive the
  computed **inherent EU-AI-Act risk tier** and NAIC materiality, with a recorded rationale.
- **FR-AS-003**: The **Data** tab MUST capture: data description; data sources (a list; later a
  data-catalog reference); data classification; **PII presence** (none | direct | indirect |
  special-category); sensitive-insurance-data categories; lawful basis / consent; residency /
  cross-border transfer; retention & lineage; and training/inference use. Special-category PII
  MUST raise the risk signal and trigger the privacy obligations (DPIA, minimization, retention).
- **FR-AS-004**: The **Security & Access** tab MUST enumerate, as discrete approvable items, the
  **sources** the asset reads, the **targets** it writes/acts on, and the **tools** it invokes
  (each with scope / classification / egress), plus credential handling and network egress. On
  intake approval each item MUST be recorded as **governance-approved**.
- **FR-AS-005**: The approved access items MUST be exportable as an **Access Approval Record**
  (justification + governance decision) for submission to an external **ITSM/IAM** system. Verity
  records and approves the access **intent**; it MUST NOT be assumed to provision IAM/ITSM grants
  directly.
- **FR-AS-006**: Any risk-flagged answer MUST support one or more **mitigation / risk-treatment**
  records, each carrying: procedure (text); treatment type (avoid | reduce | transfer | accept);
  the addressed control / `canonical_requirement` (or "compensating"); owner; status (planned |
  in-place | verified); and **residual risk**.
- **FR-AS-007**: A mitigation that satisfies a required control MUST be capturable as **evidence**
  toward the obligation set ([[0008-compliance-control-evidence-model]]). An `accept` of an unmet
  **required** control MUST route to a compliance exception via `approve_exception` (FR-RP-009),
  not silently pass.
- **FR-AS-008**: The system MUST record both the **inherent tier** (fixed by the use case; NOT
  downgraded by mitigations) and the **residual risk** (after mitigations) per risk item. Risk
  classification (FR-IN-004) MUST use the inherent tier.
- **FR-AS-009**: The **Risk & Obligations** tab MUST present (read-only): the computed tier + NAIC
  materiality + rationale; the resolved obligation set (each triggered `canonical_requirement`
  with its source answer); the required approver quorum (FR-IN-005); and any outstanding
  justifications blocking approval.
- **FR-AS-010**: The assessment MUST support **progressive disclosure** (follow-up questions
  appear only when triggered) and MUST keep full revision history (extending
  `intake_impact_assessment`). The intake MUST NOT be approvable while required justifications
  are outstanding.

### Capability area: Registry & composition

- **FR-RG-001**: The system MUST register governed entities and return their identity:
  agents, tasks, prompts (header + versions); inference configs, tools, data connectors,
  MCP servers (single-row, unversioned); and applications. Inference-config and entity
  names MUST be unique as defined; re-registering an identical version triple MUST be
  rejected as a duplicate. Registering a prompt version MUST auto-derive its
  `template_variables` from `{{variable}}` references in the prompt content when not
  explicitly supplied (deduplicated, first-occurrence order preserved).
- **FR-RG-002**: The I/O binding grammar MUST be **Source Binding** (declarative inputs)
  and **Target Binding** (declarative outputs), renamed from v1 `source_binding` /
  `write_target` per [[binding-grammar]] and ADR-0005. Bindings MUST apply **uniformly to
  tasks and agents**; **tools and MCP servers are agent-only**. The legacy per-task-only
  `task_version_source`/`task_version_target` tables MUST NOT be carried forward as a
  separate grammar.
- **FR-RG-003**: A Source Binding MUST carry a `template_var`, a `reference` (the wiring
  DSL string), a `binding_kind` (`text` default | `content_blocks`), a `required` flag, and
  an execution order, unique per `(owner, template_var)`. `content_blocks` bindings MUST be
  the exclusive path for multimodal content. The wiring DSL MUST support exactly
  `input.<path>`, `output.<path>` (targets only), `const:<literal>`, and
  `fetch:<connector>/<method>(input.<field>)` (sources only); paths are dotted keys with
  bracketed integer indices, with no JSONPath, arithmetic, or conditionals.
- **FR-RG-004**: A Target Binding MUST carry a logical name, a connector, a write method, an
  optional static container hint, a `required` flag, an execution order (unique per
  `(owner, name)`), and one or more payload fields (each a `payload_field` + a DSL
  `reference` restricted to `input.*` / `output.*` / `const:*` — `fetch:*` not valid on
  target payloads, unique per `(target, payload_field)`).
- **FR-RG-005**: The system MUST support composition attachments on versioned entities:
  prompt assignments (with `api_role` (`system` default | `user` | `assistant_prefill`),
  `governance_tier` (`behavioural` default | `contextual` | `formatting`), execution order,
  required flag, optional condition logic; unique per `(entity_type, entity_version,
  prompt_version, api_role)`); tool authorizations (agent and task; unique per `(version,
  tool)`); and agent-to-agent delegations.
- **FR-RG-006**: Agent-to-agent delegation MUST specify **exactly one** of a champion-
  tracking `child_agent_name` or a version-pinned `child_agent_version_id` (else rejected),
  with an optional scope, an `authorized` flag, and rationale. The runtime delegation gate
  MUST resolve the effective child version (the pinned version, else the named agent's
  current champion) and return only authorized targets. Holding the `delegate_to_agent`
  capability and authorizing a specific child are two independent gates.
- **FR-RG-007**: Composition association sets MUST be replaceable only on **draft**
  versions, transactionally (delete-all + batch-insert; partial failure rolls back the
  whole set); attempting to replace associations on a non-draft version MUST be rejected
  because promoted-version composition is immutable.
- **FR-RG-008**: The system MUST support **clone-into-new-draft**: copy a source version's
  fields and every association into a new draft version (state forced to `draft`, channel
  `development`, recording `cloned_from_version_id` provenance), transactionally. A missing
  source or a malformed version label MUST be rejected.
- **FR-RG-009**: In-place edits MUST be supported for **unversioned** tools and inference
  configs (taking effect for every authorizing version on next run) and for **draft**
  versioned entities, each guarded by an optimistic-concurrency stamp; a stale or non-draft
  target MUST be rejected as a conflict. Deleting a draft version MUST cascade its
  associations; deleting a draft prompt still referenced by an assignment MUST be rejected.
- **FR-RG-010**: The system MUST resolve a runtime-ready config for an entity by name with
  a fixed priority: explicit `version_id` (direct) > `effective_date` (temporal/SCD-2) >
  default (current champion). Resolution MUST assemble the inference config, ordered prompt
  assignments, and authorized tools; an unknown or championless entity MUST be rejected.
  Every resolved config MUST expose a frozen inference snapshot stored on each decision-log
  row for replay.
- **FR-RG-011**: The system MUST support retrieval/listing of headers, versions (ordered by
  version components), and single-row entities (filtering inactive where defined), and a
  **where-used reverse lookup** (`get_entity_consumers`) over FK-based edges (prompt
  assignments, tool junctions, inference-config, connector edges) to power safe-edit
  guarantees. The reverse lookup's known coverage gap for Source-Binding `fetch:` connector
  references MUST be closed in v2 (see disposition).
- **FR-RG-012**: The system MUST maintain a model price catalog as SCD-2 windows (at most
  one active price per model, DB-enforced) and compute invocation cost point-in-time by
  joining each invocation to the price window containing its start time; price edits MUST
  NOT alter historical cost.
- **FR-RG-013**: Tools MUST carry a `data_classification_max` from the `data_classification`
  vocabulary — `tier1_public` | `tier2_internal` | `tier3_confidential` (default) |
  `tier4_pii_restricted` — plus an `is_write_operation` flag and a `requires_confirmation`
  flag, surfaced on each `ToolAuthorization`. Classification ceiling and write-operation
  gating MUST be enforced before any tool dispatch, including for MCP-routed tool calls.
- **FR-RG-014**: An execution context MUST be registerable/upsertable keyed on
  `(application_id, context_ref)`, carrying an opaque `context_ref`, a `context_type`, and
  free-form `metadata`. Verity MUST store **no business keys**: domain identity flows only
  through the resulting `execution_context_id`.

### Capability area: Entity/version model (SCD-2)

- **FR-VM-001**: Governed entities MUST follow a header + immutable-version model for
  agents, tasks, and prompts; inference configs, tools, data connectors, and MCP servers
  MUST be single-row and unversioned. Agents and tasks MUST carry a champion pointer on the
  header; prompts MUST resolve champion purely by version state (no header pointer in v1 —
  see disposition for v2 normalization).
- **FR-VM-002**: Versions MUST carry `major.minor.patch` components with a derived,
  read-only `version_label`, unique per entity; an agent/task version MUST carry a caller-
  facing `input_schema` (rejected as empty when promoting out of draft) and the lifecycle
  gate flags `staging_tests_passed`, `ground_truth_passed`, `fairness_passed`, plus agent
  challenger shadow-mode / A-B completion flags and traffic-percentage fields.
- **FR-VM-003**: SCD-2 temporal windows MUST apply to agent/task/prompt versions: pre-
  champion states leave `valid_from`/`valid_to` NULL (not date-resolvable); promotion to
  champion opens `valid_from = now`, `valid_to = open-ended sentinel`; deprecation closes
  `valid_to = now`. A temporal resolution query MUST reconstruct the champion at a given
  effective date.
- **FR-VM-004**: The promotion/deprecation sequence MUST maintain a contiguous, non-
  overlapping champion timeline per entity (the prior champion's window closes as the new
  one opens). The v1 race where this is not transactionally guarded MUST be closed in v2
  (champion-set MUST be atomic; see disposition).
- **FR-VM-005**: Promoted-version composition (prompts, inference, tools, thresholds,
  schema) MUST be immutable; changes require a new version. v2 MUST enforce this at the
  governance API/data layer, not application-level only (see disposition).

### Capability area: 6-state lifecycle & promotion

- **FR-LC-001**: The lifecycle has **6 states**: `draft`, `candidate`, `staging`,
  `challenger`, `champion`, `deprecated`. (v1's `shadow` is CHANGED to a **challenger
  run-mode**, not a state — a challenger deploys in `shadow` or `ab` mode, switchable; see
  packaging/deployment.) Legal transition graph: `draft → {candidate}`; `candidate →
  {staging, champion, deprecated}`; `staging → {challenger, deprecated}`; `challenger →
  {champion, deprecated}`; `champion → {deprecated}`; `deprecated → {champion, challenger}`
  (**rollback** — `deprecated` is restorable, not terminal). An illegal transition MUST be
  rejected with the legal target set.
- **FR-LC-002**: Each state MUST map to a deployment channel: `draft`/`candidate` →
  `development`, `staging` → `staging`, `challenger` → `evaluation`, `champion` →
  `production`, `deprecated` → `production` (inherited). (The v1 `shadow` channel is
  retired — shadow is a challenger run-mode.) The channel MUST be set on every promotion.
- **FR-LC-003**: Promotion gates MUST combine stored version facts with approver review-
  flag assertions: `→ challenger` requires `staging_tests_passed` and
  `staging_results_reviewed`; `challenger → champion` requires `shadow_evaluation_reviewed`
  (when the challenger was run in `shadow` mode), `ground_truth_passed`,
  `ground_truth_reviewed`, `model_card_reviewed`, and `challenger_metrics_reviewed`. A
  failed gate MUST be rejected with the human-readable issue list; the gate must also be
  previewable read-only (to enable/disable UI controls).
- **FR-LC-004**: The `candidate → champion` fast-track MUST NOT be gate-free in v2. v1
  allowed it for demo seeding with no gate; in v2 **any non-seed promotion to champion** —
  by fast-track or via `challenger → champion` — MUST satisfy the **full champion evidence
  set**: staging tests passed; `ground_truth_passed`, `ground_truth_reviewed`,
  `model_card_reviewed`, `challenger_metrics_reviewed`; the risk-tier approval quorum and
  server-authoritative champion confirmation (FR-LC-003/005, FR-AP-005); impact assessment
  complete for `limited`/`high` intakes; all linked `functional`/`compliance` requirements
  satisfied; **and** captured evidence for every **design-time and static/model control**
  required at the asset's tier (FR-RP-007/008/011). Deploy-time and execution controls
  enforce at their own phases. A seed-only bootstrap path MAY bypass gates but MUST be
  flagged as seed and is non-production.
- **FR-LC-005**: Champion-targeted promotion MUST require an explicit, server-authoritative
  champion-confirmation step (deliberate acknowledgement; the v1 Studio name-typeback is
  one such mechanism) recorded as a dedicated audit fact, never inferred from free text.
  Unlike v1 — where the JSON API could promote to champion without this — v2 MUST enforce
  champion confirmation on **every** champion promotion across **all** surfaces.
- **FR-LC-006**: Promotion MUST also evaluate the intake promotion gate (FR-AP-005) and
  MUST reject promotion the gate blocks. Each successful promotion MUST append an
  attestation audit record capturing the transition, actor, rationale, and all review
  flags. Promotion MUST be authorized per the action matrix (`promote_registry`).
- **FR-LC-007**: Rollback MUST be supported on a `champion` version (agents and tasks),
  deprecating it and appending a `rollback` attestation. v1 rollback only deprecated the
  current champion (it did **not** restore the prior champion despite its docstring); v2
  MUST restore the immediately-prior champion in the same atomic transaction (reopening its
  temporal window and repointing the header), and MUST reject rollback when no prior
  champion exists (see disposition).

### Capability area: Approvals & sign-off

- **FR-AP-001**: The system MUST maintain **two distinct approval surfaces**: (a) the
  single-approver **promotion attestation** record per lifecycle transition (free-text
  gate type, review flags, champion-confirmation fact; no quorum); and (b) the multi-role
  **intake approval request** with `approval_signoff` quorum. The only coupling between
  them MUST be the intake promotion gate.
- **FR-AP-002**: An approval request MUST carry a `kind` (`intake` | `risk_reclassification`
  | `promote_candidate` | `promote_champion` | `retire`), a status (`pending` default |
  `approved` | `rejected` | `withdrawn`), a per-request `required_roles` set, and optional
  target entity reference (populated for promote kinds). The system MUST support opening
  requests, **withdrawing** an open request (`withdraw_approval` action; status →
  `withdrawn`; roles `business_owner`/`compliance`/`legal`/`model_risk`/`ai_governance`),
  listing them per intake, and reading a request with its sign-offs.
- **FR-AP-003**: A sign-off MUST record a role (`approval_role`), approver identity, a
  decision (`approved` | `rejected` | `requested_changes` | `abstained`), and optional
  comment/evidence; one identity MUST NOT sign the same role twice on the same request.
- **FR-AP-004**: Request status roll-up MUST be: any `rejected` sign-off → request
  `rejected`; every required role has ≥1 `approved` and none `rejected` → request
  `approved`; empty required roles → stays `pending`; otherwise `pending`.
  `requested_changes` and `abstained` neither satisfy a role nor reject. When a
  `kind=intake` request flips to `approved`, the intake MUST flip to `approved`, and (best-
  effort, non-fatal, post-commit) plan generation, cost-envelope lock, and ROI lock MUST
  fire, crediting the signing role.
- **FR-AP-005**: The intake promotion gate MUST block promotion when, for any linked
  intake: the intake status is not in `(approved, in_build, live)`; or there is any open
  `intake`/`risk_reclassification` approval; or `target_state = champion` and the intake is
  `high`-risk and there is no `approved` `promote_champion` request for that entity; or any
  linked `functional`/`compliance` requirement is not in `(approved, implemented,
  verified)`. Unlinked entities MUST pass (backward compatibility). Block reasons MUST be
  surfaced verbatim.

### Capability area: Decision & model-invocation logging

- **FR-DL-001**: Exactly one **append-only** decision-log row MUST be ingested per AI
  invocation (agent, task, or tool — the entity-type domain for decision rows is
  `agent`/`task`/`tool`), capturing the frozen inference snapshot, channel, mock mode,
  correlation ids (`workflow_run_id`, `execution_run_id`, `parent_decision_id`,
  `decision_depth`, `execution_context_id`), input/output summaries and payloads,
  reasoning, risk factors, confidence, model/token/duration metrics, tool calls, message
  history, Source-Binding resolutions, Target-Binding writes, HITL flags, status
  (`complete`/`error`), redaction record, an audit-rerun lineage pointer
  (`reproduced_from_decision_id`), and run purpose (`production` | `test` | `validation` |
  `audit_rerun`). The caller MAY pre-supply the row id to thread sub-agent hierarchies.
  Each Source-Binding resolution audit entry MUST carry a status from `resolved` |
  `skipped_no_ref` | `failed` plus a `mocked` flag; each Target-Binding write audit entry
  MUST carry a status from `wrote` | `logged` (both counting as fired; failed/skipped
  writes are excluded). The envelope's `sources_resolved` / `targets_fired` counts MUST
  derive from these.
- **FR-DL-002**: Decision rows MUST be immutable: no update or delete path exists.
  Corrections flow exclusively through additive per-field HITL overrides; the decision-
  level override log is retired.
- **FR-DL-003**: Decision-log **ingest MUST be via the API on an async/batched path**
  (ADR-0003/0004); callers MUST NOT write the log directly. The decision log is the Tier-1
  system-of-record thin row; bulk/historical analytics MUST live in a separate, latency-
  tolerant, **customer-portable** tier (open Iceberg/Parquet) per ADR-0004/0007.
- **FR-DL-004**: The system MUST support decision reads: get by id (detail), list with
  filters (status, entity type, log-detail, application, entity-name substring, created-at
  window) with count, recent list, and audit trail by `execution_context_id` and by
  `workflow_run_id` (ordered by depth then time, reconstructing the parent/child chain).
- **FR-DL-005**: `decision_log_detail` (`full` | `standard` default | `summary` |
  `metadata` | `none`) MUST govern logging verbosity and recorded redaction; `none` MUST
  write no decision row, and audit reconstruction MUST tolerate its absence.
- **FR-DL-006**: One **append-only** model-invocation-log row MUST be ingested per decision
  (token counts incl. cache tokens, turn count, model identity, timing, stop reason, status
  (`complete` | `failed`)), referencing a catalog model and cascading on decision deletion.
  The model catalog MUST carry a `status` (`active` | `deprecated` | `beta`) and a
  `modality` (`chat` | `embedding` | `vision`); deprecated models MUST still resolve for
  historical cost (joined by id, not by status). Cost MUST be computed point-in-time via the
  price-window join (FR-RG-012); a missing covering price window MUST exclude the invocation
  from cost reports (no fabricated cost).
- **FR-DL-007**: Per-field HITL overrides MUST be recorded append-only, anchored by both
  the technical axis (`decision_log_id` + `output_path`) and a business axis
  (`application`, `entity_type`, `entity_reference`, `fact_type`), carrying the AI value,
  an `ai_found` flag, the human value, actor, and reason. Overrides MUST never mutate the
  decision row and MUST be queryable by either axis.
- **FR-DL-008**: A **canonical execution envelope** MUST be the single read-derived return
  shape for any terminal run (`envelope_version = "1.0"`), with status `success`/`failure`
  (no `partial`), mutually exclusive output/error, telemetry, and provenance. Building an
  envelope for a non-terminal run MUST be rejected.

### Capability area: Run / execution state

- **FR-RN-001**: Run state MUST be **event-sourced across insert-only tables** (submission
  row, status ledger, terminal completion row, terminal error row) with a resolved
  combined-state view. Callers MUST NOT join the underlying tables; reads go through the
  resolved view or a full event-sequence query.
- **FR-RN-002**: Run submission MUST accept an entity kind (`task` | `agent`) + name,
  input (validated server-side against the unit's `input_schema`), channel, optional
  correlation ids, application, submitter, mock mode, write mode (`auto` | `log_only` |
  `write`), and (agents only) output-schema enforcement; it MUST return synchronously
  `{run_id, status: "submitted", submitted_at}`; execution is asynchronous.
- **FR-RN-003**: The resolved current status MUST be one of `submitted`, `claimed`,
  `heartbeat`, `released`, `complete`, `cancelled`, `failed`, with terminal rows
  (completion/error) overriding the latest status event. The terminal set is `(complete,
  cancelled, failed)`.
- **FR-RN-004**: Worker claim MUST be atomic and contention-free: claim the oldest
  available run (`submitted`/`released`, no terminal row, not `inproc`) under `SKIP
  LOCKED`, inserting a `claimed` event in the same transaction; concurrent workers MUST
  never claim the same run. Heartbeat and release events MUST be supported; a janitor MUST
  re-release stuck claims past a threshold (idempotently).
- **FR-RN-005**: Cancel MUST insert a terminal `cancelled` completion row; cancelling an
  already-terminal run MUST be an idempotent no-op (terminal-row uniqueness).
- **FR-RN-006**: The system MUST support run reads: get by id, filtered list with count
  (exact `entity_name` vs case-insensitive substring; inclusive-lower/exclusive-upper
  submission window), full lifecycle timeline, runs for a workflow, runs for an execution
  context, and the terminal-only result envelope (returning none for an in-flight run).
- **FR-RN-007**: Write-mode and channel MUST jointly gate Target-Binding writes:
  validation/test runs never write (the intended write is recorded in the decision log
  instead); `auto` writes only on the production channel; `log_only` forces a dry run;
  `write` forces a write subject to authority.

### Capability area: Quotas

- **FR-QT-001**: A quota MUST pair a scope (`application` | `agent` | `task` | `model`)
  with a period (`daily` | `weekly` | `monthly`) and a USD budget, plus an alert threshold
  percent (default 80), an `enabled` flag, an accepted-but-not-yet-enforced `hard_stop`
  flag, and notes. The system MUST support quota create, list, get, update, and delete.
  (v1 narrative docs list a `scope = entity` value and a `metric` axis; the shipped v1 code
  uses `application | agent | task | model` with a USD-only budget — the code surface is
  authoritative here.)
- **FR-QT-002**: A quota check MUST compute period-scoped spend (UTC period windows: daily
  from 00:00, weekly from ISO-Monday, monthly from day 1) from the same cost view used by
  usage reporting, compare to budget, and record a `quota_check` outcome row with integer
  `spend_pct` and an alert level: `breach` (≥100%), `warning` (≥ threshold), or none.
  Budget ≤ 0 MUST yield `spend_pct = 0` and never fire.
- **FR-QT-003**: A batch check MUST iterate all quotas, skip disabled ones, isolate per-
  quota failures (one failure MUST NOT abort the batch), and auto-resolve a prior active
  breach when a quota comes back clear (decrementing the active-breach count). The system
  MUST surface check history, latest-check-per-quota, and active-breach count (most-recent
  check per quota with an unresolved fired alert).
- **FR-QT-004**: Quota enforcement MUST be **per-quota configurable** via an enforcement
  mode: **soft by default** (record `warning`/`breach`, never refuse the invocation), with
  an optional **hard-stop** (`hard_stop=true`) that **refuses** the invocation as an
  execution-phase control when the budget is exceeded. Soft remains the default to preserve
  v1 behavior; the `hard_stop` flag (stored but inert in v1) becomes enforceable in v2.
  Quota guidance for a realized entity MUST be derivable by reverse-looking-up its plan-row
  link to the parent intake's locked envelope.

### Capability area: Plan generation

- **FR-PL-001**: On intake approval (and on demand for authorized roles), the system MUST
  generate a build plan deterministically (rule-based; no model call) from the intake's
  `functional` requirements, producing `intake_artifact_plan` rows flagged
  `auto_generated`, returning the created rows. An `unacceptable` intake MUST generate
  nothing. A missing intake MUST be rejected; an unmatched requirement MUST be skipped (not
  an error).
- **FR-PL-002**: The generator MUST map requirement text to a proposed entity kind and
  capability type via an ordered, first-match keyword ruleset, deriving a stable artifact
  name and a `proposed_materiality_tier` from the intake tier (`high → high`, `limited →
  medium`, `minimal → low`). For a `high`-risk intake it MUST additionally always propose a
  ground-truth dataset and a test suite.
- **FR-PL-003**: A plan row MUST carry the proposed kind, name (unique per `(intake,
  kind, name)`), display name, description/purpose, inputs/outputs, capability type (tasks
  only; `classification` | `extraction` | `generation` | `summarisation` | `matching` |
  `validation`), materiality tier, status (`proposed` | `in_progress` | `realized` |
  `cancelled`),
  and an optional realized-entity pointer. The system MUST support plan add/list/update/
  delete; deleting a `realized` plan row MUST be refused (deprecate the realized entity
  instead).
- **FR-PL-004**: Realizing a plan row MUST set its realized-entity pointer, flip status to
  `realized`, and idempotently map the realized entity to its owning application; duplicate
  mappings MUST be non-fatal.
- **FR-PL-005**: The system MUST support plan **estimate scenarios** (at most one active per
  plan row), each carrying author-supplied assumptions (model, token sizes, invocations/
  year, peak multiplier, tool-call count, input-file expectations, purpose/seasonality
  text). The system MUST compute per-invocation and yearly cost as
  `((in_tok×in_price + out_tok×out_price)/1e6) × (1 + 0.02×tool_calls) × invocations/year`,
  loading the model's current-window price; missing inputs or no active price MUST null the
  derived columns with a recorded reason and MUST block envelope lock.
- **FR-PL-006**: A scenario manual override MUST require override-USD and explanation
  together (both set or both clear); a partial override MUST be rejected. The effective
  per-row yearly cost is the override if set, else the computed estimate.
- **FR-PL-007**: The intake **cost envelope** MUST be lockable as one row per intake with
  `total_envelope = total_estimate × (1 + upside_pct/100)` (upside fixed at 20% in this
  scope), recording `any_override`, the locking actor/role, and an authorizing approval
  reference. Lock MUST be **refused** when any plan row has neither an estimate nor an
  override (reporting the missing row codes). Re-locking replaces the row.
- **FR-PL-008**: The intake **ROI assessment** MUST support scenarios (at most one active)
  with Forrester-TEI-for-P&C benefit and cost assumptions and framing (horizon years,
  discount rate), computing labor/loss-ratio/premium-uplift benefits, total run cost (ai
  spend defaulting from the locked envelope when basis is `cost_envelope`), net annual,
  payback months, NPV over the whole-year horizon, and ROI percent (ai spend basis
  `cost_envelope` default | `manual_override`). Lock MUST apply only to
  the active scenario and MUST be a no-op (logged) when none is active (ROI encouraged, not
  required).
- **FR-PL-009**: The system MUST expose actuals and drift: per-intake actual spend windows
  (yearly, trailing-30d, trailing-90d, restricted to realized agent/task entities) and a
  drift status `within` | `trending_over` (90d-annualised exceeds envelope) | `over`
  (rolling-365d exceeds envelope) | none (no envelope yet).

### Capability area: Testing / validation

- **FR-TV-001**: The system MUST own test-suite and test-case **definitions** and **ground-
  truth datasets** (governance-owned), while execution **results** are produced by the
  runtime and stored back. The system MUST support listing suites/cases for an entity,
  logging a test result, listing results for a version, getting the latest validation run,
  and listing model cards.
- **FR-TV-002**: A test case MUST carry input/expected-output, a metric type (`exact_match`
  | `schema_valid` | `field_accuracy` | `classification_f1` | `semantic_similarity` |
  `human_rubric`), optional metric config, an adversarial flag, and tags. A test execution
  result MUST carry pass/fail, metric result, failure reason, and timing.
- **FR-TV-003**: Ground-truth datasets MUST follow a three-table model — dataset (status
  `collecting` | `labeling` | `adjudicating` | `ready` | `deprecated`; quality `silver`
  (single annotator, no review) | `gold` (multi-annotator with inter-annotator agreement)),
  record (the unlabeled question; source `document` | `submission` | `synthetic`), and
  annotation (the label; annotator `human_sme` | `llm_judge` | `adjudicator`; exactly one
  authoritative annotation per record) — with kinded mocks (`tool` | `source` | `target`).
  Storage references MUST be storage-abstracted (provider/container/key). Datasets MUST
  carry `designed_for_version_id`, `applies_to_versions[]`, and `superseded_by` lineage,
  computed counters (`record_count`, `annotated_count`, `authoritative_count`), and, for
  gold-tier datasets, IAA fields (`iaa_score`, `iaa_method`, `iaa_computed_at`).
- **FR-TV-004**: A validation run MUST carry a status (`running` default | `complete` |
  `failed`) and capture precision/recall/F1, Cohen's kappa, confusion matrix, field
  accuracy, fairness metrics + pass flag, threshold details, and an overall pass flag, with
  per-record drill-down (expected vs actual, correctness, match type/score, decision-log
  reference). Metric thresholds MUST be definable per `(entity, materiality_tier, metric,
  field)`; field extraction config MUST be definable for tasks.
- **FR-TV-005**: A model card MUST capture purpose, design rationale, I/O descriptions,
  known limitations, conditions of use, optional LM-specific notes, validator/validation-
  run reference, regulatory notes, materiality classification, and an approval/lifecycle
  state, surfaced in the model inventory.

### Capability area: YAML import/export

- **FR-YM-001**: The system MUST export a registry entity (and its transitive dependency
  graph) as a self-contained YAML **Bundle** (`apiVersion: studio.verity.ai/v1`,
  `kind: Bundle`) with entries emitted leaves-first (inference config → tool → data
  connector → prompt → task → agent), references by **name + version label (never UUID)**,
  and deterministic byte-stable serialization. Two scoping modes MUST be supported: lineage
  (all versions of the start entity; specific versions for transitive deps) and pinned
  (one start version).
- **FR-YM-002**: Bundle **import** MUST be a two-phase operation: validate (every outgoing
  reference resolves to a same-bundle entry or an existing DB row; **all** errors
  aggregated and reported at once) then write in strict dependency order. The system MUST
  also offer a dry-run plan (`would-insert`/`would-skip`).
- **FR-YM-003**: Import MUST be idempotent and conservative: existing headers and versions
  are skipped (header edits go through registry operations, not import); imported
  `lifecycle_state` is **always forced to `draft`** (channel `development`); schema-NOT-NULL
  defaults are injected. A dangling reference MUST abort the import.
- **FR-YM-004**: Intake export/import MUST be a single-document round-trip
  (`apiVersion: verity.intake/v1`) covering header, requirements, plan rows, entity links,
  impact assessment, and approvals; import MUST be idempotent on `code`, MUST NOT replay
  approval requests/sign-offs (a clean intake approval is auto-opened), MUST NOT re-trigger
  triage or plan auto-generation, and MUST validate the `apiVersion`. Out-of-vocabulary
  enum values MUST be rejected.
- **FR-YM-005**: YAML import/export operations MUST be authorized by the `export_yaml` /
  `import_yaml` action codes and exposed **as API operations** (closing the v1 gap where
  these were CLI-only with no HTTP surface). Import MUST be transactional in v2 (no partial-
  state mid-import failure — see disposition).

### Capability area: Reporting / compliance

- **FR-RP-001**: The system MUST expose dashboard counts (catalog counts, total decisions,
  total overrides, open incidents), optionally scoped to an application set, and model
  inventory for agents and tasks (champion-only, with latest validation + model-card +
  30-day override/decision counts + active incidents) — the SR 11-7 governed-entity
  inventory.
- **FR-RP-002**: Open incidents MUST unify governance incidents with active quota breaches.
  Override analysis MUST group HITL overrides by fact type and entity type over a window.
- **FR-RP-003**: The system MUST maintain the **three-axis compliance metamodel**
  ([[0008-compliance-control-evidence-model]]), replacing v1's requirement→feature mapping:
  **(left)** regulatory frameworks and citable provisions; **(center, stable)** canonical
  requirements — defined once, technology-agnostic — each assigned to one or more
  **governance domains** and decomposed into a **cumulative, variable-length tier ladder**;
  **(right)** **controls** (carrying `type`, lifecycle `phase`, `enforcement_action`) and
  **evidence specifications** (`artifact_type`, `produced_by`, `citable_as`). **Bridge 1**
  maps provisions↔canonical requirements many-to-many with a **minimum tier**; **Bridge 2**
  maps canonical requirements↔controls/evidence **per tier, per phase**. The center axis is
  stable; the left and right axes grow independently. Embedding identity MUST be a single
  current `embedding_config`. Controlled vocabularies preserved verbatim: framework
  `jurisdiction` (`US-FED` | `US-NAIC` | `US-CO` | `INDUSTRY`); provision↔requirement
  `mapping_source` (`manual` | `semantic_recommended` | `human_validated`); the **new** v2
  control `phase` set (`design_time` | `deploy_time` | `static_model` | `execution`). The
  v1 requirement↔feature `role` and `feature.status` vocabularies and the feature hierarchy
  are **dropped** (replaced by controls + evidence specs — see disposition). The
  analytics-mart/report vocabularies are **unchanged** and used by reporting (FR-RP-005/006):
  `mart_field.semantic_type` (`identifier` | `measure` | `date` | `category` | `text` |
  `json`); mart-field `role` (`key` | `measure` | `dimension` | `filter` | `context`) and
  `aggregation` (`count` | `sum` | `avg` | `min` | `max` | `distinct_count`); and
  `report_kind` (`metadata_driven` | `template_driven`).
- **FR-RP-007 — Control phases.** Each control MUST declare exactly one lifecycle phase —
  `design_time` (asset/binding/prompt/schema definition, at intake/compose), `deploy_time`
  (package promotion/deployment, enforced at the governed-deployment gate, FR-PK-002/003),
  `static_model` (continuous checks on the at-rest champion package/config/model card), or
  `execution` (enforced during a run by the harness) — plus an `enforcement_action`. A
  control MUST **block non-compliant activity at the point of occurrence**: a hard gate at
  `design_time`/`deploy_time`; refusal or Target-Binding write-suppression at `execution`.
- **FR-RP-008 — Evidence capture.** On enforcement, each control MUST produce **evidence**
  satisfying its evidence specification, recorded as an **append-only audit fact** tied to
  the canonical requirement + tier + phase + the entity/version/run that produced it (stored
  per ADR-0004/0007). Evidence MUST be immutable and reconstructable for audit.
- **FR-RP-009 — Exception governance.** When a control would block but an exception is
  warranted, the system MUST require a registered **exception** before proceeding, carrying:
  the **specific tier waived**, the **canonical requirement affected**, the **approving
  authority** (a principal holding the dedicated **`approve_exception`** action — granted to
  the `compliance` and `security` roles, distinct from promotion sign-off;
  [[user-authentication]]), the **compensating controls**, and a **maximum permitted
  duration (expiry)**. Exceptions MUST be first-class, **append-only** audit records visible
  in the audit trail; an **expired** exception MUST stop suppressing its control (the block
  re-applies).
- **FR-RP-010 — Maturity scoring.** The system MUST score **maturity per governance domain**:
  for each applicable canonical requirement it evaluates the highest tier whose controls are
  satisfied with evidence (tiers are cumulative — tier N implies all tiers below N), then
  **normalizes** across requirements with different tier-ladder lengths before aggregating
  per domain. The precise normalization formula is fixed in the compliance component spec
  ([[0008-compliance-control-evidence-model]]).
- **FR-RP-011 — Continuous, lifecycle-gated enforcement (compliance gate).** Compliance MUST
  be enforced continuously across the asset lifecycle, not at periodic reviews. An asset MUST
  NOT advance to a lifecycle state whose required controls — for its applicable canonical
  requirements at its domains/tier — are unmet or lack captured evidence, unless a valid,
  unexpired exception is registered (ties to the FR-LC promotion gates and constitution
  Principle VIII).
- **FR-RP-004**: The seeded regulatory shelf MUST include SR 11-7, the NAIC AI Model
  Bulletin, the NAIC AI Systems Evaluation Tool, Colorado SB21-169, and ORSA/ASOP-56/CAS.
  NIST AI RMF and ISO/IEC 42001 are **net-new for v2** (absent in v1) — see disposition and
  Out of scope.
- **FR-RP-005**: Report generation MUST resolve a report definition, dispatch to a composer
  (model inventory, decision/workflow audit trail, fairness validation summary, NAIC
  Exhibit C, intake inventory, approval audit log, impact-assessment register), render the
  declared output formats, and record a `report_run_log` row (`pending` →
  `succeeded`/`failed`) with artifact references. Unknown report code, unregistered
  composer, or missing template MUST be rejected; missing required scope parameters MUST be
  rejected before generation.
- **FR-RP-006**: The system MUST expose an incremental **analytics feed** over an active
  allow-list of feed views, paged by an opaque `(ingest_ts, source_pk)` keyset cursor with
  a `next_cursor` and a `complete` flag; a requested view not on the active allow-list MUST
  be refused **before any query runs** (guarding arbitrary reads), and malformed cursors/
  bounds MUST be rejected. Analytics reads MUST go through the L2 logical-mart views, never
  L1 tables directly, so the L1→materialized-mart swap is transparent (ADR-0004/0007).

### Capability area: Packaging & governed deployment *(v2-new — ADR-0006)*

- **FR-PK-001**: Champion promotion MUST produce a deployable **package** — `.vtx` for a
  task, `.vax` for an agent — carrying the resolved composition needed to run (inference,
  prompts, bindings, tool authorizations, schema) and a **digest-pinned compatible
  harness-image reference**. The package build MUST be recorded in an **insert-only**
  package inventory.
- **FR-PK-002**: Deployment MUST be governed and **lifecycle-gated** by the source
  version's state: `staging` packages deploy to **non-prod only**; `challenger` packages
  deploy to **prod in `shadow` or `ab` run-mode**; `champion` packages deploy to **any
  live** target; `deprecated` packages are **locked** (no execution; restorable via
  rollback). A request violating
  the gate MUST be refused with the reason.
- **FR-PK-003**: Deployment MUST be refused when the package's pinned harness-image digest
  does not match the target environment's harness-image digest (compatibility check). Every
  deployment (successful or refused) MUST be recorded in an **insert-only deployment
  inventory** with the actor, package, target, and outcome.

### Capability area: Harness runtime, enrollment & dispatch *(v2-new — ADR-0010)*

- **FR-HR-001**: All harness↔governance integration MUST be **API-only** ([[0003-harness-governance-api]]):
  the spoke holds **no database credential**. The **Harness Gateway API** is the sole write
  path; register, claim, release, heartbeat, and command-ack are gateway operations whose
  database effects (including any `SKIP LOCKED` claim and the coordinator-lease update) run
  **hub-side**.
- **FR-HR-002**: Each cluster MUST elect **exactly one coordinator** via a hub-arbitrated
  **heartbeat lease** — an atomic conditional update that makes split-brain impossible.
  Leadership failover MUST NOT interrupt in-flight execution (workers complete jobs they
  have claimed regardless of coordinator state).
- **FR-HR-003**: Run dispatch MUST follow the transactional outbox → NATS → coordinator-claim
  path. `harness_dispatch` MUST hold the mutable operational dispatch state and MUST be
  written in the **same transaction** as the append-only `execution_run_status` audit. The
  coordinator is the cluster's **sole hub uplink**; workers MUST NOT call the hub directly.
- **FR-HR-004**: Enrollment MUST exchange a **one-time, short-lived token** for a
  cluster-scoped **mTLS identity + app-scoped API key**; all spoke→hub traffic MUST be
  **outbound-only** (no inbound ports), and certificates MUST auto-rotate on an overlap
  window.
- **FR-HR-005**: App data-source credentials MUST be **metadata-only at the hub** (Model B):
  name, connector type, and verification status **only** — never a value, never a vault
  reference. The secret MUST remain on the spoke; the coordinator reports
  `credential_verification_status` via the gateway.
- **FR-HR-006**: **Package** deployment (`deploy_package`) MUST NOT drain or interrupt
  in-flight jobs — bundles load once at claim time and old/new bundles coexist in cache.
  **Image** patch MUST surface a **graceful vs. force** drain choice in the portal; force
  requeues interrupted jobs with a new idempotency key.

---

## Key Entities *(observable; no schema internals)*

- **Application** — the owning tenant-of-record for intakes and registry entities; the
  unit of app-team scoping and report/dashboard scoping.
- **Intake** — a use case under governance, with a status lifecycle, an EU-AI-Act risk
  tier, NAIC materiality, requirements, entity links, an impact assessment, a cost
  envelope, ROI scenarios, and a build plan.
- **Requirement** — a typed, status-tracked statement on an intake, semantically de-
  duplicated, linkable to realized entities and verified before champion promotion.
- **Registry entity** — an agent, task, or prompt as a header plus immutable versions; or a
  single-row tool, inference config, data connector, or MCP server.
- **Version** — an immutable composition of an entity (inference, prompts, Source/Target
  Bindings, tools, thresholds, schema) with a lifecycle state, deployment channel, and SCD-2
  temporal window when champion/deprecated.
- **Source Binding / Target Binding** — declarative input/output wiring (uniform for tasks
  and agents) expressed in the constrained reference DSL.
- **Delegation** — an authorized agent-to-agent edge (champion-tracking or version-pinned).
- **Approval request / sign-off** — the multi-role intake quorum and its individual role
  decisions.
- **Promotion attestation** — the single-approver audit record of one lifecycle transition,
  including champion confirmation.
- **Decision** — one immutable, append-only record of an AI invocation, with frozen
  inference snapshot, binding-resolution audit, correlation ids, and HITL state.
- **Model-invocation** — one immutable usage record per decision; cost is computed point-in-
  time from the SCD-2 price catalog, never stored.
- **HITL override** — an additive per-field human correction anchored technically and by
  business identity.
- **Run** — an event-sourced execution with a resolved current status and a terminal
  execution envelope.
- **Quota / quota-check** — a soft budget definition and its period-scoped check outcomes.
- **Plan row / plan estimate / cost envelope / ROI assessment** — the generated build plan
  and its business-case envelope.
- **Test suite / case / result / ground-truth dataset / validation run / model card** — the
  testing and validation evidence surface.
- **Package** *(v2-new)* — a `.vtx`/`.vax` artifact produced at champion promotion, pinned
  to a compatible harness-image digest, recorded in an insert-only inventory.
- **Deployment record** *(v2-new)* — an insert-only record of a governed, lifecycle-gated
  deployment of a package to an environment.
- **Harness node / coordinator lease** *(v2-new — ADR-0010)* — a coordinator-eligible runtime
  host in a cluster, and the per-cluster lease naming the elected coordinator (master).
- **Dispatch record** *(v2-new — ADR-0010)* — the mutable per-run operational dispatch state
  the coordinator drives (queued → published → claimed → assigned → executing → released),
  twinned with the append-only run-status audit.
- **Harness app credential** *(v2-new — ADR-0010)* — a metadata-only registry entry (name,
  type, verification) for an app data-source secret that lives on the spoke, never at the hub.
- **Compliance metamodel** — regulatory **frameworks & provisions** (left); **canonical
  requirements** with **governance domains** and **cumulative tier ladders** (stable
  center); **controls** (typed, phase-scoped, with an enforcement action) and **evidence
  specifications** (right); the provision↔requirement (min-tier) and requirement↔control
  (per tier/phase) bridges; **evidence** (append-only audit facts); **exceptions**
  (append-only — waived tier, affected requirement, named approver, compensating controls,
  expiry); per-domain **maturity scores**; the **obligation set** resolved at intake; report
  definitions and feed views.

---

## API surface *(observable operation contracts, grouped by capability area)*

All operations are governance-API operations behind the single API boundary (FR-API-001),
authorized per the action matrix (FR-AUTHZ-001). Verbs/paths here describe the contract
shape, not a binding wire format; the canonical OpenAPI lives with the service.

### Intake & AI-risk classification
- Create intake; get by `(application, code)`; get by id; list (filter by status / tier /
  owner / application); update mutable fields.
- Triage / risk-classify (sets tier + materiality + rationale; advances status; rewrites
  required roles; auto-rejects `unacceptable`); reclassify risk (opens
  `risk_reclassification` approval); approve; mark in-build; mark live; retire.
- Requirements: add / list / update; semantic redundancy check (top-N similar).
- Entity links: create / list / delete; reverse-lookup intakes for an entity.
- Impact assessment: upsert / get. Governance dashboard counts. Lifecycle-stepper read.

### Registry & composition
- Register agent / task / prompt (+ versions), inference config, tool, data connector, MCP
  server, application; map entity → application; upsert execution context (keyed on
  `(application_id, context_ref)`).
- Compose: assign prompt; authorize agent/task tool; register delegation; replace-association
  sets (draft-only, transactional) for prompts / tools / delegations.
- Source Binding / Target Binding (+ payload fields): insert / list / delete-for-owner.
- In-place update tool / inference config (concurrency-stamped); draft-version update;
  draft-version delete (cascade); clone-into-new-draft.
- Resolve config (priority: version_id > effective_date > champion); retrieval/listing of
  headers, versions, single-row entities; where-used reverse lookup.
- Model catalog + SCD-2 price: insert/list/get model; set/get/list prices; usage rollups.

### Entity/version model (SCD-2)
- Champion-at-date temporal resolution; list versions ordered by components; version
  validity-window reads (derived, read-only).

### 6-state lifecycle & promotion
- Promote (transition + gate evidence + champion confirmation); rollback; list promotion
  attestations for a version; legal-next-states and gate-block-reason previews.

### Approvals & sign-off
- Open approval request; withdraw open request; list per intake; get request + sign-offs;
  record sign-off (role server-derived); evaluate intake promotion gate (consumed by
  promote).

### Decision & model-invocation logging
- Ingest decision (async/batched); get decision detail; list/count decisions (filtered);
  recent decisions; audit trail by execution context / by workflow run.
- Ingest model-invocation; get invocation (cost view) by decision; usage aggregations.
- Record HITL override; list overrides (technical or business axis); get override detail.
- Build/return canonical execution envelope (terminal-only).

### Run / execution state
- Submit run; get run; list/count runs (filtered); run lifecycle timeline; runs for
  workflow; runs for execution context; run result (envelope).
- Worker: claim-next (SKIP LOCKED); heartbeat; release; janitor reclaim; cancel.

### Quotas
- Register / list / get / update / delete quota; run-check (one); run-all-checks;
  list checks / latest-per-quota / active-breach count; quota guidance for a realized
  entity.

### Plan generation
- Generate plan; plan rows add/list/update/delete; realize plan row.
- Plan estimate scenarios: list/get/get-active/upsert/activate/override/delete/compute.
- Cost envelope: summary/lock/get/delete; ROI: list/get/get-active/upsert/activate/lock/
  delete/compute; actuals + drift; active-models picker.

### Testing / validation
- List suites/cases for entity; log test result; list results; get latest validation; list
  model cards; register suites/cases/datasets/records/annotations/thresholds/model cards;
  ground-truth + test-case kinded mocks CRUD; validation-run reads + per-record drill-down.

### YAML import/export *(v2: exposed as API operations; v1 gap closed)*
- Export agent/task/prompt/tool/inference-config/data-connector bundle (lineage or pinned);
  serialize/deserialize bundle; import bundle (validate-then-write); plan import (dry-run /
  diff); export intake YAML; import intake YAML.

### Reporting / compliance
- Dashboard counts (global / scoped); model inventory (agents/tasks); override analysis;
  incidents; inventory graph.
- Compliance metamodel reads (frameworks/provisions; canonical requirements + governance
  domains + tier ladders; controls + evidence specs; both bridges); control-enforcement
  results + evidence facts by requirement/tier/phase; exception register (create / list /
  expire); per-domain maturity scores; report definitions list + recent runs; generate
  report (record run log); manifest/DDL metadata.
- Analytics feed: list views; read view by keyset cursor.

### Packaging & governed deployment *(v2-new — ADR-0006)*
- Build package on champion promotion (`.vtx`/`.vax`, digest-pinned harness compatibility);
  list/get package; package inventory (insert-only).
- Evaluate deployment (lifecycle-gated: staging → non-prod; challenger → prod in shadow/ab
  run-mode; champion → any live; deprecated → locked but rollback-restorable; harness-image
  digest must match); record deployment (insert-only inventory); list deployments.

### Cross-cutting: identity & authorization *(composed from [[user-authentication]])*
- Resolve principal roles; evaluate action gate; grant/revoke platform and app-team roles
  (append-only); emit auth events. (Full contract specified in [[user-authentication]].)

---

## UI surfaces *(reference; build detail out of scope)*

All UI-serving and Studio/admin surfaces are **clients of this gated API** (FR-AUTHZ-001),
not a separate authority; their visual and interaction design is governed by the canonical
[[design-system]] (`specs/ui/design-system.md`) — UI build detail is out of scope for this
service spec. Key surfaces are illustrated by approved references: **navigation** →
`specs/ui/verity-nav-framework.html` (apps-based model, design-system §7); **agent/task
compose** → `specs/ui/verity-agent-studio.html` (authoring canvas, design-system §10);
**intake** → `specs/ui/verity-intake-wireframe.html` (early-iteration UX, carried into the
Intake feature spec). These bind the *observable* surfaces (intake, registry/compose,
lifecycle, runs, decisions, compliance) to a consistent UX without constraining
implementation.

## Success Criteria *(mandatory; measurable, technology-agnostic)*

- **SC-001**: 100% of governance writes occur through the API; zero non-governance
  components hold a working governance DB credential (verified by credential inventory and
  by the absence of any direct-DB write path in callers).
- **SC-002**: 100% of API operations have an explicit action-matrix mapping; any route
  without one denies by default (asserted by a startup/total-coverage check).
- **SC-003**: 100% of v1 governance capabilities appear in the disposition table with a
  KEEP / CHANGE / DROP-with-reason / DEFER-with-reason verdict (no silent loss).
- **SC-004**: The 7 lifecycle states, the legal transition graph, all risk tiers, all
  approval roles/decisions/request kinds, and all enum vocabularies match v1 **verbatim**
  (asserted by enum-equivalence tests against `contracts/enums.py`, `models/intake.py`, the
  schema CHECK vocabularies enumerated in FR-RG/FR-DL/FR-TV/FR-RP, and the `studio_role` /
  action-code sets carried in [[user-authentication]]).
- **SC-005**: Every champion promotion produces exactly one package with a non-empty,
  digest-pinned harness-image compatibility record, and 0 deployments succeed against a
  mismatched harness-image digest or a lifecycle-disallowed target.
- **SC-006**: Decision and model-invocation logs are provably append-only (no update/delete
  path exists), and a decision-log row is ingested for ≥99.9% of non-`none`-detail
  invocations.
- **SC-006a**: A decision-log record is visible in the UI within **20 seconds (p95)** of the
  invocation, via async/batched ingest; reporting/analytics run separately as jobs and are
  never on the status path.
- **SC-007**: A YAML bundle round-trips deterministically: re-exporting an imported bundle
  yields byte-identical output, the dependency graph reconstructs in a fresh store, and all
  imported versions land as `draft`.
- **SC-008**: Concurrent worker claims never double-claim a run (0 duplicate terminal rows
  under contention), and a stuck claim is recovered and re-claimable within the configured
  janitor threshold.
- **SC-009**: A cost-envelope lock is refused whenever any plan row lacks both an estimate
  and an override, and the missing row codes are reported (no envelope locks with gaps).
- **SC-010**: Every governance operation fails closed for an unauthorized or unmapped
  caller (0 fail-open observations in authorization tests).
- **SC-011**: The analytics feed never serves a view outside the active allow-list, and
  keyset paging returns each row at most once across pages under steady ingest.
- **SC-012**: Historical cost and audit reads are stable across model-price edits and across
  the L1→materialized-mart swap (same numbers before/after).

---

## Assumptions

- **Local-dev-first.** Single-process governance service, single Postgres, per-process
  caching/dispatch are acceptable for local dev; the production deltas are enumerated under
  *What changes for production* and are normative for any non-single-process deployment.
- **Authorization is composed, not redefined here.** The identity/session/role model,
  the action matrix's cells, and the approval-by-risk-tier sets are specified in
  [[user-authentication]]; this spec assumes them and references the same controlled
  vocabularies. App-team action cells remain partially specified there (an open item) and
  are therefore not enforced for app-scoped governance operations beyond the platform-role
  gate until that item is resolved.
- **API surface is built out incrementally.** The full operation surface above is the
  committed target; the equity-research slice ([[equity-research-slice]]) implements only
  the subset it needs (register/compose/promote/run/override) first.
- **Tier-1/Tier-2 split.** Postgres is the thin Tier-1 system-of-record; bulk decision/
  invocation history and the customer-portable analytics tier (open Iceberg/Parquet) are a
  dedicated phase (ADR-0004/0007). Insert-only/append-only modeling applies from day one
  regardless; analytics reads go through L2 logical-mart views so the swap is transparent.
- **Packaging format.** `.vtx` (task) / `.vax` (agent) packages carry the resolved
  composition needed to run plus a digest-pinned compatible-harness-image reference; the
  precise envelope layout is detailed in [[0006-packages-and-governed-deployment]]. This
  spec fixes the observable gating and inventory behaviour, not the byte layout.
- **Cost/ROI formulas** (per-invocation cost with +2%/tool overhead, 20% fixed envelope
  upside, Forrester-TEI-for-P&C ROI, history-blend skipped) are carried verbatim from v1
  Phase D; any change is a separate decision.
- **Prompt champion normalization.** v2 is assumed to normalize prompts onto the same
  header champion-pointer + channel + rollback model as agents/tasks (closing the v1
  asymmetry); recorded as a CHANGE in the disposition.
- **Embedding model.** Requirement/compliance semantic features use the v1 BGE-small
  384-dim embedding identity unless a later decision changes `embedding_config`.
- **Deprecated/dead v1 artifacts** (`pipeline` enum branch, decision-level override log,
  unused `fairness_analysis_reviewed`/`similarity_flags_reviewed` gate flags, dormant
  `decision_override` columns) are not carried forward as live behaviour (see disposition).

---

## Out of scope / v2 deferrals

- **Quota enforcement is per-quota configurable** (clarified 2026-05-31): **soft by
  default** (alert-only), with an optional **hard-stop** that refuses the invocation as an
  execution-phase control (FR-QT-004). *(No longer deferred; soft remains the default so the
  v1 audit signal is preserved unless a quota opts into hard-stop.)*
- **Scheduled quota checker / notifications.** On-demand and batch checks are in scope; a
  scheduled checker and outbound notifications are **DEFERRED**.
- **Tier-2 bulk log store + portable analytics materialization.** The customer-portable
  Iceberg/Parquet tier and the L1→materialized-fact swap are a **DEFERRED** dedicated phase
  (ADR-0004/0007); only the L2 view abstraction and append-only modeling are in scope now.
- **NIST AI RMF and ISO/IEC 42001 frameworks.** Net-new regulatory shelves not present in
  v1; **DEFERRED** to a compliance-content phase (the metamodel supports them; the seed
  content is later).
- **Full app-team authorization cells.** The 5 `app_team_role` action mappings are
  **DEFERRED** to [[user-authentication]]'s open item; until resolved, app-scoped governance
  operations enforce only the platform-role gate.
- **Multi-step orchestration / pipelines.** Pipelines are **DROPPED** from Verity
  (orchestration lives in application code); the canonical envelope has no nested steps.
- **Streaming-to-UI, response caching, batch model API, tool versioning, DB-trigger
  immutability, session continuity, execution hooks, model retry/circuit-breaker.** All
  **DEFERRED** (listed in the v1 design's "not built yet"); v2 enforces immutability at the
  API/data layer rather than via DB triggers in this scope.
- **Production hardening** — Kubernetes/Helm packaging, HA primary/replica Postgres, shared
  session/cache store, OTEL/Prometheus/Grafana — is **DEFERRED** to its own committed phase;
  see *What changes for production*.

---

## v1 → v2 capability disposition

Verdicts: **KEEP** (carried as-is), **CHANGE** (carried with a stated delta),
**DROP** (with reason), **DEFER** (with reason). Every capability surfaced in the
inventories is accounted for.

### Intake & AI-risk classification

| v1 capability | Verdict | Notes |
|---|---|---|
| Create intake (status `proposed`, slug derive + uniqueness, auto-open intake approval) | KEEP | Now API-only, gated `create_intake`, actor server-resolved. |
| Get by `(app, code)` / by id; list + filters | KEEP | |
| Update mutable intake fields | KEEP | |
| Triage / risk-classify (tier, materiality, rationale; status advance; role rewrite; auto-reject `unacceptable`) | KEEP | Vocabularies + auto-reject note verbatim. |
| Risk reclassification (`reclassify_risk`; re-triage + open `risk_reclassification` approval) | KEEP | Gated action; opens the promotion-blocking reclassification request (FR-IN-013). |
| `REQUIRED_ROLES_BY_RISK_TIER` sets | KEEP | Verbatim. |
| NAIC materiality (orthogonal, no gate) | KEEP | |
| Reject / retire intake | KEEP | |
| Add/list/update requirements (+ embedding, re-embed on change) | KEEP | Embedding identity per `embedding_config`. |
| Semantic redundancy check (top-5, min 0.78) | KEEP | Non-fatal on failure. |
| Re-embed stale requirements (batch) | CHANGE | Becomes a governance-owned API/batch op, not a direct-DB CLI. |
| Link entity / list / delete / intakes-for-entity | KEEP | |
| Artifact plan add/list/update/delete; realize | KEEP | See Plan generation. |
| Impact assessment upsert/get (+ JSON validation) | KEEP | |
| Approvals list/open; sign-off; recompute roll-up | KEEP | Sign-off role server-derived (FR-AUTHZ-002). |
| Promotion gate | KEEP | See Approvals. |
| Governance dashboard / counts | KEEP | |
| Persona switcher (cookie) | DROP | Replaced by Entra SSO + DB roles ([[user-authentication]]); no self-selected persona. |
| Intake detail aggregated read; lifecycle stepper | KEEP | UI concern; data exposed via API. |
| Form-failure re-render at HTTP 200 | DROP | UI-layer artifact; API returns proper validation status. |

### Phase D — business-case envelope (cost + ROI)

| v1 capability | Verdict | Notes |
|---|---|---|
| Plan estimate scenarios list/get/active; upsert/activate; override (paired); delete | KEEP | |
| Compute plan estimate (per-invocation +2%/tool, yearly) | KEEP | History-blend stays skipped. |
| Cost envelope summary/lock (refuse on missing rows)/get/delete; 20% upside | KEEP | |
| ROI scenarios upsert/activate/lock/delete; Forrester-TEI compute | KEEP | |
| Drift + actuals + quota guidance; active-models picker | KEEP | |
| Auto-lock (plan-gen → envelope → ROI) on intake approval | KEEP | Best-effort/non-fatal. |

### Registry & composition

| v1 capability | Verdict | Notes |
|---|---|---|
| Header+version model (agent/task/prompt); single-row tool/config/connector/MCP | KEEP | |
| Register all entity/composition types; map entity→app; execution context | KEEP | API-only, gated `author_registry`. |
| `source_binding` / `write_target` / `target_payload_field` grammar | CHANGE | Renamed **Source Binding / Target Binding** (ADR-0005, [[binding-grammar]]); uniform on tasks **and** agents; tools+MCP agent-only. |
| Legacy per-task `task_version_source` / `task_version_target` | DROP | Superseded by the unified binding grammar; not carried forward. |
| Wiring DSL (`input`/`output`/`const`/`fetch`, bracket paths) | KEEP | |
| Prompt assignment / tool authorization / delegation | KEEP | |
| Agent-to-agent delegation (XOR child, champion-tracking vs pinned, runtime gate) | KEEP | |
| Replace-association-set (draft-guarded, transactional) | KEEP | |
| Clone-into-new-draft (provenance) | KEEP | |
| In-place update tool/config (optimistic concurrency) | KEEP | |
| Draft-version update/delete (cascade; assigned-prompt block) | KEEP | |
| Resolve config (version_id > date > champion) + frozen snapshot | KEEP | |
| Retrieval/listing (headers/versions/single-row) | KEEP | |
| Where-used reverse lookup (`get_entity_consumers`) | CHANGE | v2 MUST also cover Source-Binding `fetch:` connector edges (v1 coverage gap closed). |
| pgvector registry-entity similarity (declared, never populated) | DEFER | Schema groundwork only; population deferred (consistent with v1 "populated later"). |
| `data_classification` (`tier1_public`/`tier2_internal`/`tier3_confidential` default/`tier4_pii_restricted`) + tool `is_write_operation`/`requires_confirmation` | KEEP | Enforced pre-dispatch incl. MCP tool calls (FR-RG-013); vocabulary verbatim. |
| `trust_level` vocabulary (`trusted`/`conditional`/`sandboxed`/`blocked`; declared, unused in v1 paths) | DEFER | Carried as schema vocabulary; no enforcement path existed in v1, so population/enforcement is deferred. |
| `transport`/MCP routing vocabularies | KEEP | |
| `backfill_inference_config_model_id` (one-time model-id linkage) | DROP | One-time v1 migration utility; not a recurring v2 capability (re-run as a migration if ever needed). |
| `purge_application_activity` (env-gated destructive op) | CHANGE | Retained as an explicitly authorized, audited admin API op (no env-flag side door). |

### Entity/version model (SCD-2)

| v1 capability | Verdict | Notes |
|---|---|---|
| `major.minor.patch` + derived `version_label`; uniqueness | KEEP | |
| Version `input_schema` admit-time non-empty rule; gate flags | KEEP | |
| SCD-2 windows (NULL pre-champion; open sentinel on champion; close on deprecate) | KEEP | v2 fixes the documented sentinel-value discrepancy; observable date-range behaviour unchanged. |
| Champion timeline contiguity via deprecate-prior + set-new | CHANGE | v2 MUST make champion-set **atomic** (closes the v1 non-transactional race). |
| Promoted-version composition immutability | CHANGE | Enforced at governance API/data layer in v2, not application-level only. |
| Model-price SCD-2 (`uq_mp_active`, cost view join) | KEEP | |
| Prompt has no champion pointer / no channel / no rollback | CHANGE | v2 normalizes prompts onto the agent/task champion-pointer + channel + rollback model. |

### 6-state lifecycle & promotion

| v1 capability | Verdict | Notes |
|---|---|---|
| Lifecycle states + legal transition graph + state→channel map | CHANGE | 7→**6 states** (v1 `shadow` → challenger run-mode); `deprecated` restorable via rollback (`deprecated → champion`); `shadow` channel retired. No silent loss. |
| Gate requirements (`→challenger`, `challenger→champion`) | CHANGE | Folded v1's `→shadow`/`→challenger` gates: `→challenger` = staging tests; `challenger→champion` adds shadow-evaluation review. |
| `candidate → champion` fast-track, gate-free | CHANGE | v2 MUST NOT be gate-free for non-seed promotions (FR-LC-004). |
| `promote()` effects (state, channel, attestation, SCD-2, set-champion) | KEEP | |
| Champion confirmation (name-typeback + acknowledgement) | CHANGE | Enforced on **all** surfaces in v2 (v1 enforced it only in Studio UI, not the JSON API). |
| `rollback()` (deprecate-only despite docstring) | CHANGE | v2 MUST atomically restore the immediately-prior champion (rejecting when none exists); the v1 deprecate-only behaviour is fixed (FR-LC-007). |
| `legal_next_states` / `gate_block_reason` preview helpers | KEEP | |
| `materiality_tier` inert in lifecycle gating | KEEP | Tier drives intake required-roles only; lifecycle gating stays tier-independent. |
| Unused gate flags `fairness_analysis_reviewed`, `similarity_flags_reviewed` | DROP | Never checked in v1 gates; not carried as live gate inputs (may persist as attestation-only fields). |
| Dormant `decision_override` / `override_reason` columns | DROP | Never written/read in v1; not carried. |

### Approvals & sign-off

| v1 capability | Verdict | Notes |
|---|---|---|
| Two parallel approval surfaces (single-approver attestation vs multi-role quorum) | KEEP | Coupling only via the intake gate. |
| Approval request kinds / status / per-request `required_roles` | KEEP | |
| Open / **withdraw** approval request (`withdraw_approval` → status `withdrawn`) | KEEP | Withdraw is a gated op; status producer for `withdrawn` (FR-AP-002). |
| Sign-off (role from principal; one-per-(request,role,identity); decisions enum) | KEEP | Role now server-resolved (FR-AUTHZ-002). |
| Status roll-up rules (`requested_changes`/`abstained` neither satisfy nor reject) | KEEP | |
| Post-approval cascade (plan-gen, envelope lock, ROI lock) | KEEP | Best-effort/non-fatal. |
| Intake promotion gate (status / open approvals / high-risk promote_champion / unverified reqs) | KEEP | Verbatim reasons; unlinked entities pass. |
| `approval_record` single-row attestation (review flags, `champion_confirmation_satisfied`) | KEEP | |

### Decision & model-invocation logging

| v1 capability | Verdict | Notes |
|---|---|---|
| Append-only decision log (full column set, snapshots, correlation, binding audit, HITL) | KEEP | |
| Single `log_decision` write; caller-suppliable id | CHANGE | Ingest moves to async/batched API path (ADR-0003/0004); callers never write the DB. |
| Decision reads (get/list/count/recent/audit-trail by context + workflow) | KEEP | |
| `decision_log_detail` levels incl. `none`=no row; redaction record | KEEP | |
| Decision-level override log / `record_override` | DROP | Already retired in v1; superseded by per-field HITL override. |
| Per-field HITL override (technical + business axes; append-only) | KEEP | |
| Model catalog + model-invocation log; cost via SCD-2 price view | KEEP | Missing-price exclusion preserved. |
| Usage aggregations (`/admin/usage`) | KEEP | Exposed as reporting API. |
| Canonical execution envelope (`1.0`, success/failure, telemetry, provenance) | KEEP | Forward-compat telemetry fields remain unpopulated until later. |
| `ExecutionEventType` streaming event vocabulary (`started`/`tool_call_start`/`tool_call_result`/`text_delta`/`complete`/`error`) | DEFER | Streaming-to-UI deferred (Out of scope); the event vocabulary is retained for the runtime contract. |
| Plane split (reader/writer) | CHANGE | Hardens into the API boundary: runtime ingests via API, governance owns reads/writes. |
| No business keys in decision log (`execution_context_id` only) | KEEP | Verity stays domain-agnostic. |

### Run / execution state

| v1 capability | Verdict | Notes |
|---|---|---|
| Event-sourced run tables + resolved-state view; precedence (completion>error>latest) | KEEP | |
| Submit run (sync ack `submitted`); caller-pregenerated id | KEEP | |
| Status events (`submitted/claimed/heartbeat/released`); terminal completion/error | KEEP | |
| 7-value resolved `current_status`; terminal set | KEEP | |
| `SKIP LOCKED` claim; `inproc` exclusion | KEEP | |
| Heartbeat / release / janitor reclaim (idempotent) | KEEP | |
| Cancel (idempotent no-op on terminal) | KEEP | |
| Run reads (get/list/count/lifecycle/by-workflow/by-context/result envelope) | KEEP | |
| Write-mode × channel gating of Target-Binding writes | KEEP | Renamed to Target Binding. |

### Quotas

| v1 capability | Verdict | Notes |
|---|---|---|
| Quota definition (scope/period/budget/threshold/enabled/notes) + CRUD | KEEP | |
| Quota check (period windows, spend-vs-budget, alert level, auto-resolve) | KEEP | |
| Batch check (skip disabled, isolate failures) | KEEP | |
| Check history / latest-per-quota / active-breach count | KEEP | |
| Quota enforcement mode | CHANGE | v1 soft-only (`hard_stop` inert) → v2 **per-quota configurable**: soft default + optional **enforceable** hard-stop that refuses the run as an execution-phase control (FR-QT-004; clarified 2026-05-31). |
| Quota guidance for realized entity (envelope reverse-lookup) | KEEP | |
| Breaches not written to `incident` table | KEEP | Surfaced via the incidents union instead. |

### Plan generation

| v1 capability | Verdict | Notes |
|---|---|---|
| Rule-based `generate_plan` (functional reqs; auto-generated rows) | KEEP | LLM generator remains a later swap behind the same contract. |
| Capability/materiality mapping; name derivation; high-risk GT + test-suite auto-proposal | KEEP | |
| Plan-row entity + status; realize | KEEP | Realized-row delete refused. |
| Estimates/envelope/ROI/drift | KEEP | See Phase D rows. |

### Testing / validation

| v1 capability | Verdict | Notes |
|---|---|---|
| Testing service reads (suites/cases/results/latest validation/model cards) | KEEP | |
| Governance↔runtime testing boundary (definitions vs results) | KEEP | Aligns with the API boundary. |
| Ground-truth three-table model + statuses/tiers/source/annotator enums; kinded mocks | KEEP | |
| Validation runs + per-record drill-down; thresholds; field-extraction config | KEEP | |
| Model cards | KEEP | |

### YAML import/export

| v1 capability | Verdict | Notes |
|---|---|---|
| Bundle export (BFS dep graph, leaves-first, name+version refs, deterministic) | KEEP | |
| Lineage vs pinned scoping; state-rank resolution | KEEP | |
| Serialize/deserialize (byte-stable; literal block scalars; ISO datetimes) | KEEP | |
| Import (two-phase validate-then-write; aggregate all errors; dry-run/diff) | KEEP | |
| Idempotent skip-existing; force `draft`; default injection | KEEP | |
| Intake single-doc round-trip (no approval replay, no re-triage/auto-plan) | KEEP | |
| Import not single-transaction (partial-state risk) | CHANGE | v2 MUST make import transactional (FR-YM-005). |
| Tool `mock_responses`/`mock_response_key` round-trip asymmetry; prompt `template_variables` | CHANGE | v2 MUST close the export/import asymmetry: these fields MUST round-trip fully (prompt `template_variables` are re-derived on import per FR-RG-001). |
| No HTTP surface for YAML (CLI-only; action codes unwired) | CHANGE | v2 exposes export/import **as gated API operations** (FR-YM-005). |

### Reporting / compliance

| v1 capability | Verdict | Notes |
|---|---|---|
| Dashboard counts (global/scoped); model inventory (agents/tasks, champion-only) | KEEP | |
| Incidents union (governance ∪ quota breaches); override analysis; inventory graph | KEEP | |
| Regulatory frameworks + provisions; canonical requirements (center axis) | KEEP | Carried over; canonical vocabulary largely stable ([[0008-compliance-control-evidence-model]]). |
| Provision↔requirement bridge (many-to-many) | CHANGE | Now carries a **minimum-tier** mapping (ADR-0008). |
| Requirement↔**feature** bridge + feature hierarchy (plane→capability→feature) + coverage levels | DROP | Replaced by requirement↔**control**/evidence bridges per tier & phase — examiners consume controls + evidence, not features (ADR-0008). |
| Governance domains (grouping + per-domain maturity) | NEW | ADR-0008; v1 had no domain grouping or maturity. |
| Cumulative per-requirement tier ladders + normalized maturity scoring | NEW | ADR-0008. |
| Controls (typed; 4 lifecycle phases; enforcement action) + evidence specifications | NEW | ADR-0008; design/deploy/static/execution enforcement. |
| Evidence (append-only audit facts) + exception governance (approver / compensating / expiry) | NEW | ADR-0008; first-class audit records. |
| Intake → compliance obligation resolution | NEW | ADR-0008; intake resolves applicable canonical requirements → required controls/evidence. |
| Embedding identity (`embedding_config`, single current) | KEEP | |
| Seeded frameworks (SR 11-7, NAIC bulletin + eval tool, CO SB21-169, ORSA/ASOP/CAS) | KEEP | |
| NIST AI RMF / ISO 42001 | DEFER | Net-new for v2; metamodel supports them, seed content deferred. |
| Analytics logical-mart views (L2 over L1); feed views allow-list | KEEP | L1→materialized swap deferred but transparent via L2. |
| Report engine/composers/render (`report_run_log`; output formats) | KEEP | |
| Incremental feed (keyset cursor, allow-list guard) | KEEP | |
| Compliance/feed/metadata APIs | KEEP | |

### Cross-cutting seams & enums

| v1 capability | Verdict | Notes |
|---|---|---|
| `GovernanceCoordinator` wiring facade | CHANGE | Becomes the service composition root behind the API; no direct in-process consumer access. |
| `contracts/enums.py` (13 enums) + intake vocabularies | KEEP | Carried verbatim; names hardened to one snake_case convention (ADR-0005). |
| `MockContext` runtime mock seam (strict miss → hard fail) | KEEP | Runtime-side; governance only stores `mock_mode` / mock flags. |
| `entity_type` dead `pipeline` branch | DROP | Pipelines descoped from Verity. |
| Admin/Studio HTML surfaces; cookie persona; ungated Admin | CHANGE | UI is a client of the gated API; **all** surfaces enforced ([[user-authentication]] FR-012). |
| No-auth / no-authz / localhost-only posture | CHANGE | Replaced by Entra SSO + DB authorization, fail-closed, every surface ([[user-authentication]]). |
| Packaging & governed deployment | NEW (v2) | `.vtx`/`.vax` packages at champion promotion; lifecycle-gated, digest-pinned, insert-only deployment inventory (ADR-0006). |
| Tier-2 portable analytics store | NEW (v2) | Open Iceberg/Parquet customer-portable tier (ADR-0004/0007) — deferred build, modeled from day one. |

---

## What changes for production

This spec is local-dev-first. For production: deploy `verity-governance` on Kubernetes via
Helm (no Compose); run HA primary/replica Postgres with **authorization role resolution
reading the primary** (or an equivalently fresh shared store), never a lagging replica; use
a **shared session/role-cache store** (per-process caching is a fail-closed blocker for
multi-replica); source secrets from a vault/managed identity; switch identity to the
confidential Entra client over HTTPS ([[user-authentication]] *What changes for
production*); stand up the **Tier-2 portable analytics store** and swap the L2 logical-mart
views for materialized facts transparently (ADR-0004/0007); and front the async/batched
decision-log ingest with the production transport. The authorization model, controlled
vocabularies, lifecycle/gate semantics, packaging gates, and append-only invariants are
identical across environments — only configuration, transport, deployment substrate, and
storage tier differ.

# Feature Specification: Intake Depth Loop — Obligations, Asset Promotion & Change Proposals

**Feature Branch**: `003-intake-depth-loop`

**Created**: 2026-06-10

**Status**: Draft

**Input**: User description: "Feature 003 — the intake depth loop: the deferred downstream governance the intake points at. Resolve the compliance obligation set from an intake's assessment (FR-IN-014), gate registry-asset promotion on an approved intake + satisfied obligations (FR-IN-009), and handle post-approval change via re-approval change proposals (FR-IN-013). Build the backend + UI + seed over the existing schema."

## Overview

Feature 001 shipped the intake lifecycle (create → assess → tier-quorum approval) and 002 surfaced it in the portal, including the comprehensive risk assessment. What was deliberately deferred is the **downstream governance loop** the intake visibly points at — the "Obligations" nav link, the Risk & Obligations readout, and the promise that an approved intake is what *unlocks* a governed AI asset going live. This feature closes that loop:

1. **Obligations** — turn an intake's assessment into a concrete, tracked set of regulatory obligations (required controls + the evidence that satisfies them), with a compliance-exception path for justified waivers.
2. **Asset promotion gate** — link the registry assets that realize an intake's requirements, and block their promotion to "champion" (production) until the governing intake is approved and its obligations are satisfied or excepted.
3. **Change proposals** — let an approved intake be re-classified or materially changed through a fresh approval, forking the impacted assets so production is never silently altered.

The supporting database schema already exists (`specs/schema/`); this feature builds the **seed data** (the compliance metamodel), the **services/endpoints**, and the **portal UI**.

**Design principle — the metamodel is the source of truth (not bespoke logic).** Compliance requirements, their tier criteria, the controls that satisfy them, and the evidence that proves those controls are first-class, queryable data in one canonical metamodel: `regulatory_framework → regulatory_provision → provision_requirement → canonical_requirement → requirement_tier (cumulative — tier N implies 1..N) → requirement_control → control → evidence_specification`. Per-use-case resolution records *which* requirement tier applies (`intake_obligation.target_requirement_tier_id`) and whether it is met (evidence) or waived (`compliance_exception`, keyed by `waived_tier_level`). The acid test: *"has canonical requirement X at tier N been met for this application / use case?"* MUST be answerable by **querying the metamodel** — never by reading a bespoke flag. It follows that the **assessment questionnaire and the risk scoring should map to / derive from canonical-requirement tier criteria**, not a standalone hardcoded catalog. (Schema verified 2026-06-10: the full chain incl. `provision_requirement` exists; resolution anticipates an ontology/reasoner via `derivation_method` / `ontology_version` / `confidence`.) Reconciling 002's currently-bespoke assessment to this model is in scope — see FR-019..FR-022.

## Clarifications

### Session 2026-06-10

- Q: Metamodel seed breadth? → A: A **curated starter set** across the perimeter frameworks (EU AI Act, NAIC Model Bulletin, NY DFS CL-7, Colorado SB21-169, GDPR) — sufficient to resolve real obligations for the demo intakes, not exhaustive.
- Q: Registry-asset prerequisite for the promotion gate (P2)? → A: Build a **minimal registry-asset primitive** (create executable + version, advance lifecycle, link to a requirement) plus a **thin link/promote UI**; full Studio/Registry authoring deferred to a later feature.
- Q: Reconcile 002's bespoke assessment to the metamodel (FR-021)? → A: **Keep the 002 questionnaire UX; add a mapping layer** binding each scoring input/answer to canonical-requirement tier criteria, so resolution + scoring become metamodel-true (no full questionnaire rewrite).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Resolve and track an intake's obligations (Priority: P1)

A governance reviewer opens an assessed intake and sees its **Risk & Obligations** summary: the regulatory obligations that apply to *this* use case — derived from its risk tier, the application's governance domains, and the selected regulatory frameworks — each expressed as a required control with the evidence that would satisfy it. The reviewer marks an obligation satisfied by recording its evidence, or, when a control genuinely cannot be met, raises a **compliance exception** (a justified, time-boxed waiver) that a compliance/security approver signs off. The intake cannot reach a clean "approved + obligations resolved" state until every applicable obligation is either satisfied or excepted.

**Why this priority**: This is the heart of the deferred work and what the intake UI already advertises ("Obligations" nav, Risk & Obligations tab). It is independently valuable — it turns the computed risk tier into auditable, actionable compliance — and it is the prerequisite that the promotion gate (P2) checks against.

**Independent Test**: With the compliance metamodel seeded, open a `high`-tier assessed intake → the Risk & Obligations summary lists the resolved obligations with satisfied/outstanding status; record evidence against one (→ satisfied); raise + approve an exception against another (→ excepted); confirm the intake reports its obligation-resolution state. Fully testable without P2/P3.

**Acceptance Scenarios**:

1. **Given** an assessed intake with a computed tier and an application with governance domains + frameworks, **When** the assessment is saved, **Then** the system resolves the applicable obligation set and each obligation shows as `outstanding` with its required control and evidence specification.
2. **Given** an outstanding obligation, **When** the reviewer records the specified evidence, **Then** the obligation moves to `satisfied` and the change is recorded with attribution.
3. **Given** an obligation that cannot be met, **When** a reviewer raises a compliance exception (scope, justification, compensating controls, expiry) and a `compliance` or `security` approver signs it off, **Then** the obligation moves to `excepted` until the expiry.
4. **Given** an intake whose tier or frameworks change on re-assessment, **When** the assessment is re-saved, **Then** the obligation set is re-resolved — newly-applicable obligations appear `outstanding`, no-longer-applicable ones are withdrawn, and already-satisfied/excepted ones that remain applicable are preserved.
5. **Given** an expired exception, **When** the intake's obligation state is read, **Then** that obligation reads `outstanding` again (the waiver no longer counts).

---

### User Story 2 - Gate asset promotion on a governed intake (Priority: P2)

An engineer building the AI asset (an agent or task) for a use case **links** that asset to the intake's requirements, so the intake page rolls up which assets realize it and at what lifecycle stage. When the engineer tries to promote an asset to **champion** (the production pointer consumers resolve at runtime), the system enforces the **promotion gate**: the asset must be linked to an **approved** intake whose **obligations are satisfied or excepted**; otherwise the promotion is blocked with the specific unmet reason (intake not approved, or a named outstanding obligation). Early-stage experimentation (`draft`) is exempt so POCs stay friction-free.

**Why this priority**: This is where governance becomes load-bearing — the mechanism that prevents an ungoverned model from reaching production. It depends on P1 (the obligation state it checks) and on registry assets existing to link.

**Independent Test**: With an approved intake (P1 obligations satisfied) and a registry asset linked to its requirement, promote the asset `candidate → champion` → succeeds; with obligations outstanding or the intake unapproved, the same promotion is blocked with the unmet reason; a `draft`-stage asset promotes freely. Testable once a minimal registry asset exists to link.

**Acceptance Scenarios**:

1. **Given** a `draft`/`candidate` registry asset and an approved intake, **When** the engineer links the asset to one of the intake's requirements, **Then** a unique link edge is recorded and the intake's asset roll-up shows the asset and its stage.
2. **Given** an asset linked to an **approved** intake with all obligations satisfied/excepted, **When** the engineer promotes it beyond `candidate` (→ `champion`), **Then** the promotion succeeds.
3. **Given** an asset linked to an intake that is **not approved** (or has outstanding obligations), **When** promotion beyond `candidate` is attempted, **Then** it is **blocked** with the specific unmet reason.
4. **Given** an asset in `draft`, **When** promotion within early stages is attempted, **Then** the gate does **not** apply (free experimentation).
5. **Given** an asset already linked to an intake, **When** a second intake link is attempted, **Then** it is rejected (an asset links to at most one intake).

---

### User Story 3 - Change an approved intake via a change proposal (Priority: P3)

After an intake is approved and its assets are live, the use case changes — its risk is re-classified, or its business scope materially shifts. The owner raises a **change proposal** (a fresh approval scoped to the intake, of kind *risk reclassification* or *business change*) that selects the **impacted assets**. On approval, each impacted asset gets a **new `draft` forked** from its current champion, so production is never silently altered and the change re-enters the governed flow.

**Why this priority**: It keeps governance honest over time, but it is the least frequent path and depends on both P1 (re-resolved obligations) and P2 (the asset links it forks). It can ship after the core loop is proven.

**Independent Test**: With an approved intake that has a champion asset, raise a risk-reclassification change proposal selecting that asset → on quorum approval, the asset has a new `draft` forked from champion and the intake reflects the re-classification + re-resolved obligations. Testable independently of day-to-day promotion.

**Acceptance Scenarios**:

1. **Given** an approved intake with a champion asset, **When** the owner raises a change proposal selecting that asset and the tier quorum approves it, **Then** a new `draft` version of the asset is forked from its champion and the intake records the change.
2. **Given** a risk-reclassification change proposal, **When** it is approved, **Then** the intake's tier/obligations are re-resolved per P1.
3. **Given** a change proposal pending approval, **When** an unrelated promotion of an impacted asset is attempted, **Then** it is governed by the existing gate (the in-flight change does not bypass it).

---

### Edge Cases

- **Unseeded / partial metamodel**: if no canonical requirements apply to an intake's tier+domains+frameworks, the obligation set is empty and the intake is "no obligations" (not an error) — the promotion gate then needs only intake approval.
- **Exception expiry mid-flight**: an asset promoted while an exception was valid is not retroactively demoted, but the intake's obligation state reads `outstanding` again at expiry (surfaced for re-attestation).
- **Re-resolution conflicts**: re-resolving obligations must not silently drop a satisfied obligation that is still applicable, nor keep one that no longer applies.
- **Linking a deprecated/champion asset**: linking is restricted to early-stage assets not already linked; attempts otherwise are rejected with a clear reason.
- **Change proposal with no impacted assets**: allowed (a pure re-classification) — re-resolves obligations without forking anything.
- **Promotion-gate vs draft-exemption boundary**: the exempt stage(s) must be unambiguous so "free POC" can't be used to ship to production.

## Requirements *(mandatory)*

### Functional Requirements

**Obligation resolution (P1)**

- **FR-001**: The system MUST resolve the set of applicable regulatory obligations for an intake from its computed risk tier, its application's governance domains, and its selected regulatory frameworks, expressing each as a required control plus the evidence specification that satisfies it (FR-IN-014).
- **FR-002**: The system MUST re-resolve the obligation set whenever the assessment is re-saved (tier/frameworks/domains may change), preserving still-applicable satisfied/excepted obligations and withdrawing no-longer-applicable ones.
- **FR-003**: Users MUST be able to record evidence against an outstanding obligation, moving it to `satisfied` with attribution and timestamp.
- **FR-004**: Users MUST be able to raise a compliance exception against an obligation (scope, justification, compensating controls, expiry); it becomes effective only after sign-off by a holder of the `approve_exception` action (compliance or security), after which the obligation reads `excepted` until expiry.
- **FR-005**: An expired exception MUST cause its obligation to read `outstanding` again.
- **FR-006**: The intake MUST expose an obligation-resolution rollup (counts/state) such that "all applicable obligations satisfied or excepted" is a determinable condition.
- **FR-007**: The portal MUST render a **Risk & Obligations** surface on the intake showing the computed tier/materiality, each resolved obligation with its control, evidence spec, source provision, and status, plus the affordances to record evidence and raise/track exceptions (gated by role).

**Asset linking & promotion gate (P2)**

- **FR-008**: The system MUST support linking a registry asset to an intake requirement, unique on `(intake, requirement, entity type, entity id, relationship)`; an asset MAY link to **at most one** intake and only while in an early lifecycle stage and not already linked (FR-IN-009).
- **FR-009**: The intake MUST roll up its linked assets and each asset's most-advanced lifecycle stage, flagging lower-stage versions.
- **FR-010**: The system MUST enforce a **promotion gate**: advancing an asset beyond the exempt early stage(s) to champion MUST require a link to an **approved** intake whose obligations are all satisfied or excepted; a blocked promotion MUST state the specific unmet reason (not approved / named outstanding obligation).
- **FR-011**: The exempt early stage(s) MUST be free of the gate so experimentation/POC is unblocked.
- **FR-012**: The portal MUST let an authorized engineer link/unlink an asset to an intake requirement and attempt promotion, surfacing the gate result (success or unmet reason).

**Change proposals (P3)**

- **FR-013**: The system MUST support a **change proposal** — an approval scoped to an approved intake, of kind *risk reclassification* or *business change*, selecting impacted assets — that uses the tier→required-roles quorum (FR-IN-013).
- **FR-014**: On change-proposal approval, each impacted asset MUST get a new `draft` forked from its current champion (or most-advanced stage), and a risk-reclassification MUST re-resolve the intake's obligations (P1).
- **FR-015**: The portal MUST let an intake owner raise a change proposal, select impacted assets, and track its approval — reusing the shared sign-off gate (kind extended).

**Cross-cutting**

- **FR-016**: All obligation, evidence, exception, link, promotion, and change-proposal actions MUST be role-gated via the action matrix and recorded in the append-only history (who/when/what), consistent with the existing governance audit model.
- **FR-017**: The compliance metamodel (canonical requirements, controls, evidence specifications, provision mappings, requirement→tier and requirement→control mappings) MUST be **seeded** as governed reference/seed data (separate from demo data) — a **curated starter set** spanning the perimeter frameworks (EU AI Act, NAIC Model Bulletin, NY DFS CL-7, Colorado SB21-169, GDPR), sufficient to resolve real obligations for the demo intakes (not exhaustive).
- **FR-018**: This feature MUST include a **minimal registry-asset primitive** — create an executable + version, advance its lifecycle stage, and link it to an intake requirement — plus a **thin link/promote UI** that exercises the promotion gate. The full Studio/Registry authoring experience is deferred to a later feature.

**Metamodel as the source of truth (cross-cutting principle — your directive)**

- **FR-019**: Compliance requirements, tier criteria, controls and evidence specifications MUST be expressed **only** in the canonical metamodel; no governance decision may depend on a bespoke/hardcoded requirement list. The obligation set for an intake MUST be resolved by **querying the metamodel** (requirement → applicable tier → controls → evidence specs, with source provisions) from the intake's tier, governance domains, and frameworks.
- **FR-020**: Obligation satisfaction MUST be **queryable and tier-cumulative**: for any `(entity, canonical requirement, tier N)`, the system MUST answer **met / outstanding / excepted** by evaluating, against the metamodel, whether the controls mapped to tiers `1..N` have satisfying evidence or a valid (unexpired) exception covering that tier. *Acid test: "has canonical requirement X at tier 2 been met?" returns a definitive answer from metamodel queries alone — no bespoke flag.*
- **FR-021**: The assessment questionnaire and the risk-tier scoring MUST map to / derive from canonical-requirement tier criteria, so that completing the assessment both computes the tier **and** identifies the applicable requirement tiers — rather than a standalone bespoke catalog. **002's existing sectioned questionnaire is retained**; a **mapping layer** binds each scoring input / answer to canonical-requirement tier criteria so obligation resolution and tier scoring are metamodel-true. A full questionnaire rewrite is out of scope.
- **FR-022**: Application-level and use-case-level compliance detail (regulatory perimeter, governance domains, applicable requirements) MUST read from the **same** metamodel vocabulary, so application, use case, and risk scoring share one canonical definition (no per-surface bespoke concepts).
- **FR-023** (Compliance Model browser): The portal MUST provide a **read-only Compliance Model browser** (in the Compliance app) that surfaces the metamodel navigably — frameworks → provisions (citations), canonical requirements (by domain), each requirement's cumulative tier ladder, and per tier its controls (phase · type · enforcement) + evidence specifications — with reverse views (which requirements a provision sources; which controls/evidence prove a requirement) and a coverage view (requirements per domain × framework × tier). This validates and helps maintain the governed source of truth. **In-UI editing/versioning of the metamodel is out of scope here** (a later governed-editing follow-on) — changing the source of truth must itself be a controlled, audited, versioned action.

### Key Entities *(include if feature involves data)*

- **Canonical requirement**: a normalized regulatory obligation (e.g. "bias testing for consumer-facing decisions"), sourced from one or more regulatory provisions, applicable to certain risk tiers and governance domains; maps to one or more controls.
- **Control & evidence specification**: the concrete measure that satisfies a requirement (at a lifecycle phase) and the kind of evidence that proves the control is in place.
- **Intake obligation (resolution)**: the per-intake instance of an applicable requirement, with state `outstanding | satisfied | excepted` and a link to recorded evidence or an exception.
- **Compliance exception**: a justified, time-boxed waiver of a control for an intake — scope, justification, compensating controls, expiry, status — requiring `approve_exception` sign-off.
- **Registry asset (executable) & version**: the governed, versioned AI unit (agent/task/…) with a lifecycle stage; a champion version is the production pointer.
- **Intake↔asset link**: an edge from an intake requirement to a registry asset (with relationship type), unique and at most one intake per asset.
- **Change proposal**: an intake-scoped approval (risk reclassification / business change) selecting impacted assets; on approval forks new asset drafts.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For an assessed intake, the applicable obligation set is resolved and visible immediately on assessment save (no separate manual step); 100% of resolved obligations show a control, an evidence specification, and a source provision.
- **SC-002**: A reviewer can take an obligation from `outstanding` to `satisfied` (record evidence) or `excepted` (raise + approve a waiver) entirely within the intake's Risk & Obligations surface, in under 2 minutes per obligation.
- **SC-003**: 100% of attempts to promote a governed asset to champion are correctly allowed or blocked by the gate; every block states a specific, actionable unmet reason; no governed asset reaches champion without an approved intake + resolved obligations.
- **SC-004**: A draft-stage asset can always be advanced within the exempt stages without governance friction (0 gate blocks on exempt transitions).
- **SC-005**: A change proposal, once approved, forks a new draft for every selected impacted asset (no champion mutated in place) and re-resolves obligations for a reclassification — verifiable end-to-end with mock auth and two distinct roles (separation of duty).
- **SC-006**: The loop is demonstrable end-to-end with seeded data: assess → resolve obligations → satisfy/except → approve intake → link asset → promote (gate passes) → raise change proposal → fork — without hand-editing the database.
- **SC-007**: For any seeded canonical requirement and tier, *"is requirement R at tier N met for intake/application X?"* is answerable by a **metamodel query** (no bespoke flag) and returns met/outstanding/excepted consistent with recorded evidence and unexpired exceptions — verified across at least the high-tier demo intake. No governance surface (application, use case, scoring) defines a compliance concept outside the canonical metamodel.

## Assumptions

- **Schema exists; this feature seeds + builds over it.** The compliance metamodel, obligation, exception, executable/version lifecycle, champion, and intake↔asset link tables already exist in `specs/schema/`; no new schema design is expected beyond at most a small grouping table for change proposals (per 001's design note).
- **Inherent tier is not lowered by mitigations.** Obligations are resolved from the inherent EU-AI-Act tier; evidence/exceptions *satisfy* obligations and track residual risk separately — they do not change the tier (001 design decision).
- **Reuses the shared approval primitive.** Compliance-exception sign-off and change-proposal approval reuse the existing approval-request + sign-off + quorum machinery (and the portal's shared sign-off gate), with new request kinds / a new action (`approve_exception`).
- **P3 (change proposals) is in scope as the P3 slice** but may be deferred at planning if P1+P2 prove larger than expected; P1 is the MVP.
- **Mock-auth testable end-to-end**, mirroring 001/002 acceptance — an authoring role plus a compliance/security approver (separation of duty).
- **Registry breadth is bounded** (see FR-018): only enough asset capability to demonstrate linking + the promotion gate; full agent/task authoring (Studio) is a separate, later feature.
- **Metamodel is reasoner-ready but resolves deterministically here.** The schema carries `derivation_method` / `ontology_version` / `confidence` for a future ontology/reasoner; P1 resolves obligations via deterministic metamodel queries (`manual` / rule-derived) — an automated reasoner is a later enhancement, not required by this feature.
- **002's assessment is currently bespoke** (the `FIELDS` catalog + `compute_tier`); reconciling it to the metamodel (FR-021) is in scope via a **mapping layer** (each answer / scoring input → canonical-requirement tier criteria) rather than a full rewrite, so the shipped UX is preserved while resolution + scoring become metamodel-true.
- **Schema verification (2026-06-10)**: the full chain — `regulatory_framework → regulatory_provision → provision_requirement → canonical_requirement → requirement_tier → requirement_control → control → evidence_specification`, plus `intake_obligation(_resolution)` and `compliance_exception` (tier-precise) — exists and supports the queryable, tier-cumulative model; no new schema design is anticipated for the metamodel itself.

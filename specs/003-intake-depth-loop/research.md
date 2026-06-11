# Phase 0 Research: Intake Depth Loop

All spec clarifications were resolved in the Clarifications session (2026-06-10). This file records the **design decisions** for the load-bearing mechanisms, each grounded in the existing schema and Constitution Principle VIII.

## D1 — Obligation resolution query (the heart of Principle VIII)

**Decision**: Resolve an intake's obligations deterministically from the metamodel in three steps:
1. **Applicable requirements** = canonical requirements (current versions) that are (a) mapped via `provision_requirement` to a `regulatory_provision` of one of the intake's **frameworks**, AND (b) whose `governance_domain_code` is among the **application's governance domains**.
2. **Applicable tier per requirement** = map the intake's inherent risk tier to a `requirement_tier.tier_level`, **floored** at the provision's minimum tier and **capped** at the requirement's max tier. Map: `minimal→1, limited→2, high→3` (cumulative — tier N pulls in the controls of tiers 1..N). `unacceptable` never resolves (the intake is auto-rejected upstream).
3. **Obligations** = for each applicable requirement at its target tier, the `control`s mapped via `requirement_control` for tiers `1..target` (cumulative) and each control's `evidence_specification`s.
   Persist as one `intake_obligation_resolution` (with `derivation_method='manual'`, `ontology_version` stamped) + one `intake_obligation` per applicable requirement (carrying `canonical_requirement_id`, `governance_domain_code`, `target_requirement_tier_id`).

**Rationale**: Uses only metamodel tables — no bespoke requirement list (FR-019). The risk-tier→tier-level map is the single formal binding between the EU-AI-Act inherent tier and the cumulative requirement ladder; everything else is pure joins. Reproducible (`ontology_version`) and reasoner-ready (`derivation_method` can later become `reasoner_recommended`).

**Alternatives**: (a) Hardcode obligations per tier in Python — rejected (violates FR-019/Principle VIII). (b) Resolve from frameworks only, ignoring domains — rejected (over-resolves; Principle VIII requires the domain axis).

## D2 — Tier-cumulative queryability (the acid test, FR-020/SC-007)

**Decision**: "Is requirement R at tier N met for intake X?" is answered by one query: take R's controls for tiers `1..N`; the requirement is **met** iff every such control has either (a) satisfying evidence recorded against the intake's obligation, or (b) a valid (unexpired, `approved`) `compliance_exception` whose `waived_tier_level >= N`. Else **outstanding** (or **excepted** when fully covered by exceptions). Exposed as `GET /requirements/{code}/status?intake={id}&tier=N`.

**Rationale**: Tier cumulativity (`tier N implies 1..N`) is in the schema's own comment; satisfaction is purely a function of evidence + unexpired exceptions vs the controls for tiers ≤ N — a metamodel query, no bespoke flag.

## D3 — Assessment → metamodel mapping layer (FR-021, "keep the UX")

**Decision**: Keep 002's sectioned questionnaire + `compute_tier`; add a **data-driven mapping layer**, not bespoke code:
- The **tier** the assessment computes is the resolution input (via the D1 risk-tier→tier-level map) — this is the primary binding.
- A small **seeded signal→requirement trigger set** maps specific high-signal answers to specific canonical requirements at a tier (e.g. `solely_automated=true → GDPR-Art22 requirement`; `pii_presence=special_category → DPIA/minimization requirement`; `disparate_impact_tested` relates to the fairness-testing requirement). Stored as seed data keyed by canonical-requirement code, so the mapping is metamodel-true and editable without code.

**Rationale**: Preserves the shipped UX (FR-021 decision) while making resolution + scoring trace to canonical requirements. Keeping the triggers as **seed data** (not `if` statements) honors FR-019.

**Alternatives**: full questionnaire rewrite from requirement criteria (rejected per clarification — too large); consume tier only and ignore answer-specific triggers (rejected — loses the special-category/Art-22 obligations the answers imply).

## D4 — Promotion gate point

**Decision**: The gate fires on advancing an asset version to a **production-reaching lifecycle stage** — `challenger` or `champion` (Principle VII: challenger = prod shadow/ab, champion = live). `draft → candidate → staging` (experimentation + non-prod) are **exempt**. To advance to challenger/champion the version's executable MUST be linked to an **approved** intake whose obligations are all satisfied or excepted; otherwise blocked with the specific unmet reason.

**Rationale**: Blocks at the point a model could affect production (Principle VIII "block at the point of occurrence"), while keeping POC/staging friction-free. Satisfies 001's "moving beyond candidate to champion requires an approved intake" — champion is gated, and so is challenger (the other prod stage 001 predates).

**Alternatives**: gate only at champion (rejected — challenger runs in prod); gate at candidate→staging (rejected — over-blocks non-prod staging).

## D5 — Minimal registry primitive (P2 scope)

**Decision**: Reuse the existing `executable` / `executable_version` (immutable SCD-2) / `champion_assignment` tables + the `entity_lifecycle_current` / `entity_champion_current` views. Build only: create an executable (kind `agent`|`task`), create a version, advance its lifecycle stage (append a lifecycle event), and assign champion. **No** bindings, packaging (`.vtx`/`.vax`), compatibility, or deployment — those stay deferred to the Registry/Studio feature.

**Rationale**: Exactly enough to have a versioned asset with a real lifecycle stage to link and promote, so the gate (D4) is demonstrable. Bounded per the clarification.

## D6 — Compliance exception lifecycle

**Decision**: `compliance_exception` is **self-contained** (it carries `approver_actor_id`, `exception_status`, `signed_as_role_code`, `expires_at`) — it does **not** go through the `approval_request` quorum. Flow: raise (`requested`, `opened_by`, compensating controls + rationale + expiry) → a holder of the new `approve_exception` action (compliance/security) signs off (`approved`, sets approver/role) → it counts toward obligation satisfaction until `expires_at`, after which the obligation reads `outstanding` again. Status transitions append to `audit.status_transition`.

**Rationale**: A waiver is a single-approver, scoped, expiring record (Principle VIII "first-class, append-only exception"), not a multi-role quorum — the schema models it directly. Reusing `approval_request` would conflate two different governance objects.

## D7 — Change-proposal modeling (P3)

**Decision**: Reuse the shared `approval_request` primitive with **new kinds** `risk_reclassification` / `business_change`, scoped via `target_intake_id`, using the FR-IN-005 tier quorum + the portal's shared sign-off gate. Impacted assets are recorded in **one small grouping table** `change_proposal_asset (approval_request_id, executable_id)` — the single candidate schema growth (Principle II review). On approval: for each impacted asset, fork a new `draft` `executable_version` from its current champion (or most-advanced stage); a `risk_reclassification` re-runs D1 resolution.

**Rationale**: Maximizes reuse (approval + sign-off gate already shipped in 002); the grouping table is the minimal addition 001's design note anticipated. Forking (never mutating champion) keeps production immutable + auditable.

## D8 — New auth-matrix actions

**Decision**: Add to `auth/matrix.py`: `record_evidence` (governance authoring — the approval roles), `approve_exception` (`compliance`, `security` — per 001 Q), `link_asset` (`engineer`, `ai_governance`), `propose_change` (governance). Reuse existing `author_registry` (create executables/versions) and `promote_registry` (lifecycle advance / the gate) and `reclassify_risk` (change proposals). Every action keeps the fail-closed matrix invariant + `test_matrix_total_coverage`.

**Rationale**: Separation of duty (exception approver ≠ raiser; promotion gated independently of obligation authoring); consistent with the existing action vocabulary and FR-016 (everything role-gated + audited).

## D9 — Metamodel seed (curated starter)

**Decision**: Author a governed seed (in `specs/schema/seed/`, separate from `./dev demo`) of: regulatory provisions + `provision_requirement` mappings + canonical requirements (with governance domains) + cumulative requirement tiers + controls (across the four phases) + evidence specifications, for a **curated** set spanning EU AI Act, NAIC Model Bulletin, NY DFS CL-7, Colorado SB21-169, GDPR — sized to resolve real, non-trivial obligation sets for the demo intakes (`high`/`limited`/`minimal`). Not exhaustive.

**Rationale**: Per clarification; gives a believable, queryable metamodel without a multi-week curation effort. The seed is the governed center axis (Principle VIII); demo intakes consume it.

<!--
SYNC IMPACT REPORT
==================
Version change: (template, unversioned) → 1.0.0
Bump rationale: Initial ratification — placeholder template populated with the first
  concrete set of governing principles. MINOR/PATCH not applicable to first adoption.

Modified principles: N/A (initial adoption)
Added principles:
  - I. Spec Precedes Implementation
  - II. Schema Is the Hardened Foundation
  - III. Legacy Is Reference, Never Source
  - IV. API-Only Governance Boundary
  - V. Uniform Bindings, Agent-Only Tools
  - VI. Equity-Research Slice First, Parity Committed
Added sections:
  - Technical Standards & Constraints
  - Development Workflow & Quality Gates
  - Governance

Templates requiring updates:
  - ✅ .specify/templates/plan-template.md — "Constitution Check" gate references this
       file generically; reviewed, aligns, no edit required.
  - ✅ .specify/templates/spec-template.md — scope/requirements structure compatible;
       reviewed, no edit required.
  - ✅ .specify/templates/tasks-template.md — task categories (schema-first foundation,
       optional tests) compatible; reviewed, no edit required.
  - ✅ .specify/templates/checklist-template.md — reviewed, no edit required.
  - ⚠ .specify/templates/commands/ — directory absent; no command files to reconcile.

Deferred / follow-up TODOs:
  - specs/pcr/verity_v2_pcr.md is named as authoritative intent but does not yet exist
    in the repo. Create it (or correct the path) before it can be cited by specs.
  - specs/schema/verity_schema.sql is named as the canonical hardened schema but
    specs/schema/ is currently empty. The hardened schema must be produced and reviewed
    (per ADR-0005) before downstream implementation begins.
-->

# Verity v2 Constitution

Verity v2 is an AI governance platform for regulated insurance environments. This
constitution is the supreme source of project rules; where it conflicts with habit,
convenience, or v1 precedent, this document wins.

## Core Principles

### I. Spec Precedes Implementation

No code is written without a reviewed spec. Every feature begins as a spec artifact
under `specs/`, is reviewed, and only then implemented. The Product Change Request
(`specs/pcr/verity_v2_pcr.md`) is the authoritative statement of intent; Architecture
Decision Records under `specs/adrs/` govern cross-cutting decisions and supersede the
PCR where they explicitly say so (e.g. ADR-0005 overrides the PCR's verbatim-schema
stance). Implementation MUST trace to an approved spec.

**Rationale**: In a regulated domain, traceability from intent → decision → spec → code
is a compliance requirement, not a nicety. Spec-first prevents the undocumented drift
that motivated the v2 rebuild.

### II. Schema Is the Hardened Foundation

The canonical database schema is `specs/schema/verity_schema.sql`. The v1 schema is a
**reference input** to a clean redesign, NOT carried forward verbatim. The v2 schema is
hardened per ADR-0005: one consistent naming convention across tables, columns, enums,
indexes, and foreign keys; proper structure (explicit primary/foreign keys, correct
types, NOT NULL and check constraints encoding real invariants); insert-only /
append-only transactional records with current state expressed as a view over the latest
event; Tier-1 system-of-record vs Tier-2 bulk-log tables made explicit; and no silent
capability loss — every v1 capability maps to a v2 equivalent or is recorded as
dropped-with-reason. The hardened schema MUST be reviewed before any downstream service,
model, or API depends on it.

**Rationale**: Everything is built on the schema; inconsistency or tech debt there
propagates into every model, query, and API field. Hardening is the single
highest-priority concern (ADR-0005) and is front-loaded by design.

### III. Legacy Is Reference, Never Source

`../verity-legacy/` is read-only and MUST NEVER be imported from — no code, modules, or
artifacts are copied or linked from it into v2. Functional behavior MAY be drawn from
legacy as a behavioral reference, but only with improvements and enhancements applied,
never as a verbatim port. Where legacy behavior is intentionally not reproduced, it MUST
be recorded as dropped-with-reason (the v1-capability-inventory guard), so capability is
never lost silently.

**Rationale**: v2 exists to escape v1's accreted inconsistency. Treating legacy as a
source rather than a reference would re-import the very debt the rebuild is meant to
shed.

### IV. API-Only Governance Boundary

The harness communicates with governance exclusively through the governance API over
HTTP (ADR-0003). The harness MUST NOT hold governance database credentials and MUST NOT
access the governance database directly. All reads (registry, champion artifact
metadata) and all writes (run lifecycle, decision log, model-invocation logs, HITL
overrides) go through API endpoints. The governance API owns every write to the storage
layer and hides storage topology from callers.

**Rationale**: A hard API seam keeps central DB credentials out of every application,
bounds blast radius, gives one enforcement point for auth/validation/audit, and lets the
storage topology evolve behind the API without touching any harness.

### V. Uniform Bindings, Agent-Only Tools

Inputs and outputs are declared as **Source Binding** (input resolved before the entity
runs) and **Target Binding** (output written after it runs). These two binding kinds
apply identically to tasks and agents — "agent binder parity" — with no separate binding
mechanism per entity kind. The v1 names (`source_binding` / `write_target`) are retired;
the v2 names are used everywhere: schema, models, API field names, UI, and docs. Tool
calls and MCP integration are **agent-only** capabilities; tasks have neither.

**Rationale**: A single, consistently-named binding grammar (per the binding-grammar
contract and ADR-0005) removes a whole class of v1 naming confusion and makes tasks and
agents reason-about-able with one mental model.

### VI. Equity-Research Slice First, Parity Committed

The equity-research vertical slice is built first as the proving ground for the v2
architecture. Full 195-API parity with v1 is a **committed later phase**, not an
abandoned goal — narrowing initial scope MUST NOT silently drop committed capability.
Work that defers a v1 capability records it as deferred (not dropped) so the parity
backlog stays honest.

**Rationale**: A thin, end-to-end slice validates the schema, the API boundary, and the
binding model under real load before scaling to the full surface, while the explicit
parity commitment prevents "MVP" from becoming a euphemism for permanent capability loss.

## Technical Standards & Constraints

- **Service decomposition**: the system is composed of four services —
  `verity-governance`, `verity-runtime`, `verity-vault`, and `verity-relay`. New
  responsibilities MUST be placed in the service that owns that concern, not bolted onto
  the nearest one.
- **Backend stack**: Python 3.12, FastAPI, psycopg v3 (async), **raw SQL** (no ORM),
  Pydantic v2. These are mandatory; deviations require an ADR.
- **UI stack**: React with TypeScript, built against the Verity design system. The
  visual design is authoritative in `specs/ui/design-system.md` and its sibling examples
  in `specs/ui/`; UI work MUST conform to it.
- **Deployment target**: Kubernetes via Helm. There are **no Docker Compose
  assumptions** — local or otherwise; tooling and docs MUST NOT presuppose Compose.
- **Environments**: always use the project-local `.venv`. Dependencies MUST NEVER be
  installed globally.

## Development Workflow & Quality Gates

- **Spec → review → implement** is the only path to code (Principle I). Cross-cutting
  decisions are captured as ADRs under `specs/adrs/` before implementation depends on
  them.
- **Schema gate**: no service, model, or API may depend on the schema until the hardened
  `specs/schema/verity_schema.sql` is reviewed (Principle II).
- **Capability gate**: any deferral or removal of a v1 capability is recorded
  (deferred-with-reason or dropped-with-reason) — never silent (Principles III, VI).
- **Boundary gate**: harness ↔ governance changes are reviewed against the API-only rule
  (Principle IV); a change that introduces direct DB access from the harness is rejected.
- **Naming gate**: schema, model, API, and UI identifiers follow the hardened naming
  convention and the binding grammar (Principles II, V).
- **Plans** must complete the Constitution Check gate in `plan-template.md` against these
  principles before Phase 0 research, and re-check after design.

## Governance

This constitution supersedes all other practices and conventions on the project. When
any spec, plan, ADR, or code conflicts with it, this document prevails — except where an
explicitly-accepted ADR amends a principle, in which case the ADR is folded back into
this constitution at the next amendment.

**Amendment procedure**: amendments are proposed as a spec/PR change to this file,
reviewed by the Product Owner, and accompanied by a Sync Impact Report and any required
updates to dependent templates and docs. Merging the amendment ratifies it.

**Versioning policy** (semantic):
- **MAJOR**: backward-incompatible governance changes — removing or redefining a
  principle in a way that invalidates existing compliance.
- **MINOR**: a new principle or section, or materially expanded guidance.
- **PATCH**: clarifications, wording, and non-semantic refinements.

**Compliance review**: every PR and review verifies compliance with these principles;
the plan-template Constitution Check is the standing gate. Complexity or deviation from
the technical standards MUST be justified in the plan's Complexity Tracking and, where
cross-cutting, backed by an ADR.

**Version**: 1.0.0 | **Ratified**: 2026-05-29 | **Last Amended**: 2026-05-30

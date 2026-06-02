<!--
SYNC IMPACT REPORT
==================
Version change: 1.2.0 → 1.3.0 (latest amendment)
History:
  - (template, unversioned) → 1.0.0 — initial ratification, first concrete principles.
  - 1.0.0 → 1.1.0 — MINOR: relaxed the Docker Compose standard. Compose is now permitted
    as a local-dev convenience (was: forbidden outright) provided K8s/Helm remains the
    source of truth and every component has a clear K8s path. Per product-owner directive
    2026-05-30.
  - 1.1.0 → 1.2.0 — MINOR: added Principle VII (Governed Deployment & Reproducible
    Execution; ADR-0006), a decision-log/analytics tiering + customer-portable-export
    Technical Standard (ADR-0004/0007), and Development-Workflow deployment + sequencing
    gates (PCR §6 feature-driven roadmap). Per product-owner directive 2026-05-30.
  - 1.2.0 → 1.3.0 — MINOR: added Principle VIII (Continuous, Control-and-Evidence-Based
    Compliance; ADR-0008) and a Development-Workflow "Compliance gate". Per product-owner
    directive 2026-05-30.

Modified principles / sections:
  - 1.1.0: Technical Standards — "Deployment target" bullet amended (Compose for local dev).
  - 1.2.0: + Principle VII; + Technical Standards "Decision-log & analytics tiering" bullet;
    + Development Workflow "Deployment gate" and "Sequencing" entries.
  - 1.3.0: + Principle VIII (compliance as controls + evidence, continuous, phase-enforced);
    + Development Workflow "Compliance gate".
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
  - specs/pcr/verity_v2_pcr.md exists (v0.2). It predates ADR-0005/binding-grammar on
    two points the constitution overrides: it states the schema is "carried verbatim"
    (§1/§9) and that I/O grammar is source_binding/write_target (§1). A PCR refresh to
    v0.3 SHOULD fold in the hardening decisions; until then the constitution + ADRs govern.
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

### VII. Governed Deployment & Reproducible Execution

Deployment is mediated by the governance control plane — never out-of-band. Tasks and
agents ship as **packages** (`.vtx`/`.vax`); each package declares the **harness image(s)**
it is compatible with **by immutable digest**, and the registry enforces compatibility so
an incompatible package×image combination cannot be deployed. A package's **lifecycle
state gates the environment and mode** it may run in: `staging` → non-prod only;
`challenger` → prod in **`shadow`** run-mode (outputs suppressed, zero impact) or **`ab`**
run-mode (full I/O on a scoped sample); `champion` → any environment, `live`; `deprecated`
→ `locked`, any environment, audit/replay only (and **restorable via rollback**). `shadow`
mode means the harness executes and logs decisions but its Target Bindings are suppressed
(no business side effects). The platform keeps an insert-only **deployment inventory** of what runs
where. Together these make any past execution **reproducibly replayable** from its image
digest, package, and decision log.

**Rationale**: In a regulated setting, "show exactly what ran, and prove nothing else
could have" is a hard requirement. Governed, compatibility-gated deployment with an
inventory is what makes it provable; out-of-band deploys or mutable-tag images would make
the audit trail and the safety rails fiction. (ADR-0002, ADR-0006.)

### VIII. Continuous, Control-and-Evidence-Based Compliance

Compliance is expressed as **controls and evidence**, not product features, and is
enforced **continuously** across the asset lifecycle — never periodically at review
cycles. Regulatory provisions map (many-to-many, by minimum tier) to a **stable center
axis of canonical requirements**; each canonical requirement belongs to one or more
**governance domains** and defines a cumulative **tier ladder**; each requirement binds,
per tier and per lifecycle phase, to **controls** (each with an enforcement action) and
**evidence specifications**. Controls enforce at four phases — **design-time, deploy-time,
static/model, and execution** — and block non-compliant activity at the point of
occurrence. Every **exception** is a first-class, append-only audit record (waived tier,
affected requirement, named approver, compensating controls, expiry). From **intake**
onward, the platform resolves which canonical requirements apply and drives the required
controls and evidence through the asset's life; maturity is scored per domain, normalized
across variable tier ladders.

**Rationale**: Examiners ask for the control and the evidence, not a feature list. A
stable canonical center lets frameworks and controls evolve independently while
obligations stay rationalized and de-duplicated; continuous, phase-based enforcement with
audited exceptions is what makes "controlled non-compliance" a defensible position. The
four phases map onto intake/compose, the deployment gate (Principle VII), the champion
package, and the runtime harness. (ADR-0008.)

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
- **Deployment target**: Kubernetes via Helm is the **source of truth** for all service
  configuration and the production substrate. Docker Compose is permitted **only as a
  local-development convenience** and MUST NOT be the source of truth for service config;
  any service or component introduced for local dev MUST carry a clear, documented path
  to its K8s/Helm equivalent. Specs and tooling MUST NOT treat Compose as the deployment
  model or let Compose-only assumptions leak into service design.
- **Environments**: always use the project-local `.venv`. Dependencies MUST NEVER be
  installed globally.
- **Decision-log & analytics tiering**: decision and model-invocation logs are
  append-only and ingested via the governance API's async/batched path (never a
  synchronous bottleneck on execution). Analytics is a **separate, latency-tolerant read
  tier** — reports run as jobs — persisted in an **open columnar format (Iceberg/Parquet
  on object storage)** with a documented **customer-portable export** to external
  warehouses. The query engine is a tunable; the tiering, append-only model, and
  portability are not. (ADR-0004, ADR-0007.)

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
- **Deployment gate**: a deploy that bypasses the governance control plane, pins a harness
  image by mutable tag rather than digest, or violates the lifecycle→environment matrix is
  rejected (Principle VII; ADR-0006).
- **Compliance gate**: an AI asset cannot advance to a lifecycle state whose required
  controls — for the canonical requirements applicable at its governance domains and tier —
  are unmet or lack captured evidence, unless a valid, unexpired exception is registered
  (Principle VIII; ADR-0008).
- **Sequencing**: capability work follows the feature-driven, vertical-slice roadmap in
  PCR §6 (intake → registry/compose → harness/packaging/deploy → decision logging →
  testing → lifecycle/promotion → prod-like run → compliance → reporting), with the
  hardened schema as the foundation and infrastructure pulled in per phase (Principle VI).
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

**Version**: 1.3.0 | **Ratified**: 2026-05-29 | **Last Amended**: 2026-05-30

# ADR-0001 — Rebuild Verity v2 from a clean foundation

- **Status:** Accepted
- **Date:** 2026-05-29
- **Deciders:** Product Owner (Anil)
- **Supersedes:** none

---

## Context

Verity v1 is a working AI-governance platform for P&C insurance: ~33K lines in the
`verity` package, ~9K in the UW demo, ~11K across 89 test files, an 81-table
PostgreSQL schema, ~195 API endpoints, and a standalone worker that already claims
runs with `FOR UPDATE SKIP LOCKED` plus heartbeats. The data layer (schema, raw SQL
query files, Pydantic models, async psycopg v3) is clean and correct.

Two pressures push toward a fresh start rather than continued enhancement:

1. **The harness model changes core flows.** The target state is an
   application-hosted execution container (the "harness") that runs deployed
   `.vax`/`.vtx` champion packages (see [[0002-execution-model]]). This changes how
   promotion produces a deployable artifact, how a run is claimed, and how entity
   configuration reaches the execution environment. Retrofitting this into v1's
   in-process promotion and worker paths is exactly the kind of break-one-fix-another
   churn we want to leave behind.

2. **Spec-first only works from a clean base.** v2 is committed to
   specification-driven development — the spec precedes the code. Writing specs to
   describe code that already exists is documentation, not specification. The
   discipline holds only when we start from specs.

A full assessment of v1 confirmed it is *not* a tangled monolith — the database pool
is dependency-injected, the coordinator is a thin 46-line wiring class, and the
worker is already a separate process. So the rebuild is a deliberate choice to reset
the foundation and adopt the harness model cleanly, **not** a rescue of unsalvageable
code.

## Decision

Build **Verity v2 as a new, spec-first codebase.** v1 is retained, unmodified, as the
reference implementation.

Concretely:

- **The schema is hardened, not copied verbatim.** This is the **top-priority**
  concern (see [[0005-schema-hardening]]). v1's schema is the *reference input* to a
  clean redesign — consistent naming, proper table structure, no carried-over tech
  debt. Transactional operations adopt **insert-only / append-only** behavior, and the
  high-volume logging tables move to a **tiered storage** model (see
  [[0004-storage-architecture]]). We do **not** treat v1's `schema.sql` as canonical
  the way the PCR assumed.
- **Carry forward selectively, as code.** The Pydantic models and well-isolated v1
  logic (e.g. the SKIP LOCKED claim loop, the decision-log writer) are *adapted* into
  v2 shapes rather than rewritten from memory. The PCR's "copy no Python" rule is
  relaxed for these — re-typing correct code adds risk for no benefit — but they are
  re-aligned to the hardened schema and the API-only harness boundary
  ([[0003-harness-governance-api]]).
- **First deliverable is a vertical slice; full API parity is a committed phase.** The
  equity-research slice (one task → one agent with a human review step → one task,
  local Docker) proves the model first. **All 195 v1 API operations are then completed**
  — this is a committed goal, not deferred indefinitely. Kubernetes, NATS, and HA
  Postgres remain deferred to later phases (local Docker first).
- **Each phase ships something that runs.** No phase depends on a later phase to
  function.

## Consequences

**Positive**
- The harness model is designed in from the start instead of bolted on.
- Spec-first is genuinely possible; every piece of code traces to a reviewed spec.
- v1 keeps running and demoing the whole time — zero risk to existing capability.
- We keep the crown jewels (the data model's intent, the Pydantic models, hard-won SQL
  and behavior captured in the v1 test suite) while hardening the schema and rebuilding
  the flows that actually change.

**Negative / costs**
- Two codebases exist during the transition; we must be disciplined about v1 being
  reference-only.
- Some correct v1 code is re-touched as we adapt it into v2 shapes.
- Real risk of scope creep: the v2 PCR describes enterprise infrastructure (K8s, NATS,
  HA, observability) that is *months* of work. This ADR's mitigation is the
  vertical-slice-first rule — that scope is deferred, not adopted up front.

## Alternatives considered

**Strangler refactor of v1 in place.** Extract services from the existing code,
add the harness model incrementally behind feature flags, keep one repo and one
history. *Rejected* because the harness model changes core promotion/claim flows
enough that incremental change means sustained break-fix churn, and because spec-first
cannot be applied retroactively to 53K lines of existing code in any honest way. The
refactor path is lower-risk for *capability* but higher-friction for the two things
that actually motivate v2 (the harness model and spec-first discipline).

**Continue iterative enhancement of v1.** Rejected for the same reasons; this is the
status quo that produced the churn.

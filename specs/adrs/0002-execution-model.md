# ADR-0002 — Execution model: application-hosted harness

- **Status:** Accepted
- **Date:** 2026-05-29
- **Deciders:** Product Owner (Anil)
- **Related:** [[0001-rebuild-vs-refactor]]

---

## Context

Verity governs AI entities (agents and tasks) but does not own the business workflow.
A key v2 question is *where the execution container — the "harness" — physically runs*.
Two topologies were drawn up:

- **Centralized execution.** The harness runs inside the Verity governance platform.
  Business applications invoke it remotely and receive a result. Verity owns both
  governance *and* execution compute.

- **Application-hosted harness.** The harness runs *inside the business application's*
  own deployment. It pulls a predefined harness **image** plus the champion `.vax`/`.vtx`
  packages from the centralized registry, executes locally, and reports decision logs
  and registry snapshots back to centralized analytics.

The product goal is clear separation of concerns across the lifecycle — Intake,
Compose, Promote, Deploy, Invocation, state, logging — with **centralized governance
and registry, distributed execution, distributed logging/auditing, and centralized
reporting.**

## Decision

Adopt the **application-hosted harness** model.

- **Centralized governance + registry.** One governance metamodel (PostgreSQL) is the
  source of truth: entities are registered, composed, and promoted through the 6-state
  lifecycle here. Promotion to `champion` produces a signed `.vax` (agent) / `.vtx`
  (task) artifact in a shared artifact library.
- **Distributed execution.** Each business application runs its own harness container,
  built from a **predefined Verity harness image**. The harness performs a registry
  lookup, pulls the champion artifact, verifies its integrity, and executes. Verity
  does not host the application's execution compute.
- **Distributed logging/auditing.** The harness emits the canonical decision log and
  audit trail from where it runs.
- **Centralized reporting.** Decision logs and registry snapshots are routed to a
  centralized analytics store. Analytics is a reporting sink, never in the live
  invocation path.

The boundary between application and platform is the **canonical envelope** (structured
input/output) and the **audit trail** — the application handles domain logic,
orchestration, tool implementations, data persistence, delivery surface, and the
HITL UX; the platform handles registration, composition, promotion, artifact delivery,
and the governance record.

A **shared-container fallback** remains available for low-materiality workloads that do
not warrant a dedicated harness (a default fleet that claims runs for any application).
High-materiality applications get their own owned harness.

## Consequences

**Positive**
- Applications own their execution blast radius, resource limits, and data locality —
  one app's load or failure does not affect another's runs.
- The platform stays stateless with respect to execution; it governs and serves
  artifacts rather than running everyone's compute.
- Audit and decisions originate at the point of execution, matching the
  distributed-logging goal.
- The same harness image runs on a laptop and in production — promotion just changes
  which artifact it pulls.

**Negative / costs**
- The harness image and artifact-pull/integrity-check path must be rock-solid; a bad
  image affects every app that runs it.
- Versioning discipline is required: which harness image + which champion artifact an
  app is running becomes a thing we must track and report on.
- More moving parts at the edge (each app runs a container) than a single central
  executor.

## Alternatives considered

**Centralized execution (harness on the platform).** *Rejected* as the primary model.
It couples governance and execution compute, makes the platform a shared bottleneck and
a multi-tenant blast-radius risk, and puts the platform in the path of every business
invocation. It remains conceptually available as the shared-container fallback for
low-materiality work, but is not the target topology.

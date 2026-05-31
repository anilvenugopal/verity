# ADR-0008 — Compliance model: regulatory → canonical → controls & evidence

- **Status:** Accepted
- **Date:** 2026-05-30
- **Deciders:** Product Owner (Anil)
- **Related:** [[0005-schema-hardening]], [[0006-packages-and-governed-deployment]],
  [[0004-storage-architecture]], [[0007-decision-log-scale-and-portable-analytics]],
  [[user-authentication]], [[verity_v2_pcr]]

---

## Context

v1 maps canonical requirements to **"Verity features."** That is the wrong join: an
examiner does not ask which product features exist — they ask **which control enforces an
obligation, and what evidence proves it.** The v1 model couples compliance to the product
feature list, cannot express tiered maturity, and treats governance as a periodic review
artifact rather than continuous enforcement.

The product owner built a separate data-governance platform around a better model — a
three-axis structure (regulatory / canonical / controls + evidence), organized by
governance domains, with tiered maturity scoring and controls enforced continuously across
the lifecycle. This ADR brings that improvement into Verity AI governance. The **canonical
requirement vocabulary is largely stable and carries over**; what changes is the model
*around* it (domains, tier ladders, controls, evidence specifications, exceptions, and the
lifecycle phases at which controls fire).

## Decision

Adopt the **three-axis, two-bridge** compliance model as the v2 governance compliance
metamodel.

**Axes**
- **Left — Regulatory frameworks** (e.g. AIC, GLBA, NIST, State) and their **citable
  provisions** (`citation`, `jurisdiction`, `effective_date`).
- **Center (stable) — Canonical requirements**: the rationalized, **technology-agnostic**
  vocabulary of what is actually required. Each is **defined once**, assigned to **one or
  more governance domains**, and decomposed into a **variable, cumulative tier ladder**.
- **Right — Controls** (`type`, lifecycle `phase`, `enforcement_action`) and **Evidence
  specifications** (`artifact_type`, `produced_by`, `citable_as`).

**Bridges**
- **Bridge 1 — provisions ↔ canonical requirements**: many-to-many, with a **minimum-tier**
  mapping. New regulations **insert by mapping** their provisions onto existing canonical
  requirements without restructuring the center; multiple provisions across frameworks
  reference the same canonical requirement; coverage gaps close **without duplicating the
  underlying obligation**.
- **Bridge 2 — canonical requirements ↔ controls/evidence**: **per tier, per lifecycle
  phase.**

The **center axis is stable**; the left and right axes grow independently as regulations
change and controls mature.

**Domains & maturity.** Governance domains group canonical requirements for organization
and **per-domain maturity scoring**. Tiers are **cumulative** (operating at Tier N means
all tiers below N are active); no artificial tiers are created — a requirement has as many
tiers as regulation and best practice actually require. Maturity scores are **normalized
algorithmically** across requirements with different tier counts and aggregated per domain.

**Control lifecycle phases (AI-governance adaptation).** Every canonical requirement
enforces through controls at four phases — each mapping onto existing v2 machinery:

| Phase | Fires when | Verity enforcement point |
|---|---|---|
| **Design-time** | an AI asset / binding / prompt / schema is being *defined* (before it runs) | intake + compose/authoring |
| **Deploy-time** | a package is being promoted/deployed to an environment (before live traffic) | the governed-deployment gate ([[0006-packages-and-governed-deployment]]) |
| **Static / model controls** *(replaces data-at-rest)* | continuously, on the at-rest model/package artifact (config snapshot, model card, package contents) regardless of invocation | the champion package (`.vtx`/`.vax`) |
| **Execution controls** *(replaces data-in-motion)* | during a run, as inputs resolve, the model is invoked, tools are called, outputs are written | the runtime harness (Source/Target Binding, write-suppression) |

Controls **block non-compliant activity at the phase where they operate** — a hard gate at
design-time/deploy-time; refusal or write-suppression at execution.

**Evidence.** Every control produces evidence that meets its **evidence specification**,
tied to the canonical requirement + tier + phase + the entity/run that produced it.
Evidence is an **append-only audit fact** in the audit/log store
([[0004-storage-architecture]], [[0007-decision-log-scale-and-portable-analytics]]).

**Exception governance.** Where an exception is warranted, it is **registered as a
first-class, append-only audit record** carrying: the **specific tier waived**, the
**canonical requirement affected**, the **approving authority** (a named approver, bound to
the authorization role model in [[user-authentication]]), the **compensating controls** in
place, and a **maximum permitted duration (expiry)**. Exceptions appear in the audit trail
with full context. Controlled non-compliance with documented compensating controls and an
expiry is a **defensible position under examination**.

**Continuous governance.** Enforcement is continuous across the asset lifecycle and data
flow — **not periodic at review cycles.**

**Intake linkage (the product consequence).** At intake and AI-risk classification, the
platform **resolves the applicable canonical requirements** (by governance domain + risk
tier) and the **target maturity tiers**, producing the **obligation set** — the controls
(per phase) and evidence specifications the asset must satisfy through its lifecycle. From
intake onward, design/deploy/static/execution controls enforce that set, evidence accrues,
and maturity is scored per domain. **The product is designed, starting at intake, to
implement the controls and capture the evidence the canonical requirements demand.**

## Consequences

**Positive**
- Audit-aligned: the system speaks in controls and evidence, which is what examiners
  consume; the canonical→features mapping is gone.
- The stable canonical center lets frameworks and controls evolve independently and
  de-duplicates obligations across overlapping regulations.
- Tiered, per-domain maturity makes "how compliant, where" measurable and continuous.
- It **unifies** with the rest of v2: the four control phases land exactly on
  intake/compose (design), the deployment gate (deploy, ADR-0006), the champion package
  (static/model), and the runtime harness (execution); evidence and exceptions live in the
  append-only audit store (ADR-0004/0007); exception approvers use the auth role model.

**Negative / costs**
- A net-new metamodel (frameworks, provisions, canonical requirements, domains, tiers,
  controls, evidence specs, evidence/audit facts, exceptions) — schema, API, and
  enforcement work, front-loaded onto the hardened schema ([[0005-schema-hardening]]).
- The **maturity-normalization algorithm** and the precise **per-phase "block" semantics**
  must be specified (deferred to the compliance component spec).
- Migration: v1's `canonical → feature` mapping is dropped-with-reason and re-expressed as
  `canonical → control + evidence spec`.

## Alternatives considered

- **Keep v1 `canonical → features`.** *Rejected* — not what auditors consume; no tiering or
  maturity; couples compliance to the product feature list.
- **Map controls directly to provisions (skip the canonical center).** *Rejected* — the
  provision↔control matrix explodes as frameworks grow and re-introduces duplicated
  obligations; the stable canonical center is the entire point.

## Notes

The canonical requirement vocabulary is largely carried over from the data-governance
platform ("the requirements themselves need not change much"); this ADR changes the model
around it. The maturity-normalization function and per-phase enforcement mechanics are
fixed in the compliance component spec. These are hardened Tier-1 metamodel tables;
evidence and exception records are insert-only ([[0005-schema-hardening]]).

# ADR-0006 — Packages, harness-image compatibility, and governed deployment

- **Status:** Accepted
- **Date:** 2026-05-30
- **Deciders:** Product Owner (Anil)
- **Related:** [[0002-execution-model]], [[0003-harness-governance-api]],
  [[0005-schema-hardening]], [[user-authentication]]

---

## Context

[[0002-execution-model]] adopts the application-hosted harness: a business app pulls a
predefined Verity **harness image** plus the champion `.vax`/`.vtx` package from the
centralized registry and executes locally. That ADR explicitly left a thread open:
*"which harness image + which champion artifact an app is running becomes a thing we must
track and report on."* This ADR closes it.

Three concrete questions follow:

1. **Where may a package run?** A package (`.vtx` task / `.vax` agent) is the unit of
   deployment, and the same governance platform serves many **clusters** — grouped into
   **environments** (non-prod, prod), including ephemeral/temporary clusters. Not every
   package should be runnable everywhere.
2. **On what may it run?** A package is only valid on a harness image that can execute it.
   Running a package on an incompatible image is a correctness and audit hazard.
3. **Who deploys it, and how is that recorded?** If deployment happens out-of-band
   (someone runs `helm`/`kubectl` directly), the compatibility checks and placement rules
   are advisory at best and the platform cannot say what is actually running where.

## Decision

**Packages are governed deployment targets. Lifecycle state gates placement, harness-image
compatibility is enforced by digest, and all deployment is mediated by the governance
control plane.**

### 1. Lifecycle state gates environment and run mode

| Lifecycle state | Deployable to | Run mode | Target Bindings (writes) |
|---|---|---|---|
| `draft` / `candidate` | — (authoring only) | — | — |
| `staging` | non-prod clusters only | `live` | enabled (non-prod) |
| `challenger` | prod (and any) | **`shadow`** or **`ab`** (freely switchable) | suppressed (shadow) / written on the sample (ab) |
| `champion` | **any environment** | `live` | enabled |
| `deprecated` | **any environment** | `locked` | disabled (audit/replay only); cleanup allowed; **restorable via rollback** |

> **6-state lifecycle (amended 2026-05-31):** v1's `shadow` is no longer a lifecycle state —
> it is a **challenger run-mode**. A challenger deploys in `shadow` (outputs suppressed, zero
> impact) or `ab` (full I/O on a scoped sample carrying an `ab_sample` marker), switchable
> without a state change. `deprecated` is restorable (rollback `deprecated → champion`).

**"Read-only" is defined precisely:** the harness executes and **writes the decision
log**, but its **Target Bindings (output writes) are suppressed/diverted** so there are no
business-system side effects. Shadow mirrors prod traffic with no writes; challenger may
serve a live A/B slice. `champion` and `deprecated` are deployable to **any** environment
— this is what enables reproducible replay (below).

### 2. Harness-image compatibility is declared and enforced — by digest

- Each package manifest declares the set of compatible harness images by **immutable
  content digest** (not a mutable tag), and the registry tracks package×image
  compatibility.
- The governance deploy path **refuses** an incompatible package×image combination; an
  incompatible deploy cannot proceed.
- This makes **reproducible replay** a first-class capability: an old (`deprecated`)
  package can be re-run on its original image digest on an ephemeral/temp cluster, against
  its decision-log data, to reproduce exactly what executed — a direct compliance asset in
  a regulated setting.

### 3. Deployment is mediated by the governance control plane

This is the deployment-plane analog of [[0003-harness-governance-api]]:

- Deployments are requested through and **recorded by** governance. The platform maintains
  a **deployment inventory** — what package, at what lifecycle state, on which image
  digest, is running in which cluster/environment — as a Tier-1, insert-only record
  ([[0005-schema-hardening]]).
- **Out-of-band deployment is disallowed**: a manual `helm`/`kubectl` deploy that bypasses
  governance also bypasses the compatibility gate and the state→environment matrix and
  desynchronizes the inventory — so the safety rails would not hold.
- Deployment operations (`deploy_nonprod`, `deploy_prod`, `promote_champion`,
  `lock_deprecated`, `cleanup_deprecated`, …) are governed by the authorization
  action-matrix and map onto the role model in [[user-authentication]] (platform
  `security` + the per-application app-team roles).

## Consequences

**Positive**
- Reproducible audit/replay: image digest + package + decision-log data reconstruct any
  past execution exactly.
- The state→environment matrix encodes safe progression (staging can't reach prod;
  shadow/challenger can't write to prod) as enforced rules, not convention.
- The deployment inventory is a single source of truth for "what is running where,"
  enabling reporting and incident response.
- Shadow and A/B are well-defined by the read-only / write-suppression rule.

**Negative / costs**
- Governance becomes the deployment control plane — more to build than handing deploys to
  ops, and it must orchestrate (or instruct) multiple clusters incl. ephemeral ones.
- Image-digest discipline is mandatory; tag-based shortcuts are prohibited.
- The harness must enforce read-only / write-suppression airtight — a leak means a
  shadow/challenger writes to a business system.

## Alternatives considered

- **Ops-managed deployment with conventions.** *Rejected* — bypasses the compatibility
  gate and placement matrix and breaks the inventory/audit; the rails become advisory.
- **Tag-based image compatibility.** *Rejected* — tags are mutable, so "the image that
  ran" is not reproducible; digests are required for audit replay.
- **No state→environment gating.** *Rejected* — lets staging reach prod and lets
  shadow/challenger cause side effects; defeats the point of the lifecycle.

## Notes

Cluster orchestration mechanics (how governance drives or instructs clusters, ephemeral
replay-cluster provisioning) are deferred to the runtime/deployment component spec. This
ADR fixes the *governed-deployment shape*: packages as targets, digest-pinned
compatibility, the lifecycle→environment matrix, and governance as the deploy control
plane.

---

## Amendment — 2026-06-10: `candidate` state defined as a materiality-gated authoring review

### Context

The original ADR grouped `draft` and `candidate` together as "authoring only" with no
distinction between them. This left `candidate` without a defined purpose and made the
two states equivalent, which is useless.

In a regulated insurance platform, there is a real workflow gap between "I finished
authoring this package" and "this package may be deployed to a non-prod cluster for
testing." A package encodes a prompt, tool authorizations, source bindings, and write
targets — it is a governance artifact that can cause business-system side effects. Even
non-prod execution should require a human sanity check before allowing it for high-risk
use cases. For low-risk use cases, that review is unnecessary overhead.

### Decision

**`candidate` is a materiality-gated authoring-review state.** The `draft → candidate`
transition locks the package for editing and triggers a materiality check. Low-materiality
packages auto-advance to `staging`; high-materiality packages require an explicit human
approval.

#### Transition: `draft → candidate` (`submit_for_review`)

Triggered by the package author. Locks editing on the package. The system immediately
evaluates the **materiality rule** (§ below) using the materiality scores computed during
the intake assessment phase ([[0005-schema-hardening]], assessment tables). If scores are
not yet available the package is blocked at `candidate` until they are.

#### Materiality rule — auto vs. manual path

The materiality source is the **intake** the package is authored under
(`package.intake_id → core.intake.materiality_tier_code` and `naic_materiality_code`).
Both fields are set by the intake assessment (M4 assessment spec).

| `materiality_tier_code` | `naic_materiality_code` | Review path |
|---|---|---|
| `low` | `non_material` | **Auto-approve** → `staging` immediately (system action, no human required) |
| `low` | `material` | **Manual** |
| `medium` | any | **Manual** |
| `high` | any | **Manual** |
| `critical` | any | **Manual** |
| *not yet scored* | *not yet scored* | Blocked at `candidate` until assessment completes |

The rule is conservative: only packages where **both** dimensions indicate low
materiality are auto-approved. Any ambiguity or missing score defaults to manual.

#### Manual review: `candidate → staging` (`approve_candidate`)

A reviewer with the platform `governance` role (or the application's designated
`app_governance_reviewer` role) inspects the package — specifically: the prompt version,
tool authorizations, source bindings, and write targets — and approves. The approval is
recorded as an insert-only audit record (reviewer actor ID, decision, comment, timestamp).

**Separation of duty:** the package author cannot approve their own package, regardless
of their roles.

#### Rejection: `candidate → draft` (`reject_candidate`)

The reviewer may reject with a required comment. The package returns to `draft` (editing
re-enabled) for rework. The rejection is recorded in the same audit record.

#### No `candidate` deployment

`candidate` is still an authoring-only state. No deployment to any cluster
(prod or non-prod) is permitted until the package reaches `staging`.

### Updated lifecycle table

| Lifecycle state | Deployable to | Run mode | Target Binding writes | Entry condition |
|---|---|---|---|---|
| `draft` | — | — | — | Package created |
| `candidate` | — | — | — | Author submits; editing locked |
| `staging` | Non-prod only | `live` | Enabled (non-prod) | Low-mat auto OR reviewer approves |
| `challenger` | Any | `shadow` or `ab` | Suppressed (shadow) / scoped (ab) | Promoted from staging |
| `champion` | Any | `live` | Enabled | Promoted from challenger |
| `deprecated` | Any | `locked` | Disabled (audit/replay) | Superseded by new champion |

### Consequences

- Low-materiality packages (internal ops, non-consumer-facing, non-material by NAIC) reach
  non-prod testing with zero added friction — the submit action is the only gate.
- High-materiality packages (consumer-facing, NAIC-material, high/critical tier) always
  have a named human reviewer on record before any execution, satisfying audit requirements
  in regulated environments.
- Separation of duty on the review prevents the author self-certifying their own package.
- The materiality scores come from the intake assessment — no new metadata is required on
  the package itself.
- If the intake assessment has not been completed when the author submits the package, the
  package is blocked at `candidate`. This is the correct behaviour: a package cannot be
  reviewed for materiality compliance if materiality has not been assessed.

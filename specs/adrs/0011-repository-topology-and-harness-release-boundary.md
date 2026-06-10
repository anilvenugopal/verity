# ADR-0011 — Repository topology, harness release boundary, and contract ownership

- **Status:** Accepted
- **Date:** 2026-06-02
- **Deciders:** Product Owner (Anil)
- **Related:** [[0002-execution-model]], [[0003-harness-governance-api]],
  [[0006-packages-and-governed-deployment]], [[0010-harness-runtime-federated-coordinator]]

---

## Context

The harness is application-hosted ([[0002-execution-model]]): a Verity-published,
**digest-pinned** image ([[0006-packages-and-governed-deployment]]) runs in the *customer's*
environment, talks to the hub **only** through a versioned contract ([[0003-harness-governance-api]]),
and converges its desired-vs-current image **independently** of any hub deploy
([[0010-harness-runtime-federated-coordinator]]). The hub, by contrast, is Verity-operated
and releases on its own cadence.

Four independent-lifecycle signals follow from the architecture already decided: a separate
**release cadence**, a separate **security posture** (the harness handles customer data in
customer clusters; the hub does not), a separate **audience** (app teams consume the
harness; Verity operates the hub), and a **digest-pinned image lifecycle** that ADR-0010
treats as authoritative on its own. This ADR fixes how the codebase is partitioned to match
those boundaries, and what holds the parts together.

A secondary concern surfaced during the schema load test: **data seeding is currently
embedded in the DDL** (reference-vocabulary `INSERT`s live inside each table file). That
conflates structure with data and is the wrong shape for migrations.

## Decision

**Start as a modular monorepo — `hub/`, `harness/`, `app-alpha/`, `contract/` with enforced
import boundaries — and split into separate repositories at a defined trigger; bound by a
single hub-owned, versioned contract; with reference seeds separated from DDL.**

### 1. Start as a modular monorepo; split at a trigger, not a date

The four-way lifecycle split is real, but at this stage the **contract is still molten** and
hub and harness co-evolve constantly. A single repo lets a contract change and *both*
consumers update in one atomic PR — the largest early-velocity win, exactly when it matters.
So the components live as **top-level directories in one repo** and become separate repos
only when a concrete boundary forces it.

```
verity/                 # one repo, for now
  contract/             # OpenAPI 3.1 + NATS schemas + package manifest + shared vocab  ← the linchpin
  hub/                  # governance API, gateway, verity-relay, schema + separated seeds, portal
  harness/              # the harness image (one image, role by config), the operator, Helm chart, quadlets
  app-alpha/            # the demo app-team example (underwriting, §5)
  infra/                # IaC: hub platform + reference customer substrate (k8s cluster, Linux box) — infra-team persona
  specs/  adrs/ …       # existing
```

| Component (→ future repo) | Builds / owns | Cadence |
|---|---|---|
| **hub** (→ verity) | governance API, Harness Gateway API, `verity-relay`, schema **+ separated seeds**, portal, **and the published contract + generated SDK** | hub |
| **harness** (→ verity-harness) | the harness image (coordinator + worker; **one image, role by config**), the **operator** image, the **Helm chart**, the systemd/podman packaging. Signs images (cosign) → registry. Consumes a *pinned* contract version | independent, digest-pinned |
| **app-alpha** (→ verity-demo-alpha) | the **underwriting** app-team example (§5): a containerized business app + harness install for Linux (R1) and Kubernetes (R2) + enrollment + the end-to-end scenarios. Acceptance environment and demo | demo / acceptance |
| **infra** (→ verity-infra) | IaC for the **infra-team persona**: the hub platform (k8s, CloudNativePG, NATS, MinIO, registry) **and reference customer substrate** modules (a k8s cluster, a Linux box) + the substrate-requirements spec | infra |

**Boundary discipline (what makes the later split cheap):** each directory is its own
buildable unit, and the **only** permitted cross-directory dependency is on `contract/` — no
`hub↔harness` or `app↔hub` direct imports, enforced by an import-boundary check in CI.

**Split triggers (any one):** the harness ships to a real **external customer cluster** (the
security/supply-chain boundary becomes physical — separate signing, access, SBOM); release
**cadences actually diverge**; or a third party needs the demo/SDK without hub source. Because
nothing cross-imports except `contract/`, the split is a `git filter-repo` of the directory +
wiring the published contract.

The **operator, Helm chart, and quadlets live in `harness/`**, not in the demo — the demo
*consumes* them (`helm install verity-operator`, then deploy from the portal), which is exactly
the app-team experience being demonstrated.

### 1a. Three personas — infra provisions the substrate, the app team deploys onto it

Provisioning is a different job, done by a different team, than deploying. The topology makes
that explicit:

- **Infra team** (`infra/`) provisions the **substrate**: the hub platform, and — in the
  customer's environment — the **k8s cluster or the Linux box** the harness will run on. Their
  output is IaC (Terraform/Ansible/Helm), not application code.
- **App team** (`app-alpha/`) takes a provisioned substrate and does the **connect/deploy**:
  install the operator, enroll, deploy from the portal. It never provisions infrastructure.
- **Verity** (`hub/`, `harness/`, `contract/`) ships the services, the harness/operator images,
  the chart, and the contract.

The seam between infra and the harness is a **substrate-requirements spec** (the infra↔harness
contract): outbound-443-only egress, a namespace + operator RBAC, a storage class for the
artifact-cache PVC, ESO for customer secrets, and the mTLS enrollment material — for the Linux
box, the equivalent systemd/podman prerequisites. Verity publishes this spec and ships
**reference** IaC modules; the customer's infra team applies or adapts them. CI's
deploy-target tests (§3) provision an **ephemeral** substrate (kind for k8s, a VM/container for
Linux) — the test double for what the infra team provisions in production.

### 2. The contract is the linchpin — hub-owned, versioned, contract-tested both sides

Separate repos without a shared, versioned contract drift. The contract is therefore a
**first-class published artifact**, authored in the **verity** repo (governance is the
authority, [[0003-harness-governance-api]]) and consumed by both `verity-harness` and
`verity-demo-alpha`:

- **OpenAPI 3.1** for the Harness Gateway API (register, claim, release, heartbeat, ack).
- **JSON schemas** for the NATS payloads (`verity.runs.pending`, `verity.cluster.{id}.commands`, `verity.events.{run_id}`, heartbeats).
- The **`.vtx/.vax` package-manifest schema**.
- The harness-relevant **reference vocabularies** (command_kind, run_dispatch_status, …).

It is published as a versioned package; consumers pin a version. **Contract tests run on both
sides** (the harness validates its client against the published spec; the hub validates its
handlers against it), so a breaking change fails CI before it ships.

### 3. Build & test — one behavioral suite, two substrates

The harness must run identically on bare Linux and on Kubernetes. The test strategy keeps
them honest against the same contract:

1. **Unit** (no infra): lease state machine, circuit breaker, island-mode reconciliation, package verifier, binding resolvers.
2. **Contract tests** against the published OpenAPI/NATS schemas via a mock gateway (e.g. Prism) — no hub required.
3. **Integration** (testcontainers): postgres + NATS + a minimal gateway + the harness binary; exercises the full dispatch loop (submit → outbox → NATS → claim → execute → report). No Kubernetes required.
4. **Deploy-target tests — the same behavioral suite, parameterized on substrate:**
   - **Linux:** podman/systemd on a CI Linux runner/VM. Single-node = always-leader; enrollment handshake; island mode (kill the hub → in-flight jobs finish → reconnect reconciles).
   - **Kubernetes:** kind/k3d. `helm install` the operator → it reconciles coordinator+worker Deployments → run the loop + **failover** (delete the active coordinator pod → a standby steals the lease within the window) + an HPA smoke test.
5. **End-to-end / demo = `verity-demo-alpha`** (nightly): real app + real harness on **both** targets + real hub + real Claude; the full connect → deploy → run → govern story.

Two cross-cutting jobs in `verity-harness` CI: the **package×image compatibility matrix**
([[0006-packages-and-governed-deployment]]) and **model-mocked in CI / real-Claude nightly**.

### 4. Seeds are separated from DDL

`verity_schema.sql` is **structure only** (idempotent, migration-friendly). Reference
vocabulary moves to a separate, idempotent seed step (`seed_reference.sql` or a `seed/` tree)
using `INSERT … ON CONFLICT (code) DO UPDATE`, so reference data can be re-applied on every
deploy without touching structure. This is the boundary a future migration tool
(Flyway/Sqitch/Alembic) needs.

### 5. The release-1 demo is underwriting, reusing uw_demo (re-authored as v2 data)

`app-alpha`'s release-1 scenario is **underwriting triage** — the target vertical, and the job
profile ADR-0010 sizes against (1–5s jobs). It is built by **re-authoring** the legacy
`verity_legacy/uw_demo` assets as v2 data/specs (legacy is read-only — reference, never
import): its prompts → `prompt_version`s; its underwriting ontology → the compliance metamodel
(governance domains, canonical requirements, controls, D9 obligation reasoning); its seed → a
realistic `application` + `intake` + registry seed; its labeled cases → ground-truth/validation
data. This maximizes reuse, exercises the **compliance/obligation axis** (not just execution),
and is more credible than a synthetic domain. A deliberately-simple, public-data app (e.g. a
stock screener) is a candidate **second** app later, to prove multi-tenant / non-insurance.

## Consequences

**Positive**
- Early velocity: while the contract is molten, a contract change and both consumers move in one atomic PR.
- The boundary is defined now (directories + the import rule + the contract), so the eventual repo split is a cheap `filter-repo`, not a rewrite.
- Clean persona separation: infra provisions the substrate, the app team deploys onto it, Verity ships the services/images/contract — each with its own artifacts.
- The contract is an explicit, tested artifact rather than tribal knowledge — drift fails CI.
- Linux and Kubernetes are validated by one behavioral suite, so they cannot silently diverge.
- The demo doubles as the acceptance environment and the sales artifact, on the real vertical.

**Negative / costs**
- The monorepo only stays splittable if the **import-boundary rule is enforced in CI**; let it rot and the split stops being cheap.
- Independent harness release cadence and separate signing are **deferred** to the split trigger; until then hub + harness release together.
- A breaking contract change still needs a versioned bump + contract tests, even within one repo.

## Alternatives considered

- **Three separate repos from day one.** *Rejected for now* — premature while the contract is molten; the cross-repo version dance slows the very hub/harness co-evolution that dominates early work. Adopted at the split trigger (§1).
- **Monorepo forever (no split plan).** *Rejected* — the harness's customer-facing, data-handling security boundary eventually demands a physically separate, separately-signed supply chain.
- **Harness owns the contract.** *Rejected* — governance is the authority on the API and writes ([[0003-harness-governance-api]]); the hub publishes, consumers pin.
- **Infra folded into hub/harness (no `infra/`).** *Rejected* — provisioning is a different team and a different artifact type (IaC) than the services it runs; conflating them hides the infra↔harness substrate contract.
- **Demo deployment artifacts (operator/chart) in the demo repo.** *Rejected* — they are the Verity install mechanism; they belong in `verity-harness` and the demo consumes them.
- **Keep seeds in the DDL.** *Rejected* — conflates structure and data, breaks idempotent re-seeding and migration tooling (and was the source of the load-test failures).

## Notes

Nothing is built yet (spec-only, pre-Phase-2). When implementation starts, the repo is laid
out as the directories of §1 (`contract/ hub/ harness/ app-alpha/ infra/`) with the
import-boundary rule enforced in CI; the **physical** repo split happens at the trigger (§1),
not on a fixed date. Build/test specifics (CI matrices, kind topology, testcontainers wiring)
and the substrate-requirements spec are implementation concerns for the respective component
specs. This ADR fixes the *topology, the persona/substrate separation, the release boundary,
the contract ownership, and the seed/DDL split*.

---

## Amendment — 2026-06-09 (ADR-0016)

**Connector versioning is harness image versioning.** The harness image's connector
framework ([[0016-tool-invocation-harness-image-composition]] §4) is a load-bearing
component whose version is tied to the image digest. The `harness/` component therefore
has a versioning dependency on its connector library set, in addition to the Anthropic
SDK and the MCP protocol client.

The practical consequence for the build and CI pipeline: the harness image's package×image
compatibility matrix ([[0006-packages-and-governed-deployment]], [[0011]] §3) must include
**connector type availability** as a compatibility dimension alongside API surface and
runtime version. A package that declares a SQL connector requires a harness image version
that contains the SQL connector implementation. The compatibility check at governed
deployment time ([[0006]]) enforces this.

Adding a new connector type to `harness/` follows the same release path as any harness
image change: build → cosign sign → publish to registry → `patch` command to enrolled
clusters → Deployment roll. This is not a `deploy_package` operation (which is zero-downtime
bundle swap); it is an image update that requires the operator to roll the Deployment.

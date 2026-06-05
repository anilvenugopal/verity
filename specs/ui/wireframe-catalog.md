# Verity v2 — Wireframe Catalog

**Status:** Working inventory — the complete set of screens the product needs, with build priority and the prototype each fresh page strangles.
**Companion to:** [`design-system.md`](design-system.md) (the canonical kit) and the apps model (§7).
**Kit:** fresh canonical pages are built in [`kit/pages/`](kit/pages/) on the five-layer CSS + icon sprite.

## How to read this

- **ID** — stable handle (`app.screen`).
- **Priority** — P0 (foundational / blocks others), P1 (core product), P2 (nice-to-have / later).
- **§** — governing design-system section.
- **Strangler source** — the prototype this fresh page replaces, kept as read-only reference until the fresh page lands, then deleted.
- **Status** — `built` (fresh kit page exists) · `proto` (only the old prototype exists) · `none` (not yet designed).

Lifecycle (every screen): `none → proto → built → adopted (in main project)`.

---

## 0. Global / shell — P0, the chrome every app lives in

| ID | Screen | § | Strangler source | Status |
|---|---|---|---|---|
| `shell.app` | App shell (rail · sidebar · topbar · canvas · right-panel · statusbar) | §2, §7 | verity-nav-framework | **built** (`kit/pages/sample.html`) |
| `shell.launcher` | App launcher modal (grid of all apps, search, pin) | §7 | verity-nav-framework | **built** (sample.html) |
| `shell.palette` | Command palette (⌘J — apps, entities, runs, settings) | §7 | verity-nav-framework | **built** (sample.html) |
| `shell.help` | Contextual help popover (? affordance, inline explainer) | §8 | — | none |
| `shell.empty` | Empty-state pattern (every app's getting-started) | §8 | verity-homepage | **built** (styleguide + sample) |
| `shell.error` | Error / 404 / permission-denied states | §8 | — | none |
| `shell.toast` | Transient notifications + progress (>300ms / >2s) | §8, §14 | — | none |
| `style.guide` | Living styleguide (colors, type, components) | §3–§6 | verity-design-sample | **built** (`kit/pages/styleguide.html`) |
| `icons.catalog` | Icon catalog & review tool | §7 | (new) | **built** (`kit/icons/catalog.html`) |

---

## 0b. Auth & identity — P0, who you are and what you may do

> Identity ≠ authorization. Sign-in (Microsoft Entra OIDC, or a local-dev mock) establishes
> *who*; **roles always come from the Verity DB** (append-only grants), never from the token.
> See [`specs/features/user-authentication.md`](../features/user-authentication.md).

| ID | Screen | § | Strangler source | Status |
|---|---|---|---|---|
| `auth.signin` | Sign-in landing — "Sign in with Microsoft" (Entra redirect) + local-dev mock path | §8 | (new) | **built** (`kit/pages/signin.html`) |
| `auth.account-menu` | Account menu — identity · platform & app-team roles · sign out · mock indicator | §7 | (new) | **built** (`account-menu.html`) |
| `auth.states` | Fail-closed states — session expired · access denied (403) · account disabled (FR-021) | §8 | (new) | **built** (`auth-states.html`) |
| `auth.callback` | OAuth callback (state/PKCE verify, code exchange, session mint) — redirect handler, no UI | — | — | n/a |

---

## 1. Home — P1, landing & getting started

| ID | Screen | § | Strangler source | Status |
|---|---|---|---|---|
| `home.landing` | Welcome / jump-back-in, quick stats, recent decisions | §8 | verity-homepage | **built** (sample.html) |
| `home.notifications` | Notifications feed / inbox | §8 | — | none |

---

## 2. Intake — P0, aligns with active spec (001-verity-governance-service)

> "Intake" is the **process** of taking in a new AI **use case** (→ build → deploy). The app owns
> two things: **applications** (the governed tenants) and the **use cases** they take in.

### 2a · Application management

| ID | Screen | § | Strangler source | Status |
|---|---|---|---|---|
| `intake.applications` | Applications landing + searchable registry (+ non-stakeholder read-only modal) | §7 | verity-intake-wireframe | **built** (`kit/pages/applications.html`) |
| `intake.onboard` | Onboard application — governed proposal (identity · ownership · compliance perimeter · approval) | §7, §8 | verity-intake-wireframe | **built** (`onboard-application.html`) |
| `intake.onboard-approval` | Onboarding approval — approver view (read-only composition + dual gate) | §8, §10 | — | **built** (`onboard-approval.html`) |
| `intake.app-detail` | Application detail (overview · compliance perimeter · use cases · team) | §7, §12 | — | **built** (`application-detail.html`) |

### 2b · Use cases — the items intake takes in

| ID | Screen | § | Strangler source | Status |
|---|---|---|---|---|
| `intake.usecase-create` | Create use case (submission → governed use case) | §7 | verity-intake-wireframe | proto |
| `intake.usecase-detail` | Use-case detail / read (status, fields, classification, provenance) | §7 | verity-intake-wireframe | proto |
| `intake.usecase-review` | Use-case review / HITL decision | §8, §12 | verity-intake-wireframe | proto |

---

## 3. Studio — P0/P1, the authoring canvas (most differentiated surface)

| ID | Screen | § | Strangler source | Status |
|---|---|---|---|---|
| `studio.entities` | Entity list (agents / tasks / prompts), filters | §7, §10 | verity-agent-studio | proto |
| `studio.canvas-agent` | Authoring canvas — **agent** compose (library · composition · test) | §10 | verity-agent-studio | proto |
| `studio.canvas-task` | Authoring canvas — **task** compose (output schema, write targets) | §10 | verity-agent-studio | proto |
| `studio.prompt-editor` | Prompt block editor (typed blocks, variable chips, blame gutter) | §9 | prompt-editor-v2.jsx | proto |
| `studio.prompt-diff` | Prompt diff view (block-level, failure attribution) | §9, §11 | prompt_editor_diff_v14_v150 | proto |
| `studio.test-panel` | Test + inspect panel (run, last output, perf summary) | §10, §12 | verity-agent-studio | proto |
| `studio.save-suite` | Save-to-test-suite modal (capture inputs/mocks/expected) | §12 | — | none |
| `studio.version-history` | Entity version history + composition diff | §11 | — | none |

---

## 4. Registry — P1, entities & versions of record

| ID | Screen | § | Strangler source | Status |
|---|---|---|---|---|
| `registry.list` | Entity registry (all entities, lifecycle, materiality) | §6, §7 | — | none |
| `registry.detail` | Entity detail (composition, versions, perf, lineage) | §10, §12 | — | none |
| `registry.compose-diff` | Composition diff (entity version A vs B) | §11 | — | none |

---

## 5. Observability — P1, runs, traces, live monitoring

| ID | Screen | § | Strangler source | Status |
|---|---|---|---|---|
| `obs.runs` | Runs list (filter by entity, state, time, outcome) | §6, §12 | — | none |
| `obs.run-detail` | Run detail = decision log (steps, tools, confidence, cost) | §6, §12 | triage_agent_failing_cases (partial) | proto |
| `obs.trace` | Trace / span view (OpenInference/OTel spans — ADR-0013) | §12 | — | none |
| `obs.live` | Live run stream (SSE — `verity.events.{run_id}`) | §14 | — | none |

---

## 6. Governance — P0/P1, lifecycle, approvals, decisions

| ID | Screen | § | Strangler source | Status |
|---|---|---|---|---|
| `gov.lifecycle` | Lifecycle board (entities by state, promotion paths) | §10 | — | none |
| `gov.approval-gate` | Promotion / approval gate (approval_record) | §10 | — | none |
| `gov.decision-log` | Global decision log (system of record) | §6, §12 | verity-design-sample (table) | proto |
| `gov.compare` | Challenger vs champion compare (A/B, shadow) | §10, §11 | — | none |
| `gov.triage` | Pragmatic triage queue (failures, HITL spikes, drift) — **nice-to-have** | §13 | triage_agent_failing_cases | proto |

---

## 7. Compliance — P1, audit, evidence, annotation

| ID | Screen | § | Strangler source | Status |
|---|---|---|---|---|
| `comp.packages` | Audit packages list | §8 | — | none |
| `comp.package` | Audit package builder / detail (logs + approvals + evidence) | §8, §12 | — | none |
| `comp.annotation` | Unified annotation & feedback (ground truth, HITL override, judge scores — ADR-0014) | §12 | — | none |
| `comp.provenance` | Document-anchored visual provenance (ADR-0014) | §9, §10 | — | none |
| `comp.hitl-queue` | HITL override queue | §12 | — | none |

---

## 8. Harness — P2, runtime execution cluster

| ID | Screen | § | Strangler source | Status |
|---|---|---|---|---|
| `harness.clusters` | Cluster list + health | §7 | — | none |
| `harness.cluster` | Cluster detail (workers, heartbeat, dispatch queue) | §7 | — | none |

---

## 9. Settings — P1, workspace & account

| ID | Screen | § | Strangler source | Status |
|---|---|---|---|---|
| `settings.workspace` | Workspace settings | §8 | — | none |
| `settings.members` | Members & roles (RBAC) | §16 | — | none |
| `settings.quotas` | Quotas & budget (quota_check) | §13 | — | none |
| `settings.connectors` | Data connectors (source bindings) | §10 | — | none |
| `settings.keys` | API keys / tokens | §8 | — | none |

---

## Build order (proposed)

1. **P0 foundation** — `shell.*` (done), `style.guide` (done), `icons.catalog` (done), `shell.help`, `shell.toast`, `shell.error`.
2. **P0 product slices** — Intake (`intake.*`, matches active spec), then Studio canvas (`studio.canvas-agent`, `studio.prompt-editor`).
3. **P1 governance loop** — Registry, Observability, Governance, Compliance.
4. **P2** — Harness, triage, advanced settings.

## Coverage notes

- **Reusable building blocks** the catalog assumes exist in the kit before P1: command palette (✓), app launcher (✓), help popover, toast/progress, modal/drawer, tabs, drag-to-wire, block editor, diff viewer, stat tiles (✓), data table (✓), file/vault picker, SSE live-channel client (`liveChannel.js`, not yet built).
- **Live updates** ride the SSE bridge (`contract/nats/subjects.md` → `verity.events.{run_id}`); `obs.live` and `studio.test-panel` are the first consumers.
- Every screen must ship its **empty state** and **contextual help** (§8) — not tracked as separate rows but required for `built` status.

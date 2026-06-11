# Verity v2 — Feature Roadmap

**Created**: 2026-06-05  
**Purpose**: Authoritative roadmap for all features numbered 001–021 plus POC parallel tracks. Each entry is self-contained enough for a new implementation session to orient without re-reading source specs.  
**Source of truth for requirements**: `specs/001-verity-governance-service/spec.md` (umbrella), `specs/features/user-authentication.md`, `specs/features/verity-markup.md`, constitution, ADRs.  
**Active feature pointer**: `.specify/feature.json`

---

## Legend

- **Status**: `shipped` · `active` (in-progress slice) · `spec-ready` (spec+plan+tasks exist) · `placeholder` (not yet specced)
- **FRs**: references into `specs/001-verity-governance-service/spec.md` unless noted
- **Depends on**: feature # must be substantially complete before this can be implemented
- **Blocks**: this feature is a prerequisite for feature #

---

## Build Waves (execution order — balances backend / UI / POC)

The numbered list below is a **catalog**, not a build order. Build in **waves**; each wave ends with
a **demo checkpoint** a non-technical stakeholder can click (no curl in demos). POCs run in parallel.

**Wave 0 — UI catch-up: get a loginable, clickable product over EVERYTHING already built (NOW).**
- **002 · UI shell + auth + portal for all shipped backend** (M1–M3 spec-ready; **add M4 intake UI**) →
  real login + onboarding + the full intake lifecycle (create → assess → submit → approve), all over
  the four shipped 001 slices.  ▶ *Demo: sign in → onboard an app → create an intake → assess → submit → tier-quorum approval — no curl.*
- This is the **highest-priority next move**: the backend is 4 slices ahead with no UI; 002 closes the gap in one feature.
- Parallel POCs (independent): **POC-A** (compliance ontology → 015), **POC-D** (tools → 005), **POC-E** (markup browser → 014).

**Wave 1 — resume backend; UI is now caught up.**
- **003 · Intake backend completions** (no new UI shell — extends the 002 portal as tabs land): assessment tabs 2–4 (Security/mitigations/Risk), requirements grow, change proposals, asset-linking schema. *Obligation resolution stays blocked → 015.*
- **004 · Shell polish** (toast/help/error) — small; unblocks write-feedback for all UI.
- **POC-C** (ground-truth framework — 001 backend is running).

**Wave 2 — authoring.**
- **005 · Entity registry** (backend, large) + **006 · Studio UI** (interleaved).  ▶ *Demo: author an agent/task.*
- **POC-B** (Opik/Comet → 011).

**Wave 3 — compliance + runtime.**
- **015 · Compliance metamodel** (seeds + enforcement; POC-A feeds it) → **un-stubs obligation resolution**, retro-wired into the assessment.
- **007 · Packaging** → **008 · Harness runtime** → **009 · Decision logging**.

**Wave 4 — the rest** — 010, 011, 012, 013/014, 016, 017, 018, 019, 020, ordered by the per-feature `Depends on` below.

**Principle:** never more than ~1 wave of backend ahead of UI. The backend (001) is currently **4 slices ahead of any UI** — Wave 0 (build 002, the UI for *all* shipped backend + the missed auth) closes that gap before any new backend is written. After that, UI rides alongside each backend feature as it lands (003's tabs extend the 002 portal, etc.).

---

## Main Track

---

### 001 · Governance Service — intake + application onboarding (backend)

| Field | Value |
|---|---|
| **Status** | **Shipped (slices 1–4)** — intake CRUD, application onboarding, intake assessment (capture/tier/ceiling), intake approval (tier quorum) |
| **PCR Phase** | Phase 1 |
| **Spec** | `specs/001-verity-governance-service/spec.md` (umbrella — all FRs live here) |
| **Plan** | `specs/001-verity-governance-service/plan.md` |

**What it delivers (shipped)**
- Slice 1: Intake CRUD — create, get, list, update, triage (status advance, role rewrite, auto-reject unacceptable), requirements CRUD
- Slice 2: Application onboarding — governed proposal + approval (kind=`application_onboarding`), compliance perimeter capture, app-team grants
- Slice 3: Intake assessment capture/tier/ceiling — AI Decision Impact tab, Data tab, risk tier + NAIC materiality computation, inherent tier record

- Slice 4: Intake approval — `kind=intake` approval request opened on explicit submit (requires a computed tier), tier-based quorum (FR-IN-005), sign-off recording with separation of duty (submitter ≠ signer), roll-up to `approved` via audited `change_status`, submit advances `proposed→in_review`. The approval router dispatches by `request_kind_code` to both `application_onboarding` and `intake` resolvers (`hub/src/verity/hub/approval/router.py`).

**NOT built (do not assume):** the FR-AP-004 post-approval cascade (plan generation, cost-envelope lock) and the FR-AP-005 intake **promotion gate** are NOT implemented — approval only sets `intake_status = approved`. Plan generation is feature **020**; the promotion gate is **012**. The tier-classification rules are a draft pending compliance review (`specs/001-verity-governance-service/rules-mapping.md`).

**Key hub modules**
`hub/src/verity/hub/`: `intake/`, `intake_approval/`, `application/`, `approval/`, `assessment/`, `auth/`

**Deferred to 003**
- Obligation resolution (FR-IN-014) — unseeded compliance metamodel
- Change-proposal re-approval (FR-IN-013)
- Asset linking / promotion gate (FR-IN-009)
- Assessment completion (FR-AS-004–010)

**Key FRs**: FR-IN-001–006, FR-IN-015–018, FR-AP-001–003 (approval primitive + onboarding/intake quorum; **FR-AP-004/005 deferred**), FR-AS-001–003 + FR-AS-008 inherent tier (FR-AS-004–010 deferred to 003), FR-AUTHZ-001–003  
**Depends on**: —  
**Blocks**: 002, 003, 005, 006, 007, 008, 009, 010, 011, 012, 013, 014, 015, 016, 017, 018, 019, 020, 021

---

### 002 · UI Shell, Auth & Portal for everything shipped (onboarding + intake)

| Field | Value |
|---|---|
| **Status** | spec-ready (M1–M3); **M4 intake UI to be added** |
| **PCR Phase** | Phase 1 |
| **Spec** | `specs/002-ui-shell-auth-onboarding/spec.md` |
| **Plan** | `specs/002-ui-shell-auth-onboarding/plan.md` |
| **Tasks** | `specs/002-ui-shell-auth-onboarding/tasks.md` (43 tasks, T001–T043 cover M1–M3; M4 extends) |
| **API contract** | `specs/002-ui-shell-auth-onboarding/contracts/portal-api.yaml` |

> **This is the UI catch-up.** The 001 backend shipped four slices with **no UI and no real auth**.
> 002 builds **one portal over everything that already works** — real authentication (the missed
> piece) + onboarding + the full intake lifecycle — so there's a loginable, clickable product before
> any more backend is written. Intake UI is **here, not in 003** (don't scatter UI across features).
> Scope tracks the shipped backend exactly: the assessment UI covers only the **shipped tabs**
> (AI-Decision-Impact + Data); the Security/mitigation tabs land in 003 with their backend.

**What it delivers**
- **M1 Auth shell — UI + auth backend** *(already scoped in 002 tasks T014–T023)*. Today the backend has a working `MockAuthenticator` but **no session and no login endpoints** — it re-resolves the principal from env vars on every request ([`auth/authenticator.py`](../../hub/src/verity/hub/auth/authenticator.py)), which suits tests but not a browser. 002 adds:
  - *Backend (T014–T018)*: `hub/src/verity/hub/auth/session.py` (NEW) — `/auth/login`, `/auth/callback`, `POST /auth/mock`, `POST /auth/logout`; a server-side session (`request.session`) so the principal resolves from a session, not per-request env; extended `GET /me` returns `email` + `app_team_roles` + `is_mock`.
  - *UI (T019–T023)*: sign-in page (`specs/ui/kit/pages/signin.html` faithful), auth-state takeovers (session-expired, 403, disabled), account menu (identity, roles, mock indicator).
  - **First login is MOCK-auth based** — `POST /auth/mock` (T016) establishes a session through the existing `MockAuthenticator`; this is the working path. The Entra `/auth/login` + `/auth/callback` endpoints are scaffolded (T014/T015) but full end-to-end Entra validation needs a dev-tenant registration and the `EntraAuthenticator` (still a stub) — deferred; the "Sign in with Microsoft" button renders, mock is the path that works now.
- **M2 App shell + landing**: five-region layout (rail/sidebar/topbar/canvas/statusbar); app-launcher modal; landing page with `display_name`, stats tiles, recent-decisions table
- **M3 Application onboarding UI**: applications registry, onboard form (multi-step, FlowIndicator), approval view (scroll-gate), application detail (4 tabs)
- **M4 Intake lifecycle UI** *(NEW — covers the shipped Slice 1/3/4 backend)*: intake create/detail/review screens (wireframe §2b: `intake.usecase-create/-detail/-review`); requirements list; the **shipped** assessment tabs (AI-Decision-Impact, Data) with computed tier/materiality readout; submit-for-approval + the tier-quorum sign-off view (reuses the M3 `/approvals/{id}/signoff` flow — same primitive, `kind=intake`)
- Portal scaffold at `hub/portal/` (Vite 5 + React 18 + TypeScript 5); kit CSS copied from `specs/ui/kit/styles/`; icon sprite at `hub/portal/public/sprite.svg`

**Critical implementation notes**
- `GET /me` must be extended to return `email` + `app_team_roles` + `is_mock` (currently returns only `actor_id`, `display_name`, `platform_roles`)
- Approval flow in portal: `POST /applications/{id}/submit` → get `approval_request_id` → `GET /approvals/{id}` → `POST /approvals/{id}/signoff` (NOT `POST /applications/{id}/approve`)
- `VITE_VERITY_ENV=local` + `VITE_AUTH_MODE=mock` env vars gate the mock-auth DOM section at compile time
- All API calls through `src/api/client.ts` — 401 → session-expired event, route-level 403 → forbidden takeover

**Key FRs**: `specs/features/user-authentication.md` FR-001–030; spec FRs FR-001–022; intake UI surfaces FR-IN-001–006 + FR-AS-001–003 + the approval/sign-off flow (FR-AP-001–003)  
**Depends on**: 001  
**Blocks**: 004 (shell polish builds on portal); 003's later assessment-tab UI extends the M4 portal

---

### 003 · Remaining intake work — obligation resolution, assessment completion, linking, change proposals

| Field | Value |
|---|---|
| **Status** | placeholder |
| **PCR Phase** | Phase 1 (completion) |

> **Scope note (corrected).** 003 is **intake BACKEND completions only — no UI here.** The intake UI
> (create / detail / review + assessment tabs + change-proposal flows) is built in **002**, alongside
> the onboarding UI, so there is **ONE portal covering everything the backend already supports** — UI
> is not scattered across features. Items below that are **blocked or differently-tracked**:
> **obligation resolution (FR-IN-014) → 015** (metamodel unseeded — not stubbable); **lifecycle stepper
> (FR-IN-011) → needs asset stages (005/012)**; **semantic dedup (FR-IN-008) → needs the embedding
> runtime**. The buildable-now backend here: requirements grow (FR-IN-007), change proposals
> (FR-IN-013), asset-linking schema (FR-IN-009), assessment Security/mitigation **capture**.

**What it delivers**

*Backend completions (hub modules: `intake/`, `assessment/`, `intake_approval/`):*
- **Assessment tabs 2–4** (FR-AS-004–010):
  - Security & Access tab: enumerate sources (read), targets (write/act), tools as approvable items; on intake approval each becomes governance-approved; exportable as Access Approval Record for ITSM/IAM (Verity records intent, does not provision IAM directly)
  - Mitigations & risk treatment (FR-AS-006–008): per risk-flagged answer — procedure, treatment type (avoid/reduce/transfer/accept), addressed canonical_requirement, owner, status, residual risk; `accept` of unmet required control routes to `approve_exception` (not a silent pass); inherent tier is fixed (NOT downgraded by mitigations), residual risk tracked separately
  - Risk & Obligations summary tab (FR-AS-009): computed read-only — tier + materiality + rationale, resolved obligation set, required approver quorum, outstanding justifications
  - Progressive disclosure + full revision history (FR-AS-010): follow-up questions appear only when triggered; full `intake_impact_assessment` history kept
- **Obligation resolution** (FR-IN-014): ⚠️ **BLOCKED — moved to depend on 015.** The compliance metamodel (`canonical_requirement`/`regulatory_provision`/`control`/`evidence_specification`) is **entirely unseeded** (0 rows), so there is *nothing to resolve against* — the "stub against reference seed data" is not viable. This item depends on **015 seeding the metamodel** (or POC-A producing a validated seed). Do NOT attempt it in this feature; the assessment captures answers forward-compatibly for it.
- **Requirements extensions** (FR-IN-007): grow `core.intake_requirement` to add `statement`, `acceptance_criteria`, `source`, optional `parent_requirement_id`, unique `code` within intake; reconcile shipped `title`/`body` fields to this shape
- **Semantic requirement dedup** (FR-IN-008): BGE-small 384-dim embedding via `embedding_config`; top-N similarity check (default top-5, min similarity 0.78) on candidate requirement text; non-fatal on failure
- **Change proposals** (FR-IN-013): risk reclassification and business change as `approval_request` kinds (`risk_reclassification`, `business_change`); scoped to the intake, select impacted assets; on approval each impacted asset gets a new `draft` forked from its champion; reuse `approval_request` + intake↔asset links (no separate screen)
- **Asset linking schema** (FR-IN-009 — partial): intake↔entity link table (intake, requirement, entity_type, entity_id, relationship: `implements`/`tests`/`monitors`/`informs`); reverse-lookup (intakes for an entity); link constraints (asset ≤1 intake, only while draft/candidate, not already linked); **promotion gate enforcement deferred to 012** (registry entities don't exist yet)
- **Intake lifecycle stepper** (FR-IN-011 revised): `in_build`/`live` steps derived from linked-asset stage roll-up, not intake attributes

*UI:* the intake **shell** (create/detail/review + shipped assessment tabs + submit/approval) ships in
**002 M4**, not here. What 003 adds to that portal as its backend lands:
- Assessment tabs 2–4 UI (Security & Access, mitigations, Risk & Obligations) — references `specs/ui/verity-intake-wireframe.html` as strangler prototype — built alongside their FR-AS-004–010 backend
- Change proposal UI: risk reclassification + business change flows within intake detail — built alongside the FR-IN-013 backend

**Key FRs**: FR-AS-004–010, FR-IN-007–009 (partial), FR-IN-011–014  
**Depends on**: 001 (intake approval shipped), 002 (portal exists for UI screens)  
**Blocks**: 005 (asset linking schema must exist before entity ↔ intake links can be written), 015 (obligation set must be recorded at intake for compliance enforcement to wire up)  
**ADRs**: ADR-0008 (obligation resolution references the three-axis model)

---

### 004 · Shell polish

| Field | Value |
|---|---|
| **Status** | placeholder |
| **PCR Phase** | Phase 1 UI |

**What it delivers**
- `shell.toast` — transient notifications + progress (>300ms operations get a spinner, >2s get a toast); success/warning/error/info variants; dismissible + auto-expire; wires into every form submit and API error path
- `shell.help` — contextual help popover (`?` affordance per section); inline explainer copy; keyboard shortcut `?`
- `shell.error` — error / 404 / generic-failure states; catch-all route; network-error overlay

**Key FRs**: wireframe catalog §0 (`shell.toast`, `shell.help`, `shell.error`)  
**Depends on**: 002 (portal scaffold + CSS kit)  
**Blocks**: all subsequent UI features that need toast feedback on write operations

---

### 005 · Entity model & registry (backend) — incl. YAML portability

| Field | Value |
|---|---|
| **Status** | placeholder |
| **PCR Phase** | Phase 2 |

**What it delivers**
- **Entity registration**: agents, tasks, prompts (header + immutable versions, SCD-2); tools, inference configs, data connectors, MCP servers (single-row, unversioned); map entity → application; upsert execution context keyed on `(application_id, context_ref)`
- **Composition**: prompt assignments (api_role, governance_tier, order, required, condition); tool authorizations (agent + task); agent-to-agent delegations (XOR pinned-version vs champion-tracking child; authorized flag; runtime gate); replace-association-sets (draft-only, transactional delete-all + batch-insert)
- **Source/Target Binding grammar** (renamed from v1 `source_binding`/`write_target` per ADR-0005/binding-grammar): uniform on tasks AND agents; tools + MCP agent-only; wiring DSL: `input.<path>`, `output.<path>` (targets), `const:<literal>`, `fetch:<connector>/<method>(input.<field>)` (sources); `content_blocks` binding kind for multimodal
- **Target Binding payload fields**: logical name, connector, write method, container hint, required, order, payload fields (DSL restricted to `input.*`/`output.*`/`const:*` — no `fetch:` on targets)
- **Config resolution**: priority chain `version_id > effective_date > champion`; assembles inference config + ordered prompts + authorized tools; frozen snapshot stored on decision log for replay
- **SCD-2 temporal windows**: NULL pre-champion; open sentinel on champion; closes on deprecation; champion-at-date temporal query; atomic champion-set (closes v1 race)
- **Operations**: clone-into-new-draft (provenance); draft update/delete (cascade; assigned-prompt FK block); in-place update tool/inference config (optimistic concurrency); where-used reverse lookup (`get_entity_consumers`) — must cover Source-Binding `fetch:` connector edges (v1 gap closed)
- **Model catalog + SCD-2 price**: insert/list/get model; set/get/list prices (at most one active price per model, DB-enforced); invocation cost point-in-time via price-window join; missing price → exclude from cost reports (no fabricated cost)
- **Tool data-classification** (FR-RG-013): `data_classification_max` (`tier1_public`/`tier2_internal`/`tier3_confidential` default/`tier4_pii_restricted`); `is_write_operation`; `requires_confirmation`; enforced pre-dispatch including MCP
- **YAML portability** (FR-YM-001–005, v2 closes v1 CLI-only gap): bundle export (BFS dep graph, leaves-first, name+version refs, deterministic byte-stable); lineage vs pinned scope; import (two-phase validate-then-write, ALL errors aggregated, dry-run/diff); idempotent skip-existing; force `draft` on import; intake YAML round-trip (no approval replay, no re-triage); exposed as gated API operations (`export_yaml`/`import_yaml` action codes)

**Key FRs**: FR-RG-001–014, FR-VM-001–005, FR-YM-001–005  
**Depends on**: 001 (application is the owning tenant), 003 (asset linking schema must exist before entity→intake links work)  
**Blocks**: 006 (Studio UI), 007 (packages need resolved composition), 011 (testing definitions reference entity types), 012 (lifecycle gates), 020 (plan generation references entity kinds), 021 (YAML portability builds on registry)  
**ADRs**: ADR-0005 (schema hardening + binding grammar), binding-grammar contract

---

### 006 · Studio — authoring canvas (UI)

| Field | Value |
|---|---|
| **Status** | placeholder |
| **PCR Phase** | Phase 2 |

**What it delivers**
- Entity list (agents/tasks/prompts) with lifecycle filter, materiality, search
- Agent/task compose canvas: library panel + composition panel + test panel (wireframe `specs/ui/verity-agent-studio.html` as strangler prototype)
- Prompt block editor: typed blocks, variable chips, blame gutter (`specs/ui/prompt-editor-v2.jsx` as reference)
- Version history + composition diff viewer (`specs/ui/prompt_editor_diff_v14_v150.html` as reference)
- Test-and-inspect panel: submit run, last output, perf summary
- Save-to-test-suite modal (capture inputs/mocks/expected outputs)

**Key FRs**: wireframe catalog §3 (`studio.*`); consumes FR-RG-001–014, FR-RN-002, FR-DL-001  
**Depends on**: 005 (entity model), 004 (toast for save feedback), 002 (portal shell)  
**Blocks**: —

---

### 007 · Package format & deployment gateway

| Field | Value |
|---|---|
| **Status** | placeholder |
| **PCR Phase** | Phase 3 |

**What it delivers**
- `.vtx` (task) / `.vax` (agent) package produced at champion promotion: resolved composition (inference, prompts, bindings, tool authorizations, schema) + digest-pinned compatible harness-image reference
- Insert-only package inventory (build recorded)
- Lifecycle-gated deployment: `staging` → non-prod only; `challenger` → prod in `shadow`/`ab` run-mode (switchable); `champion` → any live; `deprecated` → locked (restorable via rollback)
- Harness-image digest compatibility check — refuses mismatched package×environment; every attempt (success or refused) recorded in insert-only deployment inventory
- Governed deployment actions: `deploy_nonprod`, `deploy_prod`, `promote_champion`, `lock_deprecated`, `cleanup_deprecated` added to FR-AUTHZ-001 matrix

**Key FRs**: FR-PK-001–003, FR-LC-002 (channel map), FR-AUTHZ-001 (deploy actions)  
**Depends on**: 005 (registry entities + resolved composition must exist before packaging)  
**Blocks**: 008 (harness needs packages), 012 (deployment-placement enforcement in lifecycle gates)  
**ADRs**: ADR-0006

---

### 008 · Harness runtime

| Field | Value |
|---|---|
| **Status** | placeholder |
| **PCR Phase** | Phase 3 |

**What it delivers**
- Harness image + operator + Helm chart (lives in `harness/`)
- Federated coordinator: heartbeat-lease (atomic conditional update, split-brain impossible); leader failover does not interrupt in-flight workers
- Run dispatch: transactional outbox → NATS → coordinator-claim; `harness_dispatch` mutable operational state written in same transaction as append-only `execution_run_status` audit; `SKIP LOCKED` claim; janitor reclaim of stuck claims
- Worker execution loop: coordinator is sole hub uplink; workers do NOT call hub directly
- Enrollment: one-time short-lived token → cluster-scoped mTLS identity + app-scoped API key; outbound-only spoke→hub traffic; auto-rotating certificates
- App data-source credentials: metadata-only at hub (name, connector type, verification status — no secret value, no vault reference); secret stays on spoke
- Package deployment: load-once at claim time, old/new bundles coexist in cache (no drain on package deploy); image patch surfaces graceful vs force drain choice
- **Model reference chain resolution** (ADR-0019): `gateway_llm_call` resolves `inference_config_model` rows at claim time via `get_inference_config_chain`; walks chain by priority (1 = primary, 2+ = fallbacks) with exponential-backoff retries per candidate; on exhausted retries against priority-N, tries priority-N+1; `was_fallback` and `model_reference_id` written to `audit.model_invocation_log` on every invocation so compliance reviewers can identify decisions produced by non-primary models
- **MCP transport** (net-new scope — not a v1 port): v1 MCP supports `stdio` only; this feature adds `sse` and `http` transports required for cluster-deployed MCP servers per ADR-0016 §4 topology

**Key FRs**: FR-HR-001–006, FR-RN-001–007  
**Depends on**: 007 (packages to deploy)  
**Blocks**: 009 (runs generate decision logs), 012 (deployment and run-mode gates), 016 (production HA substrate replaces local Postgres/dispatch)  
**ADRs**: ADR-0010, ADR-0003 (API-only boundary), ADR-0019 (model reference chain resolution)  
**Key contracts**: `contract/gateway-openapi.yaml` (hub↔harness; this is the linchpin — only allowed cross-component dependency)

---

### 009 · Decision logging (backend)

| Field | Value |
|---|---|
| **Status** | placeholder |
| **PCR Phase** | Phase 4 |

**What it delivers**
- Append-only decision-log row per AI invocation: frozen inference snapshot, channel, mock mode, correlation ids (`workflow_run_id`, `execution_run_id`, `parent_decision_id`, `decision_depth`, `execution_context_id`), input/output summaries + payloads, reasoning, risk factors, confidence, model/token/duration metrics, tool calls, Source-Binding resolution audit (status: `resolved`/`skipped_no_ref`/`failed` + `mocked` flag), Target-Binding write audit (status: `wrote`/`logged`), HITL flags, status, redaction record, `reproduced_from_decision_id`, run purpose
- Append-only model-invocation-log row per decision: token counts (incl. cache tokens), timing, stop reason, model identity, cost computed point-in-time via SCD-2 price-window join
- Per-field HITL overrides: append-only, anchored by technical axis (`decision_log_id` + `output_path`) AND business axis (`application`, `entity_type`, `entity_reference`, `fact_type`); queryable by either axis
- Canonical execution envelope v1.0: terminal-only, `success`/`failure`, telemetry, provenance
- Async/batched ingest API path (ADR-0003/0004): callers never write DB directly; ≤20s p95 visibility
- Tier-1/Tier-2 seam: Postgres thin row + L2 logical-mart views; L1→materialized-mart swap transparent via L2 (deferred to 017)
- `decision_log_detail` levels: `full`/`standard`/`summary`/`metadata`/`none` (none = no row written; audit reconstruction must tolerate absence)

**Key FRs**: FR-DL-001–008  
**Depends on**: 008 (runs must exist to generate decisions)  
**Blocks**: 010 (observability UI reads decisions), 013 (HITL overrides reference decisions), 015 (evidence tied to decision runs), 017 (analytics tier sources from decision log), 018 (quota cost view uses invocation log)  
**ADRs**: ADR-0004 (thin Tier-1 + portable Tier-2), ADR-0007 (customer-portable analytics)

---

### 010 · Observability UI

| Field | Value |
|---|---|
| **Status** | placeholder |
| **PCR Phase** | Phase 4 + 7 |

**What it delivers**
- Runs list: filter by entity, state, time, outcome (wireframe catalog §5 `obs.runs`)
- Run detail = decision log: steps, tools, confidence, cost, binding-resolution audit (wireframe `obs.run-detail`; strangler `specs/ui/triage_agent_failing_cases.html` partial)
- Trace/span view: OpenInference/OTel spans per ADR-0013 (wireframe `obs.trace`)
- Live run stream: SSE via `verity.events.{run_id}` (wireframe `obs.live`; `liveChannel.js` kit building block not yet built — add to shell polish or here)

**Key FRs**: wireframe catalog §5; consumes FR-DL-001–008, FR-RN-006  
**Depends on**: 009 (decision + run data), 004 (shell polish), 002 (portal shell)  
**Blocks**: —  
**ADRs**: ADR-0013 (eval/observability tooling boundaries — embed Opik judge metrics, own the SoR, vendor tools call in read-only)

---

### 011 · Eval & testing harness

| Field | Value |
|---|---|
| **Status** | placeholder |
| **PCR Phase** | Phase 5 |

**What it delivers**
- **Ground-truth dataset model** (FR-TV-003): three-table model — dataset (status: `collecting`→`labeling`→`adjudicating`→`ready`→`deprecated`; quality: `silver`=single annotator / `gold`=multi-annotator with IAA), record (unlabeled; source: `document`/`submission`/`synthetic`), annotation (label; annotator: `human_sme`/`llm_judge`/`adjudicator`; exactly one authoritative annotation per record); kinded mocks (`tool`/`source`/`target`); storage-abstracted references (provider/container/key); `designed_for_version_id`, `applies_to_versions[]`, `superseded_by` lineage; IAA fields (`iaa_score`, `iaa_method`) for gold tier
- **Test suites + cases** (FR-TV-001–002): input/expected-output, metric type (`exact_match`/`schema_valid`/`field_accuracy`/`classification_f1`/`semantic_similarity`/`human_rubric`), adversarial flag, tags; test result: pass/fail, metric result, failure reason, timing
- **Validation runs** (FR-TV-004): status `running`→`complete`/`failed`; precision/recall/F1, Cohen's kappa, confusion matrix, field accuracy, fairness metrics + pass flag, threshold details; per-record drill-down (expected vs actual, correctness, match type/score, decision-log reference)
- **Model cards** (FR-TV-005): purpose, design rationale, I/O descriptions, limitations, conditions of use, LM-specific notes, validator reference, materiality classification, approval state
- **Opik judge metric embedding** (ADR-0013): judge scores recorded as annotations (feeds 013); OpenInference/OTel span capture; Comet experiment tracking integration for eval runs
- Metric thresholds per `(entity, materiality_tier, metric, field)`; field extraction config for tasks

**Key FRs**: FR-TV-001–005; ADR-0013  
**Depends on**: 009 (validation runs produce decision logs; run purpose=`validation`), POC-B (Opik integration patterns), POC-C (ground truth schema validation)  
**Blocks**: 012 (champion promotion gate requires `staging_tests_passed`, `ground_truth_passed`, `model_card_reviewed`, `challenger_metrics_reviewed`, `shadow_evaluation_reviewed`), 013 (annotation primitive used by ground-truth annotation layer)

---

### 012 · Entity lifecycle & promotion

| Field | Value |
|---|---|
| **Status** | placeholder |
| **PCR Phase** | Phase 6 |

**What it delivers**
- **Full 6-state lifecycle enforcement** (FR-LC-001–007): `draft`→`candidate`→`staging`→`challenger`→`champion`→`deprecated`; legal transition graph enforced; `deprecated` is restorable (not terminal); `shadow` is a challenger run-mode, not a state
- **Promotion gates** (FR-LC-003/004): `→challenger` requires `staging_tests_passed` + `staging_results_reviewed`; `challenger→champion` requires `shadow_evaluation_reviewed` (if shadow-mode), `ground_truth_passed`, `ground_truth_reviewed`, `model_card_reviewed`, `challenger_metrics_reviewed`, full compliance evidence set (FR-LC-004/FR-RP-011); `candidate→champion` fast-track NOT gate-free in v2 (closes v1 gap)
- **Champion confirmation** (FR-LC-005): explicit deliberate acknowledgement (e.g. name-typeback); enforced on ALL surfaces including JSON API (closes v1 API gap)
- **Atomic champion-set** (FR-VM-004): prior champion's SCD-2 window closes in same transaction as new champion's window opens; no race
- **Rollback** (FR-LC-007): atomically restores immediately-prior champion (deprecating current, reopening prior's SCD-2 window, repointing header); rejects when no prior champion exists (fixes v1 deprecate-only docstring)
- **Intake promotion gate** (FR-AP-005): blocks promotion when intake status not in `(approved, in_build, live)`, any open `intake`/`risk_reclassification` approval exists, or high-risk with no approved `promote_champion` request
- **Deployment-placement enforcement**: lifecycle state determines allowed environment kind and run-mode; wired to packaging gates from 007
- **Approval attestation** per transition: actor, rationale, all review flags, champion-confirmation fact

**Key FRs**: FR-LC-001–007, FR-VM-003–005, FR-AP-005, FR-AUTHZ-001 (deploy actions)  
**Depends on**: 007 (deployment gates), 008 (run-mode enforcement in harness), 011 (testing gate flags must be settable)  
**Blocks**: 013 (annotation surface needs lifecycle context for compliance controls), 015 (compliance gate hooks onto promotion at design/deploy/static/execution phases)

---

### 013 · Annotation & feedback (primitive)

| Field | Value |
|---|---|
| **Status** | placeholder |
| **PCR Phase** | Phase 8 |

**What it delivers**
- **Unified annotation primitive tables** (ADR-0014): target (ground-truth record field OR `decision_log_id`+`output_path`), annotator (`annotator_kind`: `human`/`llm`/`adjudicator` + actor), result (`label`, `score`, `explanation`), optional source locator (consumed by 014); append-only invariant
- **Ground-truth labeling lifecycle**: `collecting`→`labeling`→`adjudicating`→`ready`; exactly one authoritative annotation per record/field; adjudication resolves disagreements additively (never mutates)
- **HITL override engine**: per-field corrections anchored by BOTH technical axis (`decision_log_id` + `output_path`) AND business axis (`application`, `entity_type`, `entity_reference`, `fact_type`); never mutates the decision row; queryable by either axis
- **Judge score annotations**: `annotator_kind=llm_judge`; Opik judge metrics written as annotations (from 011); confidence-tiered
- **Annotation API**: append annotation, list by target (technical or business axis), get with provenance, mark authoritative

**Key FRs**: FR-DL-007 (HITL overrides), FR-TV-003 (ground-truth annotation layer), ADR-0014  
**Depends on**: 009 (HITL overrides reference `decision_log_id`), 011 (ground-truth annotation model is the substrate)  
**Blocks**: 014 (Verity Markup is the surface over this primitive), 015 (evidence capture uses annotation primitive)  
**ADRs**: ADR-0014

---

### 014 · Verity Markup

| Field | Value |
|---|---|
| **Status** | placeholder — **full spec already written** |
| **PCR Phase** | Phase 8 |
| **Spec** | `specs/features/verity-markup.md` — complete, do not re-specify |

**What it delivers**
- Browser-based document annotation surface: bbox drawing + text selection → resolves underlying text from page cache → creates annotation with source locator (`page`, `bbox`, `source_text`, `extraction_method`)
- AI-assisted extraction: governed executable run (NOT a direct model call) → `decision_log` + `model_invocation_log` row → `annotator_kind=llm` annotations requiring human acceptance; confidence-tiered indicator (≥0.85 high / 0.65–0.85 medium / <0.65 low)
- Dual-context: **labeling** (writes `ground_truth_record` annotations) vs **execution HITL review** (writes per-field HITL overrides anchored by `decision_log_id`); surface makes context explicit; cannot cross-write
- Schema-driven form: fields rendered from JSON Schema (executable output schema); required vs optional distinct; field-completion progress; completion validates against schema
- Provenance viewer: open field's provenance → highlight source region in document; page/bbox/`extraction_method`/score/annotator/timestamp
- Document processing: on-demand page processing (auto-detect `digital` vs `ocr`), page-cache with per-block bbox + confidence; neighbour prefetch (±1 immediate, ±2 background)
- Schema supersession: completed records re-validated on schema change → still-valid=low-priority flag, now-invalid=high-priority flag; resolution creates new version (`superseded_by` lineage)
- **Spoke-side mode mandatory for customer documents** (FR-MK-026); hub-side mode for synthetic/non-sensitive only

**Key FRs**: FR-MK-001–027 (all in `specs/features/verity-markup.md`)  
**Depends on**: 013 (annotation primitive tables + API), 006 (extraction executable is a registry entity + governed run), 008 (governed run path), 009 (decision log for AI extraction)  
**Blocks**: —  
**Note**: Run `/speckit-plan` scoped to `specs/features/verity-markup.md` when scheduling; annotation primitive tables (013) are a hard prerequisite

---

### 015 · Compliance metamodel & controls

| Field | Value |
|---|---|
| **Status** | placeholder |
| **PCR Phase** | Phase 8 |

**What it delivers**
- **Three-axis compliance model** seeded + enforced (FR-RP-003):
  - Left: regulatory frameworks + citable provisions (`jurisdiction`: `US-FED`/`US-NAIC`/`US-CO`/`INDUSTRY`)
  - Center (stable): canonical requirements + governance domains (9: `model_risk`, `fairness`, `privacy`, `security`, `transparency`, `robustness`, `data_governance`, `human_oversight`, `accountability`) + cumulative tier ladders (variable length; tier N implies all below)
  - Right: controls (`type`, lifecycle `phase`: `design_time`/`deploy_time`/`static_model`/`execution`, `enforcement_action`) + evidence specifications (`artifact_type`, `produced_by`, `citable_as`)
  - Bridge 1: provisions↔canonical requirements (many-to-many, minimum tier)
  - Bridge 2: canonical requirements↔controls/evidence (per tier, per phase)
- **Regulatory shelf seeded**: SR 11-7, NAIC AI Model Bulletin + Eval Tool, CO SB21-169, ORSA/ASOP-56/CAS; **net-new for v2**: NIST AI RMF, ISO/IEC 42001
- **Obligation resolution wired** (FR-IN-014): triage resolves applicable canonical requirements from intake governance domains + risk tier → obligation set recorded; 003 lands the stub, 015 seeds the actual metamodel data
- **Control enforcement wired** (FR-RP-007/011): design-time (blocks intake/compose); deploy-time (blocks deployment gate from 007); static/model (continuous checks on champion); execution (harness enforcement via 008)
- **Evidence capture** (FR-RP-008): each enforcement produces an append-only evidence audit fact tied to canonical requirement + tier + phase + entity/version/run
- **Exception governance** (FR-RP-009): registered exception (waived tier, canonical requirement, `approve_exception` approver — `compliance`/`security` roles, distinct from promotion sign-off, compensating controls, expiry); append-only; expired exception re-applies block
- **Per-domain maturity scoring** (FR-RP-010): highest tier with satisfied controls + evidence, normalized across variable-length ladders, aggregated per governance domain
- **Ontology layer** (ADR-0009): human-validated relational SoR for obligation determination; SKOS/OWL vocabulary for framework→canonical mapping

**Key FRs**: FR-RP-003–004, FR-RP-007–011  
**Depends on**: 012 (lifecycle gates are the enforcement points), 013 (evidence uses annotation primitive), POC-A (ontology vocabulary + regulatory mapping validation)  
**Blocks**: 016 (compliance enforcement must be wired before production hardening), 017 (compliance reports source from this metamodel)  
**ADRs**: ADR-0008, ADR-0009

---

### 016 · Production infrastructure

| Field | Value |
|---|---|
| **Status** | placeholder |
| **PCR Phase** | Phase 7 |

**What it delivers**
- HA Postgres via CloudNativePG: primary + read replicas; **authorization role resolution MUST read from primary** (never lagging replica — FR-015 immediate revocation requirement)
- NATS JetStream: replaces local dispatch; transactional outbox via `verity-relay`; at-least-once delivery with deduplication
- Shared session/role-cache store (Redis or equivalent): required for multi-replica `verity-governance`; per-process cache is a fail-closed blocker for multi-replica (session_epoch invalidation must propagate across replicas)
- HPA for `verity-governance` pods
- SSE event bridge: `verity.events.{run_id}` live stream from NATS to portal (feeds 010 obs.live)
- K8s/Helm packaging for all services: `hub/`, `harness/`, `infra/`
- Secrets from vault/managed identity (not `.env`); confidential Entra client over HTTPS

**Note**: This is a deployment milestone more than a product feature — infrastructure the Phase 7 PCR gate requires.

**Key FRs**: constitution Technical Standards (K8s/Helm source of truth), `user-authentication.md` NFR-006 + "What changes for production"  
**Depends on**: 015 (compliance enforcement must be wired before hardening the production path)  
**Blocks**: 017 (analytics tier needs object store)  
**ADRs**: ADR-0010 (NATS dispatch), ADR-0003 (API-only boundary hardened at TLS)

---

### 017 · Analytics & reporting

| Field | Value |
|---|---|
| **Status** | placeholder |
| **PCR Phase** | Phase 9 |

**What it delivers**
- Tier-2 columnar analytics: open Iceberg/Parquet on object storage; L1→materialized-mart swap (transparent via existing L2 logical-mart views — no caller changes)
- Report engine + composers (FR-RP-005): model inventory, decision/workflow audit trail, fairness validation summary, NAIC Exhibit C, intake inventory, approval audit log, impact-assessment register; `report_run_log` row (`pending`→`succeeded`/`failed`); output formats rendered
- Incremental analytics feed (FR-RP-006): opaque `(ingest_ts, source_pk)` keyset cursor; `next_cursor` + `complete` flag; allow-list guarded (refuses non-allow-listed view before any query runs)
- Customer-portable warehouse export: Iceberg/Parquet format; documented schema for customer BI tools
- Dashboard counts (FR-RP-001): catalog counts, total decisions, total overrides, open incidents; optionally application-scoped
- Override analysis (FR-RP-002): group HITL overrides by fact type + entity type over a window
- Audit packages (compliance officer surface): assemble logs + approvals + evidence per intake/entity

**Key FRs**: FR-RP-001–002, FR-RP-005–006  
**Depends on**: 016 (object store infra), 009 (decision log as Tier-1 source), 015 (compliance reports source from metamodel)  
**Blocks**: —  
**ADRs**: ADR-0004, ADR-0007

---

### 018 · Quotas

| Field | Value |
|---|---|
| **Status** | placeholder |
| **PCR Phase** | Cross-cutting (wires into Phase 4 run path) |

**What it delivers**
- Quota definition per scope (`application`/`agent`/`task`/`model`) + period (`daily`/`weekly`/`monthly`) + USD budget; alert threshold %; `enabled` flag; `hard_stop` flag
- Period-scoped spend from cost view (UTC windows: daily 00:00, weekly ISO-Monday, monthly day 1); `quota_check` outcome row: `breach` (≥100%), `warning` (≥threshold), none
- Batch checker: skip disabled, isolate per-quota failures, auto-resolve prior breach when cleared; check history; latest-per-quota; active-breach count
- **Soft enforcement** (default, preserves v1 behavior): records warning/breach, never refuses run
- **Hard-stop** (`hard_stop=true`): refuses invocation at execution time as an execution-phase control (FR-QT-004)
- Quota guidance for realized entity via envelope reverse-lookup (plan row → intake → locked cost envelope)

**Key FRs**: FR-QT-001–004  
**Depends on**: 009 (cost view from decision + model-invocation logs), 008 (hard-stop enforcement point in run path)  
**Blocks**: —

---

### 019 · Settings & RBAC admin

| Field | Value |
|---|---|
| **Status** | placeholder |
| **PCR Phase** | Cross-cutting (after lifecycle) |

**What it delivers**
- Workspace settings (name, config)
- Members & role-grant UI: grant/revoke platform roles (`security` role only per FR-023); grant/revoke app-team roles (app owner/lead or `security`); append-only grant history visible; anti-lockout enforcement (cannot remove last holder of role-administration capability); anti-self-escalation (no self-grant/elevate)
- API keys management (`settings.keys` wireframe)
- Quotas admin UI: create/update/delete quota definitions (wraps 018)
- Audit log of role changes (from `platform_role_grant` / `app_team_role_grant` append-only tables)

**Key FRs**: FR-AUTHZ-001 (`grant_platform_role`, `revoke_platform_role`, `grant_app_team_role`, `revoke_app_team_role`), `user-authentication.md` FR-023; wireframe catalog §9 (`settings.*`)  
**Depends on**: 012 (full lifecycle context for role grants to make sense), 002 (portal shell)  
**Blocks**: —

---

### 020 · Plan generation & business case

| Field | Value |
|---|---|
| **Status** | placeholder |
| **PCR Phase** | Post-Phase 5 (low priority) |

**What it delivers**
- Rule-based build-plan generation from intake `functional` requirements on intake approval (and on-demand); `intake_artifact_plan` rows flagged `auto_generated`; keyword-based entity kind + capability type mapping; high-risk intake auto-proposes ground-truth dataset + test suite
- Plan row: kind, name (unique per `(intake, kind, name)`), display name, description, inputs/outputs, capability type (`classification`/`extraction`/`generation`/`summarisation`/`matching`/`validation`), materiality tier, status (`proposed`/`in_progress`/`realized`/`cancelled`); realize: sets entity pointer, flips `realized`
- Plan estimate scenarios (at most one active per row): model, token sizes, invocations/year, peak multiplier, tool-call count; computed cost = `((in_tok×in_price + out_tok×out_price)/1e6) × (1 + 0.02×tool_calls) × invocations/year`; manual override requires override-USD + explanation (both or neither)
- Cost envelope lock: `total_estimate × 1.20` (fixed 20% upside); refuses when any plan row has neither estimate nor override (reports missing codes); records locking actor/role + authorizing approval reference
- ROI assessment: Forrester-TEI-for-P&C model; labor/loss-ratio/premium-uplift benefits; NPV, payback months, ROI%; lock applies to active scenario
- Actuals + drift: per-intake actual spend (yearly/30d/90d); drift: `within`/`trending_over`/`over`/none

**Key FRs**: FR-PL-001–009  
**Depends on**: 003 (intake approval triggers plan generation), 005 (plan rows reference entity kinds), 009 (actuals from decision log cost view)  
**Blocks**: —  
**Note**: Low priority per product owner. Plan generation fires on intake approval (FR-AP-004 post-approval cascade) but output is advisory — no lifecycle hard gate depends on it.

---

### 021 · YAML portability (standalone API surface)

| Field | Value |
|---|---|
| **Status** | placeholder — **already in scope for 005** |
| **PCR Phase** | Post-019 (low priority) |

**Note**: YAML portability (FR-YM-001–005) is included in **005** scope. This entry exists to ensure it is explicitly scheduled and not dropped. If 005 ships YAML as part of registry, 021 can be marked closed. If it gets deferred during 005 implementation, 021 is the tracking entry.

**What it delivers** (if deferred from 005)
- Bundle export/import as gated API operations (closes v1 CLI-only gap); dry-run/diff; intake YAML round-trip; transactional import (closes v1 partial-state risk)

**Key FRs**: FR-YM-001–005  
**Depends on**: 005 (registry entities must exist)  
**Blocks**: —

---

## POC / Parallel Tracks

---

### POC-A · Compliance ontology

| Field | Value |
|---|---|
| **Status** | placeholder |
| **Feeds** | 015 |

**What it delivers**
- SKOS/OWL vocabulary prototype for the three-axis compliance model: framework→provision→canonical requirement→governance domain→tier ladder
- Map SR 11-7 and NIST AI RMF onto the canonical-requirement + governance-domain + tier-ladder structure (two frameworks as validation)
- Validate ADR-0009's relational SoR approach (human-validated, reasoning-assisted obligation determination)
- Output: validated ontology artifacts, seeding approach, schema decisions for 015

**Can start**: Any time; requires reading FR-RP-003 + ADR-0008/0009 + the regulatory texts

---

### POC-B · Opik/Comet integration

| Field | Value |
|---|---|
| **Status** | placeholder |
| **Feeds** | 011 |

**What it delivers**
- Opik judge metric embedding into a stub decision-log write
- OpenInference/OTel span capture patterns validated against a sample governed run
- Comet experiment tracking integration for eval runs
- Output: SDK config decisions, integration patterns, span taxonomy for ADR-0013

**Can start**: Any time; independent of main track

---

### POC-C · Ground truth validation framework

| Field | Value |
|---|---|
| **Status** | placeholder |
| **Feeds** | 011, 014 |

**What it delivers**
- Prototype the ground-truth three-table model (FR-TV-003): dataset/record/annotation schema validation
- Annotation labeling lifecycle (`collecting`→`ready`) against a sample field schema
- Acceptance harness: execute a sample task package against a ground-truth record set, compare outputs, record pass/fail
- Output: validated schema decisions handed to 013, labeling lifecycle patterns for 014

**Can start**: After 001 backend is running (needs governance API surface)

---

### POC-D · Tools framework

| Field | Value |
|---|---|
| **Status** | placeholder |
| **Feeds** | 005 |

**What it delivers**
- Tool definition schema: function-calling format + MCP server binding patterns
- Tool-call capture in decision log (tool calls field in FR-DL-001)
- Tool data-classification enforcement (FR-RG-013): `data_classification_max`, `is_write_operation`, `requires_confirmation` pre-dispatch gates
- Output: tool-schema decisions, MCP binding patterns for entity model in 005

**Can start**: Any time; reference `hub/db/queries/` for existing schema patterns

---

### POC-E · Verity Markup browser prototype

| Field | Value |
|---|---|
| **Status** | placeholder |
| **Feeds** | 014 |

**What it delivers**
- Document canvas: PDF rendering, bbox drawing, text selection highlight (browser-only; no server dependency)
- Source-locator data model validation: page/bbox/source_text/extraction_method value object
- AI extraction stub: hardcoded mock response showing how `annotator_kind=llm` annotations would surface with confidence tiers
- Output: UI patterns, source-locator schema decisions, canvas library choice for 014

**Can start**: Any time; UI-focused, minimal backend dependency  
**Reference**: `specs/ui/verity_authoring_canvas_model.html` (authoring canvas patterns)

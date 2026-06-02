# Schema design-decisions register

Human-reviewed rulings on the cross-cutting design of the v2 hardened schema. Each entry
is a deliberate decision (not an agent default). The schema DDL is brought into line with
these as they are ruled. Related: [[0005-schema-hardening]], [[0004-storage-architecture]].

| # | Decision | Ruling | Date | Status |
|---|----------|--------|------|--------|
| 1 | Controlled vocabularies: enum vs reference table | **Reference tables** (hybrid) | 2026-05-31 | ✅ Ruled — pending DDL apply |
| 2 | Primary-key strategy | UUIDv7 entities; composite NK junctions; PG18+ | 2026-05-31 | ✅ Ruled — pending DDL apply |
| 3 | Schema namespacing | **3 schemas: `reference` / `core` / `audit`** | 2026-05-31 | ✅ Ruled — pending DDL apply |
| 4 | Append-only / history scope | **Hybrid** (see below) | 2026-05-31 | ✅ Ruled — pending DDL apply |
| 5 | Polymorphic refs / `executable` supertype | **Extensible shared parent** (see below) | 2026-05-31 | ✅ Ruled — pending DDL apply |
| 6 | Attribution — unified `actor` (human + automation) | **actor_id + acting_role_code everywhere**; named automation actor, optionally linked to application | 2026-05-31 | ✅ Ruled — pending DDL apply |
| 7 | Per-domain fidelity (intake, compliance) | intake ✅; compliance ✅ (`governance_domain` confirmed) | 2026-05-31 | ✅ Ruled — pending DDL apply |
| 8 | Packages, deployment & harness control plane | **Ruled** (see below) | 2026-05-31 | ✅ Ruled — pending DDL apply |
| 9 | Obligation determination & evidence mapping via ontology/reasoning (human-validated, relational SoR) | **ADR-0009** (layered hybrid) | 2026-05-31 | ✅ Ruled — DB implications feed the re-apply |

---

## D1 — Controlled vocabularies → reference tables (RULED 2026-05-31)

**Ruling:** Convert FE-facing / growable / ordered / grouped / hierarchical vocabularies
(~70) to reference tables in a single **`reference`** schema, using the pattern below.
**Keep ~9 hot-path internal state machines as native `enum`** (`runtime.run_status`,
`run_completion_status`, `run_entity_kind`, `run_write_mode`, `outbox_status`,
`auth_event_type`, `auth_event_outcome`, `decision_status`, `invocation_status`).

**Pattern:** `code text PK` + `label`, `description`, `sort_order`, `grouping`,
`parent_code` (hierarchy), `is_active` (soft-deprecate), `metadata jsonb`. Referencing
columns become `<vocab>_code text REFERENCES reference.<vocab>(code)`.

**Notable consequences:**
- `studio_role` and `platform_role` are identical → **collapse to one `reference.role`**.
- `approval_role` is a subset of roles → **`is_approval_role` flag**, not a parallel list.
- ~361 enum-typed columns repoint to `_code` FKs; reference data is seeded; editing
  reference data becomes a governed (auditable) action.

**Apply target:** `verity_schema.sql` enum block (L19–681) + the ~361 referencing columns;
revise `naming-conventions.md §9` and the ADR-0005 convention note.

### D1-amend — Reference tables are temporally-validated (RULED 2026-05-31)

Reference tables carry **`effective_start_date` + `effective_end_date`** (replaces a bare
`is_active`): retiring a value closes its window rather than deleting it. **`code` remains
the PK and FK target** (one row per code), so referencing FK integrity is preserved and
historic reporting resolves "which codes were valid as-of <date>" by date-window.
Trade-off: an in-place *label* change is not version-tracked (rare; add a companion history
table later if attribute-change history is required). Low cost (reference changes rarely);
gain is simpler historic reporting/extraction.

## D2 — Primary-key strategy (RULED 2026-05-31)

**Ruling:**
- **Entity & transaction & log tables:** surrogate `<table>_id uuid DEFAULT uuidv7()`
  (rationale: externally-referenced IDs must be non-enumerable; env-portable for
  YAML import/replay; v7 ordering for high-volume append tables).
- **Pure junction / bridge tables:** **composite natural PK** of the two FK columns
  (refines "surrogate everywhere"); no separate surrogate.
- **Reference tables:** `code text` PK (per D1).
- **Baseline PostgreSQL 18+** for the native `uuidv7()`; the only sanctioned <18 fallback
  is the real `pg_uuidv7` extension — never a `gen_random_uuid()` (v4) wrapper.

**Apply target:** every `CREATE TABLE` PK line; `naming-conventions.md §3`;
`ASSEMBLY-AND-VERIFICATION.md` uuidv7 shim notes.

### D2b — Specific column naming (RULED 2026-05-31)

Column names match the canonical model so no translation is needed:
- IDs: `<table>_id` (per D2); FKs `<ref_table>_id`.
- Coded/status columns: **`<vocab>_code`** FK → `reference.<vocab>` (e.g. `intake_status_code`,
  `lifecycle_state_code`, `control_phase_code`). **No bare `status` or `id` anywhere.**
- Other domain columns: specific (`risk_tier_code`, not `tier`).
- **Standardized system/meta columns** (identical across all tables, never domain-prefixed):
  `created_at`, `updated_at` (`timestamptz`); `created_by_user_id`, `updated_by_user_id`
  (`uuid` → `core.account_user`) where mutable/attributed. Append-only tables omit
  `updated_*` and carry `created_at` + a specific actor column (`actor_user_id`,
  `granted_by_user_id`).

## D3 — Schema namespacing (RULED 2026-05-31)

**Ruling:** Three schemas. Schemas are organizational + the Tier-1/Tier-2 seam, NOT a
security boundary (ADR-0003: one DB role).
- **`reference`** — controlled vocabularies (D1).
- **`core`** — all Tier-1 system-of-record: entities/versions/bindings/configs, intake,
  lifecycle, approvals, the **compliance metamodel** (frameworks→controls→evidence specs,
  exceptions, maturity), packages/deployment, **runtime execution state** (`execution_run`
  +events, outbox, quotas), auth identity + grants, testing/GT *definitions*, model cards,
  incidents, settings, report/mart *definitions*. (Renamed from `governance` — it holds
  more than governance concerns.)
- **`audit`** — Tier-2 high-volume append-only bulk logs only (the ADR-0007 externalization
  seam): `decision_log`, `model_invocation_log`, `auth_event`, **`evidence`** (compliance
  fact stream), execution/validation/evaluation logs, `report_run_log`.

**Consequences:** `runtime`/`governance`/`analytics`/`compliance` schemas collapse → fixes
finding #5 (no `runtime.` vs `governance.` mismatch). `analytics` is **external** (ADR-0007),
not a PG schema; mart views are thin local projections. `audit` Tier-2 tables are not FK
targets → **no hard cross-schema FKs**. `verity_schema.sql` scopes to the governance DB
only; vault is a separate database (PCR §3.1).

**Apply target:** header (`CREATE SCHEMA`/`search_path`); every schema-qualified name;
`naming-conventions.md §2`.

## D4 — Append-only / history scope (RULED 2026-05-31)

**Ruling — hybrid, applied uniformly:**
- **SCD-2 immutable versions** (full version history): `agent_version`, `task_version`,
  `prompt_version`, `model_price`.
- **Event-sourced** (dedicated event table + `_current` view) — keep: entity `lifecycle`,
  `champion`, role grants, `execution_run` state, `deployment`, compliance `exception`.
- **Bulk audit logs** (append-only, Tier-2): decision/invocation/auth/evidence + exec logs.
- **Status workflows** → **mutable `*_status_code` + ONE shared append-only
  `audit.status_transition` log** (history kept, simpler): `intake`, `intake_requirement`,
  `approval_request`, `incident`, `ground_truth_dataset`, `model_card`, plan status.
  Collapses the per-entity `*_status_event` tables + ~9 intake `_current` views.
- **Revisable figures → mutable row + `updated_at`/`updated_by`, NO prior-value history
  for now:** `intake_impact_assessment`, `intake_roi_assessment`, `intake_cost_envelope`,
  `intake_artifact_plan_estimate`, `domain_maturity`. *Pivot to SCD-2 only if a future
  compliance requirement demands it.*

**Apply target:** remove the redundant intake `*_status_event` tables + `_current` views;
add `audit.status_transition`; add mutable `*_status_code` cols; `incident`/`ground_truth_dataset`
keep their mutable status but also write to the shared log.

## D8 — Deployment status/health + harness flavor/version model (OPEN — sketched 2026-05-31)

Champion promotion **does not imply deployment** — deployment is a separate, tracked
lifecycle with health. The current `packages_deploy` domain (`harness_image`, `package`,
`package_harness_image`, `deployment_environment`, `deployment_cluster`, `deployment`)
covers part of this; it must be expanded to:
- **Harness flavor + version:** `harness_flavor` (variant/capability line) → `harness_image`
  (a flavor at a version, pinned by digest). Replaces the flat digest-only registry.
- **Package ↔ compatible harness:** `package_harness_compatibility` linking a package
  (agent/task version) to the compatible **flavor + version(s)** (range or explicit),
  enforced at the deploy gate (ADR-0006 digest-pinning).
- **Deployment status + health:** `deployment` (current placement: package, image, cluster,
  env, run-mode, lifecycle state) + an append-only **`deployment_health_event`** /
  heartbeat log (`audit`) → `deployment_health_current` view (healthy/degraded/down,
  last_seen) tying to the PCR worker-heartbeat (§3.3).

Detailed DDL to be designed in the **packages/deployment domain review** (with Decision 7).
Relates to [[0006-packages-and-governed-deployment]].

## D5 — Polymorphic references / the `executable` supertype (RULED 2026-05-31)

**Ruling — extensible shared parent:**
- Introduce **`core.executable`** (parent; `executable_id` PK, `kind_code` →
  `reference.executable_kind`) and **`core.executable_version`**. `agent`/`task` (and any
  future kind) are sub-types that FK into it. Polymorphic refs (lifecycle, champion,
  deployment, bindings) point at `executable_version` with **one real, checked FK** — no
  soft `entity_type`+`entity_id` pair, no per-type columns.
- **Kinds are data** (`reference.executable_kind`), so a new deployable kind = a reference
  row + a sub-table; the lifecycle/champion/deployment tables don't change.
- **Packaging is a separate layer**, NOT the supertype: a `package` (.vtx/.vax) is produced
  from a champion `executable_version`; whether a kind is packaged is
  `reference.executable_kind.is_packaged` + `package_format`. Supports "tracked but not
  packaged" kinds for free. (Avoids mislabeling the parent as "package"/"deployable".)
- **Components** (`prompt`, `tool`, `data_connector`, `mcp_server`): keep `*_version` rows
  (full historic reproduction) but have **no lifecycle/champion** and are **not** in
  `executable`. They attach to an `executable_version` (e.g. `entity_prompt_assignment`).
- **Prompt** is governed **within** its agent/task (no independent champion); a
  `prompt_version` may be reused across many `executable_version`s at different stages.
- **Heterogeneous scopes** (`quota.scope_id` = application|agent|task|model) and **cross-tier**
  audit→core refs remain soft (no clean supertype / Tier-2 not an FK target).

**Apply target:** add `core.executable`/`executable_version` + `reference.executable_kind`;
repoint `versioned_entity_type` refs (lifecycle/champion/deployment/bindings) to
`executable_version`; remove `prompt` from `versioned_entity_type`; keep component
`*_version` tables.

## D6 — Attribution: unified `actor` (human + automation) (RULED 2026-05-31)

**Ruling — every action is attributed by `actor_id` + `acting_role_code`, uniformly:**
- Introduce **`core.actor`** supertype (`actor_id` PK, `actor_type_code`, `display_name`,
  `primary_role_code` → `reference.role`, `is_active`). Subtypes: **`core.account_user`**
  (human; Entra `tenant_id`+`microsoft_oid`) and **`core.automation_actor`** (machine;
  harness/runtime per app, or a named automated job). Same shared-parent pattern as D5.
- **Humans** get a **primary role + secondary roles**; the *system auto-selects* the
  appropriate role for each action (no manual role-switching). In **mock/testing** the user
  may pick the role explicitly (FR-030).
- **Automation actors** have a name + role (role may equal the name, or `automation`); all
  machine-written records (decision logs, system transitions) are attributed to one.
- **Role grants** hang off `actor_id` (append-only) with an **`is_primary`** flag (one
  primary). `app_team_role` stays per-application.
- **Attribution columns** (retire free-text/email/persona): mutable rows →
  `created_by_actor_id`/`created_role_code` (+ `updated_*`); append-only →
  `actor_id`/`acting_role_code`; approvals → `approver_actor_id`/`signed_as_role_code`.
  All `*_actor_id` → `core.actor`; all role codes → `reference.role`, server-validated
  against the actor's held roles.

**Automation-actor granularity (RULED):** a **named automation actor, optionally linked to
its `application`** (so logs read "automation `X` on behalf of app `Y`").

**Apply target:** `auth`/identity tables (`account_user` → `actor` supertype +
`automation_actor`); role grants gain `is_primary`; every `*_user_id`/`created_by`/
`approver_email`/`acting_as_role` across the schema → `*_actor_id` + `*_role_code`.

## D7 — Per-domain review

### Intake (RULED 2026-05-31)

- **Obligation model confirmed.** `intake_obligation_resolution` (the event of determining
  what an intake must comply with) → `intake_obligation` rows (canonical_requirement +
  target maturity tier). Drives controls/evidence (ADR-0008). Resolution stays
  **append-only** (auditors need "what was required as-of approval"; re-classification = new
  resolution).
- **D4 collapse applied:** drop the 6 event/lock tables (`intake_status_event`,
  `intake_requirement_status_event`, `intake_artifact_plan_status_event`,
  `approval_request_status_event`, `intake_roi_assessment_lock_event`,
  `intake_cost_envelope_lock_event`) + their `_current` views → mutable `*_status_code`
  (+ `locked` flags) + shared `audit.status_transition`. ~19 → ~13 tables.
- **`intake_impact_assessment` KEEPS full history** (SCD-2/versioned) — the audit-sensitive
  exception to "revisable figures mutable"; ROI/estimate stay mutable.
- **D5 links:** `intake_entity_link.entity_id`, `intake_artifact_plan.realized_entity_id`
  → `executable_version` (checked FK). **D6:** attribution → `*_actor_id` + `*_role_code`.
  `approval_signoff` stays append-only.

### Compliance (RULED 2026-05-31)

- **Three-axis / two-bridge model confirmed faithful** (framework→provision | governance_domain→
  canonical_requirement→requirement_tier (cumulative) | control(phase×type×enforcement)→
  evidence_specification; Bridge 1 provision_requirement(min_tier); Bridge 2
  requirement_control(per tier/phase); evidence; exception; domain_maturity). control_phase =
  design_time/deploy_time/static_model/execution.
- **ALL axes + both bridges are effective-dated** (`effective_start_date`/`effective_end_date`)
  with **versioning-on-change** (close current row + insert new version) for **full as-of
  reproducibility**. Bridges/obligations/evidence reference the **stable business key + as-of
  date**. (Stronger than the reference-table validity-lite of D1-amend — intentional for the
  compliance spine.)
- **D3:** metamodel → `core`; `evidence` (Tier-2) → `audit`. **D1:** control_phase/type,
  enforcement_action, evidence_artifact_type, mapping_source, coverage_level, exception_status
  → reference vocab. **D6:** `evidence.produced_by` = **actor** (auto-captured → automation
  actor; attested → human); `exception` approver → `approver_actor_id` + `signed_as_role_code`
  (`approve_exception` action). **Keep:** `exception` event-sourced; `domain_maturity`
  append-only snapshots.
- **`governance_domain`** → reference vocab. **Name confirmed `governance_domain`** (AI-governance
  areas, broader than compliance; matches the "AI governance domain" framing).

## D8 — Packages, deployment & harness control plane (RULED 2026-05-31)

Renamed `harness_flavor` → **`harness_variant`**. **champion ≠ deployed.** Three distinct
things: **cluster** (infra), **`harness_instance`** (a running harness container on a cluster
— the "collector", BigID-style), **`package_deployment`** (a package placed to run).
**Digest** = a content fingerprint (`sha256:…`) of an artifact's exact bytes; a deployment
pins **both** the `package_digest` and the resolved harness `image_digest` for reproducibility.

**Harness control plane (two-directional):**
- `harness_variant` (execution-engine variant, e.g. `claude_agentic_loop`) → `harness_image`
  (variant + version + `image_digest`).
- `harness_instance` — running harness on a cluster: `current_image` + `desired_image`
  (patch by desired-vs-current convergence), owned/shared scope, `status`
  (active/draining/disabled), denormalized `last_seen`.
- **Up:** `harness_heartbeat` (**audit**, append-only, partitioned) — **minor** (frequent/light)
  + **major** (less frequent/full, carries the **running-package catalog**) →
  `harness_instance_health_current`, `harness_running_package_current`; enables **drift
  detection** (actual vs intended deployments).
- **Down:** `harness_instance_command` (append-only) — portal→agent: patch/restart/drain/
  enable/disable/reload_packages; status pending→acknowledged→succeeded/failed.
- Logs/diagnostics are **NOT** in the SoR → observability; a `collect_diagnostics` command
  points to them.

**Package deployment:**
- `package` (`.vtx`/`.vax`, `package_digest`) from an `executable_version` (D5).
- `package_harness_compatibility` — package ↔ **variant + version range** (declare loose;
  deploy resolves + pins the exact harness `image_digest`).
- `package_deployment` — package on a target cluster, pinned harness `image_digest`,
  `run_mode`, environment, `status`; **lifecycle-gated** (staging/shadow/challenger/champion
  → 0..N targets per the ADR-0006 matrix).
- `package_deployment_event` — append-only governed ops + outcome + actor.
- `deployment_connection` — env-specific connections; in the SoR **and** materialized into
  the package bundle (runtime self-contained).
- `deployment_binding_override` — per Source/Target binding `real | mocked` (+ payload);
  **`run_mode` read-only forcibly suppresses/mocks Target Bindings** (shadow/challenger
  safety rail).
- `deployment_environment`, `deployment_cluster` (`non_prod`/`prod`/`ephemeral`).

**Cross-cutting:** vocab → `reference` (variant, run_mode, deployment_operation, outcome,
health_status, command_kind, environment_kind); control plane + deployment inventory →
`core`, heartbeats → `audit`; `package` → `executable_version`; actor attribution incl.
**automation actors**; deployment `status` mutable + append-only events; health append-only
+ current view. Relates to [[0006-packages-and-governed-deployment]], [[0002-execution-model]].

**Run-mode semantics (clarified 2026-05-31):** `live` (champion: full Source+Target
bindings, all traffic) · `read_only` (**shadow**: full Source bindings, **Target bindings
forcibly suppressed** → zero data impact) · `ab` (**challenger/A-B**: full Source+Target
bindings on a **scoped sample**; the run input carries an optional **`ab_sample`** marker
scoping it to the package/deployment; decision logs tagged for champion-vs-challenger
comparison) · `locked` (deprecated: no execution). Run-modes are **`live` / `shadow` / `ab`
/ `locked`**. A `lifecycle_deployment_rule` table encodes the
state→environment→allowed-run-modes→output-suppression matrix as auditable data.

**LIFECYCLE AMENDED TO 6 STATES (2026-05-31):** `draft → candidate → staging → challenger
→ champion → deprecated`. v1's **`shadow` is no longer a state** — it is a **challenger
run-mode** (a challenger deploys in `shadow` or `ab`, **freely switchable**, no state
change). **`deprecated` is restorable via rollback** (`deprecated → champion`; `is_terminal
= false`). CHANGE-with-reason vs v1's 7 states (no silent loss). Docs updated: PCR,
constitution, ADR-0002/0005/0006, design-system. **Pending sweep:** the 001 component-spec
lifecycle FRs (FR-LC transition graph) + retirement of the old draft schema files.

### D9 — Obligation/evidence reasoning → [[0009-obligation-reasoning-ontology]] (RULED 2026-05-31)

Layered hybrid: **Postgres is the system-of-record**; **SPARQL via a virtual knowledge graph**
(OBDA/R2RML) over `core`/`reference`/`compliance`; **heavy reasoning via an optional
triplestore as a derivation engine** that **recommends**, with **human validation**
(`derivation_method = human_validated`) before anything is authoritative; reasoner **never
auto-commits**; derivations are explainable. Scope = metamodel, not raw `audit` logs. Engine
choice deferred to the component spec.

**DB implications to fold into the re-apply:** stable IRI scheme (`schema.table.<uuid>` +
reference `code`s); **generalized provenance** on derivable rows (`derivation_method`,
`ontology_version`, `confidence`, `validated_by_actor_id`); reference tables documented as
**SKOS** (`parent_code` = broader/narrower); a small `ontology_version` reference; keep
relations explicit (no catch-all JSON).

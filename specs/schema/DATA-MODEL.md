# Verity Data Model

The canonical hardened schema. **One file per object** under `reference/`, `core/`, `audit/`;
load via `verity_schema.sql`. Find any table in `TABLE-INDEX.md`. The human-reviewed design
rulings behind this model are in `DESIGN-DECISIONS.md` (D1–D10); related ADRs in `../adrs/`.

## The three schemas (D3)

| Schema | Holds | Tier |
|---|---|---|
| **`reference`** | controlled vocabularies (code-lists) | — |
| **`core`** | the system-of-record metamodel + transactional state | Tier-1 |
| **`audit`** | high-volume append-only logs (decision/invocation/evidence/auth/heartbeat/transitions) | Tier-2 |

Schemas are organizational + the Tier-1/Tier-2 seam (ADR-0004) — **not** a security boundary
(one DB role, ADR-0003). `audit` is the external-analytics seam (ADR-0007); its tables are
**not FK targets** (soft `uuid` refs to `core`, validated at the API layer).

## Key design constructs

- **Reference tables, not enums (D1).** Every controlled vocabulary is a `reference.<x>`
  table: `code` PK, `label`, `sort_order`, `grouping`, `parent_code` (= SKOS broader/narrower),
  `effective_start/end_date` (retire = close the window). The FE reads these; values change
  as data (INSERT), not DDL. A few hot-path internal state machines stay native `enum`
  (`run_status`, `decision_status`, `auth_event_*`, …).
- **Keys (D2).** UUIDv7 surrogate PKs (`<table>_id`); pure junctions use composite natural
  keys; PostgreSQL 18+ (`uuidv7()`). Columns are specifically named (`*_code`, `*_id`); no
  bare `id`/`status`. Standard meta columns: `created_at/updated_at`, `created_by_actor_id`.
- **Unified `actor` (D6).** One attribution identity — **human** (`account_user`, Entra) and
  **automation** (`automation_actor`, the harness) share `core.actor`. Every auditable row
  carries `*_actor_id` + `*_role_code`. Roles are granted append-only (`actor_role_grant`,
  `actor_app_role_grant`).
- **`executable` supertype (D5).** `agent`/`task` are *kinds* of one `core.executable`
  (kind = data, extensible). Lifecycle, champion, bindings, packaging, and deployment all
  point at `executable_version`. Prompts/tools/connectors/MCP are versioned **components**
  (no lifecycle), attached to a version. **Packaging is a separate layer** from identity.
- **History patterns (D4).** *SCD-2 versions* (`*_version`, the compliance axes, `model_price`,
  impact-assessment); *event-sourced + `_current` view* (lifecycle, champion, runs, grants);
  *mutable `*_status_code` + the shared `audit.status_transition` log* for ordinary workflows;
  *mutable rows* for revisable figures.
- **6-state lifecycle.** `draft → candidate → staging → challenger → champion → deprecated`.
  `shadow`/`ab` are **challenger run-modes** (switchable), not states; `deprecated` is
  restorable via rollback.
- **Compliance: three axes, two bridges (ADR-0008).** frameworks→provisions →
  canonical_requirements (in governance_domains, cumulative tiers) → controls (4 phases) +
  evidence_specs; bridges `provision_requirement` (min-tier) and `requirement_control`. All
  evolving axes are **SCD-2 effective-dated** so past obligations/evidence resolve as-of.
  Intake resolves an **obligation set**; reasoning may recommend it, human-validated (ADR-0009).
- **Model decoupling + fallback (D10).** `inference_config` points at stable
  `model_reference`s (ordered: primary + fallbacks), each resolving to an actual `model` via
  an effective-dated binding — **swap a model centrally with no re-promotion**; fall back per
  executable when a provider is down.
- **Governed deployment + harness control plane (D8/ADR-0006).** Packages declare
  digest-pinned harness compatibility; deployment is governed, lifecycle-gated (the
  `lifecycle_deployment_rule` matrix as data). `harness_instance`s heartbeat (minor/major +
  running-package catalog → drift) and take portal commands (patch/drain/…).


## Tables by subject

Every table/view/enum, grouped by subject area, with its purpose. (Index: TABLE-INDEX.md.)


### identity

| Object | Schema | Kind | Purpose |
|---|---|---|---|
| `account_user` | core | table | tier:1. Human actor subtype (Entra identity). Keyed on immutable (tenant_id, microsoft_oid); email/upn display-only. user-authentication.md. |
| `actor` | core | table | tier:1. Unified attribution principal (human or automation). Single actor_id target for actor_id + acting_role_code across the schema. D6. |
| `actor_role_grant` | core | table | tier:1 append-only. Platform-role grant/revoke events per actor; is_primary = default capacity. Current state via current_actor_role. D4/D6. |
| `actor_type` | reference | table | Vocabulary: kind of actor (human vs machine). D1/D6. |
| `automation_actor` | core | table | tier:1. Automation actor subtype: named machine principal, optionally on behalf of an application. D6. |
| `role` | reference | table | Vocabulary: platform/governance roles (v1 studio_role+platform_role collapsed). is_approval_role = v1 approval_role subset. D1. |
| `current_actor_role` | core | view | Effective platform roles per actor (latest non-revoked grant per role). D4. |

### registry

| Object | Schema | Kind | Purpose |
|---|---|---|---|
| `api_role` | reference | table |  |
| `binding_delivery_mode` | reference | table |  |
| `capability_type` | reference | table |  |
| `connector_type` | reference | table |  |
| `data_classification` | reference | table |  |
| `data_connector` | core | table | tier:1 component. A configured connection to a storage/data backend (connector_type). Backend config (bucket/container/base path/auth ref) in the connector vers |
| `data_connector_version` | core | table |  |
| `executable` | core | table | tier:1. SUPERTYPE: the governed/versioned/promotable unit (agent, task, future kinds). kind_code discriminates; no mutable champion/lifecycle columns (event-sou |
| `executable_kind` | reference | table | Vocabulary: kinds of executable (agent, task, future). is_packaged/package_format decouple "governed" from "packaged" (D5/D8). New kind = new row, no schema cha |
| `executable_mcp_assignment` | core | table |  |
| `executable_prompt_assignment` | core | table | tier:1. A prompt_version used by an executable_version in an api_role. Uniform for agent+task. D5. |
| `executable_tool_assignment` | core | table | tier:1. Tool attached to an AGENT version. agent-only enforced by composite FK to (executable_version_id, kind_code) + CHECK kind=agent (binding-grammar). D5. |
| `executable_version` | core | table | tier:1 immutable SCD-2 version of an executable (valid_from/valid_to). Lifecycle/champion/bindings/deployment all reference THIS. kind_code denormalized to enfo |
| `governance_tier` | reference | table |  |
| `inference_config` | core | table | tier:1. Inference parameters for an executable_version. The MODEL is decoupled: resolved via an ORDERED list of model_references (inference_config_model, in 06- |
| `mcp_server` | core | table |  |
| `mcp_server_version` | core | table |  |
| `prompt` | core | table | tier:1 component (no lifecycle). Reusable prompt; content lives in prompt_version. D5. |
| `prompt_version` | core | table | tier:1 immutable prompt version (full historic reproduction). No lifecycle — governed within the executable that uses it. D5. |
| `source_binding` | core | table | tier:1. Declarative INPUT resolved before the executable runs (v1 source_binding renamed). Files-from-storage via connector + locator + delivery_mode (inline/re |
| `source_kind` | reference | table |  |
| `target_binding` | core | table | tier:1. Declarative OUTPUT written after the executable runs (v1 write_target renamed). Files-to-storage via connector + locator + write_mode. Uniform for agent |
| `tool` | core | table |  |
| `tool_transport` | reference | table |  |
| `tool_version` | core | table |  |
| `trust_level` | reference | table |  |
| `version_change_type` | reference | table |  |
| `write_mode` | reference | table |  |

### lifecycle

| Object | Schema | Kind | Purpose |
|---|---|---|---|
| `approval_decision` | reference | table |  |
| `approval_request` | core | table | tier:1. General gating request (lifecycle promotions + intake). Exactly one target (intake XOR executable_version). status_code mutable; history in audit.status |
| `approval_request_status` | reference | table |  |
| `approval_signoff` | core | table | tier:1 append-only audit fact. Per-approver sign-off keyed by the required role filled (signed_as_role_code), by a real actor (FR-018/D6). One sign-off per requ |
| `champion_assignment` | core | table | tier:1 append-only. Champion pointer events (assign/revoke). Current champion via entity_champion_current. Replaces v1 mutable champion column (D4/C6). |
| `lifecycle_event` | core | table | tier:1 append-only. One executable_version state transition per row; current state via entity_lifecycle_current. D4. |
| `lifecycle_state` | reference | table | Vocabulary: the 6-state executable lifecycle (v1 7-state CHANGED: shadow folded into a challenger run-mode). sort_order = progression. deprecated is_terminal=fa |
| `entity_champion_current` | core | view | Current champion executable_version per executable (latest non-revoked assignment). D4. |
| `entity_lifecycle_current` | core | view | Current lifecycle state per executable_version (latest transition). D4. |

### intake

| Object | Schema | Kind | Purpose |
|---|---|---|---|
| `actor_app_role_grant` | core | table | tier:1 append-only. Per-application app-team role grants (app_*: owner/lead/dev/sre/ops). Current via current_actor_app_role. D6. |
| `ai_risk_tier` | reference | table |  |
| `app_team_role` | reference | table |  |
| `application` | core | table | tier:1. Business application that owns intakes/use-cases and (via app-team grants) its own team. |
| `artifact_plan_status` | reference | table |  |
| `derivation_method` | reference | table |  |
| `intake` | core | table | tier:1. Use-case intake header. intake_status_code mutable (D4; transitions in audit.status_transition). Risk/materiality drive the obligation set. data_classification_code = the intake's actual sensitivity (assessment Data tab), <= the app ceiling (FR-IN-018). |
| `intake_artifact_plan` | core | table |  |
| `intake_artifact_plan_estimate` | core | table |  |
| `intake_cost_envelope` | core | table |  |
| `intake_entity_link` | core | table |  |
| `intake_impact_assessment` | core | table | tier:1 SCD-2 versioned. The audit-sensitive figure that KEEPS full history (D4 exception): immutable revisions, current = valid_to IS NULL. |
| `intake_obligation` | core | table | tier:1. A resolved obligation (canonical_requirement + target tier) this intake must satisfy. Compliance FKs wired in 05-compliance (deferred). FR-IN-014. |
| `intake_obligation_resolution` | core | table | tier:1 append-only. One obligation-set resolution per (re)classification; latest = current, history retained. D9 provenance (method/ontology_version/confidence) |
| `intake_requirement` | core | table |  |
| `intake_roi_assessment` | core | table |  |
| `intake_status` | reference | table |  |
| `materiality_tier` | reference | table |  |
| `naic_materiality` | reference | table |  |
| `requirement_kind` | reference | table |  |
| `requirement_status` | reference | table |  |
| `current_actor_app_role` | core | view | Effective per-application app-team roles per actor (latest non-revoked grant). D6. |
| `intake_impact_assessment_current` | core | view |  |

### compliance

| Object | Schema | Kind | Purpose |
|---|---|---|---|
| `canonical_requirement` | core | table | tier:1 SCD-2. Center axis: the stable, technology-agnostic requirement vocabulary, grouped by governance_domain. Versions for as-of reproducibility. ADR-0008/D7 |
| `compliance_exception` | core | table | tier:1 first-class audit. A controlled, time-boxed waiver of a requirement tier: compensating controls, named approver (approve_exception), expiry. status mutab |
| `control` | core | table | tier:1 SCD-2. Right axis: an enforcement control at a lifecycle phase. Versions as controls mature (D7). phase lives here (requirement_control derives it — reso |
| `control_phase` | reference | table |  |
| `control_type` | reference | table |  |
| `coverage_level` | reference | table |  |
| `domain_maturity` | core | table | tier:1 append-only. Per-domain normalized maturity score snapshots (trend history). Latest via domain_maturity_current. D7. |
| `enforcement_action` | reference | table |  |
| `evidence_artifact_type` | reference | table |  |
| `evidence_specification` | core | table | tier:1 SCD-2. The evidence a control must produce (artifact_type/produced_by/citable_as). The actual evidence facts are Tier-2 (audit.evidence, 06). ADR-0008. |
| `exception_status` | reference | table |  |
| `governance_domain` | reference | table | Vocabulary: AI-governance domains; unit of maturity scoring (D7). parent_code allows sub-domains. |
| `provision_requirement` | core | table | tier:1 SCD-2. Bridge 1: many-to-many provision->requirement with min-tier. Effective-dated (mappings change as regs are mapped). derivation_method = manual/reas |
| `regulatory_framework` | core | table | tier:1. Left axis: a regulatory framework (NAIC, EU AI Act, SR 11-7…). Stable identity + validity window. ADR-0008. |
| `regulatory_provision` | core | table | tier:1 SCD-2. Left axis: a citable provision within a framework; versions over time (amendments). ADR-0008/D7. |
| `requirement_control` | core | table | tier:1 SCD-2. Bridge 2: which controls satisfy a requirement at a tier (phase derived from control, not stored — resolves verification S4). Effective-dated. |
| `requirement_tier` | core | table | tier:1 SCD-2. Cumulative tier ladder per canonical requirement (tier N implies all below). Variable depth per requirement. ADR-0008. |
| `domain_maturity_current` | core | view |  |

### decisions

| Object | Schema | Kind | Purpose |
|---|---|---|---|
| `auth_event_outcome` | audit | enum |  |
| `auth_event_type` | audit | enum |  |
| `decision_status` | audit | enum |  |
| `invocation_status` | audit | enum |  |
| `auth_event` | audit | table | tier:2 append-only (partitioned). Authentication/authorization events (login/logout/denial). user-authentication.md FR-024. |
| `currency` | reference | table |  |
| `decision_log` | audit | table | tier:2 append-only (partitioned). The canonical per-run decision record. Soft refs to core. ab_sample/run_mode tag A/B runs for champion-vs-challenger. ADR-0004 |
| `evidence` | audit | table | tier:2 append-only (partitioned). The compliance evidence FACT stream (vs evidence_specification = the spec). Tied to requirement+tier+phase+entity/run. produce |
| `hitl_override` | core | table | tier:1 append-only. Per-field human override on a decision (soft ref to the Tier-2 decision_log). Attributed to the human actor. D6. |
| `inference_config_model` | core | table | tier:1. The ordered model_references an executable_version uses: priority 1 = primary, 2+ = fallbacks. Per-executable fallback (D): the harness tries the next r |
| `model` | core | table | tier:1. Model registry (identity stable; pricing is SCD-2 in model_price). |
| `model_invocation_log` | audit | table | tier:2 append-only (partitioned). Per-model-call token usage. Cost computed point-in-time via v_model_invocation_cost (never stored). |
| `model_price` | core | table | tier:1 SCD-2. Per-model price windows (valid_from/valid_to). Cost is computed point-in-time, never stored. |
| `model_reference` | core | table | tier:1. Stable logical model alias the registry points at; decouples packages from the actual model so it can be swapped centrally without re-promotion (legacy  |
| `model_reference_binding` | core | table | tier:1 SCD-2. Which actual model a reference resolves to, over time. Central swap = close old + open new (NO package re-promotion); windows allow as-of resoluti |
| `model_status` | reference | table |  |
| `status_transition` | audit | table | tier:2 append-only (partitioned). The ONE shared transition log for every mutable *_status_code in the schema (D4). entity_type + entity_id are soft refs. |
| `v_model_invocation_cost` | audit | view | Point-in-time cost: tokens × price-in-effect-at-invocation (SCD-2 join on model_price window). Stable across later price edits. |

### runs

| Object | Schema | Kind | Purpose |
|---|---|---|---|
| `run_entity_kind` | core | enum |  |
| `execution_run` | core | table | tier:1. A governed run of an executable_version. Carries deployment_run_mode + ab_sample (A/B tagging). State is event-sourced in execution_run_status. ADR-0002 |
| `execution_run_status` | core | table | tier:1 append-only. One row per run state transition (submitted/claimed/heartbeat/released). Current state via execution_run_current. Generalized v1 event-sourc |
| `harness_dispatch` | core | table | tier:1. LEG hub->cluster->worker. Current operational dispatch state per run; the coordinator polls it. Audit in execution_run_status (same txn). ADR-0010. |
| `outbox_status` | reference | table |  |
| `quota` | core | table | tier:1. A budget quota over a scope/period. enforcement_mode soft (default; warn) or hard (refuse the run as an execution-phase control). D-clarify. |
| `quota_alert_level` | reference | table |  |
| `quota_check` | core | table | tier:1 append-only. A quota evaluation (spend vs budget) with alert level; refused=true only under hard enforcement. Latest-per-quota = current breach state. |
| `quota_enforcement_mode` | reference | table |  |
| `quota_period` | reference | table |  |
| `quota_scope_type` | reference | table |  |
| `run_completion_status` | reference | table |  |
| `run_dispatch_outbox` | core | table | tier:1. Transactional outbox: run insert + outbox row in one txn; verity-relay publishes to NATS and marks published_at (PCR §3.3). |
| `run_dispatch_status` | reference | table |  |
| `run_purpose` | reference | table |  |
| `run_status` | reference | table |  |
| `execution_run_current` | core | view | Current state per run (latest status event). The status path reads this view, never the analytics tier (PCR §3.4). |

### deploy

| Object | Schema | Kind | Purpose |
|---|---|---|---|
| `command_kind` | reference | table |  |
| `command_outbox_status` | reference | table |  |
| `command_status` | reference | table |  |
| `credential_verification_status` | reference | table |  |
| `deployment` | core | table | tier:1. A package placed to run: pinned harness image (both package & image digests recorded), cluster, run_mode, status. champion!=deployed. D8/ADR-0006. |
| `deployment_binding_override` | core | table | tier:1. Per-binding real/mock override for a deployment. NOTE: run_mode=shadow FORCIBLY suppresses/mocks ALL Target Bindings regardless of these rows (the shado |
| `deployment_channel` | reference | table |  |
| `deployment_cluster` | core | table | tier:1. A cluster within an environment (multiple per env, incl. ephemeral/replay). D8. |
| `deployment_connection` | core | table | tier:1. Env-specific connections for a deployment; also materialized into the package bundle so the harness is self-contained at core. D8. |
| `deployment_environment` | core | table |  |
| `deployment_event` | core | table | tier:1 append-only. Governed deployment operations + outcome (the inventory/audit of deploy actions, incl. rejections). D8/ADR-0006. |
| `deployment_operation` | reference | table |  |
| `deployment_outcome` | reference | table |  |
| `deployment_run_mode` | reference | table |  |
| `deployment_status` | reference | table |  |
| `environment_kind` | reference | table |  |
| `harness_app_credential` | core | table | tier:1. Metadata-only app data-source credential registry (Model B); the secret stays on the spoke. ADR-0010. |
| `harness_command_outbox` | core | table | tier:1. LEG hub->cluster. Transactional outbox for hub->coordinator commands; separate from run_dispatch_outbox. ADR-0010. |
| `harness_coordinator` | core | table | tier:1. Per-cluster coordinator (master) lease; atomic hub-side election (no advisory locks, no split-brain). ADR-0010. |
| `harness_heartbeat` | audit | table | tier:2 append-only (partitioned). Agent->portal heartbeats: minor (frequent/light) + major (running-package catalog -> drift detection). D8. |
| `harness_image` | core | table | tier:1. A built harness container = variant + version + immutable image_digest (the identity; tags are advisory). ADR-0006/D8. |
| `harness_instance` | core | table | tier:1. A running harness container on a cluster (the "collector"): current/desired image (patch via convergence), owned/shared scope, status, last_seen. D8. |
| `harness_instance_command` | core | table | tier:1 append-only. Portal->agent control commands (patch/drain/enable/...). status pending->acknowledged->succeeded/failed. D8. |
| `harness_instance_status` | reference | table |  |
| `harness_node` | core | table | tier:1. Coordinator-eligible runtime host (pod in k8s, VM on Linux). Distinct from harness_instance. ADR-0010. |
| `harness_node_status` | reference | table |  |
| `harness_variant` | reference | table | Vocabulary: harness execution-engine variant (the kind of container/runtime). D8. |
| `health_status` | reference | table |  |
| `heartbeat_kind` | reference | table |  |
| `lifecycle_deployment_rule` | core | table | tier:1. The ADR-0006 lifecycle->environment matrix as auditable DATA: which run-modes a state may use per environment, and whether outputs suppress. The deploy |
| `package` | core | table | tier:1 insert-only. The .vtx/.vax artifact built from a champion executable_version. D8/ADR-0006. |
| `package_harness_compatibility` | core | table | tier:1. Package <-> harness variant + version range it can run on. Declared loosely; the deploy gate resolves & pins an exact image_digest. D8/ADR-0006. |
| `harness_instance_health_current` | audit | view |  |
| `harness_running_package_current` | audit | view | Latest reported running-package catalog per instance (from major heartbeats). Compare to deployments for drift. D8. |

### reporting

| Object | Schema | Kind | Purpose |
|---|---|---|---|
| `embedding_config` | core | table | tier:1. The active embedding runtime + dimension used for similarity (intake_requirement/canonical_requirement embeddings). One current row (effective-dated). |
| `embedding_runtime` | reference | table |  |
| `report_definition` | core | table | tier:1. A report definition (metadata- or template-driven). Reports run as async jobs against the analytics tier (ADR-0007), never on the status path. |
| `report_field` | core | table |  |
| `report_kind` | reference | table |  |
| `report_run_log` | audit | table | tier:2 append-only (partitioned). Async report-job runs. The canonical analytics store is EXTERNAL (Iceberg/Parquet, customer-portable) — ADR-0007. |
| `report_run_status` | reference | table |  |

### validation

| Object | Schema | Kind | Purpose |
|---|---|---|---|
| `description_similarity_log` | audit | table | tier:2 append-only (partitioned). pgvector similarity hits (dedup/recommendation). C9. |
| `evaluation_run` | core | table |  |
| `evaluation_type` | reference | table |  |
| `extraction_field_type` | reference | table |  |
| `extraction_match_type` | reference | table |  |
| `field_extraction_config` | core | table |  |
| `ground_truth_annotation` | core | table |  |
| `ground_truth_dataset` | core | table | tier:1. A ground-truth dataset; status mutable (D4). C9. |
| `ground_truth_record` | core | table |  |
| `ground_truth_record_mock` | core | table |  |
| `gt_annotator_type` | reference | table |  |
| `gt_dataset_status` | reference | table |  |
| `gt_quality_tier` | reference | table |  |
| `gt_source_type` | reference | table |  |
| `incident` | core | table | tier:1. Governance incident; status mutable (D4). C9. |
| `incident_severity` | reference | table |  |
| `incident_status` | reference | table |  |
| `metric_threshold` | core | table |  |
| `mock_kind` | reference | table |  |
| `model_card` | core | table | tier:1. Model-card review lifecycle; state mutable (D4). Distinct from the executable lifecycle. C9. |
| `model_card_state` | reference | table |  |
| `platform_settings` | core | table |  |
| `setting_input_type` | reference | table |  |
| `test_case` | core | table |  |
| `test_case_mock` | core | table |  |
| `test_execution_log` | audit | table | tier:2 append-only (partitioned). Per-test-case execution results. Soft refs to core. C9/C10. |
| `test_suite` | core | table | tier:1. A test suite for an executable (agent/task). D5/C9. |
| `tolerance_unit` | reference | table |  |
| `validation_match_type` | reference | table |  |
| `validation_record_result` | core | table |  |
| `validation_run` | core | table |  |
| `validation_run_status` | reference | table |  |

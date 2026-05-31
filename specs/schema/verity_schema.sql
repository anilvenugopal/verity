-- =====================================================================
-- verity_schema.sql — Verity v2 CANONICAL hardened schema (ADR-0005)
-- Status: ASSEMBLED DRAFT (2026-05-31), deterministically reconstructed.
--   intake recovered from agent /tmp output; compliance taken in full from
--   04-compliance.sql; enums de-duplicated; fixes #5 (decision-log FK schema)
--   and #7 (reserved-word table 'exception') applied. Residual: S4 (compliance
--   control UNIQUE(control_id,phase)) — see ASSEMBLY-AND-VERIFICATION.md.
-- Target: PostgreSQL 18+ (uuidv7()). PG<18 shim: see naming-conventions.md.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE SCHEMA IF NOT EXISTS governance;
CREATE SCHEMA IF NOT EXISTS runtime;
CREATE SCHEMA IF NOT EXISTS compliance;
CREATE SCHEMA IF NOT EXISTS analytics;
SET search_path = governance, runtime, compliance, analytics, public;

-- ############ CONSOLIDATED ENUMS ############
-- =====================================================================
-- CONSOLIDATED ENUM BLOCK
-- Every shared/owned enum emitted EXACTLY ONCE under its single owner.
-- Member-set conflicts (C2) resolved per ASSEMBLY-AND-VERIFICATION.md §A;
-- the chosen set + rationale is noted inline. Tables are NOT emitted here.
-- Enums are grouped by owning fragment in concatenation order (steps 2-9
-- + validation). Schema-qualified per naming-conventions.md §1.
-- =====================================================================

-- ---------------------------------------------------------------------
-- OWNER: intake (step 2) — shared governance enums + intake-only enums
-- ---------------------------------------------------------------------

-- Intake workflow status (v1 governance.intake_status, verbatim).
CREATE TYPE governance.intake_status AS ENUM (
    'proposed', 'in_review', 'impact_assessment', 'approved',
    'in_build', 'live', 'rejected', 'retired'
);
COMMENT ON TYPE governance.intake_status IS
    'tier:1 Intake workflow lifecycle (distinct from asset lifecycle_state); verbatim from v1.';

-- SHARED, owner=intake (A4). Was also declared in lifecycle_approvals (identical
-- members) — dropped there. EU-AI-Act-aligned risk tier (v1 verbatim).
CREATE TYPE governance.ai_risk_tier AS ENUM (
    'minimal', 'limited', 'high', 'unacceptable'
);
COMMENT ON TYPE governance.ai_risk_tier IS
    'tier:1 EU-AI-Act-aligned AI risk tier; v1 verbatim. Single owner intake (A4).';

-- NAIC materiality (v1 governance.naic_materiality, verbatim).
CREATE TYPE governance.naic_materiality AS ENUM (
    'material', 'non_material'
);

-- SHARED, owner=intake (A3). Identical 3-member set also appeared in entities;
-- chose intake as the single owner per A3, deleted the entities copy.
CREATE TYPE governance.materiality_tier AS ENUM ('high', 'medium', 'low');
COMMENT ON TYPE governance.materiality_tier IS
    'tier:1 materiality classification. Single owner intake (A3); entities/lifecycle_approvals copies dropped (identical members).';

-- Requirement kind (v1 governance.requirement_kind, verbatim).
CREATE TYPE governance.requirement_kind AS ENUM (
    'business', 'functional', 'non_functional', 'compliance'
);

-- Requirement status (v1 governance.requirement_status, verbatim).
CREATE TYPE governance.requirement_status AS ENUM (
    'draft', 'approved', 'implemented', 'verified', 'deprecated'
);

-- Requirement-to-entity relationship (v1 governance.requirement_relationship, verbatim).
CREATE TYPE governance.requirement_relationship AS ENUM (
    'implements', 'tests', 'monitors', 'informs'
);

-- Studio actor role (v1 governance.studio_role, verbatim).
CREATE TYPE governance.studio_role AS ENUM (
    'business_owner', 'compliance', 'legal', 'model_risk', 'ai_governance',
    'security', 'privacy', 'engineer', 'auditor', 'viewer'
);

-- SHARED, owner=intake (A3). Approval-capable subset of studio_role (v1 verbatim).
-- Dropped from lifecycle_approvals.
CREATE TYPE governance.approval_role AS ENUM (
    'business_owner', 'compliance', 'legal', 'model_risk', 'ai_governance',
    'security', 'privacy'
);
COMMENT ON TYPE governance.approval_role IS
    'tier:1 approval-capable subset of studio_role; v1 verbatim. Single owner intake (A3).';

-- SHARED, owner=intake (A3). Per-approver decision (v1 verbatim). lifecycle_approvals
-- copy had identical members — dropped.
CREATE TYPE governance.approval_decision AS ENUM (
    'approved', 'rejected', 'requested_changes', 'abstained'
);
COMMENT ON TYPE governance.approval_decision IS
    'tier:1 per-approver decision; v1 verbatim. Single owner intake (A3).';

-- SHARED, owner=intake (A3). lifecycle_approvals copy had a smaller set; this is the
-- full v1 set — dropped the lifecycle_approvals copy.
CREATE TYPE governance.approval_request_kind AS ENUM (
    'intake', 'risk_reclassification', 'promote_candidate',
    'promote_champion', 'retire'
);
COMMENT ON TYPE governance.approval_request_kind IS
    'tier:1 approval-request kind; v1 verbatim. Single owner intake (A3).';

-- Artifact plan status (v1 governance.artifact_plan_status, verbatim).
CREATE TYPE governance.artifact_plan_status AS ENUM (
    'proposed', 'in_progress', 'realized', 'cancelled'
);

-- SHARED, owner=intake (A5). MEMBER CONFLICT (C2): intake had
-- {pending,approved,rejected,cancelled}; lifecycle_approvals had
-- {pending,approved,rejected,withdrawn}. Chosen set = intake's 'cancelled' variant
-- (terminal-cancel matches v1 free-text approval_request.status intent and ADR-0006
-- promotion-request flow); the lifecycle_approvals 'withdrawn' synonym is folded into
-- 'cancelled'. lifecycle_approvals copy dropped.
CREATE TYPE governance.approval_request_status AS ENUM (
    'pending', 'approved', 'rejected', 'cancelled'
);
COMMENT ON TYPE governance.approval_request_status IS
    'tier:1 Hardened from v1 free-text approval_request.status. C2: chose cancelled (intake) over withdrawn (lifecycle_approvals); withdrawn folded into cancelled.';

-- ---------------------------------------------------------------------
-- OWNER: auth (step 3) — identity / authz / audit enums
-- ---------------------------------------------------------------------

-- SHARED, owner=auth. Identical copy in entities dropped (whole AUTH block, B9).
-- v1 studio_role taxonomy verbatim (10 values).
CREATE TYPE governance.platform_role AS ENUM (
    'business_owner',
    'compliance',
    'legal',
    'model_risk',
    'ai_governance',
    'security',
    'privacy',
    'engineer',
    'auditor',
    'viewer'
);
COMMENT ON TYPE governance.platform_role IS
    'tier:1 platform/governance role taxonomy; 10 values verbatim from v1 studio_role. Approval-capable subset = {business_owner,compliance,legal,model_risk,ai_governance,security,privacy}. Single owner auth (B9); entities copy dropped.';

-- SHARED, owner=auth. v2-NEW per-application authorization dimension. entities copy dropped (B9).
CREATE TYPE governance.app_team_role AS ENUM (
    'app_demo_owner',
    'app_demo_sre',
    'app_demo_dev',
    'app_demo_lead',
    'app_demo_ops'
);
COMMENT ON TYPE governance.app_team_role IS
    'tier:1 v2-new per-application role dimension; scoped to application_id. Single owner auth (B9).';

-- Auth audit closed value sets (spec sketch free-text hardened to enums per §9).
CREATE TYPE governance.auth_event_type AS ENUM (
    'login',
    'logout',
    'session_expiry',
    'session_termination',
    'authz_denial'
);
COMMENT ON TYPE governance.auth_event_type IS
    'tier:2 authentication/authorization event category.';

CREATE TYPE governance.auth_event_outcome AS ENUM (
    'success',
    'failure',
    'denied'
);
COMMENT ON TYPE governance.auth_event_outcome IS
    'tier:2 outcome of an auth_event.';

-- ---------------------------------------------------------------------
-- OWNER: entities (step 4) — registry / lifecycle / binding enums
-- ---------------------------------------------------------------------

-- SHARED, owner=entities (A1). Identical copies in lifecycle_approvals + packages_deploy dropped.
CREATE TYPE governance.lifecycle_state AS ENUM (
    'draft', 'candidate', 'staging', 'shadow', 'challenger', 'champion', 'deprecated'
);
COMMENT ON TYPE governance.lifecycle_state IS
    'Verbatim v1 lifecycle states. Single owner entities (A1); lifecycle_approvals + packages_deploy copies dropped (identical members). ADR-0006 §1.';

-- SHARED, owner=entities (A2). lifecycle_approvals copy dropped (identical members).
CREATE TYPE governance.deployment_channel AS ENUM (
    'development', 'staging', 'shadow', 'evaluation', 'production'
);
COMMENT ON TYPE governance.deployment_channel IS
    'Deployment channel; v1 verbatim. Single owner entities (A2).';

CREATE TYPE governance.capability_type AS ENUM (
    'classification', 'extraction', 'generation', 'summarisation', 'matching', 'validation'
);

CREATE TYPE governance.trust_level AS ENUM (
    'trusted', 'conditional', 'sandboxed', 'blocked'
);

CREATE TYPE governance.data_classification AS ENUM (
    'tier1_public', 'tier2_internal', 'tier3_confidential', 'tier4_pii_restricted'
);

-- SHARED, owner=entities (A6). decisions re-declaration (subset agent/task/prompt/tool) dropped.
-- C11 NOTE: test_suite/ground_truth_dataset retained — their backing tables now exist
-- in the validation fragment (10-validation), so no orphaned members.
CREATE TYPE governance.entity_type AS ENUM (
    'agent', 'task', 'prompt', 'tool', 'test_suite', 'ground_truth_dataset'
);
COMMENT ON TYPE governance.entity_type IS
    'Versioned/governed entity kinds. Single owner entities (A6); decisions copy dropped. test_suite/ground_truth_dataset backed by validation-domain tables (C11 resolved).';

CREATE TYPE governance.governance_tier AS ENUM (
    'behavioural', 'contextual', 'formatting'
);

CREATE TYPE governance.api_role AS ENUM ('system', 'user', 'assistant_prefill');

CREATE TYPE governance.metric_type AS ENUM (
    'exact_match', 'schema_valid', 'field_accuracy',
    'classification_f1', 'semantic_similarity', 'human_rubric'
);

-- SHARED, owner=entities (A6). decisions re-declaration (identical members) dropped.
CREATE TYPE governance.run_purpose AS ENUM (
    'production', 'test', 'validation', 'audit_rerun'
);
COMMENT ON TYPE governance.run_purpose IS
    'Why a decision/run was produced; v1 verbatim. Single owner entities (A6); decisions copy dropped.';

CREATE TYPE governance.version_change_type AS ENUM ('major', 'minor', 'patch');

-- SHARED, owner=entities (A6). MEMBER CONFLICT (C2): entities = {minimal,standard,verbose};
-- decisions = {minimal,standard,full}. Chosen set = entities' 'verbose' variant — v1
-- inventory shows only free-text 'standard' in use, so the third member is free choice;
-- 'verbose' kept and decisions code is expected to use it. decisions copy dropped.
CREATE TYPE governance.decision_log_detail AS ENUM ('minimal', 'standard', 'verbose');
COMMENT ON TYPE governance.decision_log_detail IS
    'Decision-log detail level. C2: chose entities {minimal,standard,verbose} over decisions {minimal,standard,full}; v1 only used standard. Single owner entities (A6).';

CREATE TYPE governance.tool_transport AS ENUM (
    'python_inprocess', 'mcp', 'http'
);

-- Source/Target binding kinds (binding-grammar.md).
CREATE TYPE governance.source_kind AS ENUM (
    'vault', 'task_output', 'structured'
);
CREATE TYPE governance.source_payload_kind AS ENUM ('text', 'content_blocks');
CREATE TYPE governance.target_kind AS ENUM (
    'vault', 'task_output', 'structured'
);
CREATE TYPE governance.binding_owner_kind AS ENUM ('task_version', 'agent_version');

-- ---------------------------------------------------------------------
-- OWNER: decisions (step 5) — decisions-only enums
-- (run_purpose / decision_log_detail / entity_type re-declarations DROPPED — owned by entities, A6)
-- ---------------------------------------------------------------------

-- Decision-log terminal status (v1 free varchar 'complete', hardened).
CREATE TYPE governance.decision_status AS ENUM (
    'complete',
    'error',
    'partial'
);
COMMENT ON TYPE governance.decision_status IS
    'Terminal status captured on an immutable decision-log row.';

-- Model-invocation status (v1 free varchar 'complete', hardened).
CREATE TYPE governance.invocation_status AS ENUM (
    'complete',
    'error',
    'timeout'
);

-- Model lifecycle status (v1 model.status free varchar 'active', hardened).
CREATE TYPE governance.model_status AS ENUM (
    'active',
    'deprecated',
    'retired'
);

-- Currency code (v1 model_price.currency varchar(3) 'USD'; small enum, extend additively).
CREATE TYPE governance.currency_code AS ENUM (
    'usd',
    'eur',
    'gbp'
);

-- ---------------------------------------------------------------------
-- OWNER: packages_deploy (step 6) — package / deployment enums
-- (these supersede the entities + lifecycle_approvals copies — A7, A8)
-- ---------------------------------------------------------------------

-- SHARED, owner=packages_deploy (A7). entities + lifecycle_approvals copies (identical
-- members) dropped.
CREATE TYPE governance.package_kind AS ENUM (
    'vtx',
    'vax'
);
COMMENT ON TYPE governance.package_kind IS
    'Package artifact kind: vtx (.vtx task package) / vax (.vax agent package). ADR-0006. Single owner packages_deploy (A7); entities + lifecycle_approvals copies dropped.';

-- packages_deploy-only: environment tier grouping for clusters (ADR-0006 §1).
CREATE TYPE governance.environment_kind AS ENUM (
    'non_prod',
    'prod',
    'ephemeral'
);
COMMENT ON TYPE governance.environment_kind IS
    'Environment classification for clusters: non_prod, prod, ephemeral (temp/replay). ADR-0006.';

-- SHARED, owner=packages_deploy (A8). Canonicalized over entities.deployment_action
-- ({deploy_nonprod,deploy_prod,promote_champion,lock_deprecated,cleanup_deprecated}) and
-- lifecycle_approvals.deployment_action; this is the most complete set (adds 'rollback').
-- The entities + lifecycle_approvals copies are dropped.
CREATE TYPE governance.deployment_operation AS ENUM (
    'deploy_nonprod',
    'deploy_prod',
    'promote_champion',
    'lock_deprecated',
    'cleanup_deprecated',
    'rollback'
);
COMMENT ON TYPE governance.deployment_operation IS
    'Governed deployment operations mediated by the control plane. ADR-0006 §3. C2/A8: canonical superset (adds rollback) replacing entities/lifecycle_approvals deployment_action.';

-- SHARED, owner=packages_deploy (A8). MEMBER CONFLICT (C2): entities = {live,read_only,ab_slice};
-- lifecycle_approvals = {live,read_only,ab,locked}. Chosen set keeps the explicit
-- 'ab_slice' spelling (entities) AND adds 'locked' (lifecycle_approvals) — the union is
-- the ADR-0006 §1 matrix. 'ab' is the lifecycle_approvals synonym for 'ab_slice' and is
-- dropped. entities + lifecycle_approvals copies dropped.
CREATE TYPE governance.deployment_run_mode AS ENUM (
    'live',
    'read_only',
    'ab_slice',
    'locked'
);
COMMENT ON TYPE governance.deployment_run_mode IS
    'Run mode: live / read_only (writes suppressed) / ab_slice / locked. ADR-0006 §1. C2/A8: ab_slice spelling kept, locked added; ab synonym dropped.';

-- SHARED, owner=packages_deploy (A8). 3-way MEMBER CONFLICT (C2): entities =
-- {succeeded,failed,refused}; lifecycle_approvals = {succeeded,rejected,failed}.
-- Chosen set = packages_deploy's fine-grained outcomes (distinguishes the three refusal
-- reasons + superseded), which subsumes the coarse 'refused'/'rejected' of the others.
-- entities + lifecycle_approvals copies dropped.
CREATE TYPE governance.deployment_outcome AS ENUM (
    'requested',
    'rejected_incompatible',
    'rejected_lifecycle',
    'rejected_unauthorized',
    'succeeded',
    'failed',
    'superseded'
);
COMMENT ON TYPE governance.deployment_outcome IS
    'Outcome per governed deployment event. ADR-0006 §1-§3. C2/A8: fine-grained set subsumes entities {refused} / lifecycle_approvals {rejected} coarse outcomes.';

-- ---------------------------------------------------------------------
-- OWNER: runs_quotas (step 7) — runtime run + governance quota enums
-- ---------------------------------------------------------------------

-- Run state-machine transition kinds (append-only event vocabulary; v1 CHECK hardened).
CREATE TYPE runtime.run_status AS ENUM (
    'submitted',
    'claimed',
    'heartbeat',
    'released'
);
COMMENT ON TYPE runtime.run_status IS
    'Run state-machine transition kinds recorded append-only on runtime.execution_run_status. Terminal outcomes (complete/cancelled/failed) live in the completion/error tables, not here.';

-- Terminal non-error completion outcome (v1 VARCHAR CHECK hardened).
CREATE TYPE runtime.run_completion_status AS ENUM (
    'complete',
    'cancelled'
);
COMMENT ON TYPE runtime.run_completion_status IS
    'Non-error terminal outcome for a run; recorded once per run on runtime.execution_run_completion.';

-- Entity kind a run targets (v1 VARCHAR CHECK hardened).
CREATE TYPE runtime.run_entity_kind AS ENUM (
    'task',
    'agent'
);
COMMENT ON TYPE runtime.run_entity_kind IS 'Whether a run targets a task version or an agent version.';

-- Run write/side-effect mode (v1 free-text + PCR 3.7 read-only concept hardened).
CREATE TYPE runtime.run_write_mode AS ENUM (
    'live',
    'read_only'
);
COMMENT ON TYPE runtime.run_write_mode IS
    'live = Target Bindings execute (business side effects); read_only = harness runs and logs but Target Bindings are suppressed (PCR 3.7 shadow/challenger/deprecated environments).';

-- SHARED, owner=runs_quotas (runtime). The governance + lifecycle_approvals
-- run_dispatch_outbox tables are dropped (B15); only this runtime outbox survives, so
-- the lifecycle_approvals governance.outbox_status copy is dropped in favour of this.
CREATE TYPE runtime.outbox_status AS ENUM (
    'pending',
    'published',
    'claimed',
    'failed'
);
COMMENT ON TYPE runtime.outbox_status IS
    'Lifecycle of a transactional outbox row (PCR §3.3). Single owner runs_quotas (runtime); lifecycle_approvals governance.outbox_status copy dropped with its table (B15).';

-- Quota scope target (v1 VARCHAR CHECK hardened).
CREATE TYPE governance.quota_scope_type AS ENUM (
    'application',
    'agent',
    'task',
    'model'
);
COMMENT ON TYPE governance.quota_scope_type IS 'What a spend quota is scoped to.';

-- Quota budgeting period (v1 VARCHAR CHECK hardened).
CREATE TYPE governance.quota_period AS ENUM (
    'daily',
    'weekly',
    'monthly'
);
COMMENT ON TYPE governance.quota_period IS 'Rolling budget window for a quota.';

-- v2-NEW configurable quota enforcement action (v1 boolean hard_stop generalized).
CREATE TYPE governance.quota_enforcement_action AS ENUM (
    'alert_only',
    'block',
    'throttle'
);
COMMENT ON TYPE governance.quota_enforcement_action IS
    'Configurable action when a quota period budget is exceeded. v1 boolean hard_stop maps to block (true) / alert_only (false); throttle is v2-new.';

-- Quota alert severity band (v1 free-text VARCHAR hardened).
CREATE TYPE governance.quota_alert_level AS ENUM (
    'warning',
    'exceeded',
    'critical'
);
COMMENT ON TYPE governance.quota_alert_level IS 'Severity band of a fired quota alert.';

-- ---------------------------------------------------------------------
-- OWNER: compliance (step 8) — control / evidence enums
-- ---------------------------------------------------------------------

-- v2-NEW. Lifecycle phase at which a control fires (ADR-0008 four-phase model).
CREATE TYPE compliance.control_phase AS ENUM (
    'design_time',
    'deploy_time',
    'static_model',
    'execution'
);

-- v2-NEW. Control category.
CREATE TYPE compliance.control_type AS ENUM (
    'preventive',
    'detective',
    'corrective',
    'directive'
);

-- v2-NEW. Action a control takes when it fires.
CREATE TYPE compliance.enforcement_action AS ENUM (
    'block',
    'refuse',
    'suppress_write',
    'warn',
    'log_only'
);

-- v2-NEW. Form of evidence artifact a control produces.
CREATE TYPE compliance.evidence_artifact_type AS ENUM (
    'config_snapshot',
    'model_card',
    'package_manifest',
    'approval_record',
    'test_result',
    'validation_report',
    'decision_log',
    'binding_resolution',
    'deployment_record',
    'document'
);

-- v1 provision_requirement_map.mapping_source CHECK -> enum (members verbatim).
CREATE TYPE compliance.mapping_source AS ENUM (
    'manual',
    'semantic_recommended',
    'human_validated'
);

-- v1 requirement_coverage.coverage_level CHECK -> enum (members verbatim).
CREATE TYPE compliance.coverage_level AS ENUM (
    'full',
    'substantial',
    'partial',
    'gap'
);

-- v2-NEW. Append-only exception lifecycle state (projected via exception_current view).
CREATE TYPE compliance.exception_status AS ENUM (
    'requested',
    'approved',
    'rejected',
    'revoked',
    'expired'
);

-- ---------------------------------------------------------------------
-- OWNER: reporting (step 9) — analytics + compliance reporting enums
-- ---------------------------------------------------------------------

-- mart_field.semantic_type (v1 CHECK verbatim).
CREATE TYPE analytics.mart_field_semantic_type AS ENUM (
    'identifier', 'measure', 'date', 'category', 'text', 'json'
);
COMMENT ON TYPE analytics.mart_field_semantic_type IS
    'Semantic class of a report-reachable column. Verbatim from v1 mart_field.semantic_type CHECK.';

-- evidence-field role (v1 requirement_evidence_field.role + report_field_override.role_override).
CREATE TYPE analytics.evidence_field_role AS ENUM (
    'key', 'measure', 'dimension', 'filter', 'context'
);
COMMENT ON TYPE analytics.evidence_field_role IS
    'Role a mart_field plays for a requirement/report. Verbatim from v1 requirement_evidence_field.role.';

-- evidence-field aggregation (v1 aggregation CHECK; NULL allowed at column level).
CREATE TYPE analytics.evidence_field_aggregation AS ENUM (
    'count', 'sum', 'avg', 'min', 'max', 'distinct_count'
);
COMMENT ON TYPE analytics.evidence_field_aggregation IS
    'Aggregation applied to a measure field. Verbatim from v1 aggregation CHECK. NULL means no aggregation.';

-- report kind (v1 report_definition.report_kind CHECK verbatim).
CREATE TYPE compliance.report_kind AS ENUM (
    'metadata_driven', 'template_driven'
);
COMMENT ON TYPE compliance.report_kind IS
    'How a report is rendered. Verbatim from v1 report_definition.report_kind CHECK.';

-- report run status (v1 report_run_log.status CHECK verbatim).
CREATE TYPE compliance.report_run_status AS ENUM (
    'pending', 'succeeded', 'failed'
);
COMMENT ON TYPE compliance.report_run_status IS
    'Outcome of a report generation job. Verbatim from v1 report_run_log.status CHECK.';

-- embedding runtime (v1 free text default 'fastembed'; closed set, additive-only).
CREATE TYPE compliance.embedding_runtime AS ENUM (
    'fastembed'
);
COMMENT ON TYPE compliance.embedding_runtime IS
    'Embedding inference runtime. Members appended via ALTER TYPE as runtimes are adopted (additive only).';

-- ---------------------------------------------------------------------
-- OWNER: validation (testing/GT/eval subsystem; C9 disposition) — governance enums
-- gt_* carried verbatim from v1; remaining free-text columns promoted to enums.
-- ---------------------------------------------------------------------

-- v1 governance.gt_dataset_status VERBATIM (5 members).
CREATE TYPE governance.gt_dataset_status AS ENUM (
    'collecting',
    'labeling',
    'adjudicating',
    'ready',
    'deprecated'
);
COMMENT ON TYPE governance.gt_dataset_status IS
    'Ground-truth dataset lifecycle status. v1 governance.gt_dataset_status carried verbatim.';

-- v1 governance.gt_quality_tier VERBATIM (2 members).
CREATE TYPE governance.gt_quality_tier AS ENUM (
    'silver',
    'gold'
);
COMMENT ON TYPE governance.gt_quality_tier IS
    'Ground-truth quality classification. v1 governance.gt_quality_tier carried verbatim.';

-- v1 governance.gt_source_type VERBATIM (3 members).
CREATE TYPE governance.gt_source_type AS ENUM (
    'document',
    'submission',
    'synthetic'
);
COMMENT ON TYPE governance.gt_source_type IS
    'Ground-truth record source type. v1 governance.gt_source_type carried verbatim.';

-- v1 governance.gt_annotator_type VERBATIM (3 members).
CREATE TYPE governance.gt_annotator_type AS ENUM (
    'human_sme',
    'llm_judge',
    'adjudicator'
);
COMMENT ON TYPE governance.gt_annotator_type IS
    'Ground-truth annotator type. v1 governance.gt_annotator_type carried verbatim.';

-- v2-NEW. Per-call mock discriminator (v1 free-text CHECK promoted; shared by both mock tables).
CREATE TYPE governance.mock_kind AS ENUM (
    'tool',
    'source',
    'target'
);
COMMENT ON TYPE governance.mock_kind IS
    'Per-call mock discriminator for test_case_mock / ground_truth_record_mock. v1 free-text CHECK promoted to enum.';

-- v2-NEW. Validation-run lifecycle (v1 validation_run.status free-text promoted).
CREATE TYPE governance.validation_run_status AS ENUM (
    'running',
    'complete',
    'failed'
);
COMMENT ON TYPE governance.validation_run_status IS
    'Validation-run lifecycle. v1 validation_run.status free-text promoted to enum.';

-- v2-NEW. Per-record match classification (v1 validation_record_result.match_type promoted).
CREATE TYPE governance.validation_match_type AS ENUM (
    'exact',
    'partial',
    'fuzzy'
);
COMMENT ON TYPE governance.validation_match_type IS
    'Validation per-record match classification. v1 validation_record_result.match_type free-text promoted to enum.';

-- v2-NEW. Per-field comparison datatype (v1 field_extraction_config.field_type promoted).
CREATE TYPE governance.extraction_field_type AS ENUM (
    'string', 'numeric', 'date', 'boolean', 'enum'
);
COMMENT ON TYPE governance.extraction_field_type IS
    'Extraction field datatype for tolerance comparison. v1 field_extraction_config.field_type free-text promoted to enum.';

-- v2-NEW. Per-field match strategy (v1 field_extraction_config.match_type promoted).
CREATE TYPE governance.extraction_match_type AS ENUM (
    'exact', 'numeric_tolerance', 'case_insensitive', 'contains'
);
COMMENT ON TYPE governance.extraction_match_type IS
    'Extraction field comparison strategy. v1 field_extraction_config.match_type free-text promoted to enum.';

-- v2-NEW. Numeric tolerance unit (v1 field_extraction_config.tolerance_unit promoted).
CREATE TYPE governance.tolerance_unit AS ENUM (
    'percent', 'absolute'
);
COMMENT ON TYPE governance.tolerance_unit IS
    'Numeric tolerance unit for extraction comparison. v1 field_extraction_config.tolerance_unit free-text promoted to enum.';

-- v2-NEW. Incident severity (v1 incident.severity free-text promoted).
CREATE TYPE governance.incident_severity AS ENUM (
    'critical', 'high', 'medium', 'low'
);
COMMENT ON TYPE governance.incident_severity IS
    'Incident severity. v1 incident.severity free-text promoted to enum (members chosen to cover v1 usage; reviewer to confirm vocabulary).';

-- v2-NEW. Incident lifecycle status (v1 incident.status default 'open' promoted).
CREATE TYPE governance.incident_status AS ENUM (
    'open', 'investigating', 'mitigated', 'resolved', 'closed'
);
COMMENT ON TYPE governance.incident_status IS
    'Incident lifecycle status. v1 incident.status free-text (default open) promoted to enum.';

-- v2-NEW. Evaluation-run kind (v1 evaluation_run.evaluation_type promoted).
CREATE TYPE governance.evaluation_type AS ENUM (
    'shadow', 'challenger', 'periodic', 'drift_check'
);
COMMENT ON TYPE governance.evaluation_type IS
    'Evaluation-run kind. v1 evaluation_run.evaluation_type free-text promoted to enum (reviewer to confirm vocabulary vs v1 callers).';

-- v2-NEW. Model-card review lifecycle (v1 model_card.lifecycle_state default 'draft' promoted).
-- Distinct from governance.lifecycle_state (entity lifecycle) — kept separate deliberately.
CREATE TYPE governance.model_card_state AS ENUM (
    'draft', 'in_review', 'approved', 'superseded'
);
COMMENT ON TYPE governance.model_card_state IS
    'Model-card review lifecycle. v1 model_card.lifecycle_state (free text default draft) promoted to enum. Distinct from governance.lifecycle_state (entity lifecycle).';

-- v2-NEW. Platform-setting input widget hint (v1 platform_settings.input_type default 'text' promoted).
CREATE TYPE governance.setting_input_type AS ENUM (
    'text', 'select', 'number'
);
COMMENT ON TYPE governance.setting_input_type IS
    'Platform-setting UI input widget hint. v1 platform_settings.input_type free-text promoted to enum.';

-- ############ TABLES: auth ############
-- =============================================================================
-- DOMAIN: AUTH & IDENTITY  (v2-new; specs/features/user-authentication.md)
-- Service owner: verity-governance (ADR-0003). Tier-1 system-of-record for
-- identity + append-only role grants; Tier-2 for the auth_event audit log.
-- All objects live in schema "governance" (naming-conventions.md §2).
-- Single owner of identity (reconciliation B9): the entities AUTH block is dropped.
-- Identity table is account_user (reconciliation B9/C4; naming-conventions.md §1).
-- Enums (platform_role, app_team_role, auth_event_type, auth_event_outcome) are
-- emitted in the consolidated enum block, not here.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TABLE: governance.account_user  (Tier-1 system-of-record; identity principal)
-- Identity is the IMMUTABLE composite (tenant_id, microsoft_oid) as a UNIQUE
-- constraint; never keyed on email (FR-005/FR-006).
-- -----------------------------------------------------------------------------
CREATE TABLE governance.account_user (
    account_user_id uuid        NOT NULL DEFAULT uuidv7(),
    tenant_id       uuid        NOT NULL,                       -- Entra tid
    microsoft_oid   uuid        NOT NULL,                       -- Entra oid (immutable per tenant)
    display_name    text        NOT NULL,                       -- display only (mutable, non-key)
    email           text,                                       -- display only (mutable, non-key)
    upn             text,                                        -- display only (mutable, non-key)
    session_epoch   integer     NOT NULL DEFAULT 0,             -- bumped on any role change (FR-015)
    disabled_at     timestamptz,                                 -- non-null => fail closed on refresh (FR-021)
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_account_user PRIMARY KEY (account_user_id),
    CONSTRAINT uq_account_user_tenant_oid UNIQUE (tenant_id, microsoft_oid),
    CONSTRAINT ck_account_user_session_epoch_nonneg CHECK (session_epoch >= 0)
);
COMMENT ON TABLE governance.account_user IS
    'tier:1 system-of-record identity principal. Natural key = (tenant_id, microsoft_oid). Display fields are point-in-time-unstable, display-only; audit reads bind to account_user_id only (FR-018). Created solely via atomic upsert on uq_account_user_tenant_oid (FR-006a).';
COMMENT ON COLUMN governance.account_user.disabled_at IS
    'Non-null fails the principal closed on next role refresh and terminates active sessions (FR-021).';
COMMENT ON COLUMN governance.account_user.session_epoch IS
    'Token/role version; bumped on any platform OR app-team grant/revoke to force re-authorization (FR-015).';

-- -----------------------------------------------------------------------------
-- TABLE: governance.platform_role_grant (Tier-1, APPEND-ONLY)
-- A revoke is a new row with is_revocation = true; current state is a VIEW over
-- the latest event per (account_user_id, role). No UPDATE/DELETE (FR-017, ADR-0005 §3).
-- -----------------------------------------------------------------------------
CREATE TABLE governance.platform_role_grant (
    platform_role_grant_id uuid                  NOT NULL DEFAULT uuidv7(),
    account_user_id        uuid                  NOT NULL,
    role                   governance.platform_role NOT NULL,
    is_revocation          boolean               NOT NULL DEFAULT false,
    granted_by_user_id     uuid                  NOT NULL,      -- server-resolved actor (FR-017); never client-supplied
    reason                 text,
    granted_at             timestamptz           NOT NULL DEFAULT now(),
    CONSTRAINT pk_platform_role_grant PRIMARY KEY (platform_role_grant_id),
    CONSTRAINT fk_platform_role_grant_account_user
        FOREIGN KEY (account_user_id) REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_platform_role_grant_actor
        FOREIGN KEY (granted_by_user_id) REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT
);
COMMENT ON TABLE governance.platform_role_grant IS
    'tier:1 append-only platform-role grant/revoke event log. Revoke = new row (is_revocation=true). No in-place mutation; current state = governance.current_platform_role view (FR-017).';
COMMENT ON COLUMN governance.platform_role_grant.granted_by_user_id IS
    'Server-resolved account_user_id of the authenticated actor; MUST NOT be accepted from request body (FR-017). Self-escalation guard (granted_by_user_id != account_user_id for elevations) is enforced in the API layer (FR-023).';

-- Latest-event-per-subject lookup (drives effective-roles resolution; FR-014).
CREATE INDEX ix_platform_role_grant_latest
    ON governance.platform_role_grant (account_user_id, role, granted_at DESC);
-- FK index on the actor reference (naming-conventions.md §6).
CREATE INDEX ix_platform_role_grant_granted_by_user_id
    ON governance.platform_role_grant (granted_by_user_id);

-- -----------------------------------------------------------------------------
-- TABLE: governance.app_team_role_grant (Tier-1, APPEND-ONLY, v2-NEW)
-- Per-application dimension scoped to application_id (FR-010). Append-only;
-- current state per (application_id, account_user_id, role) via a VIEW.
-- -----------------------------------------------------------------------------
CREATE TABLE governance.app_team_role_grant (
    app_team_role_grant_id uuid                   NOT NULL DEFAULT uuidv7(),
    account_user_id        uuid                   NOT NULL,
    application_id         uuid                   NOT NULL,     -- server-derived scope (FR-010); never client-supplied
    role                   governance.app_team_role NOT NULL,
    is_revocation          boolean                NOT NULL DEFAULT false,
    granted_by_user_id     uuid                   NOT NULL,     -- server-resolved actor (FR-017)
    reason                 text,
    granted_at             timestamptz            NOT NULL DEFAULT now(),
    CONSTRAINT pk_app_team_role_grant PRIMARY KEY (app_team_role_grant_id),
    CONSTRAINT fk_app_team_role_grant_account_user
        FOREIGN KEY (account_user_id) REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_app_team_role_grant_actor
        FOREIGN KEY (granted_by_user_id) REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT
    -- DEFERRED FK (reconciliation C18): fk_app_team_role_grant_application
    --   FOREIGN KEY (application_id) REFERENCES governance.application (application_id)
    --   ON DELETE RESTRICT. governance.application is owned by the intake domain
    --   (loads after auth); emitted as an ALTER in the deferred-FK section.
);
COMMENT ON TABLE governance.app_team_role_grant IS
    'tier:1 append-only v2-new app-team role grant/revoke event log, scoped to application_id. No v1 equivalent (v1 had a single session persona, no persistent user->role table). Current state = governance.current_app_team_role view (FR-010, FR-017).';
COMMENT ON COLUMN governance.app_team_role_grant.application_id IS
    'Scope of the grant; in authz decisions application_id is derived server-side from the target resource, never client-supplied (FR-010). FK to governance.application is a deferred cross-domain ALTER (reconciliation C18).';

-- Latest-event-per-(app,subject,role) lookup (drives scoped effective-roles).
CREATE INDEX ix_app_team_role_grant_latest
    ON governance.app_team_role_grant (application_id, account_user_id, role, granted_at DESC);
CREATE INDEX ix_app_team_role_grant_granted_by_user_id
    ON governance.app_team_role_grant (granted_by_user_id);

-- -----------------------------------------------------------------------------
-- TABLE: governance.auth_event (Tier-2, APPEND-ONLY, RANGE-partitioned by month)
-- High-volume audit substrate (FR-024). Ingested via the API async/bulk path,
-- never inline on the request hot path; writes MUST NOT block or fail-open.
-- No FK to account_user (intentional, N1): avoids a cross-tier write dependency
-- on the hot ingest path; account_user_id is nullable for pre-identity failures;
-- integrity is enforced at the API layer (spec).
-- Composite PK (auth_event_id, created_at) because the partition key must be
-- part of the PK for a RANGE-partitioned table.
-- -----------------------------------------------------------------------------
CREATE TABLE governance.auth_event (
    auth_event_id   uuid                        NOT NULL DEFAULT uuidv7(),
    event_type      governance.auth_event_type    NOT NULL,
    outcome         governance.auth_event_outcome NOT NULL,
    reason_code     text,                                       -- bad_signature | expired | nonce_mismatch | unknown_tenant | mock_auth | ...
    account_user_id uuid,                                        -- nullable for pre-identity failures (no FK; Tier-2)
    action_code     text,                                        -- requested action on authz_denial
    resource        text,
    request_id      text                        NOT NULL,       -- correlation id (NFR-008)
    ip              inet,
    created_at      timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_auth_event PRIMARY KEY (auth_event_id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE governance.auth_event IS
    'tier:2 append-only auth audit log; month-range-partitioned on created_at, BRIN on time, retention by partition DETACH/DROP. Ingested via async/bulk path; never blocks or fail-opens the request (FR-024). No FK to account_user by design (cross-tier hot-path avoidance); integrity at API layer.';

-- Per-subject time-ordered audit reads.
CREATE INDEX ix_auth_event_account_user_time
    ON governance.auth_event (account_user_id, created_at DESC);
-- Tier-2 BRIN on time (naming-conventions.md §8); UUIDv7 keeps inserts clustered
-- by time, which makes BRIN effective.
CREATE INDEX brin_auth_event_created_at
    ON governance.auth_event USING brin (created_at);

-- Seed partitions. Operational tooling rolls future partitions monthly.
CREATE TABLE governance.auth_event_2026_05
    PARTITION OF governance.auth_event
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
COMMENT ON TABLE governance.auth_event_2026_05 IS
    'tier:2 monthly partition of governance.auth_event for 2026-05.';

-- Current-month coverage (reconciliation C8): without this a 2026-06 insert fails
-- (no matching partition). A scheduled job MUST create each subsequent month.
CREATE TABLE governance.auth_event_2026_06
    PARTITION OF governance.auth_event
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
COMMENT ON TABLE governance.auth_event_2026_06 IS
    'tier:2 monthly partition of governance.auth_event for 2026-06.';

-- -----------------------------------------------------------------------------
-- CURRENT-STATE VIEWS (latest grant/revoke event per subject; ADR-0005 §3)
-- Effective roles = rows WHERE is_revocation = false. Per the spec, these MUST
-- be read from the PRIMARY for authorization decisions (replica lag must not
-- silently grant a revoked role; FR-015 / distributed-scale notes).
-- -----------------------------------------------------------------------------
CREATE VIEW governance.current_platform_role AS
SELECT DISTINCT ON (g.account_user_id, g.role)
       g.account_user_id,
       g.role,
       g.is_revocation,
       g.granted_by_user_id,
       g.granted_at
FROM   governance.platform_role_grant AS g
ORDER  BY g.account_user_id, g.role, g.granted_at DESC;
COMMENT ON VIEW governance.current_platform_role IS
    'Latest platform-role event per (account_user_id, role). Effective roles = rows WHERE is_revocation=false. Read from PRIMARY for authz (FR-015).';

CREATE VIEW governance.current_app_team_role AS
SELECT DISTINCT ON (g.application_id, g.account_user_id, g.role)
       g.application_id,
       g.account_user_id,
       g.role,
       g.is_revocation,
       g.granted_by_user_id,
       g.granted_at
FROM   governance.app_team_role_grant AS g
ORDER  BY g.application_id, g.account_user_id, g.role, g.granted_at DESC;
COMMENT ON VIEW governance.current_app_team_role IS
    'Latest app-team-role event per (application_id, account_user_id, role). Effective roles = rows WHERE is_revocation=false; scoped to application_id (FR-010). Read from PRIMARY for authz (FR-015).';

-- ############ TABLES: entities ############
-- =====================================================================
-- SECTION: entities — registry / version / binding / delegation
-- Source fragment: 02-entities.sql (hardened, ADR-0005).
-- Single-owner per ASSEMBLY-AND-VERIFICATION.md reconciliation:
--   DROPPED here: model/model_price (decisions owns, B11), application
--   (intake owns, B10), entire AUTH block (auth owns, B9), packages/
--   harness/deployment block + run_dispatch_outbox (packages_deploy/
--   runs_quotas own, B14/B15), and the mutable champion-pointer columns
--   agent/task.current_champion_version_id + their FKs (C6/D21).
--   materiality_tier enum is owned by intake (A3) -> NOT created here,
--   only referenced.
-- Schema: governance (Tier-1 system-of-record unless tagged Tier-2).
-- =====================================================================

-- ----------------------------------------------------------------------------
-- ENUMS owned by this section (entities). Shared enums collapsed per A:
--   materiality_tier -> intake (A3); platform_role/app_team_role -> auth;
--   package_kind/deployment_* -> packages_deploy (A7/A8). Those are NOT
--   created here.
-- ----------------------------------------------------------------------------

-- entity_type owner (A6). Members agent/task/prompt/tool + carried-forward
-- test_suite/ground_truth_dataset (no silent loss; see verification C11).

-- run_purpose owner (A6).

-- decision_log_detail owner (A6/C2): members minimal/standard/verbose win;
-- decisions fragment must conform to this set.

-- Source/Target Binding kinds (binding-grammar.md).

-- ============================================================================
-- INFERENCE CONFIG (single-row config registry)
-- model_id FK targets governance.model, owned by the DECISIONS section which
-- loads later -> FK DEFERRED (emit as ALTER after model exists). S6: literal
-- model_name retained as advisory only; resolve real model via model_id.
-- ============================================================================

CREATE TABLE governance.inference_config (
    inference_config_id uuid        NOT NULL DEFAULT uuidv7(),
    name            text            NOT NULL,
    display_name    text            NOT NULL,
    description     text            NOT NULL,
    intended_use    text            NOT NULL,
    model_id        uuid,                            -- FK -> governance.model (decisions section; DEFERRED)
    model_name      text            NOT NULL DEFAULT 'claude-sonnet-4-20250514',  -- S6: advisory; authoritative model is model_id
    temperature     numeric(4,3),
    max_tokens      integer,
    top_p           numeric(4,3),
    top_k           integer,
    stop_sequences  text[],
    extended_params jsonb           NOT NULL DEFAULT '{}'::jsonb,
    is_active       boolean         NOT NULL DEFAULT true,
    created_at      timestamptz     NOT NULL DEFAULT now(),
    updated_at      timestamptz     NOT NULL DEFAULT now(),
    CONSTRAINT pk_inference_config PRIMARY KEY (inference_config_id),
    CONSTRAINT uq_inference_config_name UNIQUE (name),
    CONSTRAINT ck_inference_config_temperature CHECK (temperature IS NULL OR temperature BETWEEN 0 AND 2),
    CONSTRAINT ck_inference_config_top_p CHECK (top_p IS NULL OR top_p BETWEEN 0 AND 1),
    CONSTRAINT ck_inference_config_max_tokens CHECK (max_tokens IS NULL OR max_tokens > 0)
);
CREATE INDEX ix_inference_config_model ON governance.inference_config (model_id);
COMMENT ON TABLE governance.inference_config IS 'tier:1 inference config registry (mutable settings table); fk_inference_config_model -> governance.model added by deferred-FK section';

-- ============================================================================
-- ENTITY HEADERS: agent / task / prompt
-- C6/D21: current_champion_version_id columns + their FKs REMOVED. The single
-- source of truth for the current champion is lifecycle_approvals.
-- champion_assignment + the entity_champion_current view.
-- ============================================================================

CREATE TABLE governance.agent (
    agent_id        uuid             NOT NULL DEFAULT uuidv7(),
    name            text             NOT NULL,
    display_name    text             NOT NULL,
    description     text             NOT NULL,
    description_embedding        vector(1536),
    description_embedding_model  text,
    last_similarity_check_at     timestamptz,
    similarity_flags jsonb           NOT NULL DEFAULT '[]'::jsonb,
    purpose         text             NOT NULL,
    domain          text             NOT NULL DEFAULT 'underwriting',
    materiality_tier governance.materiality_tier NOT NULL,
    owner_name      text             NOT NULL,
    owner_email     text,
    business_context text,
    known_limitations text,
    regulatory_notes text,
    created_at      timestamptz      NOT NULL DEFAULT now(),
    updated_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_agent PRIMARY KEY (agent_id),
    CONSTRAINT uq_agent_name UNIQUE (name)
);
CREATE INDEX ix_agent_materiality_tier ON governance.agent (materiality_tier);
COMMENT ON TABLE governance.agent IS 'tier:1 agent header (system-of-record); current champion is a view in lifecycle_approvals (C6/D21)';

CREATE TABLE governance.task (
    task_id         uuid             NOT NULL DEFAULT uuidv7(),
    name            text             NOT NULL,
    display_name    text             NOT NULL,
    description     text             NOT NULL,
    description_embedding        vector(1536),
    description_embedding_model  text,
    last_similarity_check_at     timestamptz,
    similarity_flags jsonb           NOT NULL DEFAULT '[]'::jsonb,
    capability_type governance.capability_type NOT NULL,
    purpose         text             NOT NULL,
    domain          text             NOT NULL DEFAULT 'underwriting',
    materiality_tier governance.materiality_tier NOT NULL,
    input_schema    jsonb            NOT NULL,
    output_schema   jsonb            NOT NULL,
    owner_name      text             NOT NULL,
    owner_email     text,
    business_context text,
    known_limitations text,
    regulatory_notes text,
    created_at      timestamptz      NOT NULL DEFAULT now(),
    updated_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_task PRIMARY KEY (task_id),
    CONSTRAINT uq_task_name UNIQUE (name)
);
CREATE INDEX ix_task_capability_type ON governance.task (capability_type);
COMMENT ON TABLE governance.task IS 'tier:1 task header (system-of-record); current champion is a view in lifecycle_approvals (C6/D21)';

CREATE TABLE governance.prompt (
    prompt_id           uuid        NOT NULL DEFAULT uuidv7(),
    name                text        NOT NULL,
    display_name        text        NOT NULL,
    description         text        NOT NULL,
    primary_entity_type governance.entity_type,
    primary_entity_id   uuid,                        -- soft polymorphic pointer (app-validated, N1)
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_prompt PRIMARY KEY (prompt_id),
    CONSTRAINT uq_prompt_name UNIQUE (name)
);
COMMENT ON TABLE governance.prompt IS 'tier:1 prompt header (system-of-record)';

-- ============================================================================
-- IMMUTABLE VERSIONS with SCD-2 temporal windows (valid_from/valid_to)
-- ============================================================================

CREATE TABLE governance.agent_version (
    agent_version_id uuid            NOT NULL DEFAULT uuidv7(),
    agent_id        uuid             NOT NULL,
    major_version   integer          NOT NULL DEFAULT 1,
    minor_version   integer          NOT NULL DEFAULT 0,
    patch_version   integer          NOT NULL DEFAULT 0,
    version_label   text             GENERATED ALWAYS AS
        (major_version || '.' || minor_version || '.' || patch_version) STORED,
    lifecycle_state governance.lifecycle_state   NOT NULL DEFAULT 'draft',
    channel         governance.deployment_channel NOT NULL DEFAULT 'development',
    inference_config_id uuid         NOT NULL,
    input_schema    jsonb            NOT NULL DEFAULT '{}'::jsonb,
    output_schema   jsonb,
    authority_thresholds jsonb       NOT NULL DEFAULT '{}'::jsonb,
    mock_mode_enabled boolean        NOT NULL DEFAULT false,
    decision_log_detail governance.decision_log_detail NOT NULL DEFAULT 'standard',
    shadow_traffic_pct      numeric(5,4) NOT NULL DEFAULT 0,
    challenger_traffic_pct  numeric(5,4) NOT NULL DEFAULT 0,
    staging_tests_passed    boolean,
    ground_truth_passed     boolean,
    fairness_passed         boolean,
    shadow_period_complete  boolean   NOT NULL DEFAULT false,
    challenger_period_complete boolean NOT NULL DEFAULT false,
    developer_name  text,
    change_summary  text,
    limitations_this_version text,
    change_type     governance.version_change_type,
    cloned_from_version_id uuid,
    valid_from      timestamptz,
    valid_to        timestamptz,
    created_at      timestamptz      NOT NULL DEFAULT now(),
    updated_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_agent_version PRIMARY KEY (agent_version_id),
    CONSTRAINT fk_agent_version_agent
        FOREIGN KEY (agent_id) REFERENCES governance.agent (agent_id) ON DELETE RESTRICT,
    CONSTRAINT fk_agent_version_inference_config
        FOREIGN KEY (inference_config_id) REFERENCES governance.inference_config (inference_config_id) ON DELETE RESTRICT,
    CONSTRAINT fk_agent_version_cloned_from
        FOREIGN KEY (cloned_from_version_id) REFERENCES governance.agent_version (agent_version_id) ON DELETE SET NULL,
    CONSTRAINT uq_agent_version_semver UNIQUE (agent_id, major_version, minor_version, patch_version),
    CONSTRAINT ck_agent_version_shadow_pct CHECK (shadow_traffic_pct BETWEEN 0 AND 1),
    CONSTRAINT ck_agent_version_challenger_pct CHECK (challenger_traffic_pct BETWEEN 0 AND 1),
    CONSTRAINT ck_agent_version_temporal CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);
CREATE INDEX ix_agent_version_agent_id ON governance.agent_version (agent_id);
CREATE INDEX ix_agent_version_lifecycle_state ON governance.agent_version (lifecycle_state);
CREATE INDEX ix_agent_version_inference_config ON governance.agent_version (inference_config_id);
CREATE INDEX ix_agent_version_cloned_from ON governance.agent_version (cloned_from_version_id);
COMMENT ON TABLE governance.agent_version IS 'tier:1 immutable agent version (SCD-2 valid_from/valid_to)';

CREATE TABLE governance.task_version (
    task_version_id uuid             NOT NULL DEFAULT uuidv7(),
    task_id         uuid             NOT NULL,
    major_version   integer          NOT NULL DEFAULT 1,
    minor_version   integer          NOT NULL DEFAULT 0,
    patch_version   integer          NOT NULL DEFAULT 0,
    version_label   text             GENERATED ALWAYS AS
        (major_version || '.' || minor_version || '.' || patch_version) STORED,
    lifecycle_state governance.lifecycle_state   NOT NULL DEFAULT 'draft',
    channel         governance.deployment_channel NOT NULL DEFAULT 'development',
    inference_config_id uuid         NOT NULL,
    output_schema   jsonb,
    mock_mode_enabled boolean        NOT NULL DEFAULT false,
    decision_log_detail governance.decision_log_detail NOT NULL DEFAULT 'standard',
    shadow_traffic_pct      numeric(5,4) NOT NULL DEFAULT 0,
    challenger_traffic_pct  numeric(5,4) NOT NULL DEFAULT 0,
    staging_tests_passed    boolean,
    ground_truth_passed     boolean,
    fairness_passed         boolean,
    developer_name  text,
    change_summary  text,
    change_type     governance.version_change_type,
    cloned_from_version_id uuid,
    valid_from      timestamptz,
    valid_to        timestamptz,
    created_at      timestamptz      NOT NULL DEFAULT now(),
    updated_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_task_version PRIMARY KEY (task_version_id),
    CONSTRAINT fk_task_version_task
        FOREIGN KEY (task_id) REFERENCES governance.task (task_id) ON DELETE RESTRICT,
    CONSTRAINT fk_task_version_inference_config
        FOREIGN KEY (inference_config_id) REFERENCES governance.inference_config (inference_config_id) ON DELETE RESTRICT,
    CONSTRAINT fk_task_version_cloned_from
        FOREIGN KEY (cloned_from_version_id) REFERENCES governance.task_version (task_version_id) ON DELETE SET NULL,
    CONSTRAINT uq_task_version_semver UNIQUE (task_id, major_version, minor_version, patch_version),
    CONSTRAINT ck_task_version_shadow_pct CHECK (shadow_traffic_pct BETWEEN 0 AND 1),
    CONSTRAINT ck_task_version_challenger_pct CHECK (challenger_traffic_pct BETWEEN 0 AND 1),
    CONSTRAINT ck_task_version_temporal CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);
CREATE INDEX ix_task_version_task_id ON governance.task_version (task_id);
CREATE INDEX ix_task_version_lifecycle_state ON governance.task_version (lifecycle_state);
CREATE INDEX ix_task_version_inference_config ON governance.task_version (inference_config_id);
CREATE INDEX ix_task_version_cloned_from ON governance.task_version (cloned_from_version_id);
COMMENT ON TABLE governance.task_version IS 'tier:1 immutable task version (SCD-2 valid_from/valid_to)';

CREATE TABLE governance.prompt_version (
    prompt_version_id uuid           NOT NULL DEFAULT uuidv7(),
    prompt_id       uuid             NOT NULL,
    major_version   integer          NOT NULL DEFAULT 1,
    minor_version   integer          NOT NULL DEFAULT 0,
    patch_version   integer          NOT NULL DEFAULT 0,
    version_label   text             GENERATED ALWAYS AS
        (major_version || '.' || minor_version || '.' || patch_version) STORED,
    content         text             NOT NULL,
    template_variables text[]        NOT NULL DEFAULT '{}',
    api_role        governance.api_role        NOT NULL DEFAULT 'system',
    governance_tier governance.governance_tier NOT NULL DEFAULT 'behavioural',
    content_embedding       vector(1536),
    content_embedding_model text,
    lifecycle_state governance.lifecycle_state NOT NULL DEFAULT 'draft',
    change_summary  text             NOT NULL,
    sensitivity_level text           NOT NULL DEFAULT 'high',
    author_name     text,
    approved_by     text,
    approved_at     timestamptz,
    test_required   boolean          GENERATED ALWAYS AS (governance_tier = 'behavioural') STORED,
    staging_tests_passed boolean,
    cloned_from_version_id uuid,
    valid_from      timestamptz,
    valid_to        timestamptz,
    created_at      timestamptz      NOT NULL DEFAULT now(),
    updated_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_prompt_version PRIMARY KEY (prompt_version_id),
    CONSTRAINT fk_prompt_version_prompt
        FOREIGN KEY (prompt_id) REFERENCES governance.prompt (prompt_id) ON DELETE RESTRICT,
    CONSTRAINT fk_prompt_version_cloned_from
        FOREIGN KEY (cloned_from_version_id) REFERENCES governance.prompt_version (prompt_version_id) ON DELETE SET NULL,
    CONSTRAINT uq_prompt_version_semver UNIQUE (prompt_id, major_version, minor_version, patch_version),
    CONSTRAINT ck_prompt_version_temporal CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);
CREATE INDEX ix_prompt_version_prompt_id ON governance.prompt_version (prompt_id);
CREATE INDEX ix_prompt_version_lifecycle_state ON governance.prompt_version (lifecycle_state);
CREATE INDEX ix_prompt_version_governance_tier ON governance.prompt_version (governance_tier);
CREATE INDEX ix_prompt_version_cloned_from ON governance.prompt_version (cloned_from_version_id);
COMMENT ON TABLE governance.prompt_version IS 'tier:1 immutable prompt version (SCD-2 valid_from/valid_to)';

-- ============================================================================
-- PROMPT ASSIGNMENT (entity_version <-> prompt_version)
-- ============================================================================

CREATE TABLE governance.entity_prompt_assignment (
    entity_prompt_assignment_id uuid NOT NULL DEFAULT uuidv7(),
    entity_type     governance.entity_type NOT NULL,
    entity_version_id uuid           NOT NULL,        -- soft polymorphic pointer to agent_version/task_version (N1)
    prompt_version_id uuid           NOT NULL,
    api_role        governance.api_role        NOT NULL,
    governance_tier governance.governance_tier NOT NULL,
    execution_order integer          NOT NULL DEFAULT 1,
    is_required     boolean          NOT NULL DEFAULT true,
    condition_logic jsonb,
    created_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_entity_prompt_assignment PRIMARY KEY (entity_prompt_assignment_id),
    CONSTRAINT fk_entity_prompt_assignment_prompt_version
        FOREIGN KEY (prompt_version_id) REFERENCES governance.prompt_version (prompt_version_id) ON DELETE RESTRICT,
    CONSTRAINT uq_entity_prompt_assignment UNIQUE (entity_type, entity_version_id, prompt_version_id, api_role),
    CONSTRAINT ck_entity_prompt_assignment_entity_kind CHECK (entity_type IN ('agent', 'task'))
);
CREATE INDEX ix_entity_prompt_assignment_entity ON governance.entity_prompt_assignment (entity_type, entity_version_id);
CREATE INDEX ix_entity_prompt_assignment_prompt_version ON governance.entity_prompt_assignment (prompt_version_id);
COMMENT ON TABLE governance.entity_prompt_assignment IS 'tier:1 prompt-to-entity-version assignment';

-- ============================================================================
-- MCP SERVERS, TOOLS, DATA CONNECTORS (single-row registries)
-- ============================================================================

CREATE TABLE governance.mcp_server (
    mcp_server_id   uuid        NOT NULL DEFAULT uuidv7(),
    name            text        NOT NULL,
    display_name    text        NOT NULL,
    description     text,
    transport       text        NOT NULL,                -- S3: open text (vs tool.transport enum); document open
    command         text,
    args            text[]      NOT NULL DEFAULT '{}',
    url             text,
    env             jsonb       NOT NULL DEFAULT '{}'::jsonb,
    auth_config     jsonb       NOT NULL DEFAULT '{}'::jsonb,
    is_active       boolean     NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_mcp_server PRIMARY KEY (mcp_server_id),
    CONSTRAINT uq_mcp_server_name UNIQUE (name)
);
COMMENT ON TABLE governance.mcp_server IS 'tier:1 MCP server registry';

CREATE TABLE governance.tool (
    tool_id         uuid             NOT NULL DEFAULT uuidv7(),
    name            text             NOT NULL,
    display_name    text             NOT NULL,
    description     text             NOT NULL,
    description_embedding        vector(1536),
    description_embedding_model  text,
    last_similarity_check_at     timestamptz,
    similarity_flags jsonb           NOT NULL DEFAULT '[]'::jsonb,
    input_schema    jsonb            NOT NULL,
    output_schema   jsonb            NOT NULL,
    transport       governance.tool_transport NOT NULL DEFAULT 'python_inprocess',
    mcp_server_id   uuid,                            -- hardened: FK to mcp_server_id (v1 keyed on name)
    mcp_tool_name   text,
    implementation_path text         NOT NULL,
    mock_mode_enabled boolean        NOT NULL DEFAULT true,
    mock_response_key text,
    mock_responses  jsonb            NOT NULL DEFAULT '{}'::jsonb,
    data_classification_max governance.data_classification NOT NULL DEFAULT 'tier3_confidential',
    is_write_operation boolean       NOT NULL DEFAULT false,
    requires_confirmation boolean    NOT NULL DEFAULT false,
    tags            text[]           NOT NULL DEFAULT '{}',
    is_active       boolean          NOT NULL DEFAULT true,
    created_at      timestamptz      NOT NULL DEFAULT now(),
    updated_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_tool PRIMARY KEY (tool_id),
    CONSTRAINT uq_tool_name UNIQUE (name),
    CONSTRAINT fk_tool_mcp_server
        FOREIGN KEY (mcp_server_id) REFERENCES governance.mcp_server (mcp_server_id) ON DELETE RESTRICT,
    CONSTRAINT ck_tool_mcp_pairing
        CHECK (transport <> 'mcp' OR (mcp_server_id IS NOT NULL AND mcp_tool_name IS NOT NULL))
);
CREATE INDEX ix_tool_mcp_server ON governance.tool (mcp_server_id);
COMMENT ON TABLE governance.tool IS 'tier:1 tool registry (agent-only capability per binding-grammar)';

CREATE TABLE governance.data_connector (
    data_connector_id uuid        NOT NULL DEFAULT uuidv7(),
    name            text          NOT NULL,
    connector_type  text          NOT NULL,              -- S3: open text; document open value set
    display_name    text          NOT NULL,
    description     text,
    config          jsonb         NOT NULL DEFAULT '{}'::jsonb,
    owner_name      text,
    created_at      timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_data_connector PRIMARY KEY (data_connector_id),
    CONSTRAINT uq_data_connector_name UNIQUE (name)
);
COMMENT ON TABLE governance.data_connector IS 'tier:1 data connector registry';

-- ============================================================================
-- VERSION->TOOL AUTHORIZATION (agent-only; task_version_tool kept for parity/no-loss)
-- ============================================================================

CREATE TABLE governance.agent_version_tool (
    agent_version_tool_id uuid       NOT NULL DEFAULT uuidv7(),
    agent_version_id uuid            NOT NULL,
    tool_id         uuid             NOT NULL,
    is_authorized   boolean          NOT NULL DEFAULT true,
    notes           text,
    created_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_agent_version_tool PRIMARY KEY (agent_version_tool_id),
    CONSTRAINT fk_agent_version_tool_version
        FOREIGN KEY (agent_version_id) REFERENCES governance.agent_version (agent_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_agent_version_tool_tool
        FOREIGN KEY (tool_id) REFERENCES governance.tool (tool_id) ON DELETE RESTRICT,
    CONSTRAINT uq_agent_version_tool UNIQUE (agent_version_id, tool_id)
);
CREATE INDEX ix_agent_version_tool_version ON governance.agent_version_tool (agent_version_id);
CREATE INDEX ix_agent_version_tool_tool ON governance.agent_version_tool (tool_id);
COMMENT ON TABLE governance.agent_version_tool IS 'tier:1 agent-version tool authorization';

CREATE TABLE governance.task_version_tool (
    task_version_tool_id uuid        NOT NULL DEFAULT uuidv7(),
    task_version_id uuid             NOT NULL,
    tool_id         uuid             NOT NULL,
    is_authorized   boolean          NOT NULL DEFAULT true,
    notes           text,
    created_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_task_version_tool PRIMARY KEY (task_version_tool_id),
    CONSTRAINT fk_task_version_tool_version
        FOREIGN KEY (task_version_id) REFERENCES governance.task_version (task_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_task_version_tool_tool
        FOREIGN KEY (tool_id) REFERENCES governance.tool (tool_id) ON DELETE RESTRICT,
    CONSTRAINT uq_task_version_tool UNIQUE (task_version_id, tool_id)
);
CREATE INDEX ix_task_version_tool_version ON governance.task_version_tool (task_version_id);
CREATE INDEX ix_task_version_tool_tool ON governance.task_version_tool (tool_id);
COMMENT ON TABLE governance.task_version_tool IS 'tier:1 KEPT for no-silent-loss; binding-grammar makes tools agent-only (DEFER deprecation)';

-- ============================================================================
-- SOURCE BINDING / TARGET BINDING (v2 grammar; retire v1 source_binding/write_target)
-- Apply uniformly to task_version and agent_version (agent binder parity).
-- ============================================================================

CREATE TABLE governance.source_binding (
    source_binding_id uuid          NOT NULL DEFAULT uuidv7(),
    owner_kind      governance.binding_owner_kind NOT NULL,
    owner_id        uuid            NOT NULL,         -- soft polymorphic to *_version (app-validated by owner_kind, N1)
    template_var    text            NOT NULL,
    reference       text            NOT NULL,
    source_kind     governance.source_kind         NOT NULL DEFAULT 'structured',
    source_payload_kind governance.source_payload_kind NOT NULL DEFAULT 'text',
    is_required     boolean         NOT NULL DEFAULT true,
    execution_order integer         NOT NULL DEFAULT 1,
    description     text,
    created_at      timestamptz     NOT NULL DEFAULT now(),
    CONSTRAINT pk_source_binding PRIMARY KEY (source_binding_id),
    CONSTRAINT uq_source_binding_owner_var UNIQUE (owner_kind, owner_id, template_var)
);
CREATE INDEX ix_source_binding_owner ON governance.source_binding (owner_kind, owner_id);
COMMENT ON TABLE governance.source_binding IS 'tier:1 Source Binding (renamed from v1 source_binding); declarative input resolution; v1 binding_kind -> source_payload_kind, new source_kind enum';

CREATE TABLE governance.target_binding (
    target_binding_id uuid          NOT NULL DEFAULT uuidv7(),
    owner_kind      governance.binding_owner_kind NOT NULL,
    owner_id        uuid            NOT NULL,         -- soft polymorphic to *_version (N1)
    name            text            NOT NULL,
    target_kind     governance.target_kind NOT NULL DEFAULT 'structured',
    data_connector_id uuid,                           -- nullable: structured/task_output targets need no connector
    write_method    text,                             -- S5: v1 carryover, no enum/CHECK yet; promote+document in binding-grammar.md
    container       text,                             -- S5: v1 carryover, no enum/CHECK yet
    is_required     boolean         NOT NULL DEFAULT false,
    execution_order integer         NOT NULL DEFAULT 1,
    description     text,
    created_at      timestamptz     NOT NULL DEFAULT now(),
    CONSTRAINT pk_target_binding PRIMARY KEY (target_binding_id),
    CONSTRAINT fk_target_binding_data_connector
        FOREIGN KEY (data_connector_id) REFERENCES governance.data_connector (data_connector_id) ON DELETE RESTRICT,
    CONSTRAINT uq_target_binding_owner_name UNIQUE (owner_kind, owner_id, name),
    CONSTRAINT ck_target_binding_vault_connector
        CHECK (target_kind <> 'vault' OR data_connector_id IS NOT NULL)
);
CREATE INDEX ix_target_binding_owner ON governance.target_binding (owner_kind, owner_id);
CREATE INDEX ix_target_binding_data_connector ON governance.target_binding (data_connector_id);
COMMENT ON TABLE governance.target_binding IS 'tier:1 Target Binding (renamed from v1 write_target); declarative output write';

CREATE TABLE governance.target_payload_field (
    target_payload_field_id uuid    NOT NULL DEFAULT uuidv7(),
    target_binding_id uuid          NOT NULL,         -- renamed from v1 write_target_id
    payload_field   text            NOT NULL,
    reference       text            NOT NULL,
    is_required     boolean         NOT NULL DEFAULT true,
    execution_order integer         NOT NULL DEFAULT 1,
    description     text,
    created_at      timestamptz     NOT NULL DEFAULT now(),
    CONSTRAINT pk_target_payload_field PRIMARY KEY (target_payload_field_id),
    CONSTRAINT fk_target_payload_field_target_binding
        FOREIGN KEY (target_binding_id) REFERENCES governance.target_binding (target_binding_id) ON DELETE CASCADE,
    CONSTRAINT uq_target_payload_field UNIQUE (target_binding_id, payload_field)
);
CREATE INDEX ix_target_payload_field_target ON governance.target_payload_field (target_binding_id);
COMMENT ON TABLE governance.target_payload_field IS 'tier:1 per-field payload mapping for a Target Binding';

-- ============================================================================
-- LEGACY I/O GRAMMAR (task_version_source / task_version_target)
-- KEPT for no-silent-loss; superseded by source_binding/target_binding (DEFER retire).
-- ============================================================================

CREATE TABLE governance.task_version_source (
    task_version_source_id uuid     NOT NULL DEFAULT uuidv7(),
    task_version_id uuid            NOT NULL,
    input_field_name text           NOT NULL,
    data_connector_id uuid          NOT NULL,
    fetch_method    text            NOT NULL,
    maps_to_template_var text       NOT NULL,
    is_required     boolean         NOT NULL DEFAULT true,
    execution_order integer         NOT NULL DEFAULT 1,
    description     text,
    created_at      timestamptz     NOT NULL DEFAULT now(),
    CONSTRAINT pk_task_version_source PRIMARY KEY (task_version_source_id),
    CONSTRAINT fk_task_version_source_version
        FOREIGN KEY (task_version_id) REFERENCES governance.task_version (task_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_task_version_source_connector
        FOREIGN KEY (data_connector_id) REFERENCES governance.data_connector (data_connector_id) ON DELETE RESTRICT,
    CONSTRAINT uq_task_version_source_field UNIQUE (task_version_id, input_field_name),
    CONSTRAINT uq_task_version_source_var UNIQUE (task_version_id, maps_to_template_var)
);
CREATE INDEX ix_task_version_source_version ON governance.task_version_source (task_version_id);
CREATE INDEX ix_task_version_source_connector ON governance.task_version_source (data_connector_id);
COMMENT ON TABLE governance.task_version_source IS 'tier:1 KEPT for no-silent-loss; superseded by source_binding (DEFER retire after migration)';

CREATE TABLE governance.task_version_target (
    task_version_target_id uuid     NOT NULL DEFAULT uuidv7(),
    task_version_id uuid            NOT NULL,
    output_field_name text          NOT NULL,
    data_connector_id uuid          NOT NULL,
    write_method    text            NOT NULL,
    target_container text,
    is_required     boolean         NOT NULL DEFAULT false,
    execution_order integer         NOT NULL DEFAULT 1,
    description     text,
    created_at      timestamptz     NOT NULL DEFAULT now(),
    CONSTRAINT pk_task_version_target PRIMARY KEY (task_version_target_id),
    CONSTRAINT fk_task_version_target_version
        FOREIGN KEY (task_version_id) REFERENCES governance.task_version (task_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_task_version_target_connector
        FOREIGN KEY (data_connector_id) REFERENCES governance.data_connector (data_connector_id) ON DELETE RESTRICT,
    CONSTRAINT uq_task_version_target_field UNIQUE (task_version_id, output_field_name)
);
CREATE INDEX ix_task_version_target_version ON governance.task_version_target (task_version_id);
CREATE INDEX ix_task_version_target_connector ON governance.task_version_target (data_connector_id);
COMMENT ON TABLE governance.task_version_target IS 'tier:1 KEPT for no-silent-loss; superseded by target_binding (DEFER retire after migration)';

-- ============================================================================
-- DELEGATIONS (agent_version -> agent_version)
-- ============================================================================

CREATE TABLE governance.agent_version_delegation (
    agent_version_delegation_id uuid NOT NULL DEFAULT uuidv7(),
    parent_agent_version_id uuid     NOT NULL,
    child_agent_name text,
    child_agent_version_id uuid,
    scope           jsonb            NOT NULL DEFAULT '{}'::jsonb,
    is_authorized   boolean          NOT NULL DEFAULT true,
    rationale       text,
    notes           text,
    created_at      timestamptz      NOT NULL DEFAULT now(),
    updated_at      timestamptz      NOT NULL DEFAULT now(),
    CONSTRAINT pk_agent_version_delegation PRIMARY KEY (agent_version_delegation_id),
    CONSTRAINT fk_agent_version_delegation_parent
        FOREIGN KEY (parent_agent_version_id) REFERENCES governance.agent_version (agent_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_agent_version_delegation_child
        FOREIGN KEY (child_agent_version_id) REFERENCES governance.agent_version (agent_version_id) ON DELETE SET NULL,
    CONSTRAINT uq_agent_version_delegation UNIQUE (parent_agent_version_id, child_agent_name, child_agent_version_id),
    CONSTRAINT ck_agent_version_delegation_child_target
        CHECK ((child_agent_name IS NOT NULL) <> (child_agent_version_id IS NOT NULL))
);
CREATE INDEX ix_agent_version_delegation_parent ON governance.agent_version_delegation (parent_agent_version_id);
CREATE INDEX ix_agent_version_delegation_child_name ON governance.agent_version_delegation (child_agent_name);
CREATE INDEX ix_agent_version_delegation_child_version ON governance.agent_version_delegation (child_agent_version_id);
COMMENT ON TABLE governance.agent_version_delegation IS 'tier:1 agent-to-agent delegation grant';

-- ============================================================================
-- APPLICATION_ENTITY (ownership grouping). application table DROPPED here
-- (B10: intake owns it). fk_application_entity_application targets
-- governance.application owned by the INTAKE section which loads later ->
-- FK DEFERRED to the deferred-FK section.
-- ============================================================================

CREATE TABLE governance.application_entity (
    application_entity_id uuid      NOT NULL DEFAULT uuidv7(),
    application_id  uuid            NOT NULL,           -- FK -> governance.application (intake section; DEFERRED)
    entity_type     governance.entity_type NOT NULL,
    entity_id       uuid            NOT NULL,           -- soft polymorphic pointer (app-validated, N1)
    created_at      timestamptz     NOT NULL DEFAULT now(),
    CONSTRAINT pk_application_entity PRIMARY KEY (application_entity_id),
    CONSTRAINT uq_application_entity UNIQUE (application_id, entity_type, entity_id)
);
CREATE INDEX ix_application_entity_application ON governance.application_entity (application_id);
CREATE INDEX ix_application_entity_entity ON governance.application_entity (entity_type, entity_id);
COMMENT ON TABLE governance.application_entity IS 'tier:1 application-to-entity ownership; fk_application_entity_application -> governance.application (intake) added by deferred-FK section (was ON DELETE CASCADE)';

-- ############ TABLES: decisions ############
-- =====================================================================
-- SECTION: DECISIONS & MODEL-INVOCATION LOGGING + HITL  (schema: governance)
-- Source fragment: 06-decisions.sql. ADR-0004/0005/0007.
-- Owners emitted here: model, model_price (SCD-2), agent_decision_log
-- (+partitions), model_invocation_log (+partitions), hitl_override,
-- view v_model_invocation_cost.
-- Reconciliation applied:
--   E1  governance.uuidv7() -> bare uuidv7() (search_path-resolved).
--   E4  hitl_override.created_by -> created_by_user_id (col + index).
--   A6  run_purpose / decision_log_detail / entity_type are OWNED by the
--       entities section; their CREATE TYPE re-declarations are dropped here.
--       decision_log_detail member set reconciled to entities' owner
--       (minimal/standard/verbose); this section uses 'standard'.
-- Solely-owned enums (decision_status, invocation_status, model_status,
-- currency_code) are emitted here.
-- SOFT-REF POLICY: Tier-2 partitioned logs are not FK targets; cross-domain
-- refs (entity_version, execution_run, model from this section is intra so
-- it IS FK'd on model_price, identity/auth user, approval) are plain uuid,
-- app-validated — NOT DB FKs. Deferred cross-domain FKs (e.g.
-- hitl_override.created_by_user_id -> identity) are emitted in the
-- deferred-FK section.
-- =====================================================================

-- -----------------------------------------------------------------------------
-- ENUM TYPES (only those solely owned by this section)
-- -----------------------------------------------------------------------------

-- governance.run_purpose, governance.decision_log_detail, governance.entity_type
-- are OWNED by the entities section and intentionally NOT declared here (A6).

COMMENT ON TYPE governance.decision_status IS
    'Terminal status captured on an immutable decision-log row.';

COMMENT ON TYPE governance.invocation_status IS
    'Terminal status of a single model API call (v1 free varchar ''complete'').';

COMMENT ON TYPE governance.model_status IS
    'Model lifecycle status (v1 model.status free varchar ''active'').';

COMMENT ON TYPE governance.currency_code IS
    'Supported settlement currencies for model_price (v1 varchar(3) ''USD''); extend additively.';

-- =============================================================================
-- TIER-1: MODEL CATALOG + SCD-2 PRICE CATALOG (this section owns model/model_price)
-- =============================================================================

-- governance.model — provider model registry (Tier-1, system-of-record).
CREATE TABLE governance.model (
    model_id          uuid                     NOT NULL DEFAULT uuidv7(),
    provider          text                     NOT NULL,
    provider_model_id text                     NOT NULL,   -- v1 model.model_id (renamed; was natural, not surrogate)
    display_name      text                     NOT NULL,
    modality          text                     NOT NULL DEFAULT 'chat',
    context_window    integer,
    status            governance.model_status  NOT NULL DEFAULT 'active',
    description       text,
    created_at        timestamptz              NOT NULL DEFAULT now(),
    updated_at        timestamptz              NOT NULL DEFAULT now(),
    CONSTRAINT pk_model PRIMARY KEY (model_id),
    CONSTRAINT uq_model_provider_model UNIQUE (provider, provider_model_id),
    CONSTRAINT ck_model_context_window_positive
        CHECK (context_window IS NULL OR context_window > 0)
);
COMMENT ON TABLE  governance.model IS
    'tier:1 system-of-record. Provider model registry. Mutable (status/display).';
COMMENT ON COLUMN governance.model.provider_model_id IS
    'Renamed from v1 model.model_id (a natural key) to avoid colliding with the surrogate <table>_id convention; the surrogate PK is model_id.';

CREATE INDEX ix_model_provider ON governance.model (provider);
CREATE INDEX ix_model_status   ON governance.model (status);

-- governance.model_price — SCD-2 temporal price catalog (Tier-1, APPEND-ONLY).
CREATE TABLE governance.model_price (
    model_price_id            uuid                     NOT NULL DEFAULT uuidv7(),
    model_id                  uuid                     NOT NULL,
    input_price_per_1m        numeric(14,6)            NOT NULL,
    output_price_per_1m       numeric(14,6)            NOT NULL,
    cache_read_price_per_1m   numeric(14,6),
    cache_write_price_per_1m  numeric(14,6),
    currency                  governance.currency_code NOT NULL DEFAULT 'usd',
    valid_from                timestamptz              NOT NULL,
    valid_to                  timestamptz,            -- NULL => current/open row
    notes                     text,
    created_at                timestamptz              NOT NULL DEFAULT now(),
    CONSTRAINT pk_model_price PRIMARY KEY (model_price_id),
    CONSTRAINT fk_model_price_model
        FOREIGN KEY (model_id) REFERENCES governance.model (model_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_model_price_window
        CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_model_price_input_nonneg
        CHECK (input_price_per_1m >= 0),
    CONSTRAINT ck_model_price_output_nonneg
        CHECK (output_price_per_1m >= 0),
    CONSTRAINT ck_model_price_cache_read_nonneg
        CHECK (cache_read_price_per_1m IS NULL OR cache_read_price_per_1m >= 0),
    CONSTRAINT ck_model_price_cache_write_nonneg
        CHECK (cache_write_price_per_1m IS NULL OR cache_write_price_per_1m >= 0)
);
COMMENT ON TABLE governance.model_price IS
    'tier:1 system-of-record, append-only SCD-2. One row per price period; valid_to NULL = current. Price change = close prior row + insert new open row. Cost computed point-in-time, never stored.';

-- At most one OPEN (current) price row per model — the SCD-2 invariant (partial unique).
CREATE UNIQUE INDEX uq_model_price_open_per_model
    ON governance.model_price (model_id)
    WHERE valid_to IS NULL;
CREATE INDEX ix_model_price_model_valid_from
    ON governance.model_price (model_id, valid_from DESC);

-- =============================================================================
-- TIER-2: AGENT DECISION LOG (append-only, month range-partitioned, BRIN)
-- =============================================================================

-- PK is (agent_decision_log_id, created_at) — partition key required in PK.
CREATE TABLE governance.agent_decision_log (
    agent_decision_log_id       uuid                           NOT NULL DEFAULT uuidv7(),
    entity_type                 governance.entity_type         NOT NULL,
    entity_version_id           uuid                           NOT NULL,  -- soft ref -> registry version (cross-domain)
    prompt_version_ids          uuid[]                         NOT NULL DEFAULT '{}',
    inference_config_snapshot   jsonb                          NOT NULL,
    channel                     text                           NOT NULL,  -- deployment_channel value (enum owned by entities)
    mock_mode                   boolean                        NOT NULL DEFAULT false,
    run_purpose                 governance.run_purpose         NOT NULL DEFAULT 'production',
    workflow_run_id             uuid,
    execution_run_id            uuid,                                     -- soft ref -> runtime.execution_run
    parent_decision_id          uuid,                                     -- soft ref -> self (Tier-2, cannot FK across partitions)
    reproduced_from_decision_id uuid,                                     -- soft ref -> self
    execution_context_id        uuid,                                     -- soft ref -> run domain
    decision_depth              integer                        NOT NULL DEFAULT 0,
    step_name                   text,
    input_summary               text,
    input_json                  jsonb,
    output_json                 jsonb,
    output_summary              text,
    reasoning_text              text,
    risk_factors                jsonb,
    confidence_score            numeric(5,4),
    low_confidence_flag         boolean                        NOT NULL DEFAULT false,
    model_used                  text,
    input_tokens                integer,
    output_tokens               integer,
    duration_ms                 integer,
    tool_calls_made             jsonb,
    message_history             jsonb,
    source_binding_resolutions  jsonb,
    target_binding_writes       jsonb,
    redaction_applied           jsonb,
    application                 text                           NOT NULL DEFAULT 'default',
    hitl_required               boolean                        NOT NULL DEFAULT false,
    hitl_completed              boolean                        NOT NULL DEFAULT false,
    hitl_approval_id            uuid,                                     -- soft ref -> approval domain
    status                      governance.decision_status     NOT NULL DEFAULT 'complete',
    error_message               text,
    decision_log_detail         governance.decision_log_detail NOT NULL DEFAULT 'standard',
    created_at                  timestamptz                    NOT NULL DEFAULT now(),
    CONSTRAINT pk_agent_decision_log
        PRIMARY KEY (agent_decision_log_id, created_at),
    CONSTRAINT ck_agent_decision_log_entity_type_known
        CHECK (entity_type IN ('agent','task','tool')),
    CONSTRAINT ck_agent_decision_log_depth_nonneg
        CHECK (decision_depth >= 0),
    CONSTRAINT ck_agent_decision_log_confidence_range
        CHECK (confidence_score IS NULL OR (confidence_score >= 0 AND confidence_score <= 1)),
    CONSTRAINT ck_agent_decision_log_tokens_nonneg
        CHECK ((input_tokens  IS NULL OR input_tokens  >= 0)
           AND (output_tokens IS NULL OR output_tokens >= 0)),
    CONSTRAINT ck_agent_decision_log_error_requires_message
        CHECK (status <> 'error' OR error_message IS NOT NULL)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE governance.agent_decision_log IS
    'tier:2 bulk-log append-only. Canonical immutable audit record, one row per decision. Range-partitioned by month on created_at; BRIN on created_at. No UPDATE/DELETE. Self/run/approval refs are soft (app-validated) — Tier-2 is not an FK target.';
COMMENT ON COLUMN governance.agent_decision_log.source_binding_resolutions IS
    'v2 rename of v1 source_resolutions (binding-grammar: Source Binding capture).';
COMMENT ON COLUMN governance.agent_decision_log.target_binding_writes IS
    'v2 rename of v1 target_writes (binding-grammar: Target Binding capture).';

CREATE INDEX brin_agent_decision_log_created_at
    ON governance.agent_decision_log USING brin (created_at);
CREATE INDEX ix_agent_decision_log_entity
    ON governance.agent_decision_log (entity_type, entity_version_id);
CREATE INDEX ix_agent_decision_log_execution_run
    ON governance.agent_decision_log (execution_run_id);
CREATE INDEX ix_agent_decision_log_workflow_run
    ON governance.agent_decision_log (workflow_run_id);
CREATE INDEX ix_agent_decision_log_parent
    ON governance.agent_decision_log (parent_decision_id);

-- Monthly partitions (created ahead by an ops/cron job): _05 and _06.
CREATE TABLE governance.agent_decision_log_2026_05
    PARTITION OF governance.agent_decision_log
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE governance.agent_decision_log_2026_06
    PARTITION OF governance.agent_decision_log
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

-- =============================================================================
-- TIER-2: MODEL INVOCATION LOG (append-only, month range-partitioned, BRIN)
-- =============================================================================

CREATE TABLE governance.model_invocation_log (
    model_invocation_log_id      uuid                         NOT NULL DEFAULT uuidv7(),
    decision_log_id              uuid                         NOT NULL,  -- soft ref -> agent_decision_log (Tier-2)
    model_id                     uuid                         NOT NULL,  -- soft ref -> governance.model (Tier-2 write path decoupled)
    provider                     text                         NOT NULL,
    model_name                   text                         NOT NULL,
    started_at                   timestamptz                  NOT NULL,
    completed_at                 timestamptz                  NOT NULL,
    input_tokens                 integer                      NOT NULL DEFAULT 0,
    output_tokens                integer                      NOT NULL DEFAULT 0,
    cache_creation_input_tokens  integer                      NOT NULL DEFAULT 0,
    cache_read_input_tokens      integer                      NOT NULL DEFAULT 0,
    api_call_count               integer                      NOT NULL DEFAULT 1,
    stop_reason                  text,
    status                       governance.invocation_status NOT NULL DEFAULT 'complete',
    error_message                text,
    per_turn_metadata            jsonb,
    created_at                   timestamptz                  NOT NULL DEFAULT now(),
    CONSTRAINT pk_model_invocation_log
        PRIMARY KEY (model_invocation_log_id, created_at),
    CONSTRAINT ck_model_invocation_log_completed_after_started
        CHECK (completed_at >= started_at),
    CONSTRAINT ck_model_invocation_log_tokens_nonneg
        CHECK (input_tokens >= 0 AND output_tokens >= 0
           AND cache_creation_input_tokens >= 0 AND cache_read_input_tokens >= 0),
    CONSTRAINT ck_model_invocation_log_api_call_count_positive
        CHECK (api_call_count >= 1),
    CONSTRAINT ck_model_invocation_log_error_requires_message
        CHECK (status <> 'error' OR error_message IS NOT NULL)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE governance.model_invocation_log IS
    'tier:2 bulk-log append-only. One row per model API call. Range-partitioned by month on created_at; BRIN on created_at. decision_log_id/model_id are soft refs (Tier-2 decouple); no cascade — logs are never deleted.';

CREATE INDEX brin_model_invocation_log_created_at
    ON governance.model_invocation_log USING brin (created_at);
CREATE INDEX ix_model_invocation_log_decision
    ON governance.model_invocation_log (decision_log_id);
CREATE INDEX ix_model_invocation_log_model_started
    ON governance.model_invocation_log (model_id, started_at);

CREATE TABLE governance.model_invocation_log_2026_05
    PARTITION OF governance.model_invocation_log
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE governance.model_invocation_log_2026_06
    PARTITION OF governance.model_invocation_log
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

-- =============================================================================
-- TIER-1: PER-FIELD HITL OVERRIDE (append-only audit fact)
-- =============================================================================

-- created_by_user_id is a soft ref to the identity table (auth section, loads
-- earlier as governance.account_user); the FK is emitted in the deferred-FK
-- section (E4 rename applied here; cross-section FK omitted).
CREATE TABLE governance.hitl_override (
    hitl_override_id     uuid         NOT NULL DEFAULT uuidv7(),
    decision_log_id      uuid         NOT NULL,            -- soft ref -> agent_decision_log (Tier-2)
    output_path          text         NOT NULL,            -- JSON path of the overridden field
    ai_value             jsonb,
    ai_found             boolean      NOT NULL,
    hitl_value           jsonb        NOT NULL,
    application          text         NOT NULL,
    business_entity_type text         NOT NULL,            -- v1 entity_type (free-text business taxonomy)
    entity_reference     text         NOT NULL,
    fact_type            text         NOT NULL,
    reason               text,
    created_by_user_id   uuid         NOT NULL,            -- soft ref -> identity (auth); FK deferred (E4)
    created_at           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_hitl_override PRIMARY KEY (hitl_override_id)
);
COMMENT ON TABLE governance.hitl_override IS
    'tier:1 system-of-record, append-only. One immutable row per human override of one AI output field. decision_log_id is a soft ref to the Tier-2 decision log; no cascade.';
COMMENT ON COLUMN governance.hitl_override.business_entity_type IS
    'Free-text business taxonomy (v1 entity_type varchar) — intentionally NOT the registry governance.entity_type enum.';
COMMENT ON COLUMN governance.hitl_override.created_by_user_id IS
    'Acting principal (E4 rename from v1 created_by). Soft ref to identity; FK added in deferred-FK section.';

CREATE INDEX ix_hitl_override_decision
    ON governance.hitl_override (decision_log_id);
CREATE INDEX ix_hitl_override_fact
    ON governance.hitl_override (application, business_entity_type, fact_type);
CREATE INDEX ix_hitl_override_entity_ref
    ON governance.hitl_override (application, business_entity_type, entity_reference);
CREATE INDEX ix_hitl_override_created_at
    ON governance.hitl_override (created_at);
CREATE INDEX ix_hitl_override_created_by_user
    ON governance.hitl_override (created_by_user_id);

-- =============================================================================
-- VIEW: point-in-time invocation cost (cost computed, never stored)
-- =============================================================================

CREATE VIEW governance.v_model_invocation_cost AS
SELECT
    mil.model_invocation_log_id,
    mil.decision_log_id,
    mil.model_id,
    mil.provider,
    mil.model_name,
    mil.started_at,
    mil.completed_at,
    mil.input_tokens,
    mil.output_tokens,
    mil.cache_creation_input_tokens,
    mil.cache_read_input_tokens,
    mp.currency,
    mp.input_price_per_1m,
    mp.output_price_per_1m,
    mp.cache_read_price_per_1m,
    mp.cache_write_price_per_1m,
    (mil.input_tokens  / 1000000.0) * mp.input_price_per_1m                                  AS input_cost,
    (mil.output_tokens / 1000000.0) * mp.output_price_per_1m                                 AS output_cost,
    (mil.cache_creation_input_tokens / 1000000.0) * COALESCE(mp.cache_write_price_per_1m, 0) AS cache_write_cost,
    (mil.cache_read_input_tokens     / 1000000.0) * COALESCE(mp.cache_read_price_per_1m, 0)  AS cache_read_cost,
      (mil.input_tokens  / 1000000.0) * mp.input_price_per_1m
    + (mil.output_tokens / 1000000.0) * mp.output_price_per_1m
    + (mil.cache_creation_input_tokens / 1000000.0) * COALESCE(mp.cache_write_price_per_1m, 0)
    + (mil.cache_read_input_tokens     / 1000000.0) * COALESCE(mp.cache_read_price_per_1m, 0) AS total_cost
FROM governance.model_invocation_log AS mil
LEFT JOIN governance.model_price AS mp
       ON mp.model_id = mil.model_id
      AND mil.started_at >= mp.valid_from
      AND (mp.valid_to IS NULL OR mil.started_at < mp.valid_to);
COMMENT ON VIEW governance.v_model_invocation_cost IS
    'Point-in-time cost per invocation: each call priced by the model_price row whose [valid_from, valid_to) window contains started_at. Cost is computed here, never persisted.';

-- ############ TABLES: intake ############
-- =====================================================================
-- SECTION: INTAKE (tables/views) — single owner of application, intake_*,
--   approval_request, approval_signoff, and the obligation-set linkage.
-- Domain enums are emitted earlier (load step 2, "intake enums").
--
-- SYSTEM-WIDE PATTERN A (state = append-only events): any state-tracking
--   field is modeled as an immutable <entity>_status_event table; "current
--   state" is a VIEW <entity>_current over the latest event. The base tables
--   below hold only immutable descriptive attributes; status/decision/lock
--   transitions live in their event tables. See [[ADR-0004]] / [[ADR-0005]] §7.
-- SYSTEM-WIDE PATTERN B (requirement tags): spec/FR/ADR references in comments
--   are wrapped in [[ ]] so they are easy to find, update, or remove.
--
-- Reconciliation applied: [[B10]] application owner, [[B12]] approval_* owner,
--   [[B13]]/[[E3]] FR-018 user-id attribution on intake estimate/roi/envelope +
--   core intake tables, [[E2]] approval_signoff keyed on approver_user_id,
--   [[C16]] intake_obligation compliance FKs deferred, [[C5]]/[[C20]]
--   intake_requirement embedding FK deferred.
-- Identity FKs target governance.account_user ([[auth]], load step 10 — exists).
-- =====================================================================

-- ---------------------------------------------------------------------
-- TABLE: application  (Tier-1)  — owner [[B10]]. Adds name-not-blank CHECK.
-- ---------------------------------------------------------------------
CREATE TABLE governance.application (
    application_id   uuid        NOT NULL DEFAULT uuidv7(),
    name             text        NOT NULL,
    display_name     text        NOT NULL,
    description      text,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_application PRIMARY KEY (application_id),
    CONSTRAINT uq_application_name UNIQUE (name),
    CONSTRAINT ck_application_name_not_blank CHECK (length(btrim(name)) > 0)
);
COMMENT ON TABLE governance.application IS 'tier:1 system-of-record. Business application that owns intakes/use-cases.';

-- ---------------------------------------------------------------------
-- TABLE: intake  (Tier-1) — immutable header attributes only.
--   State (status + approved_at/retired_at) lives in intake_status_event;
--   read current state via view intake_current. FR-018: created_by_user_id.
-- ---------------------------------------------------------------------
CREATE TABLE governance.intake (
    intake_id                       uuid        NOT NULL DEFAULT uuidv7(),
    application_id                  uuid        NOT NULL,
    code                            text        NOT NULL,
    title                           text        NOT NULL,
    problem_statement               text        NOT NULL,
    expected_benefit                text        NOT NULL,
    in_scope_decisions              text,
    out_of_scope_decisions          text,
    affected_populations            jsonb       NOT NULL DEFAULT '[]'::jsonb,
    business_owner_name             text        NOT NULL,
    business_owner_email            text,
    requesting_team                 text,
    ai_risk_tier                    governance.ai_risk_tier   NOT NULL,
    risk_classification_rationale   text        NOT NULL,
    naic_materiality                governance.naic_materiality NOT NULL,
    hitl_strategy                   text,
    hitl_review_threshold           text,
    intake_at                       timestamptz NOT NULL DEFAULT now(),
    effective_date                  date,
    next_recertification_due        date,
    created_by_user_id              uuid        NOT NULL,
    acting_as_role                  governance.studio_role,
    notes                           text,
    created_at                      timestamptz NOT NULL DEFAULT now(),
    updated_at                      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake PRIMARY KEY (intake_id),
    CONSTRAINT fk_intake_application
        FOREIGN KEY (application_id)
        REFERENCES governance.application (application_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_intake_created_by_user
        FOREIGN KEY (created_by_user_id)
        REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_intake_application_code UNIQUE (application_id, code),
    CONSTRAINT ck_intake_code_not_blank CHECK (length(btrim(code)) > 0),
    CONSTRAINT ck_intake_affected_populations_array
        CHECK (jsonb_typeof(affected_populations) = 'array')
);
COMMENT ON TABLE governance.intake IS 'tier:1 system-of-record. Immutable intake header (one AI use-case per row); lifecycle status tracked in intake_status_event, projected by intake_current.';
CREATE INDEX ix_intake_application_id      ON governance.intake (application_id);
CREATE INDEX ix_intake_created_by_user_id  ON governance.intake (created_by_user_id);
CREATE INDEX ix_intake_ai_risk_tier        ON governance.intake (ai_risk_tier);
CREATE INDEX ix_intake_owner_email         ON governance.intake (business_owner_email);

-- Append-only intake lifecycle transitions (pattern A). One immutable row per
-- status change; approved_at/retired_at derive from the matching transition.
CREATE TABLE governance.intake_status_event (
    intake_status_event_id  uuid        NOT NULL DEFAULT uuidv7(),
    intake_id               uuid        NOT NULL,
    status                  governance.intake_status NOT NULL,
    reason                  text,
    changed_by_user_id      uuid        NOT NULL,
    acting_as_role          governance.studio_role,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_status_event PRIMARY KEY (intake_status_event_id),
    CONSTRAINT fk_intake_status_event_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_status_event_changed_by_user
        FOREIGN KEY (changed_by_user_id)
        REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT
);
COMMENT ON TABLE governance.intake_status_event IS 'tier:1 append-only. One immutable intake lifecycle transition per row; current status projected by intake_current. [[ADR-0005]] §7.';
CREATE INDEX ix_intake_status_event_intake_id
    ON governance.intake_status_event (intake_id, created_at DESC);
CREATE INDEX ix_intake_status_event_status
    ON governance.intake_status_event (status);

-- Current intake state = latest transition per intake (default 'proposed' until
-- the first event exists). approved_at/retired_at are the first time the intake
-- entered that status.
CREATE VIEW governance.intake_current AS
SELECT i.intake_id,
       i.application_id,
       i.code,
       i.title,
       i.ai_risk_tier,
       i.naic_materiality,
       COALESCE(s.status, 'proposed') AS status,
       s.created_at                   AS status_changed_at,
       (SELECT min(e.created_at) FROM governance.intake_status_event AS e
         WHERE e.intake_id = i.intake_id AND e.status = 'approved') AS approved_at,
       (SELECT min(e.created_at) FROM governance.intake_status_event AS e
         WHERE e.intake_id = i.intake_id AND e.status = 'retired')  AS retired_at,
       i.created_by_user_id,
       i.created_at,
       i.updated_at
FROM   governance.intake AS i
LEFT JOIN LATERAL (
    SELECT e.status, e.created_at
    FROM   governance.intake_status_event AS e
    WHERE  e.intake_id = i.intake_id
    ORDER BY e.created_at DESC, e.intake_status_event_id DESC
    LIMIT 1
) AS s ON true;
COMMENT ON VIEW governance.intake_current IS 'tier:1 projection. Current intake lifecycle state = latest intake_status_event (defaults to proposed).';

-- ---------------------------------------------------------------------
-- TABLE: intake_impact_assessment  (Tier-1). Versioned (append a new version
--   rather than mutate); each row is a complete immutable assessment version.
-- ---------------------------------------------------------------------
CREATE TABLE governance.intake_impact_assessment (
    intake_impact_assessment_id  uuid        NOT NULL DEFAULT uuidv7(),
    intake_id                    uuid        NOT NULL,
    version                      integer     NOT NULL DEFAULT 1,
    data_sources                 jsonb       NOT NULL DEFAULT '[]'::jsonb,
    potential_harms              jsonb       NOT NULL DEFAULT '[]'::jsonb,
    mitigations                  jsonb       NOT NULL DEFAULT '[]'::jsonb,
    fairness_considerations      text,
    privacy_considerations       text,
    human_oversight_plan         text,
    completed_at                 timestamptz,
    completed_by_user_id         uuid,
    notes                        text,
    created_by_user_id           uuid        NOT NULL,
    created_at                   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_impact_assessment PRIMARY KEY (intake_impact_assessment_id),
    CONSTRAINT fk_intake_impact_assessment_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_impact_assessment_completed_by_user
        FOREIGN KEY (completed_by_user_id)
        REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_intake_impact_assessment_created_by_user
        FOREIGN KEY (created_by_user_id)
        REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_intake_impact_assessment_version UNIQUE (intake_id, version),
    CONSTRAINT ck_intake_impact_assessment_version_positive CHECK (version >= 1),
    CONSTRAINT ck_intake_impact_assessment_data_sources_array
        CHECK (jsonb_typeof(data_sources) = 'array'),
    CONSTRAINT ck_intake_impact_assessment_potential_harms_array
        CHECK (jsonb_typeof(potential_harms) = 'array'),
    CONSTRAINT ck_intake_impact_assessment_mitigations_array
        CHECK (jsonb_typeof(mitigations) = 'array')
);
COMMENT ON TABLE governance.intake_impact_assessment IS 'tier:1 append-only versioned. Immutable impact-assessment version per intake (limited/high AI-risk); newest version = max(version).';
CREATE INDEX ix_intake_impact_assessment_intake_id
    ON governance.intake_impact_assessment (intake_id, version DESC);

-- Latest impact assessment per intake.
CREATE VIEW governance.intake_impact_assessment_current AS
SELECT DISTINCT ON (a.intake_id) a.*
FROM   governance.intake_impact_assessment AS a
ORDER BY a.intake_id, a.version DESC, a.created_at DESC;
COMMENT ON VIEW governance.intake_impact_assessment_current IS 'tier:1 projection. Highest-version impact assessment per intake.';

-- ---------------------------------------------------------------------
-- TABLE: intake_requirement  (Tier-1) — immutable attributes; status tracked
--   in intake_requirement_status_event. FR-018: created_by_user_id.
--   NOTE: embedding_model_id FK -> embedding_config OMITTED ([[C5]]/[[C20]]):
--   embedding_config is owned by the reporting section (loads later); FK emitted
--   as a deferred ALTER.
-- ---------------------------------------------------------------------
CREATE TABLE governance.intake_requirement (
    intake_requirement_id    uuid        NOT NULL DEFAULT uuidv7(),
    intake_id                uuid        NOT NULL,
    code                     text        NOT NULL,
    kind                     governance.requirement_kind   NOT NULL,
    statement                text        NOT NULL,
    acceptance_criteria      text,
    source                   text,
    parent_requirement_id    uuid,
    embedding                vector(384),
    embedding_model_id       uuid,
    embedding_input_hash     bytea,
    created_by_user_id       uuid        NOT NULL,
    acting_as_role           governance.studio_role,
    created_at               timestamptz NOT NULL DEFAULT now(),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_requirement PRIMARY KEY (intake_requirement_id),
    CONSTRAINT fk_intake_requirement_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_requirement_parent
        FOREIGN KEY (parent_requirement_id)
        REFERENCES governance.intake_requirement (intake_requirement_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_intake_requirement_created_by_user
        FOREIGN KEY (created_by_user_id)
        REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT,
    -- fk_intake_requirement_embedding_config (embedding_model_id ->
    --   compliance.embedding_config) DEFERRED [[C5]]/[[C20]]: target owned by reporting section.
    CONSTRAINT uq_intake_requirement_intake_code UNIQUE (intake_id, code),
    CONSTRAINT ck_intake_requirement_not_self_parent
        CHECK (parent_requirement_id IS NULL OR parent_requirement_id <> intake_requirement_id)
);
COMMENT ON TABLE governance.intake_requirement IS 'tier:1 system-of-record. Immutable BR/FR/NFR/compliance requirement attributes per intake; status in intake_requirement_status_event; pgvector embedding for similarity.';
CREATE INDEX ix_intake_requirement_intake_id          ON governance.intake_requirement (intake_id);
CREATE INDEX ix_intake_requirement_created_by_user_id ON governance.intake_requirement (created_by_user_id);
CREATE INDEX ix_intake_requirement_parent_id          ON governance.intake_requirement (parent_requirement_id);
-- pgvector cosine ANN index (ivfflat). Created conditionally at deploy if pgvector present.
CREATE INDEX ix_intake_requirement_embedding
    ON governance.intake_requirement USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- Append-only requirement status transitions (pattern A).
CREATE TABLE governance.intake_requirement_status_event (
    intake_requirement_status_event_id  uuid        NOT NULL DEFAULT uuidv7(),
    intake_requirement_id               uuid        NOT NULL,
    status                              governance.requirement_status NOT NULL,
    reason                              text,
    changed_by_user_id                  uuid        NOT NULL,
    acting_as_role                      governance.studio_role,
    created_at                          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_requirement_status_event PRIMARY KEY (intake_requirement_status_event_id),
    CONSTRAINT fk_intake_requirement_status_event_requirement
        FOREIGN KEY (intake_requirement_id)
        REFERENCES governance.intake_requirement (intake_requirement_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_requirement_status_event_changed_by_user
        FOREIGN KEY (changed_by_user_id)
        REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT
);
COMMENT ON TABLE governance.intake_requirement_status_event IS 'tier:1 append-only. One immutable requirement status transition per row; current status projected by intake_requirement_current.';
CREATE INDEX ix_intake_requirement_status_event_requirement_id
    ON governance.intake_requirement_status_event (intake_requirement_id, created_at DESC);

CREATE VIEW governance.intake_requirement_current AS
SELECT r.intake_requirement_id,
       r.intake_id,
       r.code,
       r.kind,
       r.statement,
       r.parent_requirement_id,
       COALESCE(s.status, 'draft') AS status,
       s.created_at                AS status_changed_at,
       r.created_by_user_id,
       r.created_at,
       r.updated_at
FROM   governance.intake_requirement AS r
LEFT JOIN LATERAL (
    SELECT e.status, e.created_at
    FROM   governance.intake_requirement_status_event AS e
    WHERE  e.intake_requirement_id = r.intake_requirement_id
    ORDER BY e.created_at DESC, e.intake_requirement_status_event_id DESC
    LIMIT 1
) AS s ON true;
COMMENT ON VIEW governance.intake_requirement_current IS 'tier:1 projection. Current requirement status = latest intake_requirement_status_event (defaults to draft).';

-- ---------------------------------------------------------------------
-- TABLE: intake_entity_link  (Tier-1). FR-018: created_by_user_id.
--   entity_id is polymorphic (no DB FK); integrity enforced at API.
-- ---------------------------------------------------------------------
CREATE TABLE governance.intake_entity_link (
    intake_entity_link_id  uuid        NOT NULL DEFAULT uuidv7(),
    intake_id              uuid        NOT NULL,
    requirement_id         uuid,
    entity_type            governance.entity_type NOT NULL,
    entity_id              uuid        NOT NULL,
    relationship           governance.requirement_relationship NOT NULL DEFAULT 'implements',
    created_by_user_id     uuid        NOT NULL,
    acting_as_role         governance.studio_role,
    created_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_entity_link PRIMARY KEY (intake_entity_link_id),
    CONSTRAINT fk_intake_entity_link_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_entity_link_requirement
        FOREIGN KEY (requirement_id)
        REFERENCES governance.intake_requirement (intake_requirement_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_intake_entity_link_created_by_user
        FOREIGN KEY (created_by_user_id)
        REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_intake_entity_link
        UNIQUE (intake_id, requirement_id, entity_type, entity_id, relationship)
);
COMMENT ON TABLE governance.intake_entity_link IS 'tier:1 system-of-record. Bridge intake/requirement -> registry entity; entity_id polymorphic (no DB FK; integrity at API).';
CREATE INDEX ix_intake_entity_link_intake_id          ON governance.intake_entity_link (intake_id);
CREATE INDEX ix_intake_entity_link_created_by_user_id ON governance.intake_entity_link (created_by_user_id);
CREATE INDEX ix_intake_entity_link_entity             ON governance.intake_entity_link (entity_type, entity_id);
-- Partial unique to forbid duplicate links when requirement_id is NULL (NULLs bypass the full uq).
CREATE UNIQUE INDEX uq_intake_entity_link_no_requirement
    ON governance.intake_entity_link (intake_id, entity_type, entity_id, relationship)
    WHERE requirement_id IS NULL;

-- ---------------------------------------------------------------------
-- TABLE: intake_artifact_plan  (Tier-1) — immutable plan attributes; status +
--   realization tracked in intake_artifact_plan_status_event. FR-018.
--   realized_entity_id is a polymorphic ref (no DB FK), carried on the event.
-- ---------------------------------------------------------------------
CREATE TABLE governance.intake_artifact_plan (
    intake_artifact_plan_id     uuid        NOT NULL DEFAULT uuidv7(),
    intake_id                   uuid        NOT NULL,
    requirement_id              uuid,
    proposed_kind               governance.entity_type        NOT NULL,
    proposed_name               text        NOT NULL,
    proposed_display_name       text        NOT NULL,
    proposed_description        text,
    proposed_purpose            text,
    proposed_inputs             jsonb       NOT NULL DEFAULT '{}'::jsonb,
    proposed_outputs            jsonb       NOT NULL DEFAULT '{}'::jsonb,
    proposed_capability_type    governance.capability_type,
    proposed_materiality_tier   governance.materiality_tier   NOT NULL,
    auto_generated              boolean     NOT NULL DEFAULT false,
    created_by_user_id          uuid        NOT NULL,
    acting_as_role              governance.studio_role,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_artifact_plan PRIMARY KEY (intake_artifact_plan_id),
    CONSTRAINT fk_intake_artifact_plan_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_artifact_plan_requirement
        FOREIGN KEY (requirement_id)
        REFERENCES governance.intake_requirement (intake_requirement_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_intake_artifact_plan_created_by_user
        FOREIGN KEY (created_by_user_id)
        REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_intake_artifact_plan UNIQUE (intake_id, proposed_kind, proposed_name),
    CONSTRAINT ck_intake_artifact_plan_inputs_object
        CHECK (jsonb_typeof(proposed_inputs) = 'object'),
    CONSTRAINT ck_intake_artifact_plan_outputs_object
        CHECK (jsonb_typeof(proposed_outputs) = 'object')
);
COMMENT ON TABLE governance.intake_artifact_plan IS 'tier:1 system-of-record. Immutable planned-entity attributes for an intake; status + realized_entity_id tracked in intake_artifact_plan_status_event.';
CREATE INDEX ix_intake_artifact_plan_intake_id         ON governance.intake_artifact_plan (intake_id);
CREATE INDEX ix_intake_artifact_plan_created_by_user_id ON governance.intake_artifact_plan (created_by_user_id);

-- Append-only plan status transitions (pattern A). realized_entity_id (polymorphic,
-- no DB FK) is supplied on the 'realized' transition.
CREATE TABLE governance.intake_artifact_plan_status_event (
    intake_artifact_plan_status_event_id  uuid        NOT NULL DEFAULT uuidv7(),
    intake_artifact_plan_id               uuid        NOT NULL,
    status                                governance.artifact_plan_status NOT NULL,
    realized_entity_id                    uuid,
    reason                                text,
    changed_by_user_id                    uuid        NOT NULL,
    acting_as_role                        governance.studio_role,
    created_at                            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_artifact_plan_status_event PRIMARY KEY (intake_artifact_plan_status_event_id),
    CONSTRAINT fk_intake_artifact_plan_status_event_plan
        FOREIGN KEY (intake_artifact_plan_id)
        REFERENCES governance.intake_artifact_plan (intake_artifact_plan_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_artifact_plan_status_event_changed_by_user
        FOREIGN KEY (changed_by_user_id)
        REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_intake_artifact_plan_status_event_realized_pair
        CHECK (status <> 'realized' OR realized_entity_id IS NOT NULL)
);
COMMENT ON TABLE governance.intake_artifact_plan_status_event IS 'tier:1 append-only. One immutable plan status transition per row; current status + realization projected by intake_artifact_plan_current.';
CREATE INDEX ix_intake_artifact_plan_status_event_plan_id
    ON governance.intake_artifact_plan_status_event (intake_artifact_plan_id, created_at DESC);

CREATE VIEW governance.intake_artifact_plan_current AS
SELECT p.intake_artifact_plan_id,
       p.intake_id,
       p.requirement_id,
       p.proposed_kind,
       p.proposed_name,
       p.proposed_materiality_tier,
       COALESCE(s.status, 'proposed') AS status,
       s.realized_entity_id,
       s.created_at                   AS status_changed_at,
       p.created_by_user_id,
       p.created_at,
       p.updated_at
FROM   governance.intake_artifact_plan AS p
LEFT JOIN LATERAL (
    SELECT e.status, e.realized_entity_id, e.created_at
    FROM   governance.intake_artifact_plan_status_event AS e
    WHERE  e.intake_artifact_plan_id = p.intake_artifact_plan_id
    ORDER BY e.created_at DESC, e.intake_artifact_plan_status_event_id DESC
    LIMIT 1
) AS s ON true;
COMMENT ON VIEW governance.intake_artifact_plan_current IS 'tier:1 projection. Current plan status + realized_entity_id = latest intake_artifact_plan_status_event (defaults to proposed).';

-- ---------------------------------------------------------------------
-- TABLE: intake_artifact_plan_estimate  (Tier-1). FR-018: created_by_user_id.
--   proposed_model_id -> governance.model ([[decisions]], load step 12 — exists).
--   Scenario versioning is append-only: a new estimate row supersedes; "active"
--   scenario per plan projected by intake_artifact_plan_estimate_current.
-- ---------------------------------------------------------------------
CREATE TABLE governance.intake_artifact_plan_estimate (
    intake_artifact_plan_estimate_id    uuid        NOT NULL DEFAULT uuidv7(),
    intake_artifact_plan_id             uuid        NOT NULL,
    scenario_label                      text        NOT NULL DEFAULT 'expected',
    scenario_notes                      text,
    proposed_model_id                   uuid,
    purpose_text                        text,
    expected_input_size_tokens          integer,
    expected_output_size_tokens         integer,
    expected_invocations_per_year       integer,
    peak_multiplier                     numeric(6,2)  NOT NULL DEFAULT 1.00,
    seasonality_pattern_text            text,
    expected_tool_call_count            integer       NOT NULL DEFAULT 0,
    expected_input_file                 boolean       NOT NULL DEFAULT false,
    expected_input_file_avg_kb          integer,
    expected_input_file_max_kb          integer,
    cost_estimate_per_invocation_usd    numeric(14,6),
    cost_estimate_yearly_usd            numeric(14,2),
    estimate_basis                      jsonb,
    cost_override_yearly_usd            numeric(14,2),
    cost_override_explanation           text,
    superseded                          boolean       NOT NULL DEFAULT false,
    created_by_user_id                  uuid          NOT NULL,
    acting_as_role                      governance.studio_role,
    created_at                          timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_artifact_plan_estimate PRIMARY KEY (intake_artifact_plan_estimate_id),
    CONSTRAINT fk_intake_artifact_plan_estimate_plan
        FOREIGN KEY (intake_artifact_plan_id)
        REFERENCES governance.intake_artifact_plan (intake_artifact_plan_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_artifact_plan_estimate_model
        FOREIGN KEY (proposed_model_id)
        REFERENCES governance.model (model_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_intake_artifact_plan_estimate_created_by_user
        FOREIGN KEY (created_by_user_id)
        REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_intake_artifact_plan_estimate_override_pair
        CHECK ((cost_override_yearly_usd IS NULL) = (cost_override_explanation IS NULL)),
    CONSTRAINT ck_intake_artifact_plan_estimate_peak_positive
        CHECK (peak_multiplier > 0)
);
COMMENT ON TABLE governance.intake_artifact_plan_estimate IS 'tier:1 append-only. Immutable scenario cost forecast per plan row; superseded marks history; active scenario projected by intake_artifact_plan_estimate_current.';
CREATE INDEX ix_intake_artifact_plan_estimate_plan_id
    ON governance.intake_artifact_plan_estimate (intake_artifact_plan_id);
CREATE INDEX ix_intake_artifact_plan_estimate_created_by_user_id
    ON governance.intake_artifact_plan_estimate (created_by_user_id);
-- At most one active (non-superseded) estimate per plan.
CREATE UNIQUE INDEX uq_intake_artifact_plan_estimate_active
    ON governance.intake_artifact_plan_estimate (intake_artifact_plan_id)
    WHERE superseded = false;

CREATE VIEW governance.intake_artifact_plan_estimate_current AS
SELECT e.*
FROM   governance.intake_artifact_plan_estimate AS e
WHERE  e.superseded = false;
COMMENT ON VIEW governance.intake_artifact_plan_estimate_current IS 'tier:1 projection. Active (non-superseded) cost estimate per plan row.';

-- ---------------------------------------------------------------------
-- TABLE: approval_request  (Tier-1) — owner [[B12]]. Immutable request
--   attributes; status (pending->approved/rejected/cancelled) + decided_at
--   tracked in approval_request_status_event. target_entity_id polymorphic.
--   FR-018: opened_by_user_id.
-- ---------------------------------------------------------------------
CREATE TABLE governance.approval_request (
    approval_request_id   uuid        NOT NULL DEFAULT uuidv7(),
    intake_id             uuid        NOT NULL,
    kind                  governance.approval_request_kind   NOT NULL,
    target_entity_type    governance.entity_type,
    target_entity_id      uuid,
    required_roles        jsonb       NOT NULL,
    summary               text        NOT NULL,
    notes                 text,
    opened_at             timestamptz NOT NULL DEFAULT now(),
    opened_by_user_id     uuid        NOT NULL,
    opened_by_role        governance.studio_role,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_approval_request PRIMARY KEY (approval_request_id),
    CONSTRAINT fk_approval_request_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_approval_request_opened_by_user
        FOREIGN KEY (opened_by_user_id)
        REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_approval_request_required_roles_array
        CHECK (jsonb_typeof(required_roles) = 'array'),
    CONSTRAINT ck_approval_request_target_pair
        CHECK ((target_entity_type IS NULL) = (target_entity_id IS NULL))
);
COMMENT ON TABLE governance.approval_request IS 'tier:1 system-of-record. Immutable gating-event attributes; status tracked in approval_request_status_event; target_entity_id polymorphic (no DB FK).';
CREATE INDEX ix_approval_request_intake_id        ON governance.approval_request (intake_id);
CREATE INDEX ix_approval_request_opened_by_user_id ON governance.approval_request (opened_by_user_id);

-- Append-only approval-request status transitions (pattern A). decided_at = the
-- transition's created_at when the status is terminal.
CREATE TABLE governance.approval_request_status_event (
    approval_request_status_event_id  uuid        NOT NULL DEFAULT uuidv7(),
    approval_request_id               uuid        NOT NULL,
    status                            governance.approval_request_status NOT NULL,
    reason                            text,
    changed_by_user_id                uuid        NOT NULL,
    acting_as_role                    governance.studio_role,
    created_at                        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_approval_request_status_event PRIMARY KEY (approval_request_status_event_id),
    CONSTRAINT fk_approval_request_status_event_request
        FOREIGN KEY (approval_request_id)
        REFERENCES governance.approval_request (approval_request_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_approval_request_status_event_changed_by_user
        FOREIGN KEY (changed_by_user_id)
        REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT
);
COMMENT ON TABLE governance.approval_request_status_event IS 'tier:1 append-only. One immutable approval-request status transition per row; current status projected by approval_request_current.';
CREATE INDEX ix_approval_request_status_event_request_id
    ON governance.approval_request_status_event (approval_request_id, created_at DESC);

CREATE VIEW governance.approval_request_current AS
SELECT ar.approval_request_id,
       ar.intake_id,
       ar.kind,
       ar.target_entity_type,
       ar.target_entity_id,
       ar.required_roles,
       ar.summary,
       COALESCE(s.status, 'pending') AS status,
       CASE WHEN s.status IN ('approved','rejected','cancelled') THEN s.created_at END AS decided_at,
       ar.opened_by_user_id,
       ar.opened_at,
       ar.created_at
FROM   governance.approval_request AS ar
LEFT JOIN LATERAL (
    SELECT e.status, e.created_at
    FROM   governance.approval_request_status_event AS e
    WHERE  e.approval_request_id = ar.approval_request_id
    ORDER BY e.created_at DESC, e.approval_request_status_event_id DESC
    LIMIT 1
) AS s ON true;
COMMENT ON VIEW governance.approval_request_current IS 'tier:1 projection. Current approval-request status = latest approval_request_status_event (defaults to pending); decided_at set on terminal status.';

-- ---------------------------------------------------------------------
-- TABLE: approval_signoff  (Tier-1, APPEND-ONLY audit fact) — owner [[B12]].
--   FR-018 / [[E2]]: keyed on approver_user_id (not approver_email); FK to
--   account_user. Insert-only; corrections are new rows ([[ADR-0005]] rule 3).
-- ---------------------------------------------------------------------
CREATE TABLE governance.approval_signoff (
    approval_signoff_id   uuid        NOT NULL DEFAULT uuidv7(),
    approval_request_id   uuid        NOT NULL,
    role                  governance.approval_role     NOT NULL,
    approver_user_id      uuid        NOT NULL,
    decision              governance.approval_decision NOT NULL,
    comment               text,
    evidence_url          text,
    signed_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_approval_signoff PRIMARY KEY (approval_signoff_id),
    CONSTRAINT fk_approval_signoff_request
        FOREIGN KEY (approval_request_id)
        REFERENCES governance.approval_request (approval_request_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_approval_signoff_approver_user
        FOREIGN KEY (approver_user_id)
        REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_approval_signoff_request_role_user
        UNIQUE (approval_request_id, role, approver_user_id)
);
COMMENT ON TABLE governance.approval_signoff IS 'tier:1 append-only audit fact. Immutable per-approver sign-off keyed on approver_user_id (FR-018); corrections are new rows.';
CREATE INDEX ix_approval_signoff_request_id       ON governance.approval_signoff (approval_request_id);
CREATE INDEX ix_approval_signoff_approver_user_id ON governance.approval_signoff (approver_user_id);

-- ---------------------------------------------------------------------
-- TABLE: intake_roi_assessment  (Tier-1) — immutable ROI scenario attributes.
--   FR-018: created_by_user_id. Scenario versioning is append-only (superseded
--   flag); the lock is a state transition tracked in intake_roi_assessment_lock_event.
-- ---------------------------------------------------------------------
CREATE TABLE governance.intake_roi_assessment (
    intake_roi_assessment_id          uuid        NOT NULL DEFAULT uuidv7(),
    intake_id                         uuid        NOT NULL,
    scenario_label                    text        NOT NULL DEFAULT 'expected',
    scenario_notes                    text,
    labor_hours_saved_per_year        numeric(12,2),
    loaded_labor_cost_per_hour_usd    numeric(10,2),
    annual_premium_in_scope_usd       numeric(14,2),
    loss_ratio_improvement_pp         numeric(6,3),
    submission_volume_per_year        integer,
    bind_rate_uplift_pp               numeric(6,3),
    avg_premium_per_bound_usd         numeric(12,2),
    risk_avoidance_yearly_usd         numeric(14,2),
    risk_avoidance_basis              text,
    other_benefit_label               text,
    other_benefit_yearly_usd          numeric(14,2),
    ai_spend_yearly_usd               numeric(14,2),
    ai_spend_basis                    text          NOT NULL DEFAULT 'cost_envelope',
    hitl_oversight_fte                numeric(6,2),
    hitl_loaded_cost_per_fte_usd      numeric(12,2),
    infrastructure_yearly_usd         numeric(12,2),
    build_cost_one_time_usd           numeric(14,2),
    horizon_years                     numeric(4,1)  NOT NULL DEFAULT 3.0,
    discount_rate_pct                 numeric(5,2)  NOT NULL DEFAULT 10.00,
    labor_savings_yearly_usd          numeric(14,2),
    loss_ratio_savings_yearly_usd     numeric(14,2),
    premium_uplift_yearly_usd         numeric(14,2),
    total_benefit_yearly_usd          numeric(14,2),
    total_run_cost_yearly_usd         numeric(14,2),
    net_annual_benefit_usd            numeric(14,2),
    payback_period_months             numeric(6,2),
    npv_horizon_usd                   numeric(14,2),
    roi_pct                           numeric(8,2),
    superseded                        boolean       NOT NULL DEFAULT false,
    approval_request_id               uuid,
    created_by_user_id                uuid          NOT NULL,
    acting_as_role                    governance.studio_role,
    created_at                        timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_roi_assessment PRIMARY KEY (intake_roi_assessment_id),
    CONSTRAINT fk_intake_roi_assessment_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_roi_assessment_approval_request
        FOREIGN KEY (approval_request_id)
        REFERENCES governance.approval_request (approval_request_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_intake_roi_assessment_created_by_user
        FOREIGN KEY (created_by_user_id)
        REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_intake_roi_assessment_horizon_positive CHECK (horizon_years > 0)
);
COMMENT ON TABLE governance.intake_roi_assessment IS 'tier:1 append-only. Immutable ROI scenario per intake; superseded marks history; lock state in intake_roi_assessment_lock_event; active scenario via intake_roi_assessment_current.';
CREATE INDEX ix_intake_roi_assessment_intake_id        ON governance.intake_roi_assessment (intake_id);
CREATE INDEX ix_intake_roi_assessment_created_by_user_id ON governance.intake_roi_assessment (created_by_user_id);
-- At most one active (non-superseded) ROI scenario per intake.
CREATE UNIQUE INDEX uq_intake_roi_assessment_active
    ON governance.intake_roi_assessment (intake_id)
    WHERE superseded = false;

-- Append-only ROI lock transitions (pattern A). FR-018: locked_by_user_id.
CREATE TABLE governance.intake_roi_assessment_lock_event (
    intake_roi_assessment_lock_event_id  uuid        NOT NULL DEFAULT uuidv7(),
    intake_roi_assessment_id             uuid        NOT NULL,
    locked                               boolean     NOT NULL,
    reason                               text,
    locked_by_user_id                    uuid        NOT NULL,
    locked_role                          governance.studio_role,
    created_at                           timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_roi_assessment_lock_event PRIMARY KEY (intake_roi_assessment_lock_event_id),
    CONSTRAINT fk_intake_roi_assessment_lock_event_roi
        FOREIGN KEY (intake_roi_assessment_id)
        REFERENCES governance.intake_roi_assessment (intake_roi_assessment_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_roi_assessment_lock_event_locked_by_user
        FOREIGN KEY (locked_by_user_id)
        REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT
);
COMMENT ON TABLE governance.intake_roi_assessment_lock_event IS 'tier:1 append-only. One immutable ROI lock/unlock transition per row; current lock state projected by intake_roi_assessment_current.';
CREATE INDEX ix_intake_roi_assessment_lock_event_roi_id
    ON governance.intake_roi_assessment_lock_event (intake_roi_assessment_id, created_at DESC);

CREATE VIEW governance.intake_roi_assessment_current AS
SELECT r.intake_roi_assessment_id,
       r.intake_id,
       r.scenario_label,
       r.ai_spend_yearly_usd,
       r.net_annual_benefit_usd,
       r.npv_horizon_usd,
       r.roi_pct,
       r.approval_request_id,
       COALESCE(l.locked, false) AS locked,
       CASE WHEN l.locked THEN l.created_at END         AS locked_at,
       CASE WHEN l.locked THEN l.locked_by_user_id END  AS locked_by_user_id,
       r.created_by_user_id,
       r.created_at
FROM   governance.intake_roi_assessment AS r
LEFT JOIN LATERAL (
    SELECT e.locked, e.locked_by_user_id, e.created_at
    FROM   governance.intake_roi_assessment_lock_event AS e
    WHERE  e.intake_roi_assessment_id = r.intake_roi_assessment_id
    ORDER BY e.created_at DESC, e.intake_roi_assessment_lock_event_id DESC
    LIMIT 1
) AS l ON true
WHERE  r.superseded = false;
COMMENT ON VIEW governance.intake_roi_assessment_current IS 'tier:1 projection. Active ROI scenario per intake with current lock state from intake_roi_assessment_lock_event.';

-- ---------------------------------------------------------------------
-- TABLE: intake_cost_envelope  (Tier-1) — immutable spend-cap attributes, one
--   per intake. FR-018: created_by_user_id. The lock is a state transition in
--   intake_cost_envelope_lock_event (FR-018: locked_by_user_id).
-- ---------------------------------------------------------------------
CREATE TABLE governance.intake_cost_envelope (
    intake_cost_envelope_id     uuid        NOT NULL DEFAULT uuidv7(),
    intake_id                   uuid        NOT NULL,
    total_yearly_estimate_usd   numeric(14,2) NOT NULL,
    upside_pct                  numeric(5,2)  NOT NULL DEFAULT 20.00,
    total_yearly_envelope_usd   numeric(14,2) NOT NULL,
    any_row_override            boolean       NOT NULL DEFAULT false,
    approval_request_id         uuid,
    notes                       text,
    created_by_user_id          uuid          NOT NULL,
    created_at                  timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_cost_envelope PRIMARY KEY (intake_cost_envelope_id),
    CONSTRAINT fk_intake_cost_envelope_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_cost_envelope_approval_request
        FOREIGN KEY (approval_request_id)
        REFERENCES governance.approval_request (approval_request_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_intake_cost_envelope_created_by_user
        FOREIGN KEY (created_by_user_id)
        REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_intake_cost_envelope_intake UNIQUE (intake_id),
    CONSTRAINT ck_intake_cost_envelope_amounts_nonneg
        CHECK (total_yearly_estimate_usd >= 0 AND total_yearly_envelope_usd >= 0)
);
COMMENT ON TABLE governance.intake_cost_envelope IS 'tier:1 system-of-record. Immutable spend cap, one per intake; lock state in intake_cost_envelope_lock_event.';
CREATE INDEX ix_intake_cost_envelope_intake_id        ON governance.intake_cost_envelope (intake_id);
CREATE INDEX ix_intake_cost_envelope_created_by_user_id ON governance.intake_cost_envelope (created_by_user_id);

-- Append-only cost-envelope lock transitions (pattern A). FR-018: locked_by_user_id.
CREATE TABLE governance.intake_cost_envelope_lock_event (
    intake_cost_envelope_lock_event_id  uuid        NOT NULL DEFAULT uuidv7(),
    intake_cost_envelope_id             uuid        NOT NULL,
    locked                              boolean     NOT NULL,
    reason                              text,
    locked_by_user_id                   uuid        NOT NULL,
    locked_role                         governance.studio_role,
    created_at                          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_cost_envelope_lock_event PRIMARY KEY (intake_cost_envelope_lock_event_id),
    CONSTRAINT fk_intake_cost_envelope_lock_event_envelope
        FOREIGN KEY (intake_cost_envelope_id)
        REFERENCES governance.intake_cost_envelope (intake_cost_envelope_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_cost_envelope_lock_event_locked_by_user
        FOREIGN KEY (locked_by_user_id)
        REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT
);
COMMENT ON TABLE governance.intake_cost_envelope_lock_event IS 'tier:1 append-only. One immutable cost-envelope lock/unlock transition per row; current lock state projected by intake_cost_envelope_current.';
CREATE INDEX ix_intake_cost_envelope_lock_event_envelope_id
    ON governance.intake_cost_envelope_lock_event (intake_cost_envelope_id, created_at DESC);

CREATE VIEW governance.intake_cost_envelope_current AS
SELECT c.intake_cost_envelope_id,
       c.intake_id,
       c.total_yearly_estimate_usd,
       c.upside_pct,
       c.total_yearly_envelope_usd,
       c.any_row_override,
       c.approval_request_id,
       COALESCE(l.locked, false) AS locked,
       CASE WHEN l.locked THEN l.created_at END        AS locked_at,
       CASE WHEN l.locked THEN l.locked_by_user_id END AS locked_by_user_id,
       c.created_by_user_id,
       c.created_at
FROM   governance.intake_cost_envelope AS c
LEFT JOIN LATERAL (
    SELECT e.locked, e.locked_by_user_id, e.created_at
    FROM   governance.intake_cost_envelope_lock_event AS e
    WHERE  e.intake_cost_envelope_id = c.intake_cost_envelope_id
    ORDER BY e.created_at DESC, e.intake_cost_envelope_lock_event_id DESC
    LIMIT 1
) AS l ON true;
COMMENT ON VIEW governance.intake_cost_envelope_current IS 'tier:1 projection. Spend cap per intake with current lock state from intake_cost_envelope_lock_event.';

-- =====================================================================
-- V2-NEW: OBLIGATION-SET LINKAGE ([[ADR-0008]], [[FR-IN-014]])
--   Append-only resolution header + immutable obligation rows; current set is
--   a VIEW over the latest active resolution per intake (pattern A).
-- =====================================================================

-- Append-only resolution event. FR-018: resolved_by_user_id.
CREATE TABLE governance.intake_obligation_resolution (
    intake_obligation_resolution_id  uuid        NOT NULL DEFAULT uuidv7(),
    intake_id                        uuid        NOT NULL,
    resolved_ai_risk_tier            governance.ai_risk_tier NOT NULL,
    resolved_naic_materiality        governance.naic_materiality NOT NULL,
    resolution_method                text        NOT NULL DEFAULT 'auto',
    resolver_notes                   text,
    superseded                       boolean     NOT NULL DEFAULT false,
    resolved_by_user_id              uuid        NOT NULL,
    acting_as_role                   governance.studio_role,
    created_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_obligation_resolution PRIMARY KEY (intake_obligation_resolution_id),
    CONSTRAINT fk_intake_obligation_resolution_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_obligation_resolution_resolved_by_user
        FOREIGN KEY (resolved_by_user_id)
        REFERENCES governance.account_user (account_user_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_intake_obligation_resolution_method
        CHECK (resolution_method IN ('auto', 'manual', 'reclassification'))
);
COMMENT ON TABLE governance.intake_obligation_resolution IS 'tier:1 append-only. One obligation-set resolution per (re)classification of an intake; superseded marks history. [[FR-IN-014]] / [[ADR-0008]].';
CREATE INDEX ix_intake_obligation_resolution_intake_id
    ON governance.intake_obligation_resolution (intake_id, created_at DESC);
CREATE INDEX ix_intake_obligation_resolution_resolved_by_user_id
    ON governance.intake_obligation_resolution (resolved_by_user_id);
-- At most one active (non-superseded) resolution per intake.
CREATE UNIQUE INDEX uq_intake_obligation_resolution_active
    ON governance.intake_obligation_resolution (intake_id)
    WHERE superseded = false;

-- Immutable obligation rows. [[C16]]: the three compliance FKs
--   (canonical_requirement, governance_domain, requirement_tier) are OMITTED
--   here — those tables are owned by the compliance section (loads later); the
--   FKs are emitted as deferred ALTERs in the deferred-FK section.
CREATE TABLE governance.intake_obligation (
    intake_obligation_id             uuid        NOT NULL DEFAULT uuidv7(),
    intake_obligation_resolution_id  uuid        NOT NULL,
    intake_id                        uuid        NOT NULL,
    canonical_requirement_id         uuid        NOT NULL,
    governance_domain_id             uuid,
    target_requirement_tier_id       uuid,
    target_tier_level                integer     NOT NULL,
    is_mandatory                     boolean     NOT NULL DEFAULT true,
    rationale                        text,
    created_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_obligation PRIMARY KEY (intake_obligation_id),
    CONSTRAINT fk_intake_obligation_resolution
        FOREIGN KEY (intake_obligation_resolution_id)
        REFERENCES governance.intake_obligation_resolution (intake_obligation_resolution_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_intake_obligation_intake
        FOREIGN KEY (intake_id)
        REFERENCES governance.intake (intake_id)
        ON DELETE CASCADE,
    -- fk_intake_obligation_canonical_requirement, fk_intake_obligation_governance_domain,
    -- fk_intake_obligation_requirement_tier DEFERRED [[C16]]: targets owned by compliance section.
    CONSTRAINT uq_intake_obligation_resolution_requirement
        UNIQUE (intake_obligation_resolution_id, canonical_requirement_id),
    CONSTRAINT ck_intake_obligation_target_tier_positive
        CHECK (target_tier_level >= 1)
);
COMMENT ON TABLE governance.intake_obligation IS 'tier:1 append-only. Resolved obligation: a canonical_requirement + target maturity tier this intake must satisfy (cumulative). [[FR-IN-014]] / [[ADR-0008]].';
CREATE INDEX ix_intake_obligation_resolution_id
    ON governance.intake_obligation (intake_obligation_resolution_id);
CREATE INDEX ix_intake_obligation_intake_id
    ON governance.intake_obligation (intake_id);
CREATE INDEX ix_intake_obligation_canonical_requirement_id
    ON governance.intake_obligation (canonical_requirement_id);

-- Current obligation set per intake: obligations from the active resolution only.
CREATE VIEW governance.intake_obligation_current AS
SELECT o.intake_obligation_id,
       o.intake_id,
       r.intake_obligation_resolution_id,
       o.canonical_requirement_id,
       o.governance_domain_id,
       o.target_requirement_tier_id,
       o.target_tier_level,
       o.is_mandatory,
       o.rationale,
       r.resolved_ai_risk_tier,
       r.resolved_naic_materiality,
       r.created_at AS resolved_at
FROM   governance.intake_obligation AS o
JOIN   governance.intake_obligation_resolution AS r
       ON r.intake_obligation_resolution_id = o.intake_obligation_resolution_id
WHERE  r.superseded = false;
COMMENT ON VIEW governance.intake_obligation_current IS 'tier:1 projection. Live obligation set per intake = obligations under the non-superseded resolution. [[ADR-0005]] §7.';

-- ############ TABLES: compliance ############
-- 04-compliance.sql — hardened v2 schema domain: compliance
-- See ASSEMBLY-AND-VERIFICATION.md for cross-domain FKs & review items.

-- =============================================================================
-- VERITY v2 HARDENED SCHEMA — DOMAIN: COMPLIANCE (ADR-0008)
-- Three-axis, two-bridge control/evidence metamodel.
--   Left   axis : regulatory_framework -> regulatory_provision
--   Center axis : governance_domain, canonical_requirement -> requirement_tier (cumulative)
--   Right  axis : control (type/phase/enforcement_action), evidence_specification
--   Bridge 1    : provision_requirement (min-tier)
--   Bridge 2    : requirement_control (per tier, per phase)
--   Audit facts : evidence (append-only, Tier-2), exception (append-only)
--   Maturity    : domain_maturity (per-domain, append-only score snapshots)
--
-- Conventions: ADR-0005 / naming-conventions.md.
--   snake_case; singular tables; surrogate PK <table>_id uuid DEFAULT uuidv7();
--   named pk_/fk_/uq_/ck_/ix_/brin_ constraints; timestamptz; enums as pg ENUM.
-- uuidv7(): requires PostgreSQL 18+. Fallback for <18: install pg_uuidv7 ext and
--   alias, or DEFAULT gen_random_uuid() (loses time-ordering / BRIN locality).
-- Tier-1 = system-of-record metamodel (thin Postgres, not partitioned).
-- Tier-2 = bulk append-only audit log (evidence): range-partitioned on created_at,
--   BRIN on created_at, never UPDATE/DELETE in place.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS compliance;

-- -----------------------------------------------------------------------------
-- ENUM TYPES  (v1 used inline CHECK(... IN ...); v2 promotes closed sets to enums)
-- -----------------------------------------------------------------------------

-- v2-NEW. Lifecycle phase at which a control fires (ADR-0008 four-phase model).

-- v2-NEW. What category of control this is.

-- v2-NEW. What a control does when it fires against non-compliant activity.

-- v2-NEW. Form of an evidence artifact a control produces.

-- CHANGE of v1 provision_requirement_map.mapping_source CHECK -> enum (members verbatim).

-- KEEP of v1 requirement_coverage.coverage_level CHECK -> enum (members verbatim).
-- Retained for the analytics-mart coverage vocabulary (see open issues).

-- v2-NEW. Append-only exception lifecycle state, projected via exception_current view.

-- =============================================================================
-- LEFT AXIS — regulatory frameworks & provisions  (KEEP from v1)
-- =============================================================================

-- Tier-1. KEEP (v1 compliance.regulatory_framework). Bitemporal validity preserved.
CREATE TABLE compliance.regulatory_framework (
    regulatory_framework_id  uuid        NOT NULL DEFAULT uuidv7(),
    code                     text        NOT NULL,
    name                     text        NOT NULL,
    jurisdiction             text        NOT NULL,
    version                  text,
    effective_date           date,
    valid_from               date        NOT NULL DEFAULT current_date,
    valid_to                 date        NOT NULL DEFAULT DATE '2099-12-31',
    source_url               text,
    description              text,
    sort_seq                 integer     NOT NULL DEFAULT 0,
    created_at               timestamptz NOT NULL DEFAULT now(),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_regulatory_framework PRIMARY KEY (regulatory_framework_id),
    CONSTRAINT uq_regulatory_framework_code UNIQUE (code),
    CONSTRAINT ck_regulatory_framework_valid_range CHECK (valid_from <= valid_to)
);
COMMENT ON TABLE compliance.regulatory_framework IS 'tier:1 system-of-record. Left axis: regulatory frameworks (KEEP from v1).';

-- Tier-1. KEEP (v1 compliance.regulatory_provision). embedding_model_id dropped here
-- (embedding_config lives outside this domain; see open issues / DEFER in mapping).
CREATE TABLE compliance.regulatory_provision (
    regulatory_provision_id  uuid        NOT NULL DEFAULT uuidv7(),
    regulatory_framework_id  uuid        NOT NULL,
    citation                 text        NOT NULL,
    title                    text        NOT NULL,
    provision_text           text,
    effective_date           date,
    valid_from               date        NOT NULL DEFAULT current_date,
    valid_to                 date        NOT NULL DEFAULT DATE '2099-12-31',
    sort_seq                 integer     NOT NULL DEFAULT 0,
    created_at               timestamptz NOT NULL DEFAULT now(),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_regulatory_provision PRIMARY KEY (regulatory_provision_id),
    CONSTRAINT fk_regulatory_provision_framework
        FOREIGN KEY (regulatory_framework_id)
        REFERENCES compliance.regulatory_framework (regulatory_framework_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_regulatory_provision_citation
        UNIQUE (regulatory_framework_id, citation),
    CONSTRAINT ck_regulatory_provision_valid_range CHECK (valid_from <= valid_to)
);
COMMENT ON TABLE compliance.regulatory_provision IS 'tier:1 system-of-record. Left axis: citable provisions within a framework (KEEP from v1; column "text" renamed provision_text to avoid reserved-word use).';
CREATE INDEX ix_regulatory_provision_framework
    ON compliance.regulatory_provision (regulatory_framework_id);

-- =============================================================================
-- CENTER AXIS — governance domains, canonical requirements, cumulative tiers
-- =============================================================================

-- Tier-1. CHANGE (v1 compliance.canonical_requirement_theme -> governance_domain).
-- ADR-0008 organizes canonical requirements by governance DOMAIN and scores maturity
-- per domain; v1's "theme" was pure grouping. Domain is the carry-forward + new role.
CREATE TABLE compliance.governance_domain (
    governance_domain_id  uuid        NOT NULL DEFAULT uuidv7(),
    code                  text        NOT NULL,
    name                  text        NOT NULL,
    description           text,
    sort_seq              integer     NOT NULL DEFAULT 0,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_governance_domain PRIMARY KEY (governance_domain_id),
    CONSTRAINT uq_governance_domain_code UNIQUE (code)
);
COMMENT ON TABLE compliance.governance_domain IS 'tier:1 system-of-record. Center axis grouping + unit of maturity scoring (CHANGE of v1 canonical_requirement_theme).';

-- Tier-1. KEEP (v1 compliance.canonical_requirement). Stable technology-agnostic vocab.
-- theme_id -> governance_domain_id (CHANGE). embedding_model_id DEFERred (see open issues).
CREATE TABLE compliance.canonical_requirement (
    canonical_requirement_id  uuid        NOT NULL DEFAULT uuidv7(),
    governance_domain_id      uuid        NOT NULL,
    code                      text        NOT NULL,
    title                     text        NOT NULL,
    description               text,
    sort_seq                  integer     NOT NULL DEFAULT 0,
    created_at                timestamptz NOT NULL DEFAULT now(),
    updated_at                timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_canonical_requirement PRIMARY KEY (canonical_requirement_id),
    CONSTRAINT fk_canonical_requirement_domain
        FOREIGN KEY (governance_domain_id)
        REFERENCES compliance.governance_domain (governance_domain_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_canonical_requirement_code UNIQUE (code)
);
COMMENT ON TABLE compliance.canonical_requirement IS 'tier:1 system-of-record. Center axis: stable, technology-agnostic requirement vocabulary (KEEP from v1; theme_id -> governance_domain_id).';
CREATE INDEX ix_canonical_requirement_domain
    ON compliance.canonical_requirement (governance_domain_id);

-- Tier-1. v2-NEW. Cumulative tier ladder per canonical requirement. Operating at
-- tier N implies tiers 1..N active. Variable depth: as many tiers as regulation/best
-- practice require. tier_level is the cumulative ordinal (1 = baseline).
CREATE TABLE compliance.requirement_tier (
    requirement_tier_id       uuid        NOT NULL DEFAULT uuidv7(),
    canonical_requirement_id  uuid        NOT NULL,
    tier_level                integer     NOT NULL,
    name                      text        NOT NULL,
    description               text,
    created_at                timestamptz NOT NULL DEFAULT now(),
    updated_at                timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_requirement_tier PRIMARY KEY (requirement_tier_id),
    CONSTRAINT fk_requirement_tier_requirement
        FOREIGN KEY (canonical_requirement_id)
        REFERENCES compliance.canonical_requirement (canonical_requirement_id)
        ON DELETE CASCADE,
    CONSTRAINT uq_requirement_tier_level
        UNIQUE (canonical_requirement_id, tier_level),
    CONSTRAINT ck_requirement_tier_level_positive CHECK (tier_level >= 1)
);
COMMENT ON TABLE compliance.requirement_tier IS 'tier:1 system-of-record. v2-NEW cumulative tier ladder per canonical requirement (tier N implies 1..N).';
CREATE INDEX ix_requirement_tier_requirement
    ON compliance.requirement_tier (canonical_requirement_id);

-- =============================================================================
-- RIGHT AXIS — controls & evidence specifications  (v2-NEW; replaces feature axis)
-- =============================================================================

-- Tier-1. v2-NEW. A control: type, lifecycle phase, enforcement action. Controls
-- block non-compliant activity at the phase where they operate.
CREATE TABLE compliance.control (
    control_id          uuid        NOT NULL DEFAULT uuidv7(),
    code                text        NOT NULL,
    name                text        NOT NULL,
    description         text,
    control_type        compliance.control_type        NOT NULL,
    phase               compliance.control_phase        NOT NULL,
    enforcement_action  compliance.enforcement_action   NOT NULL,
    is_active           boolean     NOT NULL DEFAULT true,
    sort_seq            integer     NOT NULL DEFAULT 0,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_control PRIMARY KEY (control_id),
    CONSTRAINT uq_control_code UNIQUE (code)
);
COMMENT ON TABLE compliance.control IS 'tier:1 system-of-record. v2-NEW right axis: enforcement control (type/phase/enforcement_action). Replaces v1 feature hierarchy.';
CREATE INDEX ix_control_phase ON compliance.control (phase);

-- Tier-1. v2-NEW. Evidence specification: what artifact a control must produce, who
-- produces it, and how it is citable. Each spec belongs to exactly one control.
CREATE TABLE compliance.evidence_specification (
    evidence_specification_id  uuid        NOT NULL DEFAULT uuidv7(),
    control_id                 uuid        NOT NULL,
    code                       text        NOT NULL,
    name                       text        NOT NULL,
    artifact_type              compliance.evidence_artifact_type NOT NULL,
    produced_by                text        NOT NULL,   -- enforcement point that emits it
    citable_as                 text,                   -- how it is referenced in audit
    description                text,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_evidence_specification PRIMARY KEY (evidence_specification_id),
    CONSTRAINT fk_evidence_specification_control
        FOREIGN KEY (control_id)
        REFERENCES compliance.control (control_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_evidence_specification_code UNIQUE (code)
);
COMMENT ON TABLE compliance.evidence_specification IS 'tier:1 system-of-record. v2-NEW: artifact_type/produced_by/citable_as spec for evidence a control produces.';
CREATE INDEX ix_evidence_specification_control
    ON compliance.evidence_specification (control_id);

-- =============================================================================
-- BRIDGE 1 — provision <-> canonical requirement, with MINIMUM TIER  (CHANGE)
-- =============================================================================

-- Tier-1. CHANGE (v1 compliance.provision_requirement_map -> provision_requirement).
-- Adds min_tier_level: the minimum cumulative tier this provision demands of the
-- canonical requirement. match_strength/confidence/mapping_source preserved.
CREATE TABLE compliance.provision_requirement (
    provision_requirement_id  uuid        NOT NULL DEFAULT uuidv7(),
    regulatory_provision_id   uuid        NOT NULL,
    canonical_requirement_id  uuid        NOT NULL,
    min_tier_level            integer     NOT NULL DEFAULT 1,
    match_strength            numeric(3,2) NOT NULL DEFAULT 1.00,
    confidence                numeric(3,2) NOT NULL DEFAULT 1.00,
    mapping_source            compliance.mapping_source NOT NULL DEFAULT 'manual',
    validated_by              text,
    validated_at              timestamptz,
    notes                     text,
    created_at                timestamptz NOT NULL DEFAULT now(),
    updated_at                timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_provision_requirement PRIMARY KEY (provision_requirement_id),
    CONSTRAINT fk_provision_requirement_provision
        FOREIGN KEY (regulatory_provision_id)
        REFERENCES compliance.regulatory_provision (regulatory_provision_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_provision_requirement_requirement
        FOREIGN KEY (canonical_requirement_id)
        REFERENCES compliance.canonical_requirement (canonical_requirement_id)
        ON DELETE CASCADE,
    CONSTRAINT uq_provision_requirement
        UNIQUE (regulatory_provision_id, canonical_requirement_id),
    CONSTRAINT ck_provision_requirement_match_strength
        CHECK (match_strength > 0 AND match_strength <= 1),
    CONSTRAINT ck_provision_requirement_confidence
        CHECK (confidence >= 0 AND confidence <= 1),
    CONSTRAINT ck_provision_requirement_min_tier_positive
        CHECK (min_tier_level >= 1)
);
COMMENT ON TABLE compliance.provision_requirement IS 'tier:1 system-of-record. Bridge 1 (CHANGE of v1 provision_requirement_map): provision<->canonical requirement with min_tier_level. New regs insert by mapping.';
CREATE INDEX ix_provision_requirement_provision
    ON compliance.provision_requirement (regulatory_provision_id);
CREATE INDEX ix_provision_requirement_requirement
    ON compliance.provision_requirement (canonical_requirement_id);

-- =============================================================================
-- BRIDGE 2 — canonical requirement <-> control/evidence, PER TIER, PER PHASE
-- =============================================================================

-- Tier-1. v2-NEW. Wires a specific requirement_tier to a control (and optionally the
-- evidence specification it satisfies) at a given lifecycle phase. phase is denormalized
-- here for query convenience but must equal the control's own phase (enforced in app /
-- see open issues for a composite-FK alternative).
CREATE TABLE compliance.requirement_control (
    requirement_control_id     uuid        NOT NULL DEFAULT uuidv7(),
    requirement_tier_id        uuid        NOT NULL,
    control_id                 uuid        NOT NULL,
    evidence_specification_id  uuid,
    phase                      compliance.control_phase NOT NULL,
    is_required                boolean     NOT NULL DEFAULT true,
    notes                      text,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    updated_at                 timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_requirement_control PRIMARY KEY (requirement_control_id),
    CONSTRAINT fk_requirement_control_tier
        FOREIGN KEY (requirement_tier_id)
        REFERENCES compliance.requirement_tier (requirement_tier_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_requirement_control_control
        FOREIGN KEY (control_id)
        REFERENCES compliance.control (control_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_requirement_control_evidence_spec
        FOREIGN KEY (evidence_specification_id)
        REFERENCES compliance.evidence_specification (evidence_specification_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_requirement_control
        UNIQUE (requirement_tier_id, control_id, phase)
);
COMMENT ON TABLE compliance.requirement_control IS 'tier:1 system-of-record. Bridge 2 (v2-NEW): requirement tier <-> control/evidence spec, per tier per phase. Replaces v1 requirement_feature_link.';
CREATE INDEX ix_requirement_control_tier
    ON compliance.requirement_control (requirement_tier_id);
CREATE INDEX ix_requirement_control_control
    ON compliance.requirement_control (control_id);

-- =============================================================================
-- EVIDENCE — append-only audit fact  (Tier-2, range-partitioned, BRIN)
-- =============================================================================

-- Tier-2. v2-NEW. APPEND-ONLY. One immutable fact per evidence artifact produced by a
-- control, tied to canonical requirement + tier + phase + the entity/run that produced
-- it. Never UPDATE/DELETE in place. Range-partitioned monthly on created_at; BRIN.
-- entity_type/entity_id and run_id are cross-domain references validated in the app
-- layer (no DB FK to governance/runtime from this domain) — see open issues.
CREATE TABLE compliance.evidence (
    evidence_id                uuid        NOT NULL DEFAULT uuidv7(),
    canonical_requirement_id   uuid        NOT NULL,
    requirement_tier_id        uuid        NOT NULL,
    control_id                 uuid        NOT NULL,
    evidence_specification_id  uuid,
    phase                      compliance.control_phase NOT NULL,
    artifact_type              compliance.evidence_artifact_type NOT NULL,
    entity_type                text,        -- e.g. 'agent_version','task_version','package'
    entity_id                  uuid,        -- cross-domain ref (app-validated)
    run_id                     uuid,        -- cross-domain ref to runtime.execution_run
    artifact_uri               text,
    artifact_digest            text,        -- content hash for tamper-evidence
    payload                    jsonb,       -- captured/derived evidence detail
    produced_by                text        NOT NULL,
    produced_at                timestamptz NOT NULL DEFAULT now(),
    created_at                 timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_evidence PRIMARY KEY (evidence_id, created_at),
    CONSTRAINT fk_evidence_requirement
        FOREIGN KEY (canonical_requirement_id)
        REFERENCES compliance.canonical_requirement (canonical_requirement_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_evidence_tier
        FOREIGN KEY (requirement_tier_id)
        REFERENCES compliance.requirement_tier (requirement_tier_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_evidence_control
        FOREIGN KEY (control_id)
        REFERENCES compliance.control (control_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_evidence_specification
        FOREIGN KEY (evidence_specification_id)
        REFERENCES compliance.evidence_specification (evidence_specification_id)
        ON DELETE RESTRICT
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE compliance.evidence IS 'tier:2 bulk-log append-only. v2-NEW immutable audit fact: requirement+tier+phase+entity/run. PK includes created_at for partition pruning. No UPDATE/DELETE.';

-- Initial monthly partition (current month); operational tooling rolls subsequent months.
CREATE TABLE compliance.evidence_2026_05
    PARTITION OF compliance.evidence
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE compliance.evidence_2026_06
    PARTITION OF compliance.evidence
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

CREATE INDEX brin_evidence_created_at
    ON compliance.evidence USING brin (created_at);
CREATE INDEX ix_evidence_requirement
    ON compliance.evidence (canonical_requirement_id, created_at DESC);
CREATE INDEX ix_evidence_entity
    ON compliance.evidence (entity_type, entity_id);
CREATE INDEX ix_evidence_run
    ON compliance.evidence (run_id);

-- =============================================================================
-- EXCEPTION — append-only governance record  (Tier-1 audit; current via view)
-- =============================================================================

-- Tier-1 (audit, append-only). v2-NEW. One immutable row per exception state event.
-- Carries waived tier, affected requirement, named approver, compensating controls,
-- and expiry. Status transitions are appended (new row), never updated in place;
-- exception_current projects the latest state per exception_key. approver_user_id is a
-- cross-domain ref to the auth user (app-validated) — see open issues.
CREATE TABLE compliance.compliance_exception (
    exception_id              uuid        NOT NULL DEFAULT uuidv7(),
    exception_key             uuid        NOT NULL,   -- stable id across status events
    canonical_requirement_id  uuid        NOT NULL,
    requirement_tier_id       uuid        NOT NULL,   -- the specific tier WAIVED
    entity_type               text,
    entity_id                 uuid,
    status                    compliance.exception_status NOT NULL,
    reason                    text        NOT NULL,
    compensating_controls     text        NOT NULL,
    approver_user_id          uuid,                   -- cross-domain auth ref (app-validated)
    approver_name             text,
    approver_role             text,
    requested_by              text        NOT NULL,
    expires_at                timestamptz,            -- maximum permitted duration
    created_at                timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_exception PRIMARY KEY (exception_id),
    CONSTRAINT fk_exception_requirement
        FOREIGN KEY (canonical_requirement_id)
        REFERENCES compliance.canonical_requirement (canonical_requirement_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_exception_tier
        FOREIGN KEY (requirement_tier_id)
        REFERENCES compliance.requirement_tier (requirement_tier_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_exception_approved_has_approver
        CHECK (status <> 'approved' OR approver_user_id IS NOT NULL OR approver_name IS NOT NULL),
    CONSTRAINT ck_exception_approved_has_expiry
        CHECK (status <> 'approved' OR expires_at IS NOT NULL)
);
COMMENT ON TABLE compliance.compliance_exception IS 'tier:1 append-only audit. v2-NEW first-class exception: waived tier, requirement, approver, compensating controls, expiry. Status events appended; current state via exception_current.';
CREATE INDEX ix_exception_key
    ON compliance.compliance_exception (exception_key, created_at DESC);
CREATE INDEX ix_exception_requirement
    ON compliance.compliance_exception (canonical_requirement_id);
CREATE INDEX ix_exception_expires
    ON compliance.compliance_exception (expires_at) WHERE expires_at IS NOT NULL;

-- Current-state projection: latest event per exception_key (ADR-0005 rule 3).
CREATE VIEW compliance.compliance_exception_current AS
SELECT DISTINCT ON (e.exception_key)
       e.exception_key,
       e.exception_id              AS latest_event_id,
       e.canonical_requirement_id,
       e.requirement_tier_id,
       e.entity_type,
       e.entity_id,
       e.status,
       e.reason,
       e.compensating_controls,
       e.approver_user_id,
       e.approver_name,
       e.approver_role,
       e.expires_at,
       e.created_at               AS status_at
FROM   compliance.compliance_exception AS e
ORDER  BY e.exception_key, e.created_at DESC;
COMMENT ON VIEW compliance.compliance_exception_current IS 'Current state per exception_key over append-only compliance.compliance_exception.';

-- =============================================================================
-- PER-DOMAIN MATURITY  (append-only score snapshots)
-- =============================================================================

-- Tier-1 (append-only). v2-NEW. Normalized maturity score per governance domain at a
-- point in time. Scores recomputed/appended; latest per domain via domain_maturity_current.
-- The normalization algorithm itself is deferred to the compliance component spec.
CREATE TABLE compliance.domain_maturity (
    domain_maturity_id    uuid        NOT NULL DEFAULT uuidv7(),
    governance_domain_id  uuid        NOT NULL,
    score                 numeric(5,4) NOT NULL,   -- normalized 0..1
    requirement_count     integer     NOT NULL DEFAULT 0,
    method                text        NOT NULL DEFAULT 'normalized_v1',
    detail                jsonb,
    computed_at           timestamptz NOT NULL DEFAULT now(),
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_domain_maturity PRIMARY KEY (domain_maturity_id),
    CONSTRAINT fk_domain_maturity_domain
        FOREIGN KEY (governance_domain_id)
        REFERENCES compliance.governance_domain (governance_domain_id)
        ON DELETE CASCADE,
    CONSTRAINT ck_domain_maturity_score_range CHECK (score >= 0 AND score <= 1)
);
COMMENT ON TABLE compliance.domain_maturity IS 'tier:1 append-only. v2-NEW per-domain normalized maturity score snapshots; latest via domain_maturity_current.';
CREATE INDEX ix_domain_maturity_domain
    ON compliance.domain_maturity (governance_domain_id, computed_at DESC);

CREATE VIEW compliance.domain_maturity_current AS
SELECT DISTINCT ON (m.governance_domain_id)
       m.governance_domain_id,
       m.domain_maturity_id,
       m.score,
       m.requirement_count,
       m.method,
       m.detail,
       m.computed_at
FROM   compliance.domain_maturity AS m
ORDER  BY m.governance_domain_id, m.computed_at DESC;
COMMENT ON VIEW compliance.domain_maturity_current IS 'Latest maturity score per governance domain over append-only compliance.domain_maturity.';

-- ############ TABLES: reporting ############
-- =====================================================================
-- SECTION: REPORTING & ANALYTICS (analytics + compliance schemas)
-- Source fragment: 09-reporting.sql. Reconciliation patches applied:
--   C5  embedding_config schema RESOLVED to compliance.embedding_config
--       (see decision note below).
--   C7  removed tautological ck_report_definition_template_requires_docx
--       (see decision note below).
-- Load order: this section is step 15, AFTER compliance (step 14). Therefore
--   FKs to compliance.canonical_requirement are intra-load-order safe and kept
--   INLINE (canonical_requirement already exists). No deferred-FK is needed for
--   this section's own objects. The reverse cross-domain FK
--   intake.intake_requirement.embedding_model_id -> compliance.embedding_config
--   (reconciliation #C20/#20) is emitted by the DEFERRED-FK section, because
--   intake (step 13) loads before this section.
-- =====================================================================

-- C5 DECISION — embedding_config owning schema = compliance.embedding_config.
--   The intake fragment FK'd governance.embedding_config; the reporting fragment
--   defines compliance.embedding_config. Per ASSEMBLY #C5/#C20 the resolution is
--   to make the deferred intake_requirement FK reference compliance.embedding_config,
--   i.e. compliance is the single owning schema. This section keeps the table in
--   compliance and the (intra-section) mart_field FK references it here; the
--   intake-side FK is rewritten to compliance.embedding_config in the deferred section.

CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS compliance;

-- ---------------------------------------------------------------------
-- ENUM TYPES (v2: promote v1 CHECK-on-text pseudo-enums to real enums;
--             members preserved verbatim from v1 contracts).
-- ---------------------------------------------------------------------

COMMENT ON TYPE analytics.mart_field_semantic_type IS
    'Semantic class of a report-reachable column. Verbatim from v1 mart_field.semantic_type CHECK.';

COMMENT ON TYPE analytics.evidence_field_role IS
    'Role a mart_field plays for a requirement/report. Verbatim from v1 requirement_evidence_field.role.';

COMMENT ON TYPE analytics.evidence_field_aggregation IS
    'Aggregation applied to a measure field. Verbatim from v1 aggregation CHECK. NULL means no aggregation.';

COMMENT ON TYPE compliance.report_kind IS
    'How a report is rendered. Verbatim from v1 report_definition.report_kind CHECK.';

COMMENT ON TYPE compliance.report_run_status IS
    'Outcome of a report generation job. Verbatim from v1 report_run_log.status CHECK.';

COMMENT ON TYPE compliance.embedding_runtime IS
    'Embedding inference runtime. Members appended via ALTER TYPE as runtimes are adopted (additive only).';

-- ---------------------------------------------------------------------
-- TABLE: compliance.embedding_config  (Tier-1, append-only history)  [C5 owner]
-- Embedding-model identity registry. v1 used a mutable is_current boolean with a
-- partial unique index. v2 generalizes to append-only: each row is an immutable
-- registration; "the current embedding config" is the latest row by created_at,
-- projected through embedding_config_current (ADR-0005 rule 3).
-- ---------------------------------------------------------------------
CREATE TABLE compliance.embedding_config (
    embedding_config_id  uuid        NOT NULL DEFAULT uuidv7(),
    model_name           text        NOT NULL,
    model_version        text        NOT NULL,
    dim                  integer     NOT NULL,
    runtime              compliance.embedding_runtime NOT NULL DEFAULT 'fastembed',
    created_at           timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_embedding_config PRIMARY KEY (embedding_config_id),
    CONSTRAINT uq_embedding_config_model_name_version UNIQUE (model_name, model_version),
    CONSTRAINT ck_embedding_config_dim_positive CHECK (dim > 0)
);
COMMENT ON TABLE compliance.embedding_config IS
    'tier:1 append-only. Embedding-model identity registry. Latest row by created_at is current (see embedding_config_current). C5: single owning schema = compliance (intake_requirement FK retargets here via deferred ALTER).';
COMMENT ON COLUMN compliance.embedding_config.dim IS 'Embedding vector dimensionality (e.g. 384).';

CREATE INDEX ix_embedding_config_created_at
    ON compliance.embedding_config (created_at DESC);

CREATE VIEW compliance.embedding_config_current AS
SELECT ec.embedding_config_id,
       ec.model_name,
       ec.model_version,
       ec.dim,
       ec.runtime,
       ec.created_at
FROM   compliance.embedding_config AS ec
ORDER  BY ec.created_at DESC
LIMIT  1;
COMMENT ON VIEW compliance.embedding_config_current IS
    'Current embedding config = latest compliance.embedding_config row by created_at. Generalizes v1 is_current=true partial-unique.';

-- ---------------------------------------------------------------------
-- TABLE: analytics.mart_field  (Tier-1)
-- L2 analytics manifest: registry of every report-reachable column
-- (table/view + column) exposed by the logical mart. embedding/embedding_model_id
-- retained for semantic search of the manifest (vector index deferred).
-- ---------------------------------------------------------------------
CREATE TABLE analytics.mart_field (
    mart_field_id        uuid        NOT NULL DEFAULT uuidv7(),
    table_name           text        NOT NULL,
    column_name          text        NOT NULL,
    semantic_type        analytics.mart_field_semantic_type NOT NULL,
    description          text,
    is_pii               boolean     NOT NULL DEFAULT false,
    embedding            vector(384),
    embedding_model_id   uuid,
    sort_seq             integer     NOT NULL DEFAULT 0,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_mart_field PRIMARY KEY (mart_field_id),
    CONSTRAINT uq_mart_field_table_column UNIQUE (table_name, column_name),
    CONSTRAINT fk_mart_field_embedding_config
        FOREIGN KEY (embedding_model_id)
        REFERENCES compliance.embedding_config (embedding_config_id)
        ON DELETE SET NULL
);
COMMENT ON TABLE analytics.mart_field IS
    'tier:1. Manifest of every report-reachable mart column (logical-mart table/view + column). Reports and requirement evidence bind to rows here. ADR-0004/0007 logical-mart seam.';
COMMENT ON COLUMN analytics.mart_field.table_name IS 'Logical-mart view or table name exposing the column (e.g. v_entity_version).';
COMMENT ON COLUMN analytics.mart_field.is_pii IS 'True if the column carries PII; gates export/redaction.';

CREATE INDEX ix_mart_field_table_name ON analytics.mart_field (table_name);
CREATE INDEX ix_mart_field_embedding_model_id ON analytics.mart_field (embedding_model_id);

-- ---------------------------------------------------------------------
-- TABLE: analytics.feed_view  (Tier-1)
-- Allowlist of logical-mart views exposed via the Rung-1 feed endpoint
-- (/api/v1/feed/{view_name}). ADR-0007: only allowlisted view names are servable.
-- ---------------------------------------------------------------------
CREATE TABLE analytics.feed_view (
    feed_view_id   uuid        NOT NULL DEFAULT uuidv7(),
    view_name      text        NOT NULL,
    description    text,
    is_active      boolean     NOT NULL DEFAULT true,
    sort_seq       integer     NOT NULL DEFAULT 0,
    created_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_feed_view PRIMARY KEY (feed_view_id),
    CONSTRAINT uq_feed_view_view_name UNIQUE (view_name)
);
COMMENT ON TABLE analytics.feed_view IS
    'tier:1. Allowlist of logical-mart views exposed via the Rung-1 feed endpoint. ADR-0007 logical-mart read seam.';

-- ---------------------------------------------------------------------
-- TABLE: compliance.requirement_evidence_field  (Tier-1)
-- L4 semantic layer: binds a canonical requirement to the mart_field columns
-- that supply its reporting evidence, with role + aggregation. FK to
-- compliance.canonical_requirement is INLINE (compliance loads at step 14,
-- before this section at step 15 — target already exists).
-- ---------------------------------------------------------------------
CREATE TABLE compliance.requirement_evidence_field (
    requirement_evidence_field_id  uuid    NOT NULL DEFAULT uuidv7(),
    canonical_requirement_id       uuid    NOT NULL,
    mart_field_id                  uuid    NOT NULL,
    role                           analytics.evidence_field_role NOT NULL DEFAULT 'dimension',
    aggregation                    analytics.evidence_field_aggregation,
    sort_seq                       integer NOT NULL DEFAULT 0,
    notes                          text,
    created_at                     timestamptz NOT NULL DEFAULT now(),
    updated_at                     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_requirement_evidence_field PRIMARY KEY (requirement_evidence_field_id),
    CONSTRAINT uq_requirement_evidence_field_req_field
        UNIQUE (canonical_requirement_id, mart_field_id),
    CONSTRAINT fk_requirement_evidence_field_canonical_requirement
        FOREIGN KEY (canonical_requirement_id)
        REFERENCES compliance.canonical_requirement (canonical_requirement_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_requirement_evidence_field_mart_field
        FOREIGN KEY (mart_field_id)
        REFERENCES analytics.mart_field (mart_field_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_requirement_evidence_field_agg_for_measure
        CHECK (aggregation IS NULL OR role = 'measure')
);
COMMENT ON TABLE compliance.requirement_evidence_field IS
    'tier:1. Manifest binding a canonical requirement to the analytics mart_field columns that evidence it (role + aggregation). canonical_requirement owned by COMPLIANCE (ADR-0008), loaded earlier — FK inline.';
COMMENT ON CONSTRAINT ck_requirement_evidence_field_agg_for_measure ON compliance.requirement_evidence_field IS
    'Aggregation only meaningful on a measure-role field.';

CREATE INDEX ix_requirement_evidence_field_canonical_requirement_id
    ON compliance.requirement_evidence_field (canonical_requirement_id);
CREATE INDEX ix_requirement_evidence_field_mart_field_id
    ON compliance.requirement_evidence_field (mart_field_id);

-- ---------------------------------------------------------------------
-- TABLE: compliance.report_definition  (Tier-1)
-- L5 reports-as-data: one row per report definition.
-- C7: the tautological ck_report_definition_template_requires_docx
--     (... OR EXISTS (SELECT 1), always true; a CHECK cannot reference another
--     table) is REMOVED. The "template_driven needs a renderer" invariant is
--     enforced by the 1:1 compliance.report_sql_template (uq_report_sql_template_report)
--     and/or in the application layer, not by an unenforceable row CHECK.
-- ---------------------------------------------------------------------
CREATE TABLE compliance.report_definition (
    report_definition_id  uuid        NOT NULL DEFAULT uuidv7(),
    code                  text        NOT NULL,
    name                  text        NOT NULL,
    description           text,
    report_kind           compliance.report_kind NOT NULL DEFAULT 'metadata_driven',
    docx_template         text,
    output_formats        text[]      NOT NULL DEFAULT ARRAY['html','docx','pdf'],
    scope_params          jsonb       NOT NULL DEFAULT '{}'::jsonb,
    sort_seq              integer     NOT NULL DEFAULT 0,
    is_active             boolean     NOT NULL DEFAULT true,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_report_definition PRIMARY KEY (report_definition_id),
    CONSTRAINT uq_report_definition_code UNIQUE (code),
    CONSTRAINT ck_report_definition_output_formats_nonempty
        CHECK (array_length(output_formats, 1) >= 1)
    -- C7: ck_report_definition_template_requires_docx removed (tautological /
    --     cannot cross-reference report_sql_template). Presence of a renderer for
    --     a template_driven report is enforced by report_sql_template (1:1) + app.
);
COMMENT ON TABLE compliance.report_definition IS
    'tier:1. Report definitions (reports-as-data). metadata_driven reports resolve fields via requirement_evidence_field + overrides; template_driven reports carry a report_sql_template (1:1). C7: template-renderer presence enforced via report_sql_template/app, not a row CHECK.';
COMMENT ON COLUMN compliance.report_definition.scope_params IS 'Declarative scope/parameter defaults; open shape -> jsonb is correct here.';

CREATE INDEX ix_report_definition_is_active ON compliance.report_definition (is_active);

-- ---------------------------------------------------------------------
-- TABLE: compliance.report_requirement  (Tier-1)
-- L5 bridge (M:N): a report covers canonical requirements, ordered, sectioned.
-- FK to compliance.canonical_requirement INLINE (compliance loaded earlier).
-- ---------------------------------------------------------------------
CREATE TABLE compliance.report_requirement (
    report_requirement_id     uuid        NOT NULL DEFAULT uuidv7(),
    report_definition_id      uuid        NOT NULL,
    canonical_requirement_id  uuid        NOT NULL,
    section                   text,
    sort_seq                  integer     NOT NULL DEFAULT 0,
    notes                     text,
    created_at                timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_report_requirement PRIMARY KEY (report_requirement_id),
    CONSTRAINT uq_report_requirement_report_req
        UNIQUE (report_definition_id, canonical_requirement_id),
    CONSTRAINT fk_report_requirement_report_definition
        FOREIGN KEY (report_definition_id)
        REFERENCES compliance.report_definition (report_definition_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_report_requirement_canonical_requirement
        FOREIGN KEY (canonical_requirement_id)
        REFERENCES compliance.canonical_requirement (canonical_requirement_id)
        ON DELETE RESTRICT
);
COMMENT ON TABLE compliance.report_requirement IS
    'tier:1. M:N bridge: which canonical requirements a report covers (ordered, sectioned). canonical_requirement owned by COMPLIANCE (ADR-0008), loaded earlier — FK inline.';

CREATE INDEX ix_report_requirement_report_definition_id
    ON compliance.report_requirement (report_definition_id);
CREATE INDEX ix_report_requirement_canonical_requirement_id
    ON compliance.report_requirement (canonical_requirement_id);

-- ---------------------------------------------------------------------
-- TABLE: compliance.report_field_override  (Tier-1)
-- L5: per-report override of a mart_field's role/aggregation/sort.
-- ---------------------------------------------------------------------
CREATE TABLE compliance.report_field_override (
    report_field_override_id  uuid        NOT NULL DEFAULT uuidv7(),
    report_definition_id      uuid        NOT NULL,
    mart_field_id             uuid        NOT NULL,
    role_override             analytics.evidence_field_role,
    aggregation_override      analytics.evidence_field_aggregation,
    sort_seq_override         integer,
    notes                     text,
    created_at                timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_report_field_override PRIMARY KEY (report_field_override_id),
    CONSTRAINT uq_report_field_override_report_field
        UNIQUE (report_definition_id, mart_field_id),
    CONSTRAINT fk_report_field_override_report_definition
        FOREIGN KEY (report_definition_id)
        REFERENCES compliance.report_definition (report_definition_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_report_field_override_mart_field
        FOREIGN KEY (mart_field_id)
        REFERENCES analytics.mart_field (mart_field_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_report_field_override_at_least_one
        CHECK (role_override IS NOT NULL
               OR aggregation_override IS NOT NULL
               OR sort_seq_override IS NOT NULL)
);
COMMENT ON TABLE compliance.report_field_override IS
    'tier:1. Per-report override of a mart_field role/aggregation/sort, layered over requirement_evidence_field defaults.';
COMMENT ON CONSTRAINT ck_report_field_override_at_least_one ON compliance.report_field_override IS
    'An override row must override at least one attribute (real invariant, not in v1).';

CREATE INDEX ix_report_field_override_report_definition_id
    ON compliance.report_field_override (report_definition_id);
CREATE INDEX ix_report_field_override_mart_field_id
    ON compliance.report_field_override (mart_field_id);

-- ---------------------------------------------------------------------
-- TABLE: compliance.report_sql_template  (Tier-1)
-- L5 BYO-SQL escape hatch; one row per template_driven report (1:1). The 1:1
-- uniqueness (uq_report_sql_template_report) is the structural half of the C7
-- template-renderer invariant.
-- ---------------------------------------------------------------------
CREATE TABLE compliance.report_sql_template (
    report_sql_template_id  uuid        NOT NULL DEFAULT uuidv7(),
    report_definition_id    uuid        NOT NULL,
    sql_text                text        NOT NULL,
    parameter_schema        jsonb       NOT NULL DEFAULT '{}'::jsonb,
    notes                   text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_report_sql_template PRIMARY KEY (report_sql_template_id),
    CONSTRAINT uq_report_sql_template_report UNIQUE (report_definition_id),
    CONSTRAINT fk_report_sql_template_report_definition
        FOREIGN KEY (report_definition_id)
        REFERENCES compliance.report_definition (report_definition_id)
        ON DELETE CASCADE
);
COMMENT ON TABLE compliance.report_sql_template IS
    'tier:1. BYO-SQL template, 1:1 with a template_driven report_definition. Referenced mart fields normalized into report_sql_template_field (was v1 uuid[] array). 1:1 uq enforces the template-renderer half of the (former) C7 CHECK.';

-- Bridge replacing v1 report_sql_template.referenced_mart_fields uuid[].
CREATE TABLE compliance.report_sql_template_field (
    report_sql_template_field_id  uuid    NOT NULL DEFAULT uuidv7(),
    report_sql_template_id        uuid    NOT NULL,
    mart_field_id                 uuid    NOT NULL,
    created_at                    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_report_sql_template_field PRIMARY KEY (report_sql_template_field_id),
    CONSTRAINT uq_report_sql_template_field_template_field
        UNIQUE (report_sql_template_id, mart_field_id),
    CONSTRAINT fk_report_sql_template_field_template
        FOREIGN KEY (report_sql_template_id)
        REFERENCES compliance.report_sql_template (report_sql_template_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_report_sql_template_field_mart_field
        FOREIGN KEY (mart_field_id)
        REFERENCES analytics.mart_field (mart_field_id)
        ON DELETE RESTRICT
);
COMMENT ON TABLE compliance.report_sql_template_field IS
    'tier:1. Normalized bridge: mart_fields referenced by a BYO-SQL template. Replaces v1 report_sql_template.referenced_mart_fields uuid[] (real FK relation, ADR-0005 rule 2).';

CREATE INDEX ix_report_sql_template_field_template_id
    ON compliance.report_sql_template_field (report_sql_template_id);
CREATE INDEX ix_report_sql_template_field_mart_field_id
    ON compliance.report_sql_template_field (mart_field_id);

-- ---------------------------------------------------------------------
-- TABLE: compliance.report_run_log  (Tier-2, append-only, partitioned)
-- L5 audit trail of generated report runs. v2 makes the log append-only
-- (ADR-0005 rule 3 / ADR-0004) and Tier-2: range-partitioned monthly on
-- created_at, BRIN on created_at. Run lifecycle = appended rows keyed by
-- run_uuid, projected via report_run_current. Tier-2 log = not an FK target (N1).
-- ---------------------------------------------------------------------
CREATE TABLE compliance.report_run_log (
    report_run_log_id     uuid        NOT NULL DEFAULT uuidv7(),
    run_uuid              uuid        NOT NULL,  -- correlates the append events of one run
    report_definition_id  uuid        NOT NULL,
    requested_by          text,
    scope_params          jsonb       NOT NULL DEFAULT '{}'::jsonb,
    output_formats        text[]      NOT NULL DEFAULT '{}'::text[],
    status                compliance.report_run_status NOT NULL DEFAULT 'pending',
    error_message         text,
    artifact_uris         jsonb       NOT NULL DEFAULT '{}'::jsonb,
    duration_ms           integer,
    created_at            timestamptz NOT NULL DEFAULT now(),
    completed_at          timestamptz,
    CONSTRAINT pk_report_run_log PRIMARY KEY (report_run_log_id, created_at),
    CONSTRAINT fk_report_run_log_report_definition
        FOREIGN KEY (report_definition_id)
        REFERENCES compliance.report_definition (report_definition_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_report_run_log_failed_has_error
        CHECK (status <> 'failed' OR error_message IS NOT NULL),
    CONSTRAINT ck_report_run_log_completed_after_created
        CHECK (completed_at IS NULL OR completed_at >= created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE compliance.report_run_log IS
    'tier:2 append-only. Audit trail of report-generation jobs. Append one row per run-state event keyed by run_uuid; latest per run_uuid via report_run_current. Range-partitioned monthly on created_at (ADR-0004/0007).';
COMMENT ON COLUMN compliance.report_run_log.run_uuid IS 'Stable id of a logical report run; multiple appended rows share it as state advances.';

-- Monthly partitions: seed month + current month (today 2026-05). Subsequent
-- partitions are minted by the partition-maintenance job.
CREATE TABLE compliance.report_run_log_2026_05
    PARTITION OF compliance.report_run_log
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE compliance.report_run_log_2026_06
    PARTITION OF compliance.report_run_log
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

CREATE INDEX brin_report_run_log_created_at
    ON compliance.report_run_log USING brin (created_at);
CREATE INDEX ix_report_run_log_report_definition_id
    ON compliance.report_run_log (report_definition_id, created_at DESC);
CREATE INDEX ix_report_run_log_run_uuid
    ON compliance.report_run_log (run_uuid, created_at DESC);

CREATE VIEW compliance.report_run_current AS
SELECT DISTINCT ON (l.run_uuid)
       l.run_uuid,
       l.report_run_log_id,
       l.report_definition_id,
       l.requested_by,
       l.scope_params,
       l.output_formats,
       l.status,
       l.error_message,
       l.artifact_uris,
       l.duration_ms,
       l.created_at,
       l.completed_at
FROM   compliance.report_run_log AS l
ORDER  BY l.run_uuid, l.created_at DESC;
COMMENT ON VIEW compliance.report_run_current IS
    'Current state of each report run = latest report_run_log row per run_uuid. Append-only projection (ADR-0005 rule 3).';

-- ---------------------------------------------------------------------
-- ANALYTICS VIEWS (logical-mart): the v1 analytics.v_* mart/compliance views
-- (v_entity_version, v_decision, v_intake, v_intake_approval, v_validation_result,
-- etc.) are DEFER'd to the owning runtime/analytics-mart domains (mapping rows
-- DEFER; ASSEMBLY C10) and are NOT redefined here. analytics.v_validation_result
-- in particular has no source until the GT/validation subsystem disposition (C9)
-- is closed. The only current-state views this section owns are
-- compliance.embedding_config_current and compliance.report_run_current (above).
-- ---------------------------------------------------------------------

-- ############ TABLES: packages_deploy ############
-- ============================================================================
-- SECTION: PACKAGES & GOVERNED DEPLOYMENT  (v2-new; ADR-0006)
-- Schema: governance | Single owner of harness_image, package,
--   package_harness_image, deployment_environment, deployment_cluster,
--   deployment (+ deployment_current). Tables/views only.
-- Enums (package_kind, environment_kind, deployment_operation,
--   deployment_run_mode, deployment_outcome) are emitted in this section's
--   ENUM block (assembly step 6) and are NOT redefined here.
-- governance.lifecycle_state is owned by the entities section (reconciliation A1);
--   not declared here.
-- All tables Tier-1 (system-of-record). Insert-only / append-only as noted.
-- Cross-section FKs deferred (targets owned by other sections that have loaded
--   or load earlier, but emitted centrally per reconciliation #19):
--   harness_image.created_by_user_id, package.created_by_user_id,
--   package_harness_image.created_by_user_id, deployment.actor_user_id
--   -> governance.account_user (auth section). Left to the deferred-FK section.
-- The package source ref (source_kind + source_version_id) is polymorphic over
--   governance.agent_version / governance.task_version (entities section);
--   enforced in app/registry layer, no DB FK (intentional).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- TABLE: harness_image  (Tier-1, INSERT-ONLY registry)
--   An immutable, digest-identified Verity harness image. ADR-0006 §2.
-- ----------------------------------------------------------------------------
CREATE TABLE governance.harness_image (
    harness_image_id   uuid        NOT NULL DEFAULT uuidv7(),
    registry_ref       text        NOT NULL,                 -- e.g. ghcr.io/verity/harness
    image_tag          text,                                 -- mutable tag, informational only
    image_digest       text        NOT NULL,                 -- immutable content digest (sha256:...)
    harness_version    text        NOT NULL,                 -- semver/build of the harness build
    notes              text,
    created_at         timestamptz NOT NULL DEFAULT now(),
    created_by_user_id uuid,                                 -- E4 rename; FK deferred -> governance.account_user (auth)
    CONSTRAINT pk_harness_image PRIMARY KEY (harness_image_id),
    CONSTRAINT uq_harness_image_digest UNIQUE (image_digest),
    CONSTRAINT ck_harness_image_digest_format
        CHECK (image_digest ~ '^sha256:[0-9a-f]{64}$')
    -- fk_harness_image_created_by_user deferred (reconciliation #19, auth section).
);
COMMENT ON TABLE governance.harness_image IS
    'tier:1 insert-only. Digest-identified Verity harness image registry. ADR-0006 §2. '
    'Rows are immutable facts; never updated/deleted.';
COMMENT ON COLUMN governance.harness_image.image_digest IS
    'Immutable content digest (sha256:<64hex>); the true identity. Tags are advisory (ADR-0006 §2).';

CREATE INDEX ix_harness_image_registry_ref
    ON governance.harness_image (registry_ref);
CREATE INDEX ix_harness_image_created_by_user_id
    ON governance.harness_image (created_by_user_id);

-- ----------------------------------------------------------------------------
-- TABLE: package  (Tier-1, INSERT-ONLY inventory)
--   A built, deployable .vtx/.vax package pinned to a source entity version.
--   ADR-0006 §Context (package is the unit of deployment).
-- ----------------------------------------------------------------------------
CREATE TABLE governance.package (
    package_id          uuid        NOT NULL DEFAULT uuidv7(),
    package_kind        governance.package_kind NOT NULL,    -- vtx | vax
    -- governed source this package was built from. Polymorphic over
    -- agent_version / task_version (entities section); resolved by source_kind.
    source_kind         text        NOT NULL,                -- 'agent_version' | 'task_version'
    source_version_id   uuid        NOT NULL,                -- polymorphic ref (no DB FK; app-enforced)
    package_name        text        NOT NULL,
    package_semver      text        NOT NULL,                -- built package version (semver)
    package_digest      text        NOT NULL,                -- immutable content digest of the artifact
    artifact_uri        text,                                -- where the .vtx/.vax bytes live (registry)
    built_at            timestamptz,                         -- when the artifact was produced
    created_at          timestamptz NOT NULL DEFAULT now(),
    created_by_user_id  uuid,                                -- E4 rename; FK deferred -> governance.account_user (auth)
    CONSTRAINT pk_package PRIMARY KEY (package_id),
    CONSTRAINT uq_package_digest UNIQUE (package_digest),
    CONSTRAINT uq_package_name_semver UNIQUE (package_name, package_semver),
    CONSTRAINT ck_package_source_kind_known
        CHECK (source_kind IN ('agent_version', 'task_version')),
    -- a .vax must come from an agent_version, a .vtx from a task_version (ADR-0006).
    CONSTRAINT ck_package_kind_matches_source
        CHECK (
            (package_kind = 'vax' AND source_kind = 'agent_version')
            OR (package_kind = 'vtx' AND source_kind = 'task_version')
        ),
    CONSTRAINT ck_package_digest_format
        CHECK (package_digest ~ '^sha256:[0-9a-f]{64}$')
    -- fk_package_created_by_user deferred (reconciliation #19, auth section).
);
COMMENT ON TABLE governance.package IS
    'tier:1 insert-only. Built .vtx/.vax package inventory pinned to a source entity '
    'version, identified by immutable digest. ADR-0006. Rows immutable; rebuild = new row.';
COMMENT ON COLUMN governance.package.source_version_id IS
    'Polymorphic ref to governance.agent_version / governance.task_version per source_kind '
    '(entities section). App/registry-enforced; no DB FK (polymorphic target).';

CREATE INDEX ix_package_source_version_id
    ON governance.package (source_kind, source_version_id);
CREATE INDEX ix_package_created_by_user_id
    ON governance.package (created_by_user_id);

-- ----------------------------------------------------------------------------
-- TABLE: package_harness_image  (Tier-1, INSERT-ONLY compatibility bridge)
--   Declares the digest-pinned set of harness images a package may run on.
--   ADR-0006 §2: compatibility tracked by digest; deploy refuses incompatible combos.
-- ----------------------------------------------------------------------------
CREATE TABLE governance.package_harness_image (
    package_harness_image_id  uuid        NOT NULL DEFAULT uuidv7(),
    package_id                uuid        NOT NULL,
    harness_image_id          uuid        NOT NULL,
    declared_in_manifest      boolean     NOT NULL DEFAULT true,  -- from the package manifest
    created_at                timestamptz NOT NULL DEFAULT now(),
    created_by_user_id        uuid,                               -- E4 rename; FK deferred -> governance.account_user (auth)
    CONSTRAINT pk_package_harness_image PRIMARY KEY (package_harness_image_id),
    CONSTRAINT uq_package_harness_image UNIQUE (package_id, harness_image_id),
    CONSTRAINT fk_package_harness_image_package
        FOREIGN KEY (package_id)
        REFERENCES governance.package (package_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_package_harness_image_image
        FOREIGN KEY (harness_image_id)
        REFERENCES governance.harness_image (harness_image_id)
        ON DELETE RESTRICT
    -- fk_package_harness_image_created_by_user deferred (reconciliation #19, auth section).
);
COMMENT ON TABLE governance.package_harness_image IS
    'tier:1 insert-only. Digest-pinned package x harness-image compatibility set. '
    'The deploy path refuses a package on a non-listed image. ADR-0006 §2.';

CREATE INDEX ix_package_harness_image_image_id
    ON governance.package_harness_image (harness_image_id);
CREATE INDEX ix_package_harness_image_created_by_user_id
    ON governance.package_harness_image (created_by_user_id);

-- ----------------------------------------------------------------------------
-- TABLE: deployment_environment  (Tier-1 registry)
--   Named environment grouping clusters (non-prod / prod / ephemeral). ADR-0006 §1.
-- ----------------------------------------------------------------------------
CREATE TABLE governance.deployment_environment (
    deployment_environment_id  uuid        NOT NULL DEFAULT uuidv7(),
    environment_name           text        NOT NULL,
    environment_kind           governance.environment_kind NOT NULL,
    description                text,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_environment PRIMARY KEY (deployment_environment_id),
    CONSTRAINT uq_deployment_environment_name UNIQUE (environment_name),
    -- S7: composite key target so deployment can FK (deployment_environment_id,
    --   environment_kind) and the state->environment matrix is enforced without a
    --   denormalized hand-maintained copy.
    CONSTRAINT uq_deployment_environment_id_kind UNIQUE (deployment_environment_id, environment_kind)
);
COMMENT ON TABLE governance.deployment_environment IS
    'tier:1. Named environment (non_prod/prod/ephemeral) grouping clusters. ADR-0006 §1.';

-- ----------------------------------------------------------------------------
-- TABLE: deployment_cluster  (Tier-1 registry)
--   A target cluster within an environment (incl. ephemeral/replay clusters). ADR-0006 §1.
-- ----------------------------------------------------------------------------
CREATE TABLE governance.deployment_cluster (
    deployment_cluster_id      uuid        NOT NULL DEFAULT uuidv7(),
    deployment_environment_id  uuid        NOT NULL,
    cluster_name               text        NOT NULL,
    is_ephemeral               boolean     NOT NULL DEFAULT false,  -- temp/replay cluster
    description                text,
    created_at                 timestamptz NOT NULL DEFAULT now(),
    decommissioned_at          timestamptz,                          -- soft retire of a cluster registration
    CONSTRAINT pk_deployment_cluster PRIMARY KEY (deployment_cluster_id),
    CONSTRAINT uq_deployment_cluster_name UNIQUE (cluster_name),
    CONSTRAINT fk_deployment_cluster_environment
        FOREIGN KEY (deployment_environment_id)
        REFERENCES governance.deployment_environment (deployment_environment_id)
        ON DELETE RESTRICT
);
COMMENT ON TABLE governance.deployment_cluster IS
    'tier:1. Target cluster within an environment, incl. ephemeral replay clusters. ADR-0006 §1.';

CREATE INDEX ix_deployment_cluster_environment_id
    ON governance.deployment_cluster (deployment_environment_id);

-- ----------------------------------------------------------------------------
-- TABLE: deployment  (Tier-1, APPEND-ONLY, lifecycle-gated event)
--   One immutable row per governed deployment request. ADR-0006 §1-§3.
--   Records: package, lifecycle state, target cluster/environment, image digest,
--   run mode, actor, operation, outcome. Never updated in place.
-- ----------------------------------------------------------------------------
CREATE TABLE governance.deployment (
    deployment_id              uuid        NOT NULL DEFAULT uuidv7(),
    package_id                 uuid        NOT NULL,
    harness_image_id           uuid        NOT NULL,             -- the digest-pinned image used
    deployment_cluster_id      uuid        NOT NULL,
    deployment_environment_id  uuid        NOT NULL,
    -- S7: environment_kind is carried so the matrix CHECK is a real invariant, but it is
    --   no longer a hand-maintained mirror: a composite FK to deployment_environment
    --   (deployment_environment_id, environment_kind) forces it to equal the parent's kind.
    environment_kind           governance.environment_kind     NOT NULL,
    lifecycle_state            governance.lifecycle_state      NOT NULL,
    deployment_operation       governance.deployment_operation NOT NULL,
    run_mode                   governance.deployment_run_mode  NOT NULL,
    outcome                    governance.deployment_outcome   NOT NULL DEFAULT 'requested',
    rejection_detail           text,                            -- why, when outcome is a reject/fail
    actor_user_id              uuid        NOT NULL,             -- server-resolved; FK deferred -> governance.account_user (auth)
    actor_role                 text        NOT NULL,            -- platform/app-team role exercised (auth)
    requested_at               timestamptz NOT NULL DEFAULT now(),
    completed_at               timestamptz,                     -- when outcome reached terminal
    CONSTRAINT pk_deployment PRIMARY KEY (deployment_id),
    CONSTRAINT fk_deployment_package
        FOREIGN KEY (package_id)
        REFERENCES governance.package (package_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_deployment_image
        FOREIGN KEY (harness_image_id)
        REFERENCES governance.harness_image (harness_image_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_deployment_cluster
        FOREIGN KEY (deployment_cluster_id)
        REFERENCES governance.deployment_cluster (deployment_cluster_id)
        ON DELETE RESTRICT,
    -- S7: composite FK pins environment_kind to the referenced environment row, so the
    --   matrix CHECK below cannot drift from deployment_environment.
    CONSTRAINT fk_deployment_environment_kind
        FOREIGN KEY (deployment_environment_id, environment_kind)
        REFERENCES governance.deployment_environment (deployment_environment_id, environment_kind)
        ON DELETE RESTRICT,
    -- ADR-0006 §1 state->environment matrix (real invariant):
    --   draft/candidate     : not deployable at all
    --   staging             : non_prod only
    --   shadow/challenger   : prod or any (read-only / A/B)
    --   champion/deprecated : any environment
    CONSTRAINT ck_deployment_state_environment_matrix
        CHECK (
            CASE lifecycle_state
                WHEN 'draft'      THEN false
                WHEN 'candidate'  THEN false
                WHEN 'staging'    THEN environment_kind = 'non_prod'
                ELSE true   -- shadow, challenger, champion, deprecated
            END
        ),
    -- ADR-0006 §1 run-mode gating per state:
    --   staging -> live ; shadow -> read_only ; challenger -> read_only|ab_slice ;
    --   champion -> live ; deprecated -> locked
    CONSTRAINT ck_deployment_state_run_mode
        CHECK (
            CASE lifecycle_state
                WHEN 'staging'    THEN run_mode = 'live'
                WHEN 'shadow'     THEN run_mode = 'read_only'
                WHEN 'challenger' THEN run_mode IN ('read_only', 'ab_slice')
                WHEN 'champion'   THEN run_mode = 'live'
                WHEN 'deprecated' THEN run_mode = 'locked'
                ELSE false  -- draft/candidate never reach a deployment row
            END
        ),
    CONSTRAINT ck_deployment_completed_after_requested
        CHECK (completed_at IS NULL OR completed_at >= requested_at),
    CONSTRAINT ck_deployment_rejection_detail_present
        CHECK (
            outcome NOT IN ('rejected_incompatible','rejected_lifecycle',
                            'rejected_unauthorized','failed')
            OR rejection_detail IS NOT NULL
        )
    -- fk_deployment_actor_user deferred (reconciliation #19, auth section).
);
COMMENT ON TABLE governance.deployment IS
    'tier:1 append-only. One immutable row per governed deployment request: package, '
    'lifecycle state, target cluster/environment, image digest, run mode, actor, '
    'operation, outcome. Lifecycle-gated (ADR-0006 §1) and digest-compatibility-gated '
    '(§2); deployment is mediated by the control plane (§3). Never updated in place; '
    'a state change is a new row. Out-of-band deploys are disallowed.';
COMMENT ON COLUMN governance.deployment.environment_kind IS
    'Environment classification of deployment_environment_id, pinned by composite FK '
    'fk_deployment_environment_kind (S7) so the state->environment matrix CHECK is a true '
    'invariant rather than a hand-maintained copy.';

CREATE INDEX ix_deployment_package_id
    ON governance.deployment (package_id, requested_at DESC);
CREATE INDEX ix_deployment_cluster_id
    ON governance.deployment (deployment_cluster_id, requested_at DESC);
CREATE INDEX ix_deployment_environment_id
    ON governance.deployment (deployment_environment_id);
CREATE INDEX ix_deployment_image_id
    ON governance.deployment (harness_image_id);
CREATE INDEX ix_deployment_actor_user_id
    ON governance.deployment (actor_user_id);

-- ----------------------------------------------------------------------------
-- VIEW: deployment_current  — latest successful deployment per (package, cluster)
--   "What is running where" single source of truth. ADR-0006 §3 / Consequences.
-- ----------------------------------------------------------------------------
CREATE VIEW governance.deployment_current AS
SELECT DISTINCT ON (d.package_id, d.deployment_cluster_id)
       d.deployment_id,
       d.package_id,
       d.harness_image_id,
       d.deployment_cluster_id,
       d.deployment_environment_id,
       d.lifecycle_state,
       d.run_mode,
       d.actor_user_id,
       d.requested_at,
       d.completed_at AS deployed_at
FROM   governance.deployment AS d
WHERE  d.outcome = 'succeeded'
ORDER  BY d.package_id, d.deployment_cluster_id, d.requested_at DESC;
COMMENT ON VIEW governance.deployment_current IS
    'Current placement: latest succeeded deployment per (package, cluster). Live projection '
    'over the append-only governance.deployment event log. ADR-0006 Consequences.';

-- ############ TABLES: lifecycle_approvals ############
-- =====================================================================
-- SECTION: lifecycle_approvals (tables/views only)
-- Surviving objects: lifecycle_event (+view), champion_assignment (+view),
-- promotion. All other objects from 03-lifecycle_approvals.sql are DROPPED
-- per ASSEMBLY-AND-VERIFICATION.md:
--   - approval_request / approval_signoff -> owned by intake (B12)
--   - harness_image / package / package_image_compatibility / cluster /
--     deployment_event (+deployment_current) -> owned by packages_deploy (B14)
--   - intake_artifact_plan_estimate / intake_roi_assessment /
--     intake_cost_envelope -> owned by intake (B13)
--   - run_dispatch_outbox -> owned by runtime/runs_quotas (B15)
-- All duplicate CREATE TYPE blocks dropped (A1-A8): lifecycle_state,
-- deployment_channel, materiality_tier, ai_risk_tier, approval_role,
-- approval_decision, approval_request_kind, approval_request_status,
-- package_kind, deployment_action/run_mode/outcome, environment_class,
-- outbox_status are owned by entities/intake/packages_deploy/runs_quotas.
-- versioned_entity_type is unique to this section and is retained.
-- This section loads at step 17, AFTER intake (13) and packages_deploy (16),
-- so every cross-section FK target already exists -> all FKs stay inline.
-- =====================================================================

-- ---------------------------------------------------------------------
-- ENUMS retained (sole owner): versioned_entity_type.
-- ---------------------------------------------------------------------

-- Entity kinds that have a lifecycle/version (agent, task, prompt).
-- Subset of v1 governance.entity_type; not duplicated by any other section.
CREATE TYPE governance.versioned_entity_type AS ENUM ('agent', 'task', 'prompt');
COMMENT ON TYPE governance.versioned_entity_type IS
    'tier:1 — entity kinds that own a version row + lifecycle. Subset of v1 entity_type.';

-- ---------------------------------------------------------------------
-- 1. LIFECYCLE STATE MACHINE  (append-only; generalizes v1 mutable column)
--    Uses governance.lifecycle_state / deployment_channel (owned by entities,
--    loaded earlier). FK -> intake.approval_request (intake loads at step 13,
--    before this section at step 17) is kept inline.
-- ---------------------------------------------------------------------
CREATE TABLE governance.lifecycle_event (
    lifecycle_event_id  uuid                             NOT NULL DEFAULT uuidv7(),
    entity_type         governance.versioned_entity_type NOT NULL,
    entity_version_id   uuid                             NOT NULL,  -- agent_version/task_version/prompt_version PK (polymorphic; app-validated)
    from_state          governance.lifecycle_state,                 -- NULL on initial 'draft' creation
    to_state            governance.lifecycle_state       NOT NULL,
    channel             governance.deployment_channel,
    approval_request_id uuid,                                       -- gating approval that authorized this transition (nullable)
    actor_user_id       uuid                             NOT NULL,  -- server-resolved principal (FR-018)
    rationale           text                             NOT NULL,
    detail              jsonb       NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_lifecycle_event PRIMARY KEY (lifecycle_event_id),
    CONSTRAINT fk_lifecycle_event_approval_request
        FOREIGN KEY (approval_request_id)
        REFERENCES governance.approval_request (approval_request_id) ON DELETE RESTRICT,
    CONSTRAINT ck_lifecycle_event_no_self_loop
        CHECK (from_state IS NULL OR from_state <> to_state)
);
COMMENT ON TABLE governance.lifecycle_event IS
    'tier:1 append-only — one row per lifecycle state transition per entity version. Current state is governance.entity_lifecycle_current.';
CREATE INDEX ix_lifecycle_event_entity
    ON governance.lifecycle_event (entity_type, entity_version_id, created_at DESC);
CREATE INDEX ix_lifecycle_event_to_state
    ON governance.lifecycle_event (to_state);
CREATE INDEX ix_lifecycle_event_approval_request_id
    ON governance.lifecycle_event (approval_request_id);

-- Current lifecycle state = latest event per entity version.
CREATE VIEW governance.entity_lifecycle_current AS
SELECT DISTINCT ON (e.entity_type, e.entity_version_id)
       e.entity_type,
       e.entity_version_id,
       e.to_state          AS lifecycle_state,
       e.channel,
       e.actor_user_id     AS last_actor_user_id,
       e.created_at        AS state_since
FROM   governance.lifecycle_event AS e
ORDER  BY e.entity_type, e.entity_version_id, e.created_at DESC;
COMMENT ON VIEW governance.entity_lifecycle_current IS
    'tier:1 projection — latest lifecycle_event per (entity_type, entity_version_id).';

-- ---------------------------------------------------------------------
-- 2. CHAMPION RESOLUTION  (append-only; replaces v1 no-FK soft pointers)
--    Sole source of truth for current champion (reconciliation D21:
--    entities.agent/task.current_champion_version_id are dropped there).
--    FK -> governance.promotion is intra-section (kept inline).
-- ---------------------------------------------------------------------
CREATE TABLE governance.champion_assignment (
    champion_assignment_id uuid                             NOT NULL DEFAULT uuidv7(),
    entity_type            governance.versioned_entity_type NOT NULL,
    entity_id              uuid                             NOT NULL,  -- the registry entity (agent/task/prompt), app-validated polymorphic
    entity_version_id      uuid                             NOT NULL,  -- the version becoming/leaving champion
    is_retirement          boolean     NOT NULL DEFAULT false,         -- true = this entity has no champion as of this event
    promotion_id           uuid,                                       -- the promotion that minted the package, when applicable
    actor_user_id          uuid        NOT NULL,                       -- server-resolved principal (FR-018)
    rationale              text        NOT NULL,
    champion_since         timestamptz NOT NULL DEFAULT now(),
    created_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_champion_assignment PRIMARY KEY (champion_assignment_id),
    CONSTRAINT fk_champion_assignment_promotion
        FOREIGN KEY (promotion_id)
        REFERENCES governance.promotion (promotion_id) ON DELETE RESTRICT,
    CONSTRAINT ck_champion_assignment_retirement_no_promotion
        CHECK (NOT is_retirement OR promotion_id IS NULL)
);
COMMENT ON TABLE governance.champion_assignment IS
    'tier:1 append-only — sole source of truth for current champion; replaces v1 agent/task.current_champion_version_id (no-FK mutable, dropped from entities per reconciliation D21). Current champion = governance.entity_champion_current.';
CREATE INDEX ix_champion_assignment_entity
    ON governance.champion_assignment (entity_type, entity_id, created_at DESC);
CREATE INDEX ix_champion_assignment_promotion_id
    ON governance.champion_assignment (promotion_id);

-- Current champion = latest assignment per entity, excluding retirements.
CREATE VIEW governance.entity_champion_current AS
SELECT entity_type, entity_id, entity_version_id, promotion_id, champion_since
FROM (
    SELECT DISTINCT ON (a.entity_type, a.entity_id)
           a.entity_type, a.entity_id, a.entity_version_id,
           a.promotion_id, a.champion_since, a.is_retirement
    FROM   governance.champion_assignment AS a
    ORDER  BY a.entity_type, a.entity_id, a.created_at DESC
) latest
WHERE latest.is_retirement = false;
COMMENT ON VIEW governance.entity_champion_current IS
    'tier:1 projection — latest non-retirement champion_assignment per (entity_type, entity_id).';

-- ---------------------------------------------------------------------
-- 3. PROMOTION ATTESTATION  (the champion package, PCR 3.2 + ADR-0006)
--    Replaces v1 governance.approval_record. FKs:
--      - approval_request_id -> intake.approval_request (intake @13, inline)
--      - package_id -> packages_deploy.package (B14 re-point; packages_deploy
--        @16 loads before this section @17, so inline)
--    Uses lifecycle_state (entities) + materiality_tier (intake), declared
--    earlier; not redeclared here.
-- ---------------------------------------------------------------------
CREATE TABLE governance.promotion (
    promotion_id          uuid                             NOT NULL DEFAULT uuidv7(),
    entity_type           governance.versioned_entity_type NOT NULL,
    entity_version_id     uuid                             NOT NULL,
    approval_request_id   uuid                             NOT NULL,   -- the promote_champion request that authorized this
    package_id            uuid                             NOT NULL,   -- the .vtx/.vax produced at promotion (packages_deploy.package)
    from_state            governance.lifecycle_state       NOT NULL,
    to_state              governance.lifecycle_state       NOT NULL,
    materiality_tier      governance.materiality_tier      NOT NULL,
    inference_config_snapshot jsonb                        NOT NULL,   -- config.json snapshot at promotion (PCR 3.2)
    promoted_by_user_id   uuid                             NOT NULL,   -- server-resolved (FR-018); replaces v1 approver_name
    rationale             text                             NOT NULL,   -- replaces v1 approval_record.rationale (NOT NULL)
    -- Gate-review attestation flags (verbatim from v1 approval_record).
    staging_results_reviewed    boolean NOT NULL DEFAULT false,
    ground_truth_reviewed       boolean NOT NULL DEFAULT false,
    fairness_analysis_reviewed  boolean NOT NULL DEFAULT false,
    shadow_metrics_reviewed     boolean NOT NULL DEFAULT false,
    challenger_metrics_reviewed boolean NOT NULL DEFAULT false,
    model_card_reviewed         boolean NOT NULL DEFAULT false,
    similarity_flags_reviewed   boolean NOT NULL DEFAULT false,
    champion_confirmation_satisfied boolean NOT NULL DEFAULT false,
    decision_override           boolean NOT NULL DEFAULT false,
    override_reason             text,
    promoted_at           timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_promotion PRIMARY KEY (promotion_id),
    CONSTRAINT fk_promotion_approval_request
        FOREIGN KEY (approval_request_id)
        REFERENCES governance.approval_request (approval_request_id) ON DELETE RESTRICT,
    CONSTRAINT fk_promotion_package
        FOREIGN KEY (package_id)
        REFERENCES governance.package (package_id) ON DELETE RESTRICT,
    CONSTRAINT ck_promotion_override_reason
        CHECK (NOT decision_override OR override_reason IS NOT NULL),
    CONSTRAINT ck_promotion_state_advance
        CHECK (from_state <> to_state)
);
COMMENT ON TABLE governance.promotion IS
    'tier:1 append-only — promotion/attestation event. Replaces v1 governance.approval_record (lifecycle gate + champion_confirmation_satisfied); binds the .vtx/.vax package (packages_deploy.package) and config snapshot at the moment of champion promotion (PCR 3.2).';
CREATE INDEX ix_promotion_entity
    ON governance.promotion (entity_type, entity_version_id, promoted_at DESC);
CREATE INDEX ix_promotion_approval_request_id ON governance.promotion (approval_request_id);
CREATE INDEX ix_promotion_package_id          ON governance.promotion (package_id);

-- ############ TABLES: runs_quotas ############
-- =============================================================================
-- SECTION 18: runs_quotas — runtime run state machine + dispatch outbox + quotas
-- Schemas: runtime (run state + dispatch), governance (quotas)
-- Single owner of: runtime.execution_run (+status/completion/error +current view),
--   runtime.run_dispatch_outbox (SOLE owner; governance.run_dispatch_outbox copies
--   in entities/lifecycle_approvals are dropped per reconciliation B15),
--   governance.quota, governance.quota_check.
-- Enums for this section are emitted in the enum block (assembly step 7).
-- FK NOTES (load order):
--   * fk_execution_run_*_decision -> governance.agent_decision_log is owned by the
--     `decisions` section (step 12), which loads BEFORE this section (step 18),
--     so those FKs stay INLINE.
--   * S8: runtime.execution_context is defined by NO fragment (only forward-referenced).
--     Per ASSEMBLY-AND-VERIFICATION.md S8 recommendation the FK is DROPPED; the
--     execution_context_id column + its index are retained as an app-validated soft
--     pointer. Reinstate the FK only if/when an owning domain defines execution_context.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- runtime.execution_run  (Tier-1, append-only submission record)
--   One immutable row per submitted run. State is NOT stored here; it is projected
--   from the append-only status/completion/error event tables via execution_run_current.
-- -----------------------------------------------------------------------------
CREATE TABLE runtime.execution_run (
    execution_run_id        uuid                    NOT NULL DEFAULT uuidv7(),
    entity_kind             runtime.run_entity_kind NOT NULL,
    entity_version_id       uuid                    NOT NULL,
    entity_name             text                    NOT NULL,
    channel                 governance.deployment_channel NOT NULL,
    application              text                    NOT NULL DEFAULT 'default',
    input_json              jsonb,
    execution_context_id    uuid,                   -- S8: soft pointer; runtime.execution_context is unowned, no FK (see note above)
    workflow_run_id         uuid,                   -- soft pointer (app-maintained), no FK
    parent_decision_id      uuid,                   -- soft pointer to agent_decision_log, no FK
    mock_mode               boolean                 NOT NULL DEFAULT false,
    write_mode              runtime.run_write_mode  NOT NULL DEFAULT 'live',
    enforce_output_schema   boolean                 NOT NULL DEFAULT true,
    submitted_at            timestamptz             NOT NULL DEFAULT now(),
    submitted_by            text,
    CONSTRAINT pk_execution_run PRIMARY KEY (execution_run_id)
    -- S8: fk_execution_run_context DROPPED — runtime.execution_context is defined by no
    --     fragment. Reinstate as a deferred ALTER once an owning domain creates it.
);
COMMENT ON TABLE runtime.execution_run IS
    'tier:1 append-only. Immutable submission record for one run. Current state is the execution_run_current view over the append-only status/completion/error event tables (ADR-0004/0005 insert-only model).';
COMMENT ON COLUMN runtime.execution_run.execution_context_id IS 'Soft pointer (app-validated): runtime.execution_context is not defined by any v2 fragment (ASSEMBLY S8), so no DB FK. Add a deferred FK if/when an owning domain defines the table.';
COMMENT ON COLUMN runtime.execution_run.workflow_run_id IS 'Soft pointer (app-maintained), intentionally no DB FK — correlates runs in a multi-step workflow.';
COMMENT ON COLUMN runtime.execution_run.parent_decision_id IS 'Soft pointer to governance.agent_decision_log (Tier-2 decision-log domain), intentionally no DB FK to avoid cross-tier coupling.';
COMMENT ON COLUMN runtime.execution_run.write_mode IS 'live vs read_only (Target Bindings suppressed); read_only is the PCR 3.7 shadow/challenger/deprecated execution mode.';

CREATE INDEX ix_execution_run_entity
    ON runtime.execution_run (entity_kind, entity_version_id);
CREATE INDEX ix_execution_run_context_id
    ON runtime.execution_run (execution_context_id);
CREATE INDEX ix_execution_run_workflow_id
    ON runtime.execution_run (workflow_run_id);
CREATE INDEX ix_execution_run_submitted_at
    ON runtime.execution_run (submitted_at DESC);
CREATE INDEX ix_execution_run_application
    ON runtime.execution_run (application);

-- -----------------------------------------------------------------------------
-- runtime.execution_run_status  (Tier-1, append-only event table)
--   One immutable row per non-terminal state transition (submitted/claimed/heartbeat/
--   released). Never updated. The state-machine history IS this table.
--   S9: v1 free-text execution_run_status.notes is folded into detail jsonb (dropped as
--       a distinct column); structured transition detail now lives in detail.
-- -----------------------------------------------------------------------------
CREATE TABLE runtime.execution_run_status (
    execution_run_status_id uuid                NOT NULL DEFAULT uuidv7(),
    execution_run_id        uuid                NOT NULL,
    status                  runtime.run_status  NOT NULL,
    worker_id               text,
    detail                  jsonb,              -- S9: subsumes v1 free-text `notes` (folded, not a separate column)
    created_at              timestamptz         NOT NULL DEFAULT now(),
    CONSTRAINT pk_execution_run_status PRIMARY KEY (execution_run_status_id),
    CONSTRAINT fk_execution_run_status_run
        FOREIGN KEY (execution_run_id)
        REFERENCES runtime.execution_run (execution_run_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_execution_run_status_worker_when_claimed
        CHECK (status <> 'claimed' OR worker_id IS NOT NULL)
);
COMMENT ON TABLE runtime.execution_run_status IS
    'tier:1 append-only event table. One row per run state transition (submitted/claimed/heartbeat/released). Immutable: no UPDATE/DELETE; advancing a run INSERTs a new row.';
COMMENT ON COLUMN runtime.execution_run_status.detail IS 'Structured transition detail; subsumes the v1 free-text execution_run_status.notes (S9: folded into this column).';

CREATE INDEX ix_execution_run_status_run_id
    ON runtime.execution_run_status (execution_run_id, created_at DESC);

-- -----------------------------------------------------------------------------
-- runtime.execution_run_completion  (Tier-1, append-only terminal fact, one per run)
--   fk_execution_run_completion_decision -> governance.agent_decision_log: owned by the
--   `decisions` section (loads earlier), so kept inline.
-- -----------------------------------------------------------------------------
CREATE TABLE runtime.execution_run_completion (
    execution_run_completion_id uuid                        NOT NULL DEFAULT uuidv7(),
    execution_run_id            uuid                        NOT NULL,
    final_status                runtime.run_completion_status NOT NULL,
    decision_log_id             uuid,
    duration_ms                 integer,
    worker_id                   text,
    completed_at                timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_execution_run_completion PRIMARY KEY (execution_run_completion_id),
    CONSTRAINT uq_execution_run_completion_run UNIQUE (execution_run_id),
    CONSTRAINT fk_execution_run_completion_run
        FOREIGN KEY (execution_run_id)
        REFERENCES runtime.execution_run (execution_run_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_execution_run_completion_decision
        FOREIGN KEY (decision_log_id)
        REFERENCES governance.agent_decision_log (agent_decision_log_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_execution_run_completion_duration_nonneg
        CHECK (duration_ms IS NULL OR duration_ms >= 0)
);
COMMENT ON TABLE runtime.execution_run_completion IS
    'tier:1 append-only terminal fact: non-error completion of a run, at most one per run (uq_execution_run_completion_run). Immutable.';
COMMENT ON COLUMN runtime.execution_run_completion.decision_log_id IS 'FK to governance.agent_decision_log (Tier-2 decision-log domain, owned by the decisions section which loads earlier); drill-through to the terminal decision record.';

CREATE INDEX ix_execution_run_completion_decision_id
    ON runtime.execution_run_completion (decision_log_id);

-- -----------------------------------------------------------------------------
-- runtime.execution_run_error  (Tier-1, append-only terminal fact, one per run)
--   fk_execution_run_error_decision -> governance.agent_decision_log: owned by the
--   `decisions` section (loads earlier), so kept inline.
-- -----------------------------------------------------------------------------
CREATE TABLE runtime.execution_run_error (
    execution_run_error_id  uuid        NOT NULL DEFAULT uuidv7(),
    execution_run_id        uuid        NOT NULL,
    error_code              text,
    error_message           text        NOT NULL,
    error_trace             text,
    decision_log_id         uuid,
    worker_id               text,
    failed_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_execution_run_error PRIMARY KEY (execution_run_error_id),
    CONSTRAINT uq_execution_run_error_run UNIQUE (execution_run_id),
    CONSTRAINT fk_execution_run_error_run
        FOREIGN KEY (execution_run_id)
        REFERENCES runtime.execution_run (execution_run_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_execution_run_error_decision
        FOREIGN KEY (decision_log_id)
        REFERENCES governance.agent_decision_log (agent_decision_log_id)
        ON DELETE RESTRICT
);
COMMENT ON TABLE runtime.execution_run_error IS
    'tier:1 append-only terminal fact: error termination of a run, at most one per run (uq_execution_run_error_run). Immutable. Written before any data side effects on INTEGRITY_VIOLATION (PCR 3.2).';

CREATE INDEX ix_execution_run_error_decision_id
    ON runtime.execution_run_error (decision_log_id);

-- -----------------------------------------------------------------------------
-- runtime.execution_run_current  (current-state VIEW; never materialized in Tier-1)
--   Resolves current_status by precedence: completion.final_status -> 'failed' if an
--   error row exists -> latest status event -> 'submitted'. Exposes the PCR 3.6
--   run-detail columns: current_status, submitted_at, first_started_at,
--   current_worker_id, duration_ms.
-- -----------------------------------------------------------------------------
CREATE VIEW runtime.execution_run_current AS
SELECT
    r.execution_run_id,
    r.entity_kind,
    r.entity_version_id,
    r.entity_name,
    r.channel,
    r.application,
    r.write_mode,
    r.mock_mode,
    r.submitted_at,
    r.submitted_by,
    CASE
        WHEN comp.execution_run_id IS NOT NULL THEN comp.final_status::text
        WHEN err.execution_run_id  IS NOT NULL THEN 'failed'
        WHEN st.status             IS NOT NULL THEN st.status::text
        ELSE 'submitted'
    END                                                   AS current_status,
    claim.first_started_at,
    COALESCE(comp.worker_id, err.worker_id, st.worker_id) AS current_worker_id,
    COALESCE(
        comp.duration_ms,
        CASE
            WHEN comp.completed_at IS NOT NULL
                THEN (EXTRACT(EPOCH FROM (comp.completed_at - r.submitted_at)) * 1000)::integer
            WHEN err.failed_at IS NOT NULL
                THEN (EXTRACT(EPOCH FROM (err.failed_at - r.submitted_at)) * 1000)::integer
        END
    )                                                     AS duration_ms,
    comp.completed_at,
    comp.decision_log_id                                  AS completion_decision_log_id,
    err.failed_at,
    err.error_code,
    err.error_message,
    err.decision_log_id                                   AS error_decision_log_id
FROM runtime.execution_run AS r
LEFT JOIN runtime.execution_run_completion AS comp
    ON comp.execution_run_id = r.execution_run_id
LEFT JOIN runtime.execution_run_error AS err
    ON err.execution_run_id = r.execution_run_id
LEFT JOIN LATERAL (
    SELECT s.status, s.worker_id
    FROM runtime.execution_run_status AS s
    WHERE s.execution_run_id = r.execution_run_id
    ORDER BY s.created_at DESC, s.execution_run_status_id DESC
    LIMIT 1
) AS st ON true
LEFT JOIN LATERAL (
    SELECT min(s.created_at) AS first_started_at
    FROM runtime.execution_run_status AS s
    WHERE s.execution_run_id = r.execution_run_id
      AND s.status = 'claimed'
) AS claim ON true;
COMMENT ON VIEW runtime.execution_run_current IS
    'Current-state projection over the append-only run event tables. current_status precedence: completion -> error(=failed) -> latest status event -> submitted. Exposes PCR 3.6 run-detail columns.';

-- =============================================================================
-- V2-NEW: TIER-1 TRANSACTIONAL OUTBOX FOR RUN DISPATCH (PCR section 3.3)
-- SINGLE OWNER (reconciliation B15): the governance.run_dispatch_outbox copies in the
-- entities and lifecycle_approvals fragments are dropped; this runtime-schema table is
-- the only run_dispatch_outbox, as it alone carries the real FK to runtime.execution_run.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- runtime.run_dispatch_outbox
--   Inserted in the SAME transaction as execution_run on run submit. verity-relay
--   reads pending rows with SKIP LOCKED, publishes to NATS (verity.runs.pending),
--   and marks published_at. verity-dispatch-sweep re-publishes rows published but
--   not claimed within the timeout. Append-then-update-status (not insert-only):
--   this is dispatch plumbing, NOT an audit fact, so a small bounded mutable status
--   is acceptable and intentional. The audit record of the run is execution_run +
--   the append-only status events.
-- -----------------------------------------------------------------------------
CREATE TABLE runtime.run_dispatch_outbox (
    run_dispatch_outbox_id  uuid                    NOT NULL DEFAULT uuidv7(),
    execution_run_id        uuid                    NOT NULL,
    subject                 text                    NOT NULL DEFAULT 'verity.runs.pending',
    payload                 jsonb                   NOT NULL,
    status                  runtime.outbox_status   NOT NULL DEFAULT 'pending',
    publish_attempts        integer                 NOT NULL DEFAULT 0,
    last_error              text,
    created_at              timestamptz             NOT NULL DEFAULT now(),
    published_at            timestamptz,
    claimed_at              timestamptz,
    CONSTRAINT pk_run_dispatch_outbox PRIMARY KEY (run_dispatch_outbox_id),
    CONSTRAINT uq_run_dispatch_outbox_run UNIQUE (execution_run_id),
    CONSTRAINT fk_run_dispatch_outbox_run
        FOREIGN KEY (execution_run_id)
        REFERENCES runtime.execution_run (execution_run_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_run_dispatch_outbox_attempts_nonneg
        CHECK (publish_attempts >= 0),
    CONSTRAINT ck_run_dispatch_outbox_published_state
        CHECK (status <> 'published' OR published_at IS NOT NULL),
    CONSTRAINT ck_run_dispatch_outbox_claimed_state
        CHECK (status <> 'claimed' OR claimed_at IS NOT NULL)
);
COMMENT ON TABLE runtime.run_dispatch_outbox IS
    'tier:1 transactional outbox for run dispatch (PCR 3.3), SINGLE owner (B15). One row per run, inserted in the same txn as execution_run. Relay publishes pending rows (SKIP LOCKED) to NATS and advances status; sweep re-publishes stuck rows. Dispatch plumbing, not an audit fact.';
COMMENT ON COLUMN runtime.run_dispatch_outbox.status IS 'pending -> published -> claimed; failed parks the row for ops. Bounded status mutation is intentional (dispatch state, not audit).';

-- Partial index over the relay hot path (pending rows oldest-first, for FOR UPDATE SKIP LOCKED).
CREATE INDEX ix_run_dispatch_outbox_pending
    ON runtime.run_dispatch_outbox (created_at)
    WHERE status = 'pending';
-- Partial index over the sweep path (published-but-not-yet-claimed rows).
CREATE INDEX ix_run_dispatch_outbox_published_unclaimed
    ON runtime.run_dispatch_outbox (published_at)
    WHERE status = 'published';

-- =============================================================================
-- TIER-1: QUOTAS + QUOTA CHECK
-- =============================================================================

-- -----------------------------------------------------------------------------
-- governance.quota  (Tier-1 system-of-record; configurable spend cap)
--   V2 delta: keeps the v1 boolean hard_stop AND adds the configurable
--   enforcement_action enum. hard_stop is retained as a generated mirror so existing
--   semantics/queries survive (hard_stop == enforcement_action = 'block'). [N2: OK]
-- -----------------------------------------------------------------------------
CREATE TABLE governance.quota (
    quota_id            uuid                            NOT NULL DEFAULT uuidv7(),
    scope_type          governance.quota_scope_type     NOT NULL,
    scope_id            uuid,                           -- polymorphic soft pointer (app-validated), no FK [N1]
    scope_name          text                            NOT NULL,
    period              governance.quota_period         NOT NULL,
    budget_usd          numeric(14,4)                   NOT NULL,
    alert_threshold_pct integer                         NOT NULL DEFAULT 80,
    enforcement_action  governance.quota_enforcement_action NOT NULL DEFAULT 'alert_only',
    hard_stop           boolean GENERATED ALWAYS AS (enforcement_action = 'block') STORED,
    enabled             boolean                         NOT NULL DEFAULT true,
    notes               text,
    created_at          timestamptz                     NOT NULL DEFAULT now(),
    updated_at          timestamptz                     NOT NULL DEFAULT now(),
    CONSTRAINT pk_quota PRIMARY KEY (quota_id),
    CONSTRAINT ck_quota_budget_positive
        CHECK (budget_usd > 0),
    CONSTRAINT ck_quota_alert_threshold_range
        CHECK (alert_threshold_pct BETWEEN 1 AND 200)
);
COMMENT ON TABLE governance.quota IS
    'tier:1 system-of-record. Spend budget for a scope/period with configurable enforcement_action. hard_stop is a generated mirror of enforcement_action=block (v1 compatibility, N2).';
COMMENT ON COLUMN governance.quota.scope_id IS 'Polymorphic target id (application/agent/task/model), validated in the app layer; intentionally no DB FK (heterogeneous targets, N1).';
COMMENT ON COLUMN governance.quota.hard_stop IS 'V1-compat generated column: TRUE iff enforcement_action = block. Configure via enforcement_action.';

CREATE INDEX ix_quota_scope
    ON governance.quota (scope_type, scope_id);
CREATE INDEX ix_quota_enabled
    ON governance.quota (enabled);

-- -----------------------------------------------------------------------------
-- governance.quota_check  (Tier-1, append-only evaluation record)
--   One immutable row per evaluation of a quota against a period's spend.
--   resolved_at flips an alert closed -> intentional bounded operational mutation,
--   not an audit edit (the evaluation facts spend_usd/spend_pct/alert_fired are
--   immutable once written).
-- -----------------------------------------------------------------------------
CREATE TABLE governance.quota_check (
    quota_check_id  uuid                            NOT NULL DEFAULT uuidv7(),
    quota_id        uuid                            NOT NULL,
    period_start    timestamptz                     NOT NULL,
    period_end      timestamptz                     NOT NULL,
    spend_usd       numeric(14,4)                   NOT NULL,
    budget_usd      numeric(14,4)                   NOT NULL,
    spend_pct       integer                         NOT NULL,
    alert_fired     boolean                         NOT NULL DEFAULT false,
    alert_level     governance.quota_alert_level,
    note            text,
    checked_at      timestamptz                     NOT NULL DEFAULT now(),
    resolved_at     timestamptz,
    CONSTRAINT pk_quota_check PRIMARY KEY (quota_check_id),
    CONSTRAINT fk_quota_check_quota
        FOREIGN KEY (quota_id)
        REFERENCES governance.quota (quota_id)
        ON DELETE CASCADE,
    CONSTRAINT ck_quota_check_period_order
        CHECK (period_end >= period_start),
    CONSTRAINT ck_quota_check_spend_nonneg
        CHECK (spend_usd >= 0 AND budget_usd >= 0 AND spend_pct >= 0),
    CONSTRAINT ck_quota_check_alert_level_when_fired
        CHECK (alert_fired = false OR alert_level IS NOT NULL)
);
COMMENT ON TABLE governance.quota_check IS
    'tier:1 append-only. One immutable evaluation of a quota vs period spend. Evaluation facts are never edited; resolved_at is a bounded operational close of an alert. CASCADE-deleted with its quota.';

CREATE INDEX ix_quota_check_quota_checked
    ON governance.quota_check (quota_id, checked_at DESC);
CREATE INDEX ix_quota_check_active
    ON governance.quota_check (alert_fired, resolved_at);

-- ############ TABLES: validation/testing ############
-- 10-validation.sql — hardened v2 schema domain: validation / testing / ground-truth
-- See ASSEMBLY-AND-VERIFICATION.md for cross-domain FKs & review items.
-- Closes Critical C9 (no-silent-capability-loss: GT/test/validation subsystem) and
-- C10 (analytics.v_validation_result source = runtime.test_execution_log).
--
-- FULL DDL lives at /home/avenugopal/projects/verity/specs/schema/10-validation.sql
-- (reproduced verbatim below).

-- =============================================================================
-- DOMAIN: TESTING / GROUND-TRUTH / VALIDATION / EVALUATION / MODEL-CARDS /
--         INCIDENTS / SIMILARITY / PLATFORM-SETTINGS
--   governance -> Tier-1 SoR (test catalog, GT assets, thresholds, configs,
--                 model cards, incidents, platform settings).
--   runtime    -> Tier-2 append-only logs (test_execution_log, validation_run +
--                 results, evaluation_run, description_similarity_log).
--   analytics  -> v_validation_result over runtime.test_execution_log (C10).
-- Hardening: ADR-0005/0004. KEY GENERATOR: uuidv7(). Cross-domain refs are SOFT
--   (no DB FK across schemas/tiers); hard FKs only within this domain.
-- ENUM REUSE (ENTITIES domain): governance.entity_type, metric_type,
--   materiality_tier, deployment_channel (referenced, NOT re-declared here).
-- =============================================================================

-- ---- ENUM TYPES (owned by THIS domain) -------------------------------------

-- ---- TIER-1 (governance): TEST SUITE / CASE / MOCK -------------------------
CREATE TABLE governance.test_suite (
    test_suite_id       uuid                    NOT NULL DEFAULT uuidv7(),
    entity_type         governance.entity_type  NOT NULL,
    entity_id           uuid                    NOT NULL,  -- soft ref -> agent/task; no DB FK
    name                text                    NOT NULL,
    description         text,
    suite_type          text                    NOT NULL,
    created_by_user_id  uuid,                              -- soft ref -> account_user; no DB FK
    active              boolean                 NOT NULL DEFAULT true,
    created_at          timestamptz             NOT NULL DEFAULT now(),
    CONSTRAINT pk_test_suite PRIMARY KEY (test_suite_id),
    CONSTRAINT ck_test_suite_entity_kind CHECK (entity_type IN ('agent','task')),
    CONSTRAINT ck_test_suite_name_not_blank CHECK (length(btrim(name)) > 0));
CREATE INDEX ix_test_suite_entity ON governance.test_suite (entity_type, entity_id);
CREATE INDEX ix_test_suite_active ON governance.test_suite (active);

CREATE TABLE governance.test_case (
    test_case_id        uuid                    NOT NULL DEFAULT uuidv7(),
    test_suite_id       uuid                    NOT NULL,
    name                text                    NOT NULL,
    description         text,
    input_data          jsonb                   NOT NULL,
    expected_output     jsonb                   NOT NULL,
    metric_type         governance.metric_type  NOT NULL,
    metric_config       jsonb,
    applies_to_versions uuid[]                  NOT NULL DEFAULT '{}',  -- soft refs; no DB FK
    excludes_versions   uuid[]                  NOT NULL DEFAULT '{}',  -- soft refs; no DB FK
    is_adversarial      boolean                 NOT NULL DEFAULT false,
    tags                text[]                  NOT NULL DEFAULT '{}',
    active              boolean                 NOT NULL DEFAULT true,
    created_at          timestamptz             NOT NULL DEFAULT now(),
    CONSTRAINT pk_test_case PRIMARY KEY (test_case_id),
    CONSTRAINT fk_test_case_test_suite FOREIGN KEY (test_suite_id)
        REFERENCES governance.test_suite (test_suite_id) ON DELETE CASCADE,
    CONSTRAINT ck_test_case_name_not_blank CHECK (length(btrim(name)) > 0));
CREATE INDEX ix_test_case_test_suite ON governance.test_case (test_suite_id);
CREATE INDEX ix_test_case_tags ON governance.test_case USING gin (tags);

CREATE TABLE governance.test_case_mock (
    test_case_mock_id   uuid                    NOT NULL DEFAULT uuidv7(),
    test_case_id        uuid                    NOT NULL,
    mock_kind           governance.mock_kind    NOT NULL DEFAULT 'tool',
    mock_key            text                    NOT NULL,
    call_order          integer                 NOT NULL DEFAULT 1,
    mock_response       jsonb                   NOT NULL,
    description         text,
    created_at          timestamptz             NOT NULL DEFAULT now(),
    CONSTRAINT pk_test_case_mock PRIMARY KEY (test_case_mock_id),
    CONSTRAINT fk_test_case_mock_test_case FOREIGN KEY (test_case_id)
        REFERENCES governance.test_case (test_case_id) ON DELETE CASCADE,
    CONSTRAINT ck_test_case_mock_call_order_positive CHECK (call_order >= 1));
CREATE INDEX ix_test_case_mock_test_case ON governance.test_case_mock (test_case_id);
CREATE INDEX ix_test_case_mock_test_case_kind ON governance.test_case_mock (test_case_id, mock_kind);

-- ---- TIER-2 (runtime): TEST EXECUTION LOG (source for analytics.v_validation_result, C10)
CREATE TABLE runtime.test_execution_log (
    test_execution_log_id       uuid                        NOT NULL DEFAULT uuidv7(),
    test_suite_id               uuid                        NOT NULL,  -- soft ref Tier-1->Tier-2; no DB FK
    test_case_id                uuid                        NOT NULL,  -- soft ref; no DB FK
    entity_type                 governance.entity_type      NOT NULL,
    entity_version_id           uuid                        NOT NULL,  -- soft ref; no DB FK
    mock_mode                   boolean                     NOT NULL,
    channel                     governance.deployment_channel,
    input_used                  jsonb,
    actual_output               jsonb,
    expected_output             jsonb,
    metric_type                 governance.metric_type      NOT NULL,
    metric_result               jsonb,
    passed                      boolean                     NOT NULL,
    failure_reason              text,
    duration_ms                 integer,
    inference_config_snapshot   jsonb,
    run_at                      timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_test_execution_log PRIMARY KEY (test_execution_log_id),
    CONSTRAINT ck_test_execution_log_duration_nonneg CHECK (duration_ms IS NULL OR duration_ms >= 0));
CREATE INDEX ix_test_execution_log_entity ON runtime.test_execution_log (entity_type, entity_version_id);
CREATE INDEX ix_test_execution_log_suite ON runtime.test_execution_log (test_suite_id);
CREATE INDEX brin_test_execution_log_run_at ON runtime.test_execution_log USING brin (run_at);

-- ---- TIER-1 (governance): GROUND TRUTH dataset -> record -> annotation ------
CREATE TABLE governance.ground_truth_dataset (
    ground_truth_dataset_id     uuid                        NOT NULL DEFAULT uuidv7(),
    entity_type                 governance.entity_type      NOT NULL,
    entity_id                   uuid                        NOT NULL,  -- soft ref; no DB FK
    designed_for_version_id     uuid,                                  -- soft ref; no DB FK
    name                        text                        NOT NULL,
    version                     text                        NOT NULL DEFAULT '1.0',
    description                 text,
    purpose                     text                        NOT NULL,
    quality_tier                governance.gt_quality_tier  NOT NULL DEFAULT 'silver',
    status                      governance.gt_dataset_status NOT NULL DEFAULT 'collecting',
    labeling_guide_provider     text,
    labeling_guide_container    text,
    labeling_guide_key          text,
    owner_name                  text                        NOT NULL,
    created_by_user_id          uuid,                                  -- soft ref; no DB FK
    record_count                integer                     NOT NULL DEFAULT 0,
    annotated_count             integer                     NOT NULL DEFAULT 0,
    authoritative_count         integer                     NOT NULL DEFAULT 0,
    iaa_score                   numeric(5,4),
    iaa_computed_at             timestamptz,
    iaa_method                  text,
    coverage_notes              text,
    applies_to_versions         uuid[]                      NOT NULL DEFAULT '{}',  -- soft refs; no DB FK
    superseded_by_dataset_id    uuid,
    created_at                  timestamptz                 NOT NULL DEFAULT now(),
    updated_at                  timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_ground_truth_dataset PRIMARY KEY (ground_truth_dataset_id),
    CONSTRAINT uq_ground_truth_dataset_entity_name_version UNIQUE (entity_type, entity_id, name, version),
    CONSTRAINT fk_ground_truth_dataset_superseded_by FOREIGN KEY (superseded_by_dataset_id)
        REFERENCES governance.ground_truth_dataset (ground_truth_dataset_id) ON DELETE SET NULL,
    CONSTRAINT ck_ground_truth_dataset_entity_kind CHECK (entity_type IN ('agent','task')),
    CONSTRAINT ck_ground_truth_dataset_counts_nonneg CHECK (record_count >= 0 AND annotated_count >= 0 AND authoritative_count >= 0),
    CONSTRAINT ck_ground_truth_dataset_iaa_range CHECK (iaa_score IS NULL OR (iaa_score >= 0 AND iaa_score <= 1)));
CREATE INDEX ix_ground_truth_dataset_entity ON governance.ground_truth_dataset (entity_type, entity_id);
CREATE INDEX ix_ground_truth_dataset_status ON governance.ground_truth_dataset (status);
CREATE INDEX ix_ground_truth_dataset_superseded_by ON governance.ground_truth_dataset (superseded_by_dataset_id);

CREATE TABLE governance.ground_truth_record (
    ground_truth_record_id      uuid                        NOT NULL DEFAULT uuidv7(),
    ground_truth_dataset_id     uuid                        NOT NULL,
    record_index                integer                     NOT NULL,
    source_type                 governance.gt_source_type   NOT NULL,
    source_provider             text,
    source_container            text,
    source_key                  text,
    source_description          text,
    input_data                  jsonb                       NOT NULL,
    tags                        text[]                      NOT NULL DEFAULT '{}',
    difficulty                  text,
    record_notes                text,
    created_at                  timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_ground_truth_record PRIMARY KEY (ground_truth_record_id),
    CONSTRAINT uq_ground_truth_record_dataset_index UNIQUE (ground_truth_dataset_id, record_index),
    CONSTRAINT fk_ground_truth_record_dataset FOREIGN KEY (ground_truth_dataset_id)
        REFERENCES governance.ground_truth_dataset (ground_truth_dataset_id) ON DELETE CASCADE);
CREATE INDEX ix_ground_truth_record_dataset ON governance.ground_truth_record (ground_truth_dataset_id);
CREATE INDEX ix_ground_truth_record_tags ON governance.ground_truth_record USING gin (tags);

CREATE TABLE governance.ground_truth_record_mock (
    ground_truth_record_mock_id uuid                    NOT NULL DEFAULT uuidv7(),
    ground_truth_record_id      uuid                    NOT NULL,
    mock_kind                   governance.mock_kind    NOT NULL DEFAULT 'tool',
    mock_key                    text                    NOT NULL,
    call_order                  integer                 NOT NULL DEFAULT 1,
    mock_response               jsonb                   NOT NULL,
    description                 text,
    created_at                  timestamptz             NOT NULL DEFAULT now(),
    CONSTRAINT pk_ground_truth_record_mock PRIMARY KEY (ground_truth_record_mock_id),
    CONSTRAINT fk_ground_truth_record_mock_record FOREIGN KEY (ground_truth_record_id)
        REFERENCES governance.ground_truth_record (ground_truth_record_id) ON DELETE CASCADE,
    CONSTRAINT ck_ground_truth_record_mock_call_order_positive CHECK (call_order >= 1));
CREATE INDEX ix_ground_truth_record_mock_record ON governance.ground_truth_record_mock (ground_truth_record_id);
CREATE INDEX ix_ground_truth_record_mock_record_kind ON governance.ground_truth_record_mock (ground_truth_record_id, mock_kind);

CREATE TABLE governance.ground_truth_annotation (
    ground_truth_annotation_id  uuid                        NOT NULL DEFAULT uuidv7(),
    ground_truth_record_id      uuid                        NOT NULL,
    ground_truth_dataset_id     uuid                        NOT NULL,
    annotator_type              governance.gt_annotator_type NOT NULL,
    labeled_by_user_id          uuid,                                  -- soft ref; no DB FK
    label_confidence            numeric(5,4),
    label_notes                 text,
    judge_model                 text,
    judge_prompt_version_id     uuid,                                  -- v1 hard FK -> soft ref (cross-domain)
    judge_reasoning             text,
    expected_output             jsonb                       NOT NULL,
    is_authoritative            boolean                     NOT NULL DEFAULT false,
    is_corrected                boolean                     NOT NULL DEFAULT false,
    original_output             jsonb,
    corrected_at                timestamptz,
    correction_reason           text,
    labeled_at                  timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_ground_truth_annotation PRIMARY KEY (ground_truth_annotation_id),
    CONSTRAINT fk_ground_truth_annotation_record FOREIGN KEY (ground_truth_record_id)
        REFERENCES governance.ground_truth_record (ground_truth_record_id) ON DELETE CASCADE,
    CONSTRAINT fk_ground_truth_annotation_dataset FOREIGN KEY (ground_truth_dataset_id)
        REFERENCES governance.ground_truth_dataset (ground_truth_dataset_id) ON DELETE CASCADE,
    CONSTRAINT ck_ground_truth_annotation_human_attribution
        CHECK (annotator_type NOT IN ('human_sme','adjudicator') OR labeled_by_user_id IS NOT NULL),
    CONSTRAINT ck_ground_truth_annotation_judge_attribution
        CHECK (annotator_type <> 'llm_judge' OR judge_model IS NOT NULL),
    CONSTRAINT ck_ground_truth_annotation_confidence_range
        CHECK (label_confidence IS NULL OR (label_confidence >= 0 AND label_confidence <= 1)));
CREATE INDEX ix_ground_truth_annotation_record ON governance.ground_truth_annotation (ground_truth_record_id);
CREATE INDEX ix_ground_truth_annotation_dataset ON governance.ground_truth_annotation (ground_truth_dataset_id);
CREATE INDEX ix_ground_truth_annotation_annotator_type ON governance.ground_truth_annotation (annotator_type);
-- V2-NEW DB invariant: at most one authoritative annotation per record.
CREATE UNIQUE INDEX uq_ground_truth_annotation_authoritative_per_record
    ON governance.ground_truth_annotation (ground_truth_record_id) WHERE is_authoritative = true;

-- ---- TIER-2 (runtime): VALIDATION RUN + PER-RECORD RESULT ------------------
CREATE TABLE runtime.validation_run (
    validation_run_id           uuid                            NOT NULL DEFAULT uuidv7(),
    entity_type                 governance.entity_type          NOT NULL,
    entity_version_id           uuid                            NOT NULL,  -- soft ref; no DB FK
    ground_truth_dataset_id     uuid                            NOT NULL,  -- soft ref Tier-1->Tier-2; no DB FK
    dataset_version             text,
    run_by_user_id              uuid,                                      -- soft ref; no DB FK
    precision_score             numeric(7,6),
    recall_score                numeric(7,6),
    f1_score                    numeric(7,6),
    cohens_kappa                numeric(7,6),
    confusion_matrix            jsonb,
    field_accuracy              jsonb,
    overall_extraction_rate     numeric(7,6),
    low_confidence_rate         numeric(7,6),
    fairness_metrics            jsonb,
    fairness_passed             boolean,
    fairness_notes              text,
    thresholds_met              boolean,
    threshold_details           jsonb,
    sme_review_notes            text,
    sme_reviewed_by_user_id     uuid,                                      -- soft ref; no DB FK
    sme_reviewed_at             timestamptz,
    inference_config_snapshot   jsonb,
    status                      governance.validation_run_status NOT NULL DEFAULT 'running',
    passed                      boolean,
    notes                       text,
    run_at                      timestamptz                     NOT NULL DEFAULT now(),
    CONSTRAINT pk_validation_run PRIMARY KEY (validation_run_id),
    CONSTRAINT ck_validation_run_entity_kind CHECK (entity_type IN ('agent','task')));
CREATE INDEX ix_validation_run_entity ON runtime.validation_run (entity_type, entity_version_id);
CREATE INDEX ix_validation_run_dataset ON runtime.validation_run (ground_truth_dataset_id);
CREATE INDEX brin_validation_run_run_at ON runtime.validation_run USING brin (run_at);

CREATE TABLE runtime.validation_record_result (
    validation_record_result_id uuid                            NOT NULL DEFAULT uuidv7(),
    validation_run_id           uuid                            NOT NULL,
    ground_truth_record_id      uuid                            NOT NULL,  -- soft ref Tier-1->Tier-2; no DB FK
    record_index                integer                         NOT NULL,
    expected_output             jsonb                           NOT NULL,
    actual_output               jsonb                           NOT NULL,
    confidence                  numeric(5,4),
    correct                     boolean                         NOT NULL,
    match_type                  governance.validation_match_type,
    match_score                 numeric(7,6),
    field_results               jsonb,
    decision_log_id             uuid,                                      -- soft ref -> agent_decision_log; no DB FK
    duration_ms                 integer,
    created_at                  timestamptz                     NOT NULL DEFAULT now(),
    CONSTRAINT pk_validation_record_result PRIMARY KEY (validation_record_result_id),
    CONSTRAINT uq_validation_record_result_run_index UNIQUE (validation_run_id, record_index),
    CONSTRAINT fk_validation_record_result_run FOREIGN KEY (validation_run_id)
        REFERENCES runtime.validation_run (validation_run_id) ON DELETE CASCADE,
    CONSTRAINT ck_validation_record_result_duration_nonneg CHECK (duration_ms IS NULL OR duration_ms >= 0),
    CONSTRAINT ck_validation_record_result_match_score_range CHECK (match_score IS NULL OR (match_score >= 0 AND match_score <= 1)));
CREATE INDEX ix_validation_record_result_run ON runtime.validation_record_result (validation_run_id);
CREATE INDEX ix_validation_record_result_run_correct ON runtime.validation_record_result (validation_run_id, correct);

-- ---- TIER-2 (runtime): EVALUATION RUN --------------------------------------
CREATE TABLE runtime.evaluation_run (
    evaluation_run_id           uuid                        NOT NULL DEFAULT uuidv7(),
    entity_type                 governance.entity_type      NOT NULL,
    entity_version_id           uuid                        NOT NULL,  -- soft ref; no DB FK
    evaluation_type             governance.evaluation_type  NOT NULL,
    run_period_start            timestamptz                 NOT NULL,
    run_period_end              timestamptz                 NOT NULL,
    champion_version_id         uuid,                                  -- soft ref; no DB FK
    total_invocations           integer                     NOT NULL DEFAULT 0,
    successful_invocations      integer                     NOT NULL DEFAULT 0,
    failed_invocations          integer                     NOT NULL DEFAULT 0,
    agreement_rate              numeric(7,6),
    disagreement_examples       jsonb,
    avg_duration_ms             numeric(10,2),
    avg_input_tokens            numeric(10,2),
    avg_output_tokens           numeric(10,2),
    override_count              integer                     NOT NULL DEFAULT 0,
    override_rate               numeric(7,6),
    override_pattern_flags      jsonb,
    metric_drift_detected       boolean                     NOT NULL DEFAULT false,
    drift_details               jsonb,
    promotion_recommendation    text,
    created_at                  timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_evaluation_run PRIMARY KEY (evaluation_run_id),
    CONSTRAINT ck_evaluation_run_period_order CHECK (run_period_end >= run_period_start),
    CONSTRAINT ck_evaluation_run_counts_nonneg CHECK (total_invocations >= 0 AND successful_invocations >= 0 AND failed_invocations >= 0 AND override_count >= 0));
CREATE INDEX ix_evaluation_run_entity ON runtime.evaluation_run (entity_type, entity_version_id);
CREATE INDEX brin_evaluation_run_created_at ON runtime.evaluation_run USING brin (created_at);

-- ---- TIER-1 (governance): MODEL CARD / METRIC THRESHOLD / FIELD CONFIG -----
CREATE TABLE governance.model_card (
    model_card_id               uuid                        NOT NULL DEFAULT uuidv7(),
    entity_type                 governance.entity_type      NOT NULL,
    entity_version_id           uuid                        NOT NULL,  -- soft ref; no DB FK
    card_version                integer                     NOT NULL DEFAULT 1,
    purpose                     text                        NOT NULL,
    design_rationale            text                        NOT NULL,
    inputs_description          text                        NOT NULL,
    outputs_description         text                        NOT NULL,
    known_limitations           text                        NOT NULL,
    conditions_of_use           text                        NOT NULL,
    lm_specific_limitations     text,
    prompt_sensitivity_notes    text,
    validated_by_user_id        uuid,                                  -- soft ref; no DB FK
    validation_run_id           uuid,                                  -- v1 hard FK -> soft ref (Tier-1->Tier-2)
    validation_notes            text,
    regulatory_notes            text,
    materiality_classification  text,
    approved_by_user_id         uuid,                                  -- soft ref; no DB FK
    approved_at                 timestamptz,
    card_state                  governance.model_card_state NOT NULL DEFAULT 'draft',
    created_at                  timestamptz                 NOT NULL DEFAULT now(),
    updated_at                  timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_model_card PRIMARY KEY (model_card_id),
    CONSTRAINT uq_model_card_entity_version_card_version UNIQUE (entity_type, entity_version_id, card_version),
    CONSTRAINT ck_model_card_entity_kind CHECK (entity_type IN ('agent','task')),
    CONSTRAINT ck_model_card_card_version_positive CHECK (card_version >= 1));
CREATE INDEX ix_model_card_entity ON governance.model_card (entity_type, entity_version_id);

CREATE TABLE governance.metric_threshold (
    metric_threshold_id     uuid                        NOT NULL DEFAULT uuidv7(),
    entity_type             governance.entity_type      NOT NULL,
    entity_id               uuid                        NOT NULL,  -- soft ref; no DB FK
    materiality_tier        governance.materiality_tier NOT NULL,
    metric_name             text                        NOT NULL,
    field_name              text,
    minimum_acceptable      numeric(7,6)                NOT NULL,
    target_champion         numeric(7,6)                NOT NULL,
    created_at              timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_metric_threshold PRIMARY KEY (metric_threshold_id),
    CONSTRAINT ck_metric_threshold_bounds CHECK (minimum_acceptable <= target_champion));
-- v1 nullable-field UNIQUE split into two partial unique indexes:
CREATE UNIQUE INDEX uq_metric_threshold_aggregate
    ON governance.metric_threshold (entity_type, entity_id, materiality_tier, metric_name) WHERE field_name IS NULL;
CREATE UNIQUE INDEX uq_metric_threshold_per_field
    ON governance.metric_threshold (entity_type, entity_id, materiality_tier, metric_name, field_name) WHERE field_name IS NOT NULL;
CREATE INDEX ix_metric_threshold_entity ON governance.metric_threshold (entity_type, entity_id);

CREATE TABLE governance.field_extraction_config (
    field_extraction_config_id  uuid                            NOT NULL DEFAULT uuidv7(),
    entity_type                 governance.entity_type          NOT NULL,
    entity_id                   uuid                            NOT NULL,  -- soft ref; no DB FK
    field_name                  text                            NOT NULL,
    field_type                  governance.extraction_field_type NOT NULL,
    match_type                  governance.extraction_match_type NOT NULL,
    tolerance_value             numeric(10,4),
    tolerance_unit              governance.tolerance_unit,
    is_required                 boolean                         NOT NULL DEFAULT true,
    created_at                  timestamptz                     NOT NULL DEFAULT now(),
    CONSTRAINT pk_field_extraction_config PRIMARY KEY (field_extraction_config_id),
    CONSTRAINT uq_field_extraction_config_entity_field UNIQUE (entity_type, entity_id, field_name),
    CONSTRAINT ck_field_extraction_config_task_only CHECK (entity_type = 'task'),
    CONSTRAINT ck_field_extraction_config_tolerance_unit_when_numeric
        CHECK (match_type <> 'numeric_tolerance' OR tolerance_unit IS NOT NULL));
CREATE INDEX ix_field_extraction_config_entity ON governance.field_extraction_config (entity_type, entity_id);

-- ---- TIER-2 (runtime): DESCRIPTION SIMILARITY LOG --------------------------
CREATE TABLE runtime.description_similarity_log (
    description_similarity_log_id uuid                      NOT NULL DEFAULT uuidv7(),
    checked_entity_type         governance.entity_type      NOT NULL,
    checked_entity_id           uuid                        NOT NULL,  -- soft ref; no DB FK
    checked_entity_name         text                        NOT NULL,
    similar_entity_type         governance.entity_type      NOT NULL,
    similar_entity_id           uuid                        NOT NULL,  -- soft ref; no DB FK
    similar_entity_name         text                        NOT NULL,
    similarity_score            numeric(7,6)                NOT NULL,
    flagged                     boolean GENERATED ALWAYS AS (similarity_score > 0.85) STORED,
    reviewed_at                 timestamptz,
    reviewed_by_user_id         uuid,                                  -- soft ref; no DB FK
    resolution                  text,
    resolution_notes            text,
    checked_at                  timestamptz                 NOT NULL DEFAULT now(),
    CONSTRAINT pk_description_similarity_log PRIMARY KEY (description_similarity_log_id),
    CONSTRAINT ck_description_similarity_log_score_range CHECK (similarity_score >= 0 AND similarity_score <= 1));
CREATE INDEX ix_description_similarity_log_checked_entity ON runtime.description_similarity_log (checked_entity_type, checked_entity_id);
CREATE INDEX brin_description_similarity_log_checked_at ON runtime.description_similarity_log USING brin (checked_at);

-- ---- TIER-1 (governance): INCIDENT -----------------------------------------
CREATE TABLE governance.incident (
    incident_id             uuid                            NOT NULL DEFAULT uuidv7(),
    entity_type             governance.entity_type          NOT NULL,
    entity_id               uuid                            NOT NULL,  -- soft ref; no DB FK
    entity_version_id       uuid,                                      -- soft ref; no DB FK
    title                   text                            NOT NULL,
    description             text                            NOT NULL,
    severity                governance.incident_severity    NOT NULL,
    detection_source        text,
    detected_at             timestamptz                     NOT NULL DEFAULT now(),
    affected_context_ids    uuid[]                          NOT NULL DEFAULT '{}',  -- soft refs; no DB FK
    affected_decision_count integer                         NOT NULL DEFAULT 0,
    rollback_executed       boolean                         NOT NULL DEFAULT false,
    rollback_to_version_id  uuid,                                      -- soft ref; no DB FK
    rollback_at             timestamptz,
    rollback_approved_by_user_id uuid,                                 -- soft ref; no DB FK
    resolution_notes        text,
    new_test_cases_added    integer                         NOT NULL DEFAULT 0,
    resolved_at             timestamptz,
    status                  governance.incident_status      NOT NULL DEFAULT 'open',
    created_at              timestamptz                     NOT NULL DEFAULT now(),
    CONSTRAINT pk_incident PRIMARY KEY (incident_id),
    CONSTRAINT ck_incident_title_not_blank CHECK (length(btrim(title)) > 0),
    CONSTRAINT ck_incident_counts_nonneg CHECK (affected_decision_count >= 0 AND new_test_cases_added >= 0),
    CONSTRAINT ck_incident_rollback_target_when_executed CHECK (rollback_executed = false OR rollback_to_version_id IS NOT NULL));
CREATE INDEX ix_incident_entity ON governance.incident (entity_type, entity_id);
CREATE INDEX ix_incident_status ON governance.incident (status);
CREATE INDEX ix_incident_severity ON governance.incident (severity);

-- ---- TIER-1 (governance): PLATFORM SETTINGS --------------------------------
CREATE TABLE governance.platform_settings (
    platform_settings_id    uuid                            NOT NULL DEFAULT uuidv7(),
    setting_key             text                            NOT NULL,  -- v1 reserved-word `key`
    setting_value           text                            NOT NULL,  -- v1 `value`
    category                text                            NOT NULL DEFAULT 'general',
    display_name            text,
    description             text,
    input_type              governance.setting_input_type   NOT NULL DEFAULT 'text',
    options                 text,
    sort_order              integer                         NOT NULL DEFAULT 0,
    updated_at              timestamptz                     NOT NULL DEFAULT now(),
    CONSTRAINT pk_platform_settings PRIMARY KEY (platform_settings_id),
    CONSTRAINT uq_platform_settings_setting_key UNIQUE (setting_key),
    CONSTRAINT ck_platform_settings_key_not_blank CHECK (length(btrim(setting_key)) > 0),
    CONSTRAINT ck_platform_settings_options_when_select CHECK (input_type <> 'select' OR options IS NOT NULL));
CREATE INDEX ix_platform_settings_category ON governance.platform_settings (category, sort_order);

-- ---- ANALYTICS VIEW (resolves C10) -----------------------------------------
CREATE VIEW analytics.v_validation_result AS
SELECT tel.test_execution_log_id, tel.test_suite_id, tel.test_case_id, tel.entity_type,
       tel.entity_version_id, tel.mock_mode, tel.channel, tel.metric_type, tel.metric_result,
       tel.passed, tel.failure_reason, tel.duration_ms, tel.run_at
FROM runtime.test_execution_log AS tel;
COMMENT ON VIEW analytics.v_validation_result IS
    'Resolves ASSEMBLY C10: logical-mart projection over runtime.test_execution_log. Source table now exists (C9 closure).';

-- ############ DEFERRED CROSS-DOMAIN FKs ############
-- =====================================================================
-- FINAL SECTION — Deferred cross-domain FOREIGN KEY constraints.
-- Emitted LAST, after every table in every schema exists. These FKs
-- could not be declared inline because the referenced table is owned by
-- a domain that loads AFTER the referring table (see
-- ASSEMBLY-AND-VERIFICATION.md §C items 16-20, §D item 21, §E).
-- =====================================================================

-- ---------------------------------------------------------------------
-- §C16. intake_obligation -> compliance (compliance loads at step 14,
--       after intake at step 13). Three deferred FKs.
-- ---------------------------------------------------------------------
ALTER TABLE governance.intake_obligation
  ADD CONSTRAINT fk_intake_obligation_canonical_requirement
    FOREIGN KEY (canonical_requirement_id)
    REFERENCES compliance.canonical_requirement (canonical_requirement_id)
    ON DELETE RESTRICT;

ALTER TABLE governance.intake_obligation
  ADD CONSTRAINT fk_intake_obligation_governance_domain
    FOREIGN KEY (governance_domain_id)
    REFERENCES compliance.governance_domain (governance_domain_id)
    ON DELETE RESTRICT;

ALTER TABLE governance.intake_obligation
  ADD CONSTRAINT fk_intake_obligation_requirement_tier
    FOREIGN KEY (target_requirement_tier_id)
    REFERENCES compliance.requirement_tier (requirement_tier_id)
    ON DELETE RESTRICT;

-- ---------------------------------------------------------------------
-- §C18. app_team_role_grant.application_id -> application.
--       auth (step 10) left this FK commented ("application owned
--       elsewhere"); intake.application now exists (step 13).
-- ---------------------------------------------------------------------
ALTER TABLE governance.app_team_role_grant
  ADD CONSTRAINT fk_app_team_role_grant_application
    FOREIGN KEY (application_id)
    REFERENCES governance.application (application_id)
    ON DELETE RESTRICT;

-- ---------------------------------------------------------------------
-- §C19 + §E4. packages_deploy attribution columns -> identity table
--       (account_user, owned by auth). Columns renamed to *_user_id per
--       §E4. deployment.actor_user_id is NOT NULL -> RESTRICT; the three
--       created_by_user_id columns are nullable -> SET NULL acceptable.
-- ---------------------------------------------------------------------
ALTER TABLE governance.deployment
  ADD CONSTRAINT fk_deployment_actor_user
    FOREIGN KEY (actor_user_id)
    REFERENCES governance.account_user (account_user_id)
    ON DELETE RESTRICT;

ALTER TABLE governance.harness_image
  ADD CONSTRAINT fk_harness_image_created_by_user
    FOREIGN KEY (created_by_user_id)
    REFERENCES governance.account_user (account_user_id)
    ON DELETE SET NULL;

ALTER TABLE governance.package
  ADD CONSTRAINT fk_package_created_by_user
    FOREIGN KEY (created_by_user_id)
    REFERENCES governance.account_user (account_user_id)
    ON DELETE SET NULL;

ALTER TABLE governance.package_harness_image
  ADD CONSTRAINT fk_package_harness_image_created_by_user
    FOREIGN KEY (created_by_user_id)
    REFERENCES governance.account_user (account_user_id)
    ON DELETE SET NULL;

-- ---------------------------------------------------------------------
-- §C20 + §C5. intake_requirement.embedding_model_id -> embedding_config.
--       Schema mismatch resolved: embedding_config is owned by reporting
--       in the compliance schema (compliance.embedding_config), which
--       loads at step 15 AFTER intake (step 13). Deferred.
-- ---------------------------------------------------------------------
ALTER TABLE governance.intake_requirement
  ADD CONSTRAINT fk_intake_requirement_embedding_config
    FOREIGN KEY (embedding_model_id)
    REFERENCES compliance.embedding_config (embedding_config_id)
    ON DELETE RESTRICT;

-- ---------------------------------------------------------------------
-- §D21. Drop the mutable champion-pointer columns. champion_assignment
--       + entity_champion_current (lifecycle_approvals) is the single
--       append-only source of truth; agent/task must not carry a second
--       writable "current champion". Emitted here as DROPs in case they
--       were not already removed from the entities fragment body.
-- ---------------------------------------------------------------------
ALTER TABLE governance.agent DROP CONSTRAINT IF EXISTS fk_agent_current_champion;
ALTER TABLE governance.agent DROP COLUMN IF EXISTS current_champion_version_id;
ALTER TABLE governance.task DROP CONSTRAINT IF EXISTS fk_task_current_champion;
ALTER TABLE governance.task DROP COLUMN IF EXISTS current_champion_version_id;

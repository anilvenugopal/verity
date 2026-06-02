-- =====================================================================
-- 00-reference.sql — Verity v2 hardened schema · REFERENCE vocabularies
-- Re-applied from DESIGN-DECISIONS.md (D1, D1-amend, D2, D3, D9).
-- Schemas: reference (vocab) / core (Tier-1 SoR) / audit (Tier-2 logs).
-- Target: PostgreSQL 18+ (native uuidv7()). PG<18: install the pg_uuidv7
--   extension and expose uuidv7() on search_path (NEVER a gen_random_uuid wrapper).
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid() (non-PK uses only)
CREATE EXTENSION IF NOT EXISTS vector;      -- pgvector embeddings (similarity)

CREATE SCHEMA IF NOT EXISTS reference;  -- controlled vocabularies (D1)
CREATE SCHEMA IF NOT EXISTS core;       -- Tier-1 system-of-record (D3)
CREATE SCHEMA IF NOT EXISTS audit;      -- Tier-2 append-only bulk logs (D3)

SET search_path = core, reference, audit, public;

-- ---------------------------------------------------------------------
-- REFERENCE-TABLE PATTERN (every controlled vocabulary; D1 + D1-amend + D9/SKOS)
--   code         text  PK     -- stable machine key + FK target + IRI fragment
--   label        text         -- FE display
--   description  text
--   sort_order   int          -- FE ordering
--   grouping     text         -- optional FE bucket
--   parent_code  text -> self -- hierarchy (= skos:broader/narrower)
--   effective_start_date / effective_end_date  -- validity window (D1-amend);
--                                                  retire = close the window
--   is_active    bool         -- convenience flag (= effective_end_date IS NULL)
--   metadata     jsonb        -- icon/color/extra FE attrs
--   created_at / updated_at
-- Referencing columns elsewhere:  <vocab>_code text -> reference.<vocab>(code)
-- One row per code (code is PK & FK target); in-place label edits are not
-- version-tracked (rare; retire+replace if needed).  Seeds carry v1 enum
-- members verbatim (no silent capability loss).
-- More vocabularies are added to this file as each domain is re-applied.
-- ---------------------------------------------------------------------

-- ===== actor_type =====================================================
CREATE TABLE reference.actor_type (
    code                 text        NOT NULL,
    label                text        NOT NULL,
    description          text,
    sort_order           integer     NOT NULL,
    grouping             text,
    parent_code          text,
    effective_start_date date        NOT NULL DEFAULT current_date,
    effective_end_date   date,
    is_active            boolean      NOT NULL DEFAULT true,
    metadata             jsonb        NOT NULL DEFAULT '{}'::jsonb,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_actor_type PRIMARY KEY (code),
    CONSTRAINT fk_actor_type_parent FOREIGN KEY (parent_code)
        REFERENCES reference.actor_type (code) ON DELETE RESTRICT,
    CONSTRAINT uq_actor_type_sort UNIQUE (sort_order),
    CONSTRAINT ck_actor_type_effective CHECK (effective_end_date IS NULL OR effective_end_date >= effective_start_date)
);
COMMENT ON TABLE reference.actor_type IS 'Vocabulary: kind of actor (human vs machine). D1/D6.';
INSERT INTO reference.actor_type (code, label, sort_order) VALUES
    ('human',      'Human user',        1),
    ('automation', 'Automation / agent', 2);

-- ===== role ===========================================================
-- Collapses v1 studio_role + platform_role (identical). approval_role becomes
-- the is_approval_role flag (the 7 that may sign off). D1 notable consequences.
CREATE TABLE reference.role (
    code                 text        NOT NULL,
    label                text        NOT NULL,
    description          text,
    sort_order           integer     NOT NULL,
    grouping             text,        -- governance | engineering | oversight
    parent_code          text,
    is_approval_role     boolean      NOT NULL DEFAULT false,  -- may sign off on approvals
    effective_start_date date        NOT NULL DEFAULT current_date,
    effective_end_date   date,
    is_active            boolean      NOT NULL DEFAULT true,
    metadata             jsonb        NOT NULL DEFAULT '{}'::jsonb,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_role PRIMARY KEY (code),
    CONSTRAINT fk_role_parent FOREIGN KEY (parent_code)
        REFERENCES reference.role (code) ON DELETE RESTRICT,
    CONSTRAINT uq_role_sort UNIQUE (sort_order),
    CONSTRAINT ck_role_effective CHECK (effective_end_date IS NULL OR effective_end_date >= effective_start_date)
);
COMMENT ON TABLE reference.role IS 'Vocabulary: platform/governance roles (v1 studio_role+platform_role collapsed). is_approval_role = v1 approval_role subset. D1.';
INSERT INTO reference.role (code, label, sort_order, grouping, is_approval_role) VALUES
    ('business_owner', 'Business Owner', 1, 'governance',  true),
    ('compliance',     'Compliance',     2, 'oversight',   true),
    ('legal',          'Legal',          3, 'oversight',   true),
    ('model_risk',     'Model Risk',     4, 'oversight',   true),
    ('ai_governance',  'AI Governance',  5, 'governance',  true),
    ('security',       'Security',       6, 'oversight',   true),
    ('privacy',        'Privacy',        7, 'oversight',   true),
    ('engineer',       'Engineer',       8, 'engineering', false),
    ('auditor',        'Auditor',        9, 'oversight',   false),
    ('viewer',         'Viewer',        10, 'governance',  false);

-- NOTE: app_team_role (per-application: app_demo_owner/sre/dev/lead/ops) is added
-- with the intake/application domain (it pairs with application-scoped grants).

-- =====================================================================
-- REGISTRY-domain vocabularies (used by 02-registry.sql)
-- All follow the reference pattern; columns elided for brevity are the
-- standard set (description, grouping, parent_code, effective_*, is_active,
-- metadata, created_at/updated_at). Helper below keeps them consistent.
-- =====================================================================

-- executable_kind carries two extra typed columns (packaging is gated by these; D5/D8)
CREATE TABLE reference.executable_kind (
    code                 text        NOT NULL,
    label                text        NOT NULL,
    description          text,
    sort_order           integer      NOT NULL,
    is_packaged          boolean      NOT NULL DEFAULT true,   -- does a champion of this kind produce a package?
    package_format       text,                                  -- e.g. 'vtx','vax' (NULL when not packaged)
    effective_start_date date        NOT NULL DEFAULT current_date,
    effective_end_date   date,
    is_active            boolean      NOT NULL DEFAULT true,
    metadata             jsonb        NOT NULL DEFAULT '{}'::jsonb,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_executable_kind PRIMARY KEY (code),
    CONSTRAINT uq_executable_kind_sort UNIQUE (sort_order)
);
COMMENT ON TABLE reference.executable_kind IS 'Vocabulary: kinds of executable (agent, task, future). is_packaged/package_format decouple "governed" from "packaged" (D5/D8). New kind = new row, no schema change.';
INSERT INTO reference.executable_kind (code, label, sort_order, is_packaged, package_format) VALUES
    ('agent', 'Agent', 1, true, 'vax'),
    ('task',  'Task',  2, true, 'vtx');

-- Compact vocab tables (standard pattern). code PK, sort_order unique, effective window.
CREATE TABLE reference.capability_type (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_capability_type PRIMARY KEY (code), CONSTRAINT uq_capability_type_sort UNIQUE (sort_order));
INSERT INTO reference.capability_type (code, label, sort_order) VALUES
    ('classification',1),('extraction',2),('generation',3),('summarisation',4),('matching',5),('validation',6);

CREATE TABLE reference.trust_level (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_trust_level PRIMARY KEY (code), CONSTRAINT uq_trust_level_sort UNIQUE (sort_order));
INSERT INTO reference.trust_level (code, label, sort_order) VALUES
    ('trusted',1),('conditional',2),('sandboxed',3),('blocked',4);

CREATE TABLE reference.data_classification (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_data_classification PRIMARY KEY (code), CONSTRAINT uq_data_classification_sort UNIQUE (sort_order));
INSERT INTO reference.data_classification (code, label, sort_order) VALUES
    ('tier1_public',1),('tier2_internal',2),('tier3_confidential',3),('tier4_pii_restricted',4);

CREATE TABLE reference.governance_tier (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_governance_tier PRIMARY KEY (code), CONSTRAINT uq_governance_tier_sort UNIQUE (sort_order));
INSERT INTO reference.governance_tier (code, label, sort_order) VALUES
    ('behavioural',1),('contextual',2),('formatting',3);

CREATE TABLE reference.version_change_type (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_version_change_type PRIMARY KEY (code), CONSTRAINT uq_version_change_type_sort UNIQUE (sort_order));
INSERT INTO reference.version_change_type (code, label, sort_order) VALUES
    ('major',1),('minor',2),('patch',3);

CREATE TABLE reference.api_role (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_api_role PRIMARY KEY (code), CONSTRAINT uq_api_role_sort UNIQUE (sort_order));
INSERT INTO reference.api_role (code, label, sort_order) VALUES
    ('system',1),('user',2),('assistant_prefill',3);

CREATE TABLE reference.tool_transport (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_tool_transport PRIMARY KEY (code), CONSTRAINT uq_tool_transport_sort UNIQUE (sort_order));
INSERT INTO reference.tool_transport (code, label, sort_order) VALUES
    ('python_inprocess',1),('mcp',2),('http',3);

-- Source/Target Binding kinds (binding-grammar). `vault` is NO LONGER a kind — it is a
-- connector_type. A storage_object is a file in any backend, resolved via a connector.
CREATE TABLE reference.source_kind (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_source_kind PRIMARY KEY (code), CONSTRAINT uq_source_kind_sort UNIQUE (sort_order));
INSERT INTO reference.source_kind (code, label, sort_order) VALUES
    ('storage_object',1),  -- a file/object in a storage backend (via connector)
    ('task_output',2),     -- output of a prior task in the workflow
    ('structured',3),      -- a structured payload resolved from elsewhere
    ('inline_content',4);  -- literal inline content

CREATE TABLE reference.target_kind (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_target_kind PRIMARY KEY (code), CONSTRAINT uq_target_kind_sort UNIQUE (sort_order));
INSERT INTO reference.target_kind (code, label, sort_order) VALUES
    ('storage_object',1),('task_output',2),('structured',3);

-- connector_type: the storage/data backend a connector talks to (extensible).
CREATE TABLE reference.connector_type (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_connector_type PRIMARY KEY (code), CONSTRAINT uq_connector_type_sort UNIQUE (sort_order));
INSERT INTO reference.connector_type (code, label, sort_order, grouping) VALUES
    ('vault','Verity Vault',1,'object_store'),('s3','AWS S3',2,'object_store'),
    ('azure_blob','Azure Blob',3,'object_store'),('gcs','Google Cloud Storage',4,'object_store'),
    ('sharepoint','SharePoint',5,'document'),('filesystem','Filesystem',6,'file'),
    ('http','HTTP/URL',7,'web'),('database','Database',8,'database');

-- binding_delivery_mode: HOW a resolved source/target is delivered (the fix for base64-only).
CREATE TABLE reference.binding_delivery_mode (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_binding_delivery_mode PRIMARY KEY (code), CONSTRAINT uq_binding_delivery_mode_sort UNIQUE (sort_order));
INSERT INTO reference.binding_delivery_mode (code, label, sort_order, description) VALUES
    ('inline','Inline content',1,'base64/text content block (vision/small files)'),
    ('reference','By reference',2,'signed URL / object handle; tool streams it (large files)'),
    ('download','Download to workdir',3,'harness fetches the file to the run working dir'),
    ('extracted','Extracted to structured',4,'parse the file into structured fields'),
    ('write_file','Write file',5,'target: write the output as a file to the backend');

-- write_mode: how a target write places the object.
CREATE TABLE reference.write_mode (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_write_mode PRIMARY KEY (code), CONSTRAINT uq_write_mode_sort UNIQUE (sort_order));
INSERT INTO reference.write_mode (code, label, sort_order) VALUES
    ('create',1),('overwrite',2),('create_or_version',3);

-- ===== LIFECYCLE-domain vocabularies (used by 03-lifecycle.sql) =======
-- lifecycle_state: the 7-state progression (sort_order = order). is_deployable /
-- is_terminal as typed flags; per-state deployment rules live in 08 (matrix).
CREATE TABLE reference.lifecycle_state (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    is_deployable boolean NOT NULL DEFAULT false, is_terminal boolean NOT NULL DEFAULT false,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_lifecycle_state PRIMARY KEY (code), CONSTRAINT uq_lifecycle_state_sort UNIQUE (sort_order));
COMMENT ON TABLE reference.lifecycle_state IS 'Vocabulary: the 6-state executable lifecycle (v1 7-state CHANGED: shadow folded into a challenger run-mode). sort_order = progression. deprecated is_terminal=false (restorable via rollback). Deployment rules per state in 08 (lifecycle_deployment_rule).';
INSERT INTO reference.lifecycle_state (code, label, sort_order, is_deployable, is_terminal, grouping) VALUES
    ('draft','Draft',1,false,false,'authoring'),
    ('candidate','Candidate',2,false,false,'authoring'),
    ('staging','Staging',3,true,false,'pre_prod'),
    ('challenger','Challenger',4,true,false,'prod'),    -- deploys in shadow OR ab run-mode
    ('champion','Champion',5,true,false,'prod'),
    ('deprecated','Deprecated',6,true,false,'retired'); -- restorable via rollback (deprecated -> champion/challenger)

CREATE TABLE reference.approval_request_kind (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_approval_request_kind PRIMARY KEY (code), CONSTRAINT uq_approval_request_kind_sort UNIQUE (sort_order));
INSERT INTO reference.approval_request_kind (code, label, sort_order) VALUES
    ('intake',1),('risk_reclassification',2),('promote_candidate',3),('promote_champion',4),('retire',5);

CREATE TABLE reference.approval_request_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_approval_request_status PRIMARY KEY (code), CONSTRAINT uq_approval_request_status_sort UNIQUE (sort_order));
INSERT INTO reference.approval_request_status (code, label, sort_order) VALUES
    ('pending',1),('approved',2),('rejected',3),('cancelled',4);

CREATE TABLE reference.approval_decision (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_approval_decision PRIMARY KEY (code), CONSTRAINT uq_approval_decision_sort UNIQUE (sort_order));
INSERT INTO reference.approval_decision (code, label, sort_order) VALUES
    ('approved',1),('rejected',2),('requested_changes',3),('abstained',4);

-- ===== INTAKE-domain vocabularies (used by 04-intake.sql) =============
CREATE TABLE reference.intake_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_intake_status PRIMARY KEY (code), CONSTRAINT uq_intake_status_sort UNIQUE (sort_order));
INSERT INTO reference.intake_status (code, label, sort_order) VALUES
    ('proposed',1),('in_review',2),('impact_assessment',3),('approved',4),('in_build',5),('live',6),('rejected',7),('retired',8);

-- ai_risk_tier: ordered classification (minimal < limited < high < unacceptable)
CREATE TABLE reference.ai_risk_tier (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_ai_risk_tier PRIMARY KEY (code), CONSTRAINT uq_ai_risk_tier_sort UNIQUE (sort_order));
INSERT INTO reference.ai_risk_tier (code, label, sort_order) VALUES
    ('minimal',1),('limited',2),('high',3),('unacceptable',4);

CREATE TABLE reference.naic_materiality (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_naic_materiality PRIMARY KEY (code), CONSTRAINT uq_naic_materiality_sort UNIQUE (sort_order));
INSERT INTO reference.naic_materiality (code, label, sort_order) VALUES ('material',1),('non_material',2);

-- materiality_tier: ordered materiality scale. NOTE: confirm members against v1.
CREATE TABLE reference.materiality_tier (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_materiality_tier PRIMARY KEY (code), CONSTRAINT uq_materiality_tier_sort UNIQUE (sort_order));
INSERT INTO reference.materiality_tier (code, label, sort_order) VALUES ('low',1),('medium',2),('high',3),('critical',4);

CREATE TABLE reference.requirement_kind (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_requirement_kind PRIMARY KEY (code), CONSTRAINT uq_requirement_kind_sort UNIQUE (sort_order));
INSERT INTO reference.requirement_kind (code, label, sort_order) VALUES
    ('business',1),('functional',2),('non_functional',3),('compliance',4);

CREATE TABLE reference.requirement_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_requirement_status PRIMARY KEY (code), CONSTRAINT uq_requirement_status_sort UNIQUE (sort_order));
INSERT INTO reference.requirement_status (code, label, sort_order) VALUES
    ('draft',1),('approved',2),('implemented',3),('verified',4),('deprecated',5);

CREATE TABLE reference.artifact_plan_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_artifact_plan_status PRIMARY KEY (code), CONSTRAINT uq_artifact_plan_status_sort UNIQUE (sort_order));
INSERT INTO reference.artifact_plan_status (code, label, sort_order) VALUES
    ('proposed',1),('in_progress',2),('realized',3),('cancelled',4);

-- app_team_role: per-application team roles (D1; pairs with actor_app_role_grant). v2-new.
CREATE TABLE reference.app_team_role (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_app_team_role PRIMARY KEY (code), CONSTRAINT uq_app_team_role_sort UNIQUE (sort_order));
INSERT INTO reference.app_team_role (code, label, sort_order) VALUES
    ('app_demo_owner',1),('app_demo_lead',2),('app_demo_dev',3),('app_demo_sre',4),('app_demo_ops',5);

-- derivation_method: provenance of a resolved obligation / mapping (D9; generalizes v1 mapping_source).
CREATE TABLE reference.derivation_method (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_derivation_method PRIMARY KEY (code), CONSTRAINT uq_derivation_method_sort UNIQUE (sort_order));
INSERT INTO reference.derivation_method (code, label, sort_order, description) VALUES
    ('manual','Manual',1,'authored by a human directly'),
    ('reasoner_recommended','Reasoner-recommended',2,'inferred by the ontology/reasoner; pending validation (ADR-0009)'),
    ('human_validated','Human-validated',3,'reasoner/LLM recommendation reviewed & accepted by a human');

-- ===== COMPLIANCE-domain vocabularies (used by 05-compliance.sql) =====
-- governance_domain: the AI-governance areas (maturity is scored per domain). NOTE: confirm set vs v1.
CREATE TABLE reference.governance_domain (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_governance_domain PRIMARY KEY (code),
    CONSTRAINT fk_governance_domain_parent FOREIGN KEY (parent_code) REFERENCES reference.governance_domain (code),
    CONSTRAINT uq_governance_domain_sort UNIQUE (sort_order));
COMMENT ON TABLE reference.governance_domain IS 'Vocabulary: AI-governance domains; unit of maturity scoring (D7). parent_code allows sub-domains.';
INSERT INTO reference.governance_domain (code, label, sort_order) VALUES
    ('model_risk',1),('fairness',2),('privacy',3),('security',4),('transparency',5),
    ('robustness',6),('data_governance',7),('human_oversight',8),('accountability',9);

CREATE TABLE reference.control_phase (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_control_phase PRIMARY KEY (code), CONSTRAINT uq_control_phase_sort UNIQUE (sort_order));
INSERT INTO reference.control_phase (code, label, sort_order, description) VALUES
    ('design_time','Design-time',1,'when an asset/schema/pipeline is defined'),
    ('deploy_time','Deploy-time',2,'when promoting to production'),
    ('static_model','Static / model',3,'continuous on the model/artifact (AI analog of data-at-rest)'),
    ('execution','Execution',4,'during runtime (AI analog of data-in-motion)');

CREATE TABLE reference.control_type (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_control_type PRIMARY KEY (code), CONSTRAINT uq_control_type_sort UNIQUE (sort_order));
INSERT INTO reference.control_type (code, label, sort_order) VALUES
    ('preventive',1),('detective',2),('corrective',3),('directive',4);

CREATE TABLE reference.enforcement_action (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_enforcement_action PRIMARY KEY (code), CONSTRAINT uq_enforcement_action_sort UNIQUE (sort_order));
INSERT INTO reference.enforcement_action (code, label, sort_order) VALUES
    ('block',1),('refuse',2),('suppress_write',3),('warn',4),('log_only',5);

CREATE TABLE reference.evidence_artifact_type (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_evidence_artifact_type PRIMARY KEY (code), CONSTRAINT uq_evidence_artifact_type_sort UNIQUE (sort_order));
INSERT INTO reference.evidence_artifact_type (code, label, sort_order) VALUES
    ('config_snapshot',1),('model_card',2),('package_manifest',3),('approval_record',4),('test_result',5),
    ('validation_report',6),('decision_log',7),('binding_resolution',8),('deployment_record',9),('document',10);

CREATE TABLE reference.coverage_level (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_coverage_level PRIMARY KEY (code), CONSTRAINT uq_coverage_level_sort UNIQUE (sort_order));
INSERT INTO reference.coverage_level (code, label, sort_order) VALUES
    ('full',1),('substantial',2),('partial',3),('gap',4);

CREATE TABLE reference.exception_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_exception_status PRIMARY KEY (code), CONSTRAINT uq_exception_status_sort UNIQUE (sort_order));
INSERT INTO reference.exception_status (code, label, sort_order) VALUES
    ('requested',1),('approved',2),('rejected',3),('revoked',4),('expired',5);

-- Further vocabularies (deployment_channel, run_mode, environment_kind, quota_*, …)
-- are appended here as their domains are re-applied.

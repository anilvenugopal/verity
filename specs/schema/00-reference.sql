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

-- ===== DECISIONS-domain vocabularies (used by 06-decisions.sql) =======
-- (decision_status, invocation_status, auth_event_type/outcome stay NATIVE enums per D1 —
--  hot-path/Tier-2 internal; declared in 06-decisions. model_status + currency are vocab.)
CREATE TABLE reference.model_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_model_status PRIMARY KEY (code), CONSTRAINT uq_model_status_sort UNIQUE (sort_order));
INSERT INTO reference.model_status (code, label, sort_order) VALUES ('active',1),('deprecated',2),('retired',3);

CREATE TABLE reference.currency (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_currency PRIMARY KEY (code), CONSTRAINT uq_currency_sort UNIQUE (sort_order));
INSERT INTO reference.currency (code, label, sort_order) VALUES ('usd','US Dollar',1),('eur','Euro',2),('gbp','British Pound',3);

-- ===== RUNS/QUOTAS-domain vocabularies (used by 07-runs.sql) ==========
-- (run_status, run_completion_status, run_entity_kind, outbox_status stay NATIVE enums
--  per D1 — hot-path dispatch state; declared in 07-runs.)
CREATE TABLE reference.run_purpose (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_run_purpose PRIMARY KEY (code), CONSTRAINT uq_run_purpose_sort UNIQUE (sort_order));
INSERT INTO reference.run_purpose (code, label, sort_order) VALUES
    ('production',1),('test',2),('validation',3),('audit_rerun',4);

CREATE TABLE reference.quota_scope_type (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_quota_scope_type PRIMARY KEY (code), CONSTRAINT uq_quota_scope_type_sort UNIQUE (sort_order));
INSERT INTO reference.quota_scope_type (code, label, sort_order) VALUES
    ('application',1),('agent',2),('task',3),('model',4);

CREATE TABLE reference.quota_period (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_quota_period PRIMARY KEY (code), CONSTRAINT uq_quota_period_sort UNIQUE (sort_order));
INSERT INTO reference.quota_period (code, label, sort_order) VALUES ('daily',1),('weekly',2),('monthly',3);

-- enforcement is per-quota configurable: soft (warn, never refuse) default, or hard (refuse). D-clarify.
CREATE TABLE reference.quota_enforcement_mode (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_quota_enforcement_mode PRIMARY KEY (code), CONSTRAINT uq_quota_enforcement_mode_sort UNIQUE (sort_order));
INSERT INTO reference.quota_enforcement_mode (code, label, sort_order, description) VALUES
    ('soft','Soft (warn only)',1,'record warning/breach; never refuse the run'),
    ('hard','Hard-stop',2,'refuse the run when the budget is exceeded (execution-phase control)');

CREATE TABLE reference.quota_alert_level (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_quota_alert_level PRIMARY KEY (code), CONSTRAINT uq_quota_alert_level_sort UNIQUE (sort_order));
INSERT INTO reference.quota_alert_level (code, label, sort_order) VALUES ('warning',1),('exceeded',2),('critical',3);

-- ===== DEPLOY-domain vocabularies (used by 08-deploy.sql) =============
CREATE TABLE reference.harness_variant (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_harness_variant PRIMARY KEY (code), CONSTRAINT uq_harness_variant_sort UNIQUE (sort_order));
COMMENT ON TABLE reference.harness_variant IS 'Vocabulary: harness execution-engine variant (the kind of container/runtime). D8.';
INSERT INTO reference.harness_variant (code, label, sort_order, description) VALUES
    ('claude_agentic_loop','Claude agentic loop',1,'current default agent/task execution engine');

CREATE TABLE reference.environment_kind (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_environment_kind PRIMARY KEY (code), CONSTRAINT uq_environment_kind_sort UNIQUE (sort_order));
INSERT INTO reference.environment_kind (code, label, sort_order) VALUES ('non_prod',1),('prod',2),('ephemeral',3);

CREATE TABLE reference.deployment_channel (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_channel PRIMARY KEY (code), CONSTRAINT uq_deployment_channel_sort UNIQUE (sort_order));
INSERT INTO reference.deployment_channel (code, label, sort_order) VALUES
    ('development',1),('staging',2),('evaluation',3),('production',4);

-- deployment_run_mode: how a deployed package executes (the shadow/ab/live/locked clarification)
CREATE TABLE reference.deployment_run_mode (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_run_mode PRIMARY KEY (code), CONSTRAINT uq_deployment_run_mode_sort UNIQUE (sort_order));
INSERT INTO reference.deployment_run_mode (code, label, sort_order, description) VALUES
    ('live','Live',1,'champion: full Source+Target bindings, all traffic'),
    ('shadow','Shadow',2,'challenger: full inputs, Target bindings suppressed (zero impact)'),
    ('ab','A/B',3,'challenger: full I/O on a scoped sample (carries ab_sample marker)'),
    ('locked','Locked',4,'deprecated: no execution');

CREATE TABLE reference.deployment_operation (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_operation PRIMARY KEY (code), CONSTRAINT uq_deployment_operation_sort UNIQUE (sort_order));
INSERT INTO reference.deployment_operation (code, label, sort_order) VALUES
    ('deploy_nonprod',1),('deploy_prod',2),('promote_champion',3),('lock_deprecated',4),('cleanup_deprecated',5),('rollback',6);

CREATE TABLE reference.deployment_outcome (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_outcome PRIMARY KEY (code), CONSTRAINT uq_deployment_outcome_sort UNIQUE (sort_order));
INSERT INTO reference.deployment_outcome (code, label, sort_order) VALUES
    ('requested',1),('rejected_incompatible',2),('rejected_lifecycle',3),('rejected_unauthorized',4),('succeeded',5),('failed',6),('superseded',7);

CREATE TABLE reference.deployment_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_deployment_status PRIMARY KEY (code), CONSTRAINT uq_deployment_status_sort UNIQUE (sort_order));
INSERT INTO reference.deployment_status (code, label, sort_order) VALUES ('active',1),('superseded',2),('stopped',3);

CREATE TABLE reference.harness_instance_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_harness_instance_status PRIMARY KEY (code), CONSTRAINT uq_harness_instance_status_sort UNIQUE (sort_order));
INSERT INTO reference.harness_instance_status (code, label, sort_order) VALUES ('active',1),('draining',2),('disabled',3);

CREATE TABLE reference.health_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_health_status PRIMARY KEY (code), CONSTRAINT uq_health_status_sort UNIQUE (sort_order));
INSERT INTO reference.health_status (code, label, sort_order) VALUES ('healthy',1),('degraded',2),('down',3),('unknown',4);

CREATE TABLE reference.heartbeat_kind (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_heartbeat_kind PRIMARY KEY (code), CONSTRAINT uq_heartbeat_kind_sort UNIQUE (sort_order));
INSERT INTO reference.heartbeat_kind (code, label, sort_order, description) VALUES
    ('minor','Minor',1,'frequent/light: alive + basic health'),('major','Major',2,'less frequent/full: running-package catalog + metrics');

CREATE TABLE reference.command_kind (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_command_kind PRIMARY KEY (code), CONSTRAINT uq_command_kind_sort UNIQUE (sort_order));
INSERT INTO reference.command_kind (code, label, sort_order) VALUES
    ('patch',1),('restart',2),('drain',3),('enable',4),('disable',5),('reload_packages',6),('collect_diagnostics',7);

CREATE TABLE reference.command_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_command_status PRIMARY KEY (code), CONSTRAINT uq_command_status_sort UNIQUE (sort_order));
INSERT INTO reference.command_status (code, label, sort_order) VALUES
    ('pending',1),('acknowledged',2),('succeeded',3),('failed',4);

-- ===== REPORTING-domain vocabularies (used by 09-reporting.sql) =======
CREATE TABLE reference.embedding_runtime (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_embedding_runtime PRIMARY KEY (code), CONSTRAINT uq_embedding_runtime_sort UNIQUE (sort_order));
INSERT INTO reference.embedding_runtime (code, label, sort_order) VALUES ('fastembed','FastEmbed',1);

CREATE TABLE reference.report_kind (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_report_kind PRIMARY KEY (code), CONSTRAINT uq_report_kind_sort UNIQUE (sort_order));
INSERT INTO reference.report_kind (code, label, sort_order) VALUES ('metadata_driven',1),('template_driven',2);

CREATE TABLE reference.report_run_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_report_run_status PRIMARY KEY (code), CONSTRAINT uq_report_run_status_sort UNIQUE (sort_order));
INSERT INTO reference.report_run_status (code, label, sort_order) VALUES ('pending',1),('succeeded',2),('failed',3);

-- ===== VALIDATION-domain vocabularies (used by 10-validation.sql) =====
-- compact: code/label/sort_order + standard columns (description/grouping/parent_code/
-- effective_*/is_active/metadata/created_at/updated_at), PK(code), UNIQUE(sort_order).
CREATE TABLE reference.gt_dataset_status (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_gt_dataset_status PRIMARY KEY (code), CONSTRAINT uq_gt_dataset_status_sort UNIQUE (sort_order));
INSERT INTO reference.gt_dataset_status (code,label,sort_order) VALUES ('collecting',1),('labeling',2),('adjudicating',3),('ready',4),('deprecated',5);
CREATE TABLE reference.gt_quality_tier (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_gt_quality_tier PRIMARY KEY (code), CONSTRAINT uq_gt_quality_tier_sort UNIQUE (sort_order));
INSERT INTO reference.gt_quality_tier (code,label,sort_order) VALUES ('silver',1),('gold',2);
CREATE TABLE reference.gt_source_type (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_gt_source_type PRIMARY KEY (code), CONSTRAINT uq_gt_source_type_sort UNIQUE (sort_order));
INSERT INTO reference.gt_source_type (code,label,sort_order) VALUES ('document',1),('submission',2),('synthetic',3);
CREATE TABLE reference.gt_annotator_type (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_gt_annotator_type PRIMARY KEY (code), CONSTRAINT uq_gt_annotator_type_sort UNIQUE (sort_order));
INSERT INTO reference.gt_annotator_type (code,label,sort_order) VALUES ('human_sme',1),('llm_judge',2),('adjudicator',3);
CREATE TABLE reference.mock_kind (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_mock_kind PRIMARY KEY (code), CONSTRAINT uq_mock_kind_sort UNIQUE (sort_order));
INSERT INTO reference.mock_kind (code,label,sort_order) VALUES ('tool',1),('source',2),('target',3);
CREATE TABLE reference.validation_run_status (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_validation_run_status PRIMARY KEY (code), CONSTRAINT uq_validation_run_status_sort UNIQUE (sort_order));
INSERT INTO reference.validation_run_status (code,label,sort_order) VALUES ('running',1),('complete',2),('failed',3);
CREATE TABLE reference.validation_match_type (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_validation_match_type PRIMARY KEY (code), CONSTRAINT uq_validation_match_type_sort UNIQUE (sort_order));
INSERT INTO reference.validation_match_type (code,label,sort_order) VALUES ('exact',1),('partial',2),('fuzzy',3);
CREATE TABLE reference.extraction_field_type (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_extraction_field_type PRIMARY KEY (code), CONSTRAINT uq_extraction_field_type_sort UNIQUE (sort_order));
INSERT INTO reference.extraction_field_type (code,label,sort_order) VALUES ('string',1),('numeric',2),('date',3),('boolean',4),('enum',5);
CREATE TABLE reference.extraction_match_type (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_extraction_match_type PRIMARY KEY (code), CONSTRAINT uq_extraction_match_type_sort UNIQUE (sort_order));
INSERT INTO reference.extraction_match_type (code,label,sort_order) VALUES ('exact',1),('numeric_tolerance',2),('case_insensitive',3),('contains',4);
CREATE TABLE reference.tolerance_unit (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_tolerance_unit PRIMARY KEY (code), CONSTRAINT uq_tolerance_unit_sort UNIQUE (sort_order));
INSERT INTO reference.tolerance_unit (code,label,sort_order) VALUES ('percent',1),('absolute',2);
CREATE TABLE reference.incident_severity (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_incident_severity PRIMARY KEY (code), CONSTRAINT uq_incident_severity_sort UNIQUE (sort_order));
INSERT INTO reference.incident_severity (code,label,sort_order) VALUES ('critical',1),('high',2),('medium',3),('low',4);
CREATE TABLE reference.incident_status (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_incident_status PRIMARY KEY (code), CONSTRAINT uq_incident_status_sort UNIQUE (sort_order));
INSERT INTO reference.incident_status (code,label,sort_order) VALUES ('open',1),('investigating',2),('mitigated',3),('resolved',4),('closed',5);
CREATE TABLE reference.evaluation_type (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_evaluation_type PRIMARY KEY (code), CONSTRAINT uq_evaluation_type_sort UNIQUE (sort_order));
INSERT INTO reference.evaluation_type (code,label,sort_order) VALUES ('shadow',1),('challenger',2),('periodic',3),('drift_check',4);
CREATE TABLE reference.model_card_state (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_model_card_state PRIMARY KEY (code), CONSTRAINT uq_model_card_state_sort UNIQUE (sort_order));
INSERT INTO reference.model_card_state (code,label,sort_order) VALUES ('draft',1),('in_review',2),('approved',3),('superseded',4);
CREATE TABLE reference.setting_input_type (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_setting_input_type PRIMARY KEY (code), CONSTRAINT uq_setting_input_type_sort UNIQUE (sort_order));
INSERT INTO reference.setting_input_type (code,label,sort_order) VALUES ('text',1),('select',2),('number',3);

-- (END of vocabularies. This file is split into reference/<vocab>.sql at the reorg.)

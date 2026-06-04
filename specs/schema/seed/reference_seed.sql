-- =====================================================================
-- seed/reference_seed.sql — Verity v2 reference-vocabulary DATA (seed)
-- Separated from DDL (ADR-0011). Apply AFTER verity_schema.sql. Idempotent:
-- ON CONFLICT (code) DO NOTHING; re-running is a no-op.
-- =====================================================================

INSERT INTO reference.actor_type (code, label, sort_order) VALUES
    ('human',      'Human user',        1),
    ('automation', 'Automation / agent', 2)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.ai_risk_tier (code, label, sort_order) VALUES
    ('minimal','Minimal',1),('limited','Limited',2),('high','High',3),('unacceptable','Unacceptable',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.api_role (code, label, sort_order) VALUES
    ('system','System',1),('user','User',2),('assistant_prefill','Assistant Prefill',3)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.app_team_role (code, label, sort_order) VALUES
    ('app_demo_owner','App Demo Owner',1),('app_demo_lead','App Demo Lead',2),('app_demo_dev','App Demo Dev',3),('app_demo_sre','App Demo Sre',4),('app_demo_ops','App Demo Ops',5)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.approval_decision (code, label, sort_order) VALUES
    ('approved','Approved',1),('rejected','Rejected',2),('requested_changes','Requested Changes',3),('abstained','Abstained',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.approval_request_status (code, label, sort_order) VALUES
    ('pending','Pending',1),('approved','Approved',2),('rejected','Rejected',3),('cancelled','Cancelled',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.artifact_plan_status (code, label, sort_order) VALUES
    ('proposed','Proposed',1),('in_progress','In Progress',2),('realized','Realized',3),('cancelled','Cancelled',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.binding_delivery_mode (code, label, sort_order, description) VALUES
    ('inline','Inline content',1,'base64/text content block (vision/small files)'),
    ('reference','By reference',2,'signed URL / object handle; tool streams it (large files)'),
    ('download','Download to workdir',3,'harness fetches the file to the run working dir'),
    ('extracted','Extracted to structured',4,'parse the file into structured fields'),
    ('write_file','Write file',5,'target: write the output as a file to the backend')
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.capability_type (code, label, sort_order) VALUES
    ('classification','Classification',1),('extraction','Extraction',2),('generation','Generation',3),('summarisation','Summarisation',4),('matching','Matching',5),('validation','Validation',6)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.command_kind (code, label, sort_order) VALUES
    ('patch','Patch',1),('restart','Restart',2),('drain','Drain',3),('enable','Enable',4),('disable','Disable',5),('reload_packages','Reload Packages',6),('collect_diagnostics','Collect Diagnostics',7),
    ('deploy_package','Deploy Package',8),
    ('patch_cert','Patch Cert',9)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.command_outbox_status (code, label, sort_order) VALUES
    ('pending','Pending',1),('published','Published',2),('acknowledged','Acknowledged',3),('failed','Failed',4),('expired','Expired',5)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.command_status (code, label, sort_order) VALUES
    ('pending','Pending',1),('acknowledged','Acknowledged',2),('succeeded','Succeeded',3),('failed','Failed',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.connector_type (code, label, sort_order, grouping) VALUES
    ('vault','Verity Vault',1,'object_store'),('s3','AWS S3',2,'object_store'),
    ('azure_blob','Azure Blob',3,'object_store'),('gcs','Google Cloud Storage',4,'object_store'),
    ('sharepoint','SharePoint',5,'document'),('filesystem','Filesystem',6,'file'),
    ('http','HTTP/URL',7,'web'),('database','Database',8,'database')
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.control_phase (code, label, sort_order, description) VALUES
    ('design_time','Design-time',1,'when an asset/schema/pipeline is defined'),
    ('deploy_time','Deploy-time',2,'when promoting to production'),
    ('static_model','Static / model',3,'continuous on the model/artifact (AI analog of data-at-rest)'),
    ('execution','Execution',4,'during runtime (AI analog of data-in-motion)')
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.control_type (code, label, sort_order) VALUES
    ('preventive','Preventive',1),('detective','Detective',2),('corrective','Corrective',3),('directive','Directive',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.coverage_level (code, label, sort_order) VALUES
    ('full','Full',1),('substantial','Substantial',2),('partial','Partial',3),('gap','Gap',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.credential_verification_status (code, label, sort_order) VALUES
    ('unverified','Unverified',1),('verified','Verified',2),('failed','Failed',3),('expired','Expired',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.currency (code, label, sort_order) VALUES ('usd','US Dollar',1),('eur','Euro',2),('gbp','British Pound',3)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.data_classification (code, label, sort_order) VALUES
    ('tier1_public','Tier1 Public',1),('tier2_internal','Tier2 Internal',2),('tier3_confidential','Tier3 Confidential',3),('tier4_pii_restricted','Tier4 Pii Restricted',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.deployment_channel (code, label, sort_order) VALUES
    ('development','Development',1),('staging','Staging',2),('evaluation','Evaluation',3),('production','Production',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.deployment_operation (code, label, sort_order) VALUES
    ('deploy_nonprod','Deploy Nonprod',1),('deploy_prod','Deploy Prod',2),('promote_champion','Promote Champion',3),('lock_deprecated','Lock Deprecated',4),('cleanup_deprecated','Cleanup Deprecated',5),('rollback','Rollback',6)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.deployment_outcome (code, label, sort_order) VALUES
    ('requested','Requested',1),('rejected_incompatible','Rejected Incompatible',2),('rejected_lifecycle','Rejected Lifecycle',3),('rejected_unauthorized','Rejected Unauthorized',4),('succeeded','Succeeded',5),('failed','Failed',6),('superseded','Superseded',7)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.deployment_run_mode (code, label, sort_order, description) VALUES
    ('live','Live',1,'champion: full Source+Target bindings, all traffic'),
    ('shadow','Shadow',2,'challenger: full inputs, Target bindings suppressed (zero impact)'),
    ('ab','A/B',3,'challenger: full I/O on a scoped sample (carries ab_sample marker)'),
    ('locked','Locked',4,'deprecated: no execution')
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.deployment_status (code, label, sort_order) VALUES ('active','Active',1),('superseded','Superseded',2),('stopped','Stopped',3)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.derivation_method (code, label, sort_order, description) VALUES
    ('manual','Manual',1,'authored by a human directly'),
    ('reasoner_recommended','Reasoner-recommended',2,'inferred by the ontology/reasoner; pending validation (ADR-0009)'),
    ('human_validated','Human-validated',3,'reasoner/LLM recommendation reviewed & accepted by a human')
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.embedding_runtime (code, label, sort_order) VALUES ('fastembed','FastEmbed',1)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.enforcement_action (code, label, sort_order) VALUES
    ('block','Block',1),('refuse','Refuse',2),('suppress_write','Suppress Write',3),('warn','Warn',4),('log_only','Log Only',5)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.environment_kind (code, label, sort_order) VALUES ('non_prod','Non Prod',1),('prod','Prod',2),('ephemeral','Ephemeral',3)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.evaluation_type (code,label,sort_order) VALUES ('shadow','Shadow',1),('challenger','Challenger',2),('periodic','Periodic',3),('drift_check','Drift Check',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.evidence_artifact_type (code, label, sort_order) VALUES
    ('config_snapshot','Config Snapshot',1),('model_card','Model Card',2),('package_manifest','Package Manifest',3),('approval_record','Approval Record',4),('test_result','Test Result',5),
    ('validation_report','Validation Report',6),('decision_log','Decision Log',7),('binding_resolution','Binding Resolution',8),('deployment_record','Deployment Record',9),('document','Document',10)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.exception_status (code, label, sort_order) VALUES
    ('requested','Requested',1),('approved','Approved',2),('rejected','Rejected',3),('revoked','Revoked',4),('expired','Expired',5)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.executable_kind (code, label, sort_order, is_packaged, package_format) VALUES
    ('agent', 'Agent', 1, true, 'vax'),
    ('task',  'Task',  2, true, 'vtx')
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.extraction_field_type (code,label,sort_order) VALUES ('string','String',1),('numeric','Numeric',2),('date','Date',3),('boolean','Boolean',4),('enum','Enum',5)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.extraction_match_type (code,label,sort_order) VALUES ('exact','Exact',1),('numeric_tolerance','Numeric Tolerance',2),('case_insensitive','Case Insensitive',3),('contains','Contains',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.governance_domain (code, label, sort_order) VALUES
    ('model_risk','Model Risk',1),('fairness','Fairness',2),('privacy','Privacy',3),('security','Security',4),('transparency','Transparency',5),
    ('robustness','Robustness',6),('data_governance','Data Governance',7),('human_oversight','Human Oversight',8),('accountability','Accountability',9)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.governance_tier (code, label, sort_order) VALUES
    ('behavioural','Behavioural',1),('contextual','Contextual',2),('formatting','Formatting',3)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.gt_annotator_type (code,label,sort_order) VALUES ('human_sme','Human Sme',1),('llm_judge','Llm Judge',2),('adjudicator','Adjudicator',3)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.gt_dataset_status (code,label,sort_order) VALUES ('collecting','Collecting',1),('labeling','Labeling',2),('adjudicating','Adjudicating',3),('ready','Ready',4),('deprecated','Deprecated',5)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.gt_quality_tier (code,label,sort_order) VALUES ('silver','Silver',1),('gold','Gold',2)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.gt_source_type (code,label,sort_order) VALUES ('document','Document',1),('submission','Submission',2),('synthetic','Synthetic',3)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.harness_instance_status (code, label, sort_order) VALUES ('active','Active',1),('draining','Draining',2),('disabled','Disabled',3)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.harness_node_status (code, label, sort_order) VALUES
    ('active','Active',1),('draining','Draining',2),('offline','Offline',3),('decommissioned','Decommissioned',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.harness_variant (code, label, sort_order, description) VALUES
    ('claude_agentic_loop','Claude agentic loop',1,'current default agent/task execution engine')
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.health_status (code, label, sort_order) VALUES ('healthy','Healthy',1),('degraded','Degraded',2),('down','Down',3),('unknown','Unknown',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.heartbeat_kind (code, label, sort_order, description) VALUES
    ('minor','Minor',1,'frequent/light: alive + basic health'),('major','Major',2,'less frequent/full: running-package catalog + metrics')
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.incident_severity (code,label,sort_order) VALUES ('critical','Critical',1),('high','High',2),('medium','Medium',3),('low','Low',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.incident_status (code,label,sort_order) VALUES ('open','Open',1),('investigating','Investigating',2),('mitigated','Mitigated',3),('resolved','Resolved',4),('closed','Closed',5)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.intake_status (code, label, sort_order) VALUES
    ('proposed','Proposed',1),('in_review','In Review',2),('impact_assessment','Impact Assessment',3),('approved','Approved',4),('in_build','In Build',5),('live','Live',6),('rejected','Rejected',7),('retired','Retired',8)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.lifecycle_state (code, label, sort_order, is_deployable, is_terminal, grouping) VALUES
    ('draft','Draft',1,false,false,'authoring'),
    ('candidate','Candidate',2,false,false,'authoring'),
    ('staging','Staging',3,true,false,'pre_prod'),
    ('challenger','Challenger',4,true,false,'prod'),
    ('champion','Champion',5,true,false,'prod'),
    ('deprecated','Deprecated',6,true,false,'retired')
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.materiality_tier (code, label, sort_order) VALUES ('low','Low',1),('medium','Medium',2),('high','High',3),('critical','Critical',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.metric_type (code, label, sort_order) VALUES
    ('exact_match','Exact Match',1),('semantic_similarity','Semantic Similarity',2),
    ('json_schema_match','JSON Schema Match',3),('numeric_tolerance','Numeric Tolerance',4),
    ('f1_score','F1 Score',5),('accuracy','Accuracy',6),('llm_judge','LLM Judge',7),
    ('contains','Contains',8),('regex_match','Regex Match',9)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.mock_kind (code,label,sort_order) VALUES ('tool','Tool',1),('source','Source',2),('target','Target',3)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.model_card_state (code,label,sort_order) VALUES ('draft','Draft',1),('in_review','In Review',2),('approved','Approved',3),('superseded','Superseded',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.model_status (code, label, sort_order) VALUES ('active','Active',1),('deprecated','Deprecated',2),('retired','Retired',3)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.naic_materiality (code, label, sort_order) VALUES ('material','Material',1),('non_material','Non Material',2)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.outbox_status (code, label, sort_order) VALUES
    ('pending','Pending',1),('published','Published',2),('claimed','Claimed',3),('failed','Failed',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.quota_alert_level (code, label, sort_order) VALUES ('warning','Warning',1),('exceeded','Exceeded',2),('critical','Critical',3)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.quota_enforcement_mode (code, label, sort_order, description) VALUES
    ('soft','Soft (warn only)',1,'record warning/breach; never refuse the run'),
    ('hard','Hard-stop',2,'refuse the run when the budget is exceeded (execution-phase control)')
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.quota_period (code, label, sort_order) VALUES ('daily','Daily',1),('weekly','Weekly',2),('monthly','Monthly',3)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.quota_scope_type (code, label, sort_order) VALUES
    ('application','Application',1),('agent','Agent',2),('task','Task',3),('model','Model',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.report_kind (code, label, sort_order) VALUES ('metadata_driven','Metadata Driven',1),('template_driven','Template Driven',2)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.report_run_status (code, label, sort_order) VALUES ('pending','Pending',1),('succeeded','Succeeded',2),('failed','Failed',3)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.requirement_kind (code, label, sort_order) VALUES
    ('business','Business',1),('functional','Functional',2),('non_functional','Non Functional',3),('compliance','Compliance',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.requirement_status (code, label, sort_order) VALUES
    ('draft','Draft',1),('approved','Approved',2),('implemented','Implemented',3),('verified','Verified',4),('deprecated','Deprecated',5)
    ON CONFLICT (code) DO NOTHING;

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
    ('viewer',         'Viewer',        10, 'governance',  false)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.run_completion_status (code, label, sort_order) VALUES
    ('complete','Complete',1),('cancelled','Cancelled',2),('errored','Errored',3)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.run_dispatch_status (code, label, sort_order) VALUES
    ('queued','Queued',1),('published','Published',2),('claimed','Claimed',3),('assigned','Assigned',4),
    ('executing','Executing',5),('released','Released',6),('requeued','Requeued',7),('cancelled','Cancelled',8)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.run_purpose (code, label, sort_order) VALUES
    ('production','Production',1),('test','Test',2),('validation','Validation',3),('audit_rerun','Audit Rerun',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.run_status (code, label, sort_order) VALUES
    ('submitted','Submitted',1),('claimed','Claimed',2),('heartbeat','Heartbeat',3),('released','Released',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.setting_input_type (code,label,sort_order) VALUES ('text','Text',1),('select','Select',2),('number','Number',3)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.source_kind (code, label, sort_order) VALUES
    ('storage_object','Storage Object',1),
    ('task_output','Task Output',2),
    ('structured','Structured',3),
    ('inline_content','Inline Content',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.tolerance_unit (code,label,sort_order) VALUES ('percent','Percent',1),('absolute','Absolute',2)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.tool_transport (code, label, sort_order) VALUES
    ('python_inprocess','Python Inprocess',1),('mcp','Mcp',2),('http','Http',3)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.trust_level (code, label, sort_order) VALUES
    ('trusted','Trusted',1),('conditional','Conditional',2),('sandboxed','Sandboxed',3),('blocked','Blocked',4)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.validation_match_type (code,label,sort_order) VALUES ('exact','Exact',1),('partial','Partial',2),('fuzzy','Fuzzy',3)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.validation_run_status (code,label,sort_order) VALUES ('running','Running',1),('complete','Complete',2),('failed','Failed',3)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.version_change_type (code, label, sort_order) VALUES
    ('major','Major',1),('minor','Minor',2),('patch','Patch',3)
    ON CONFLICT (code) DO NOTHING;

INSERT INTO reference.write_mode (code, label, sort_order) VALUES
    ('create','Create',1),('overwrite','Overwrite',2),('create_or_version','Create Or Version',3)
    ON CONFLICT (code) DO NOTHING;

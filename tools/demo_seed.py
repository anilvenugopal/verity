"""Demo / test-data seeder — for TESTING & DEMONSTRATIONS ONLY.

Direct SQL against the dev database, entirely separate from the governed reference/core seed in
specs/schema/seed/ (different level of governance + maintenance). Every row it writes is tagged so it
can only ever touch its own data:
  - applications use TLA codes starting with 'Z' (ZAP / ZMA / ZMI / ZMR)
  - the synthetic teammate actor is named '[Demo] Teammate'

"You" is resolved to your real (Entra) account so the apps you "create" show up under MY APPLICATIONS.
States are produced by writing the same rows the app would (application + perimeter + approval +
sign-off), so the portal reads them exactly like real data. Nothing here is ever shipped or seeded
into prod — it lives only in the dev tool.
"""
from __future__ import annotations

import asyncio
import json
import uuid

import psycopg

DEMO_CODE_PREFIX = "Z"          # demo application TLAs start with Z (the teardown marker)
DEMO_TEAMMATE_NAME = "Devin Shah"   # a synthetic colleague — proposer/owner of the 'awaiting you' app


def _app_id(code: str) -> str:
    """Deterministic application_id per demo code — so refresh recreates the SAME ids and an
    already-open tab's links never 404."""
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"verity.demo.application.{code}"))


def _teammate_id() -> str:
    """Deterministic actor_id for the synthetic colleague — lets teardown find it by id rather than
    a visible '[Demo]' tag in the name."""
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, "verity.demo.teammate"))


def _intake_id(code: str) -> str:
    """Deterministic intake_id per demo use-case code — stable across refreshes (same rationale as
    _app_id)."""
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"verity.demo.intake.{code}"))


def _executable_id(code: str) -> str:
    """Deterministic executable_id for demo registry assets — stable across refreshes."""
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"verity.demo.executable.{code}"))


def _prompt_id(code: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"verity.demo.prompt.{code}"))


def _prompt_version_id(code: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"verity.demo.prompt_version.{code}.1.0.0"))


def _tool_id(code: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"verity.demo.tool.{code}"))


def _tool_version_id(code: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"verity.demo.tool_version.{code}.1.0.0"))


def _exe_version_id(code: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"verity.demo.exe_version.{code}.1.0.0"))


# ── Demo registry entities (prompts, tools, agents, tasks) ───────────────────
# Modelled after the verity_legacy uw_demo/app/setup/register_all.py entities.
# All use 'ai_governance' role + seed actor; no approval gate (direct champion promotion).

_SEED_ACTOR = "00000000-0000-0000-0000-000000000001"  # Verity Seed actor from core_seed.sql

_DEMO_PROMPTS = [
    {
        "code": "triage-system",
        "name": "triage-system",
        "display_name": "Triage System Prompt",
        "description": "System prompt for the underwriting triage agent. Sets role, constraints, output format (JSON), and escalation rules.",
        "blocks": [{"type": "prose", "text": (
            "You are an underwriting triage assistant for a commercial insurance carrier. "
            "Your role is to analyse the submitted application and produce a structured triage result.\n\n"
            "Output a JSON object with exactly these keys:\n"
            "- risk_tier: one of 'standard', 'non-standard', 'referral', 'decline'\n"
            "- confidence: float 0.0–1.0\n"
            "- rationale: string (max 200 words)\n"
            "- missing_fields: list of field names absent or incomplete\n"
            "- flags: list of concern codes (see guidelines)\n\n"
            "Do not guess missing data. Escalate to referral if material information is absent. "
            "Never output outside JSON."
        )}],
        "role": "system",
    },
    {
        "code": "triage-context",
        "name": "triage-context",
        "display_name": "Triage Context Injection",
        "description": "Context injection prompt: formats submission metadata and account context for the triage agent.",
        "blocks": [{"type": "prose", "text": (
            "## Submission Context\n\n"
            "Account: {{account_name}} | LOB: {{lob}} | Revenue: {{annual_revenue}} | "
            "SIC: {{sic_code}} ({{sic_description}})\n"
            "Limits requested: {{limits_requested}} | Retention: {{retention_requested}}\n"
            "Prior carrier: {{prior_carrier}} | Prior premium: {{prior_premium}}\n\n"
            "## Loss History (3 years)\n{{loss_history_table}}\n\n"
            "## Guidelines excerpt\n{{guidelines_excerpt}}\n\n"
            "Analyse the above and return the triage JSON."
        )}],
        "role": "user",
    },
    {
        "code": "appetite-system",
        "name": "appetite-system",
        "display_name": "Appetite Assessment System Prompt",
        "description": "System prompt for the appetite assessment agent. Evaluates a submission against LOB appetite rules and returns a structured decision.",
        "blocks": [{"type": "prose", "text": (
            "You are an appetite assessment specialist for a commercial lines insurance carrier. "
            "Your task is to evaluate whether a submission falls within or outside the published appetite "
            "for the indicated line of business.\n\n"
            "Return JSON with:\n"
            "- appetite_decision: 'within' | 'borderline' | 'outside'\n"
            "- decision_rationale: string\n"
            "- violated_rules: list of rule codes from the guidelines\n"
            "- recommended_action: 'quote' | 'refer_to_underwriter' | 'decline'\n\n"
            "Cite the specific guideline section for every violated rule. "
            "A 'borderline' decision always requires a human underwriter review."
        )}],
        "role": "system",
    },
    {
        "code": "doc-classifier-instruction",
        "name": "doc-classifier-instruction",
        "display_name": "Document Classifier Instructions",
        "description": "Instructions for classifying submission documents by type and routing them to the correct extraction pipeline.",
        "blocks": [{"type": "prose", "text": (
            "You are a document classification specialist for an insurance underwriting workflow.\n\n"
            "Classify the provided document into exactly one of these types:\n"
            "- acord_125: ACORD 125 Commercial Insurance Application\n"
            "- acord_126: ACORD 126 Commercial General Liability Section\n"
            "- acord_130: ACORD 130 Workers Compensation Application\n"
            "- loss_runs: Historical claims / loss run statement\n"
            "- financials: Financial statements (P&L, balance sheet, audit)\n"
            "- supplemental: Supplemental questionnaire\n"
            "- correspondence: Broker / underwriter correspondence\n"
            "- other: Unrecognised document type\n\n"
            "Return JSON: {\"doc_type\": \"<code>\", \"confidence\": <float>, "
            "\"page_count\": <int>, \"extraction_pipeline\": \"<code>\"}"
        )}],
        "role": "system",
    },
    {
        "code": "field-extractor-instruction",
        "name": "field-extractor-instruction",
        "display_name": "Field Extractor Instructions",
        "description": "Extraction instructions for ACORD form field extraction. Maps document text to structured JSON fields.",
        "blocks": [{"type": "prose", "text": (
            "Extract all available fields from the provided ACORD form text and return them as JSON.\n\n"
            "For each field, include:\n"
            "- value: extracted value (null if not present)\n"
            "- confidence: float 0.0–1.0\n"
            "- source_text: verbatim text from the document\n\n"
            "Required fields (return null with confidence=0 if absent):\n"
            "named_insured, fein, entity_type, state_of_incorporation, annual_revenue, "
            "employee_count, effective_date, expiration_date, limits_requested, "
            "retention_requested, prior_carrier, prior_premium, lob\n\n"
            "Do not infer or hallucinate values. Only extract text explicitly present in the document."
        )}],
        "role": "user",
    },
    {
        "code": "loss-run-analysis",
        "name": "loss-run-analysis",
        "display_name": "Loss Run Analysis Prompt",
        "description": "Loss run analysis user turn prompt. Structures and classifies historical claims data for the underwriting file.",
        "blocks": [{"type": "prose", "text": (
            "Analyse the following loss run data and produce a structured summary.\n\n"
            "{{loss_run_text}}\n\n"
            "Return JSON with:\n"
            "- years_analysed: int\n"
            "- total_incurred: float\n"
            "- total_paid: float\n"
            "- open_reserves: float\n"
            "- claim_frequency: float (claims per year)\n"
            "- severity_trend: 'improving' | 'stable' | 'deteriorating'\n"
            "- catastrophic_losses: list of {year, amount, description}\n"
            "- summary_narrative: string (max 150 words)"
        )}],
        "role": "user",
    },
]

_DEMO_TOOLS = [
    {
        "code": "get-submission-context",
        "name": "get-submission-context",
        "display_name": "Get Submission Context",
        "description": "Retrieves account context and submission metadata for a given submission ID. Returns named insured, LOB, SIC, revenue, and prior carrier details.",
        "transport": "python_inprocess",
        "data_classification": "tier3_confidential",
        "input_schema": {"type": "object", "properties": {"submission_id": {"type": "string", "format": "uuid"}}, "required": ["submission_id"]},
    },
    {
        "code": "get-underwriting-guidelines",
        "name": "get-underwriting-guidelines",
        "display_name": "Get Underwriting Guidelines",
        "description": "Returns the current underwriting guidelines and appetite rules for a specified line of business. Includes eligibility criteria, prohibited classes, and pricing benchmarks.",
        "transport": "python_inprocess",
        "data_classification": "tier2_internal",
        "input_schema": {"type": "object", "properties": {"lob": {"type": "string", "enum": ["DO", "GL", "WC", "BOP", "Cyber"]}}, "required": ["lob"]},
    },
    {
        "code": "get-documents-for-submission",
        "name": "get-documents-for-submission",
        "display_name": "Get Documents for Submission",
        "description": "Lists all documents available in the vault for a given submission, with their types, page counts, and upload timestamps.",
        "transport": "python_inprocess",
        "data_classification": "tier3_confidential",
        "input_schema": {"type": "object", "properties": {"submission_id": {"type": "string", "format": "uuid"}}, "required": ["submission_id"]},
    },
    {
        "code": "get-loss-history",
        "name": "get-loss-history",
        "display_name": "Get Loss History",
        "description": "Returns historical claims data for a named insured. Includes claim counts, incurred/paid amounts, open reserves, and catastrophic loss flags by year.",
        "transport": "python_inprocess",
        "data_classification": "tier3_confidential",
        "input_schema": {"type": "object", "properties": {"named_insured": {"type": "string"}, "years": {"type": "integer", "default": 5}}, "required": ["named_insured"]},
    },
    {
        "code": "store-extraction-result",
        "name": "store-extraction-result",
        "display_name": "Store Extraction Result",
        "description": "Persists a structured extraction result to the EDMS against a submission record. Returns a storage receipt with version ID.",
        "transport": "python_inprocess",
        "data_classification": "tier3_confidential",
        "input_schema": {"type": "object", "properties": {"submission_id": {"type": "string"}, "doc_type": {"type": "string"}, "extracted_fields": {"type": "object"}}, "required": ["submission_id", "doc_type", "extracted_fields"]},
    },
]

_DEMO_AGENTS = [
    {
        "code": "triage-agent",
        "name": "triage-agent",
        "display_name": "Underwriting Triage Agent",
        "description": "Underwriting Triage Agent — classifies commercial submissions by risk tier, identifies information gaps, and produces a structured triage recommendation for the underwriter.",
        "governance_tier": "contextual",
        "capability_type": "classification",
        "trust_level": "trusted",
        "data_classification": "tier3_confidential",
        "prompts": [("triage-system", "system", 1), ("triage-context", "user", 2)],
        "tools": ["get-submission-context", "get-underwriting-guidelines"],
    },
    {
        "code": "appetite-agent",
        "name": "appetite-agent",
        "display_name": "Appetite Assessment Agent",
        "description": "Appetite Assessment Agent — evaluates commercial submissions against published LOB appetite rules and returns a within/borderline/outside decision with cited rule violations.",
        "governance_tier": "contextual",
        "capability_type": "classification",
        "trust_level": "trusted",
        "data_classification": "tier3_confidential",
        "prompts": [("appetite-system", "system", 1)],
        "tools": ["get-underwriting-guidelines", "get-loss-history"],
    },
    {
        "code": "doc-classifier",
        "name": "doc-classifier",
        "display_name": "Document Classifier",
        "description": "Document Classifier Agent — classifies submitted insurance documents by type (ACORD forms, loss runs, financials, supplementals) and routes them to the appropriate extraction pipeline.",
        "governance_tier": "formatting",
        "capability_type": "classification",
        "trust_level": "trusted",
        "data_classification": "tier2_internal",
        "prompts": [("doc-classifier-instruction", "system", 1)],
        "tools": ["get-documents-for-submission"],
    },
]

_DEMO_TASKS = [
    {
        "code": "field-extractor",
        "name": "field-extractor",
        "display_name": "ACORD Field Extractor",
        "description": "ACORD Field Extraction Task — extracts structured data fields from ACORD 125/126/130 forms, mapping document text to the canonical underwriting data model.",
        "governance_tier": "formatting",
        "capability_type": "extraction",
        "trust_level": "trusted",
        "data_classification": "tier3_confidential",
        "prompts": [("field-extractor-instruction", "user", 1)],
    },
    {
        "code": "loss-run-classifier",
        "name": "loss-run-classifier",
        "display_name": "Loss Run Classifier",
        "description": "Loss Run Classification Task — structures and classifies historical claims data, computes frequency/severity trends, and flags catastrophic losses for underwriter review.",
        "governance_tier": "contextual",
        "capability_type": "extraction",
        "trust_level": "trusted",
        "data_classification": "tier3_confidential",
        "prompts": [("loss-run-analysis", "user", 1)],
    },
    {
        "code": "completeness-checker",
        "name": "completeness-checker",
        "display_name": "Submission Completeness Checker",
        "description": "Submission Completeness Checker — validates that all required ACORD fields and supporting documents are present before routing the submission to an underwriter.",
        "governance_tier": "formatting",
        "capability_type": "validation",
        "trust_level": "trusted",
        "data_classification": "tier2_internal",
        "prompts": [("triage-context", "user", 1)],
    },
]


def _seed_registry(conn, actor_id: str, app_id: str | None = None) -> list[str]:
    """Seed demo registry entities: prompts, tools, agents, tasks — all as champions.
    Idempotent — skips rows that already exist. Returns summary lines."""
    lines: list[str] = []

    # ── Prompts ──────────────────────────────────────────────────────────────
    for p in _DEMO_PROMPTS:
        pid = _prompt_id(p["code"])
        pvid = _prompt_version_id(p["code"])
        content_hash = f"demo-{p['code']}-v1"
        exists = conn.execute("SELECT 1 FROM core.prompt WHERE prompt_id = %s", (pid,)).fetchone()
        if exists:
            conn.execute(
                "UPDATE core.prompt SET display_name = %s, application_id = %s WHERE prompt_id = %s",
                (p.get("display_name", p["name"]), app_id, pid),
            )
            lines.append(f"  prompt '{p['name']}' — updated display_name")
            continue
        conn.execute(
            "INSERT INTO core.prompt (prompt_id, name, display_name, description, application_id, created_by_actor_id, created_role_code) "
            "VALUES (%s, %s, %s, %s, %s, %s, 'ai_governance')",
            (pid, p["name"], p.get("display_name", p["name"]), p["description"], app_id, actor_id),
        )
        conn.execute(
            "INSERT INTO core.prompt_version (prompt_version_id, prompt_id, semver, blocks, content_hash, "
            "created_by_actor_id, created_role_code) VALUES (%s, %s, '1.0.0', %s, %s, %s, 'ai_governance')",
            (pvid, pid, json.dumps(p["blocks"]), content_hash, actor_id),
        )
        lines.append(f"  prompt '{p['name']}' v1.0.0 — created")

    # ── Tools ────────────────────────────────────────────────────────────────
    for t in _DEMO_TOOLS:
        tid = _tool_id(t["code"])
        tvid = _tool_version_id(t["code"])
        exists = conn.execute("SELECT 1 FROM core.tool WHERE tool_id = %s", (tid,)).fetchone()
        if exists:
            conn.execute(
                "UPDATE core.tool SET display_name = %s, application_id = %s WHERE tool_id = %s",
                (t.get("display_name", t["name"]), app_id, tid),
            )
            lines.append(f"  tool '{t['name']}' — updated display_name")
            continue
        conn.execute(
            "INSERT INTO core.tool (tool_id, name, display_name, description, transport_code, application_id, "
            "created_by_actor_id, created_role_code) VALUES (%s, %s, %s, %s, %s, %s, %s, 'ai_governance')",
            (tid, t["name"], t.get("display_name", t["name"]), t["description"], t["transport"], app_id, actor_id),
        )
        conn.execute(
            "INSERT INTO core.tool_version (tool_version_id, tool_id, semver, input_schema, config, "
            "created_by_actor_id, created_role_code) "
            "VALUES (%s, %s, '1.0.0', %s, '{}', %s, 'ai_governance')",
            (tvid, tid, json.dumps(t["input_schema"]), actor_id),
        )
        lines.append(f"  tool '{t['name']}' v1.0.0 — created")

    # ── Agents ───────────────────────────────────────────────────────────────
    for a in _DEMO_AGENTS:
        eid = _executable_id(a["code"])
        evid = _exe_version_id(a["code"])
        exists = conn.execute("SELECT 1 FROM core.executable WHERE executable_id = %s", (eid,)).fetchone()
        if exists:
            conn.execute(
                "UPDATE core.executable SET display_name = %s, application_id = %s WHERE executable_id = %s",
                (a.get("display_name", a["name"]), app_id, eid),
            )
            lines.append(f"  agent '{a['name']}' — updated display_name")
            continue
        conn.execute(
            "INSERT INTO core.executable (executable_id, kind_code, name, display_name, description, application_id, "
            "created_by_actor_id, created_role_code) VALUES (%s, 'agent', %s, %s, %s, %s, %s, 'ai_governance')",
            (eid, a["name"], a.get("display_name", a["name"]), a["description"], app_id, actor_id),
        )
        conn.execute(
            "INSERT INTO core.executable_version (executable_version_id, executable_id, kind_code, semver, "
            "governance_tier_code, capability_type_code, trust_level_code, data_classification_code, "
            "created_by_actor_id, created_role_code) "
            "VALUES (%s, %s, 'agent', '1.0.0', %s, %s, %s, %s, %s, 'ai_governance')",
            (evid, eid, a["governance_tier"], a["capability_type"], a["trust_level"], a["data_classification"], actor_id),
        )
        for (prompt_code, role, ordinal) in a["prompts"]:
            pvid = _prompt_version_id(prompt_code)
            conn.execute(
                "INSERT INTO core.executable_prompt_assignment (executable_version_id, prompt_version_id, api_role_code, ordinal) "
                "VALUES (%s, %s, %s, %s) ON CONFLICT DO NOTHING",
                (evid, pvid, role, ordinal),
            )
        for tool_code in a["tools"]:
            tvid = _tool_version_id(tool_code)
            conn.execute(
                "INSERT INTO core.executable_tool_assignment (executable_version_id, tool_version_id, executable_kind_code) "
                "VALUES (%s, %s, 'agent') ON CONFLICT DO NOTHING",
                (evid, tvid),
            )
        le_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"verity.demo.lifecycle.{a['code']}.1.0.0"))
        ca_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"verity.demo.champion.{a['code']}.1.0.0"))
        conn.execute(
            "INSERT INTO core.lifecycle_event (lifecycle_event_id, executable_version_id, from_state_code, "
            "to_state_code, rationale, actor_id, acting_role_code) VALUES (%s, %s, 'draft', 'champion', "
            "'Demo seed champion promotion', %s, 'ai_governance')",
            (le_id, evid, actor_id),
        )
        conn.execute(
            "INSERT INTO core.champion_assignment (champion_assignment_id, executable_version_id, "
            "lifecycle_event_id, is_revocation, reason, actor_id, acting_role_code) "
            "VALUES (%s, %s, %s, false, 'Demo seed', %s, 'ai_governance')",
            (ca_id, evid, le_id, actor_id),
        )
        lines.append(f"  agent '{a['name']}' v1.0.0 (champion) — created")

    # ── Tasks ────────────────────────────────────────────────────────────────
    for t in _DEMO_TASKS:
        eid = _executable_id(t["code"])
        evid = _exe_version_id(t["code"])
        exists = conn.execute("SELECT 1 FROM core.executable WHERE executable_id = %s", (eid,)).fetchone()
        if exists:
            conn.execute(
                "UPDATE core.executable SET display_name = %s, application_id = %s WHERE executable_id = %s",
                (t.get("display_name", t["name"]), app_id, eid),
            )
            lines.append(f"  task '{t['name']}' — updated display_name")
            continue
        conn.execute(
            "INSERT INTO core.executable (executable_id, kind_code, name, display_name, description, application_id, "
            "created_by_actor_id, created_role_code) VALUES (%s, 'task', %s, %s, %s, %s, %s, 'ai_governance')",
            (eid, t["name"], t.get("display_name", t["name"]), t["description"], app_id, actor_id),
        )
        conn.execute(
            "INSERT INTO core.executable_version (executable_version_id, executable_id, kind_code, semver, "
            "governance_tier_code, capability_type_code, trust_level_code, data_classification_code, "
            "created_by_actor_id, created_role_code) "
            "VALUES (%s, %s, 'task', '1.0.0', %s, %s, %s, %s, %s, 'ai_governance')",
            (evid, eid, t["governance_tier"], t["capability_type"], t["trust_level"], t["data_classification"], actor_id),
        )
        for (prompt_code, role, ordinal) in t["prompts"]:
            pvid = _prompt_version_id(prompt_code)
            conn.execute(
                "INSERT INTO core.executable_prompt_assignment (executable_version_id, prompt_version_id, api_role_code, ordinal) "
                "VALUES (%s, %s, %s, %s) ON CONFLICT DO NOTHING",
                (evid, pvid, role, ordinal),
            )
        le_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"verity.demo.lifecycle.{t['code']}.1.0.0"))
        ca_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"verity.demo.champion.{t['code']}.1.0.0"))
        conn.execute(
            "INSERT INTO core.lifecycle_event (lifecycle_event_id, executable_version_id, from_state_code, "
            "to_state_code, rationale, actor_id, acting_role_code) VALUES (%s, %s, 'draft', 'champion', "
            "'Demo seed champion promotion', %s, 'ai_governance')",
            (le_id, evid, actor_id),
        )
        conn.execute(
            "INSERT INTO core.champion_assignment (champion_assignment_id, executable_version_id, "
            "lifecycle_event_id, is_revocation, reason, actor_id, acting_role_code) "
            "VALUES (%s, %s, %s, false, 'Demo seed', %s, 'ai_governance')",
            (ca_id, evid, le_id, actor_id),
        )
        lines.append(f"  task '{t['name']}' v1.0.0 (champion) — created")

    # ── Inference configs ─────────────────────────────────────────────────────
    ref_rows = conn.execute(
        "SELECT reference_code, model_reference_id FROM core.model_reference"
    ).fetchall()
    refs = {code: str(mid) for code, mid in ref_rows}

    _inference_configs = [
        {"code": "triage-balanced", "temperature": "0.300", "max_tokens": 4096,
         "refs": [("classification-primary", 1)]},
        {"code": "classification-strict", "temperature": "0.000", "max_tokens": 2048,
         "refs": [("classification-primary", 1)]},
        {"code": "extraction-deterministic", "temperature": "0.000", "max_tokens": 8192,
         "refs": [("extraction-primary", 1), ("extraction-fallback", 2)]},
    ]
    _exe_inference_map = {
        "triage-agent": "triage-balanced",
        "appetite-agent": "classification-strict",
        "doc-classifier": "classification-strict",
        "field-extractor": "extraction-deterministic",
        "loss-run-classifier": "extraction-deterministic",
        "completeness-checker": "classification-strict",
    }

    icfg_ids: dict[str, str] = {}
    for ic in _inference_configs:
        icid = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"verity.demo.inference_config.{ic['code']}"))
        icfg_ids[ic["code"]] = icid
        exists = conn.execute("SELECT 1 FROM core.inference_config WHERE inference_config_id = %s", (icid,)).fetchone()
        if exists:
            lines.append(f"  inference_config '{ic['code']}' — exists, skipped")
            continue
        conn.execute(
            "INSERT INTO core.inference_config (inference_config_id, temperature, max_tokens) VALUES (%s, %s, %s)",
            (icid, ic["temperature"], ic["max_tokens"]),
        )
        for ref_code, priority in ic["refs"]:
            if ref_code not in refs:
                lines.append(f"  WARN: model reference '{ref_code}' not found — skipping")
                continue
            conn.execute(
                "INSERT INTO core.inference_config_model (inference_config_id, model_reference_id, priority) "
                "VALUES (%s, %s, %s) ON CONFLICT DO NOTHING",
                (icid, refs[ref_code], priority),
            )
        lines.append(f"  inference_config '{ic['code']}' — created")

    for exe_code, ic_code in _exe_inference_map.items():
        evid = _exe_version_id(exe_code)
        icid = icfg_ids[ic_code]
        conn.execute(
            "UPDATE core.executable_version SET inference_config_id = %s "
            "WHERE executable_version_id = %s AND inference_config_id IS NULL",
            (icid, evid),
        )
    lines.append("  inference configs wired to executable versions")

    # ── Delegation ───────────────────────────────────────────────────────────
    parent_evid = _exe_version_id("triage-agent")
    child_eid = _executable_id("appetite-agent")
    del_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, "verity.demo.delegation.triage-to-appetite"))
    exists = conn.execute(
        "SELECT 1 FROM core.executable_version_delegation WHERE delegation_id = %s", (del_id,)
    ).fetchone()
    if exists:
        lines.append("  delegation triage→appetite — exists, skipped")
    else:
        conn.execute(
            "INSERT INTO core.executable_version_delegation "
            "(delegation_id, parent_version_id, child_executable_id, scope, rationale) "
            "VALUES (%s, %s, %s, %s, %s)",
            (del_id, parent_evid, child_eid,
             json.dumps({"action": "appetite_check", "required": True}),
             "Triage agent delegates appetite assessment to the appetite-agent champion."),
        )
        lines.append("  delegation triage→appetite — created")

    # ── Model / tool metadata patches ────────────────────────────────────────
    conn.execute(
        "UPDATE core.model SET context_window = 200000 WHERE context_window IS NULL "
        "AND model_code IN ('claude-opus-4-8', 'claude-sonnet-4-6', 'claude-haiku-4-5')"
    )
    conn.execute(
        "UPDATE core.tool SET is_write_operation = true "
        "WHERE name = 'store-extraction-result' AND is_write_operation = false"
    )
    lines.append("  model/tool metadata patched")

    return lines


async def _seed_003_loop_async(db_url: str, intake_id: str, you_id: str, team_id: str) -> list[str]:
    """Seed the 003 governance depth loop on a given approved intake using the service layer:
    obligation resolution → record evidence (1st obligation satisfied) → approve exception (2nd
    obligation excepted) → registry asset linked + promoted to champion.
    Returns human-readable summary lines. Idempotent — skips if obligations already resolved."""
    from psycopg.rows import dict_row
    from psycopg_pool import AsyncConnectionPool
    from uuid import UUID

    from verity.hub.auth.models import AuthContext, Principal
    from verity.hub.obligation import service as obl_svc
    from verity.hub.obligation.models import ExceptionInput
    from verity.hub.registry import service as reg_svc

    lines: list[str] = []

    def _ctx(actor_id: str, roles: set[str], action: str, role: str) -> AuthContext:
        return AuthContext(
            principal=Principal(actor_id=actor_id, tenant_id="demo", microsoft_oid=actor_id,
                                display_name="Demo", platform_roles=roles),
            action=action, acting_role=role,
        )

    you_ctx = _ctx(you_id, {"ai_governance", "business_owner", "compliance", "engineer"}, "record_evidence", "ai_governance")
    team_ctx = _ctx(team_id, {"compliance", "security", "business_owner"}, "approve_exception", "compliance")

    pool = AsyncConnectionPool(conninfo=db_url, open=False, kwargs={"row_factory": dict_row})
    await pool.open()
    try:
        async with pool.connection() as conn:
            iid = UUID(intake_id)

            # 1. Resolve obligations (idempotent — supersedes if already present).
            count = await obl_svc.resolve(conn, iid, you_ctx)
            lines.append(f"    obligations resolved: {count}")
            if count == 0:
                lines.append("    (no metamodel requirements matched — check ZUW frameworks/domains)")
                return lines

            # 2. Get the obligation set.
            oset = await obl_svc.get_obligation_set(conn, iid)
            obligations = oset.obligations
            if not obligations:
                return lines

            # 3. Record evidence for the first obligation's first unevidenced control → satisfied.
            first = obligations[0]
            unevidenced = [c for c in first.controls if not c.evidenced]
            if unevidenced:
                for ctrl in unevidenced:
                    await obl_svc.record_evidence(
                        conn, first.intake_obligation_id, ctrl.control_code,
                        "Demo: system testing confirmed compliance.", you_ctx,
                    )
                lines.append(f"    evidence recorded for '{first.requirement_code}' → satisfied")
            else:
                lines.append(f"    '{first.requirement_code}' already evidenced")

            # 4. Raise + approve an exception for the second obligation (if there is one).
            if len(obligations) >= 2:
                second = obligations[1]
                ex_input = ExceptionInput(
                    requirement_code=second.requirement_code,
                    waived_tier_level=second.target_tier,
                    compensating_controls="Manual review by compliance officer each quarter.",
                    rationale="Demo: legacy system constraint; compensating review in place.",
                    expires_at="2027-12-31T00:00:00Z",
                )
                exc = await obl_svc.raise_exception(conn, iid, ex_input, you_ctx)
                from uuid import UUID as _UUID
                exc_signoff = await obl_svc.signoff_exception(conn, exc.compliance_exception_id, "approved", team_ctx)
                lines.append(f"    exception approved for '{second.requirement_code}' → excepted")
            else:
                lines.append("    only 1 obligation — skipping exception demo")

        # 5. Create a registry asset + link to the approved intake + promote to champion.
        #    Each step needs its own connection (registry service does its own transactions).
        eid = UUID(_executable_id("ZUW-fraud-scorer"))
        async with pool.connection() as conn:
            existing = await reg_svc.list_executables(conn)
            if any(str(e.executable_id) == str(eid) for e in existing):
                lines.append("    registry asset already exists — skipped")
                return lines

        # Use raw SQL to insert with a deterministic ID (service always generates a new uuidv7).
        async with pool.connection() as conn:
            await conn.execute(
                "INSERT INTO core.executable (executable_id, kind_code, name, description, created_by_actor_id, created_role_code) "
                "VALUES (%s, 'task', 'Fraud Detection Scorer', 'Demo: detects anomalous claims.', %s, 'engineer') "
                "ON CONFLICT (executable_id) DO NOTHING",
                (str(eid), you_id),
            )
            # version
            async with conn.transaction():
                ver = await reg_svc.create_version(conn, eid, you_ctx)
            if ver is None:
                lines.append("    could not create version")
                return lines
            vid = ver.executable_version_id

        # link to intake
        async with pool.connection() as conn:
            try:
                async with conn.transaction():
                    await reg_svc.link(conn, iid, eid, None, you_ctx)
                lines.append(f"    asset linked to intake")
            except ValueError as e:
                lines.append(f"    link skipped: {e}")

        # advance to champion (requires approved intake + all_resolved)
        async with pool.connection() as conn:
            try:
                async with conn.transaction():
                    await reg_svc.advance_lifecycle(conn, vid, "candidate", you_ctx)
                    await reg_svc.advance_lifecycle(conn, vid, "champion", you_ctx)
                lines.append(f"    asset promoted to champion (gate passed)")
            except Exception as e:
                lines.append(f"    promotion skipped: {e}")

    finally:
        await pool.close()

    return lines


def _seed_003_loop(db_url: str, intake_id: str, you_id: str, team_id: str) -> list[str]:
    """Sync wrapper — runs the async 003 loop seeder via asyncio.run()."""
    return asyncio.run(_seed_003_loop_async(db_url, intake_id, you_id, team_id))

# Each demo app: who proposes/owns it, what state, and a self-documenting name + description so the
# screen explains what it's demonstrating. owner/proposer ∈ {"you", "team"}.
# state ∈ {"draft", "pending", "rejected"}.
DEMO_APPS = [
    {
        "code": "ZAP", "name": "Life New Business Triage",
        "description": "Screens individual life new-business applications: extracts medical and "
                       "financial disclosures, scores mortality risk, and refers substandard cases to an underwriter.",
        "owner": "team", "proposer": "team", "state": "pending",
        "classification": "tier4_pii_restricted", "frameworks": ["eu_ai_act", "nydfs"],
        "domains": ["model_risk", "fairness", "privacy"], "jurisdictions": ["ny", "ca"],
        "affects_consumers": True, "processes_pii": True, "consumer_facing": False,
    },
    {
        "code": "ZMA", "name": "Personal Auto Underwriting",
        "description": "Extracts risk attributes from personal-auto submissions, scores appetite, and "
                       "routes high-materiality cases to a human underwriter for review.",
        "owner": "you", "proposer": "you", "state": "draft",
        "classification": "tier2_internal", "frameworks": ["internal_only"],
        "domains": ["model_risk"], "jurisdictions": ["us_federal"],
        "affects_consumers": False, "processes_pii": False, "consumer_facing": False,
    },
    {
        "code": "ZMI", "name": "Claims Severity Predictor",
        "description": "Predicts likely claim severity at first notice of loss to prioritise adjuster "
                       "assignment and support early reserve setting.",
        "owner": "you", "proposer": "you", "state": "pending",
        "classification": "tier3_confidential", "frameworks": ["nist_ai_rmf"],
        "domains": ["fairness", "robustness"], "jurisdictions": ["ny"],
        "affects_consumers": True, "processes_pii": False, "consumer_facing": True,
    },
    {
        "code": "ZMR", "name": "Commercial Property Risk Scoring",
        "description": "Scores commercial-property submissions for catastrophe and occupancy risk to "
                       "support quote and decline decisions.",
        "owner": "you", "proposer": "you", "state": "rejected",
        "classification": "tier3_confidential", "frameworks": ["colorado_sb21_169"],
        "domains": ["fairness", "transparency"], "jurisdictions": ["co"],
        "affects_consumers": True, "processes_pii": False, "consumer_facing": False,
    },
    {
        # An ACTIVE application — the governed home that hosts the demo use cases (intakes can only be
        # created under an active app). Owned by you, so its use cases populate MY USE CASES.
        "code": "ZUW", "name": "Underwriting Workbench",
        "description": "The governed home for underwriting AI use cases — a live application hosting "
                       "submission-triage, severity and retention assistants under active oversight.",
        "owner": "you", "proposer": "you", "state": "active",
        "classification": "tier3_confidential", "frameworks": ["nist_ai_rmf", "nydfs"],
        "domains": ["model_risk", "fairness"], "jurisdictions": ["ny", "ca"],
        "affects_consumers": True, "processes_pii": True, "consumer_facing": False,
    },
]

_ROLE = {"you": "ai_governance", "team": "business_owner"}  # the capacity each acts in


def _resolve_you(conn) -> tuple[str, str] | None:
    """Your real (Entra) actor — the most recent human account that ISN'T a mock login. Mock logins
    are all provisioned with email 'dev@localhost', so excluding that picks the real Entra user.
    Returns (actor_id, display_name)."""
    row = conn.execute(
        "SELECT au.actor_id, ac.display_name "
        "FROM core.account_user au JOIN core.actor ac ON ac.actor_id = au.actor_id "
        "WHERE au.email IS DISTINCT FROM 'dev@localhost' "
        "ORDER BY au.created_at DESC LIMIT 1"
    ).fetchone()
    return (str(row[0]), row[1]) if row else None


def _ensure_teammate(conn) -> str:
    tid = _teammate_id()
    if not conn.execute("SELECT 1 FROM core.actor WHERE actor_id = %s", (tid,)).fetchone():
        conn.execute(
            "INSERT INTO core.actor (actor_id, actor_type_code, display_name) VALUES (%s,'human',%s)",
            (tid, DEMO_TEAMMATE_NAME),
        )
    return tid


def teardown(conn) -> int:
    """Remove every demo row (apps + their dependents + the demo teammate). Returns apps removed."""
    ids = [str(r[0]) for r in conn.execute(
        "SELECT application_id FROM core.application WHERE code LIKE %s", (DEMO_CODE_PREFIX + "%",)
    ).fetchall()]
    if ids:
        # use cases first — intake→application is ON DELETE RESTRICT, and intake approvals are too.
        # (requirements + assessment snapshots cascade when the intake row goes.)
        intake_ids = [str(r[0]) for r in conn.execute(
            "SELECT intake_id FROM core.intake WHERE application_id = ANY(%s)", (ids,)
        ).fetchall()]
        if intake_ids:
            # compliance_exception has ON DELETE RESTRICT — must remove before intake.
            conn.execute("DELETE FROM core.compliance_exception WHERE scope_intake_id = ANY(%s)", (intake_ids,))
            conn.execute("DELETE FROM core.approval_signoff WHERE approval_request_id IN "
                         "(SELECT approval_request_id FROM core.approval_request WHERE target_intake_id = ANY(%s))", (intake_ids,))
            conn.execute("DELETE FROM core.approval_request WHERE target_intake_id = ANY(%s)", (intake_ids,))
            conn.execute("DELETE FROM core.intake WHERE intake_id = ANY(%s)", (intake_ids,))
        # demo registry assets: agents, tasks, prompts, tools
        all_exe_codes = (
            ["ZUW-fraud-scorer"]
            + [a["code"] for a in _DEMO_AGENTS]
            + [t["code"] for t in _DEMO_TASKS]
        )
        demo_exe_ids = [_executable_id(c) for c in all_exe_codes]
        for eid in demo_exe_ids:
            if conn.execute("SELECT 1 FROM core.executable WHERE executable_id = %s", (eid,)).fetchone():
                conn.execute("DELETE FROM core.champion_assignment WHERE executable_version_id IN "
                             "(SELECT executable_version_id FROM core.executable_version WHERE executable_id = %s)", (eid,))
                conn.execute("DELETE FROM core.lifecycle_event WHERE executable_version_id IN "
                             "(SELECT executable_version_id FROM core.executable_version WHERE executable_id = %s)", (eid,))
                conn.execute("DELETE FROM core.executable_prompt_assignment WHERE executable_version_id IN "
                             "(SELECT executable_version_id FROM core.executable_version WHERE executable_id = %s)", (eid,))
                conn.execute("DELETE FROM core.executable_tool_assignment WHERE executable_version_id IN "
                             "(SELECT executable_version_id FROM core.executable_version WHERE executable_id = %s)", (eid,))
                conn.execute("DELETE FROM core.executable_version WHERE executable_id = %s", (eid,))
                conn.execute("DELETE FROM core.executable WHERE executable_id = %s", (eid,))
        # prompts seeded by _seed_registry
        for p in _DEMO_PROMPTS:
            pid = _prompt_id(p["code"])
            if conn.execute("SELECT 1 FROM core.prompt WHERE prompt_id = %s", (pid,)).fetchone():
                conn.execute("DELETE FROM core.prompt_version WHERE prompt_id = %s", (pid,))
                conn.execute("DELETE FROM core.prompt WHERE prompt_id = %s", (pid,))
        # tools seeded by _seed_registry
        for t in _DEMO_TOOLS:
            tid = _tool_id(t["code"])
            if conn.execute("SELECT 1 FROM core.tool WHERE tool_id = %s", (tid,)).fetchone():
                conn.execute("DELETE FROM core.tool_version WHERE tool_id = %s", (tid,))
                conn.execute("DELETE FROM core.tool WHERE tool_id = %s", (tid,))
        conn.execute("DELETE FROM core.approval_signoff WHERE approval_request_id IN "
                     "(SELECT approval_request_id FROM core.approval_request WHERE target_application_id = ANY(%s))", (ids,))
        conn.execute("DELETE FROM core.approval_request WHERE target_application_id = ANY(%s)", (ids,))
        conn.execute("DELETE FROM core.application_regulatory_framework WHERE application_id = ANY(%s)", (ids,))
        conn.execute("DELETE FROM core.application_governance_domain WHERE application_id = ANY(%s)", (ids,))
        conn.execute("DELETE FROM core.application_jurisdiction WHERE application_id = ANY(%s)", (ids,))
        conn.execute("DELETE FROM core.actor_app_role_grant WHERE application_id = ANY(%s)", (ids,))
        conn.execute("DELETE FROM core.application WHERE application_id = ANY(%s)", (ids,))
    # the synthetic colleague (by deterministic id) + any legacy '[Demo]' actors from older runs
    conn.execute("DELETE FROM core.actor WHERE actor_id = %s OR display_name LIKE %s", (_teammate_id(), "[Demo]%"))
    return len(ids)


def _create(conn, spec: dict, you: str, team: str) -> None:
    owner = you if spec["owner"] == "you" else team
    proposer = you if spec["proposer"] == "you" else team
    role = _ROLE[spec["proposer"]]
    app_id = _app_id(spec["code"])  # stable across refreshes
    status = "active" if spec["state"] == "active" else "pending"
    conn.execute(
        "INSERT INTO core.application "
        "(application_id, code, name, description, application_status_code, data_classification_code, "
        " business_owner_actor_id, affects_consumers, processes_pii, consumer_facing, "
        " created_by_actor_id, created_role_code) "
        "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
        (app_id, spec["code"], spec["name"], spec["description"], status, spec["classification"], owner,
         spec["affects_consumers"], spec["processes_pii"], spec["consumer_facing"], proposer, role),
    )
    for fw in spec["frameworks"]:
        conn.execute("INSERT INTO core.application_regulatory_framework (application_id, framework_code, created_by_actor_id) VALUES (%s,%s,%s)", (app_id, fw, proposer))
    for dom in spec["domains"]:
        conn.execute("INSERT INTO core.application_governance_domain (application_id, governance_domain_code, created_by_actor_id) VALUES (%s,%s,%s)", (app_id, dom, proposer))
    for jur in spec["jurisdictions"]:
        conn.execute("INSERT INTO core.application_jurisdiction (application_id, jurisdiction_code, created_by_actor_id) VALUES (%s,%s,%s)", (app_id, jur, proposer))

    # draft = never submitted; active = an already-onboarded live app (no open onboarding approval —
    # it hosts use cases instead). Neither carries an onboarding approval_request.
    if spec["state"] in ("draft", "active"):
        return

    appr_id = str(conn.execute(
        "INSERT INTO core.approval_request (request_kind_code, target_application_id, opened_by_actor_id, opened_role_code, status_code) "
        "VALUES ('application_onboarding', %s, %s, %s, 'pending') RETURNING approval_request_id",
        (app_id, proposer, role),
    ).fetchone()[0])

    if spec["state"] == "rejected":
        # a teammate rejects it as AI Governance → request closed 'rejected'; the app stays pending so
        # it can be remediated (Edit & re-submit).
        conn.execute(
            "INSERT INTO core.approval_signoff (approval_request_id, approver_actor_id, signed_as_role_code, decision_code, comment) "
            "VALUES (%s,%s,'ai_governance','rejected',%s)",
            (appr_id, team, "Rejected — the stated purpose is too broad; please narrow the scope and resubmit."),
        )
        conn.execute("UPDATE core.approval_request SET status_code = 'rejected' WHERE approval_request_id = %s", (appr_id,))
    # state == "pending": leave the approval open (In review / Awaiting your approval)


# ── Demo use cases (intakes) under the active 'ZUW' application ──────────────────────────────────
# A spread across the lifecycle. owner ∈ {"you","team"}; status is the intake_status_code; tier/naic/
# mtier/classification are the computed classification (written directly — the seeder bypasses the
# questionnaire but also writes a matching assessment snapshot so the tabs aren't blank). approval ∈
# {None, "pending_you", "pending_team", "approved"}: no approval row / an open kind=intake approval
# opened by you / by the teammate / a closed fully-signed approval.
DEMO_INTAKES = [
    {
        "code": "uc-triage", "title": "New-business submission triage",
        "description": "Reads incoming submissions, extracts key risk attributes, and routes them to the "
                       "right underwriting queue. A fresh draft — not yet assessed.",
        "owner": "you", "status": "proposed",
        "tier": None, "naic": None, "mtier": None, "classification": None, "assess": None, "approval": None,
        "reqs": [
            ("business", "Reduce manual triage time", "Route low-complexity submissions automatically to cut average triage time."),
            ("functional", "Attribute extraction", "Extract line of business, state, and effective date from each submission packet."),
        ],
    },
    {
        "code": "uc-quote-check", "title": "Quote completeness checker",
        "description": "Flags missing or inconsistent fields on a quote before it is bound so underwriters "
                       "fix gaps up front. Assessed (limited) — ready to submit.",
        "owner": "you", "status": "impact_assessment",
        "tier": "limited", "naic": "non_material", "mtier": "medium", "classification": "tier2_internal",
        "assess": dict(decision_type="underwriting", consumer_effect="rate_or_premium", populations=["brokers_agents"],
                       scale="limited", autonomy="recommends_signoff", stop=True,
                       data_name="Quote line items", data_type="tabular", source="internal", pii="none"),
        "approval": None,
        "reqs": [
            ("business", "Fewer bind-time corrections", "Reduce post-bind endorsements caused by missing quote data."),
            ("functional", "Completeness rules", "Check each quote against the required-field set for its product."),
            ("compliance", "Audit trail", "Record every completeness flag and its resolution."),
        ],
    },
    {
        "code": "uc-severity", "title": "Auto claim severity estimator",
        "description": "Predicts likely claim severity at first notice of loss to prioritise adjuster "
                       "assignment. Submitted (high tier) — awaiting the approval quorum.",
        "owner": "you", "status": "in_review",
        "tier": "high", "naic": "material", "mtier": "high", "classification": "tier3_confidential",
        "assess": dict(decision_type="claims", consumer_effect="claim_denial", annex_iii=True,
                       populations=["policyholders_consumers"], scale="production_wide",
                       autonomy="recommends_signoff", stop=True,
                       controls=[{"name": "Adjuster review", "stage": "pre_decision", "responsible_role": "adjuster",
                                  "trigger": "high-severity prediction", "can_override": True, "what_inspected": "severity band + drivers"}],
                       data_name="First-notice-of-loss reports", data_type="document", source="internal", pii="direct",
                       risks=[{"description": "Under-reserving on atypical claims.", "category": "robustness",
                               "likelihood": "possible", "severity": "moderate", "mitigation": "Human review of outliers", "residual": "low"}]),
        "approval": "pending_you",  # you submitted → you cannot sign (separation-of-duty demo)
        "reqs": [
            ("business", "Faster severe-claim response", "Route likely high-severity claims to senior adjusters within the hour."),
            ("functional", "Severity score", "Produce a calibrated severity band per claim at FNOL."),
            ("non_functional", "Latency", "Return a score within 2 seconds of FNOL intake."),
        ],
    },
    {
        "code": "uc-retention", "title": "Renewal retention scorer",
        "description": "Scores renewing policies for lapse risk so servicing can intervene early. "
                       "Submitted by a teammate (limited tier) — awaiting YOUR sign-off.",
        "owner": "team", "status": "in_review",
        "tier": "limited", "naic": "non_material", "mtier": "medium", "classification": "tier2_internal",
        "assess": dict(decision_type="servicing", consumer_effect="marketing_only", populations=["policyholders_consumers"],
                       scale="limited", autonomy="recommends_review", stop=True,
                       data_name="Renewal & engagement history", data_type="tabular", source="internal", pii="indirect"),
        "approval": "pending_team",  # teammate submitted → you (AI Governance) can approve it
        "reqs": [
            ("business", "Improve retention", "Surface at-risk renewals in time for a servicing outreach."),
            ("functional", "Lapse-risk score", "Score every renewing policy 30 days before expiry."),
        ],
    },
    {
        "code": "uc-doc-classify", "title": "Policy document classifier",
        "description": "Sorts inbound policy documents by type to speed routing. Fully approved (minimal "
                       "tier) — a completed, locked use case.",
        "owner": "you", "status": "approved",
        "tier": "minimal", "naic": "non_material", "mtier": "low", "classification": "tier2_internal",
        "assess": dict(decision_type="internal_ops", consumer_effect="none", populations=["internal_only"],
                       scale="pilot", autonomy="assists", stop=True,
                       data_name="Scanned policy documents", data_type="document", source="internal", pii="none"),
        "approval": "approved",  # opened by you, signed off by the teammate as business_owner
        "reqs": [
            ("business", "Faster document routing", "Cut manual sorting of inbound policy documents."),
            ("functional", "Document type", "Classify each document into one of the known policy-document types."),
        ],
    },
    {
        # 003 depth-loop showcase: approved high-tier intake with resolved obligations, a satisfied
        # evidence record, an approved exception, a linked registry asset promoted to champion.
        "code": "uc-fraud-detect", "title": "Claims fraud detection",
        "description": "Scores incoming claims for fraud indicators using behavioural signals and "
                       "claims history. High-tier — the full governance loop (obligations → asset → "
                       "champion) is seeded so the 003 UI is populated out of the box.",
        "owner": "you", "status": "approved",
        "tier": "high", "naic": "material", "mtier": "high", "classification": "tier3_confidential",
        "assess": dict(decision_type="claims", consumer_effect="claim_denial", annex_iii=True,
                       populations=["policyholders_consumers"], scale="production_wide",
                       autonomy="recommends_signoff", stop=True,
                       data_name="Claims event stream", data_type="document", source="internal", pii="direct",
                       risks=[{"description": "False positives flagging legitimate claims.",
                                "category": "fairness", "likelihood": "possible", "severity": "high",
                                "mitigation": "Human adjuster sign-off on all flagged claims", "residual": "low"}]),
        "approval": "approved",
        "reqs": [
            ("business", "Reduce fraud losses", "Flag anomalous claims before payment to reduce loss ratio."),
            ("functional", "Fraud score", "Output a calibrated fraud-risk score at claim submission."),
            ("compliance", "Explainability", "Provide a human-readable rationale for each flagged claim."),
        ],
        "seed_loop": True,  # triggers _seed_003_loop after intake creation
    },
]


def _assess_json(a: dict, classification: str) -> str:
    """Build a full assessment snapshot (the comprehensive AssessmentInput shape the portal reads) from
    compact params, so an assessed demo intake shows a filled sectioned assessment."""
    return json.dumps({
        "decision_context": {
            "decision_type": a["decision_type"], "consumer_effect": a["consumer_effect"],
            "annex_iii_high_risk": a.get("annex_iii", False), "solely_automated": a.get("solely", False),
            "affected_populations": a["populations"], "deployment_scale": a["scale"],
        },
        "data_inventory": [
            {"name": a["data_name"], "direction": "input", "data_type": a.get("data_type", "document"),
             "source": a.get("source", "internal"), "classification": classification, "pii_presence": a["pii"],
             "lawful_basis": a.get("lawful_basis"), "retention": a.get("retention")},
        ],
        "human_oversight": {
            "autonomy_level": a["autonomy"], "stop_mechanism": a.get("stop", True),
            "controls": a.get("controls", []),
        },
        "risks": a.get("risks", []),
        "fairness": a.get("fairness", {"disparate_impact_tested": False, "protected_classes_tested": [], "metrics": []}),
    })


def _create_intake(conn, app_id: str, spec: dict, you: str, team: str) -> None:
    creator = you if spec["owner"] == "you" else team
    role = _ROLE[spec["owner"]]
    iid = _intake_id(spec["code"])  # stable across refreshes
    conn.execute(
        "INSERT INTO core.intake "
        "(intake_id, application_id, title, description, intake_status_code, ai_risk_tier_code, "
        " naic_materiality_code, materiality_tier_code, data_classification_code, created_by_actor_id, created_role_code) "
        "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
        (iid, app_id, spec["title"], spec["description"], spec["status"], spec["tier"],
         spec["naic"], spec["mtier"], spec["classification"], creator, role),
    )
    for kind, title, body in spec["reqs"]:
        conn.execute(
            "INSERT INTO core.intake_requirement (intake_id, requirement_kind_code, title, body, created_by_actor_id, created_role_code) "
            "VALUES (%s,%s,%s,%s,%s,%s)",
            (iid, kind, title, body, creator, role),
        )
    if spec["assess"]:
        conn.execute(
            "INSERT INTO core.intake_impact_assessment (intake_id, revision, assessment, created_by_actor_id, created_role_code) "
            "VALUES (%s, 1, %s, %s, %s)",
            (iid, _assess_json(spec["assess"], spec["classification"]), creator, role),
        )
    appr = spec["approval"]
    if appr:
        opener = team if appr == "pending_team" else creator
        opener_role = "ai_governance" if opener == you else "business_owner"
        status = "approved" if appr == "approved" else "pending"
        appr_id = str(conn.execute(
            "INSERT INTO core.approval_request (request_kind_code, target_intake_id, opened_by_actor_id, opened_role_code, status_code) "
            "VALUES ('intake', %s, %s, %s, %s) RETURNING approval_request_id",
            (iid, opener, opener_role, status),
        ).fetchone()[0])
        if appr == "approved":
            # minimal-tier quorum = [business_owner]; the teammate signs (≠ the opener — separation of duty)
            conn.execute(
                "INSERT INTO core.approval_signoff (approval_request_id, approver_actor_id, signed_as_role_code, decision_code, comment) "
                "VALUES (%s,%s,'business_owner','approved',%s)",
                (appr_id, team, "Approved — low-risk internal classifier."),
            )


def run(db_url: str, mode: str) -> list[str]:
    """mode ∈ {"idempotent", "refresh"}. Returns human-readable summary lines."""
    out: list[str] = []
    with psycopg.connect(db_url, autocommit=False) as conn:
        you = _resolve_you(conn)
        if you is None:
            return ["No Entra account found — sign in via Entra once (so your account exists), then re-run."]
        you_id, you_name = you
        out.append(f"demo owner = {you_name}")

        if mode == "refresh":
            removed = teardown(conn)
            out.append(f"refresh: removed {removed} existing demo app(s)")

        team = _ensure_teammate(conn)
        existing = {r[0] for r in conn.execute(
            "SELECT code FROM core.application WHERE code LIKE %s", (DEMO_CODE_PREFIX + "%",)
        ).fetchall()}
        created = 0
        for spec in DEMO_APPS:
            if spec["code"] in existing:
                out.append(f"  {spec['code']} {spec['name']} — exists, skipped")
                continue
            _create(conn, spec, you_id, team)
            created += 1
            out.append(f"  {spec['code']} {spec['name']} — created")

        # use cases (intakes) under the active ZUW application (exists after the loop above)
        zuw_id = _app_id("ZUW")
        existing_intakes = {str(r[0]) for r in conn.execute(
            "SELECT intake_id FROM core.intake WHERE application_id = %s", (zuw_id,)
        ).fetchall()}
        loop_intakes: list[str] = []  # intake_ids that need the 003 depth-loop seeded
        for ispec in DEMO_INTAKES:
            iid = _intake_id(ispec["code"])
            if iid in existing_intakes:
                out.append(f"    use case '{ispec['title']}' — exists, skipped")
                continue
            _create_intake(conn, zuw_id, ispec, you_id, team)
            created += 1
            out.append(f"    use case '{ispec['title']}' ({ispec['status']}) — created")
            if ispec.get("seed_loop"):
                loop_intakes.append(iid)

        # Registry demo entities (prompts, tools, agents, tasks) — idempotent, part of same txn
        out.append("registry entities:")
        reg_lines = _seed_registry(conn, you_id, app_id=zuw_id)
        out.extend(reg_lines)

        conn.commit()
        out.append(f"done: {created} created, {len(existing)} skipped")

    # Seed the 003 governance depth loop for newly created loop intakes (after commit so the intake
    # rows are visible to the async pool's connections).
    for iid in loop_intakes:
        out.append(f"  seeding 003 depth loop for {iid}…")
        loop_lines = _seed_003_loop(db_url, iid, you_id, team)
        out.extend(loop_lines)

    return out

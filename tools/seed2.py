#!/usr/bin/env python3
"""tools/seed2.py — API-driven demo seed (full refresh).

Creates governed demo data through the Verity API using mock auth.  The only
SQL is in the teardown step (deleting demo applications and their owned assets
identified by TLA code).

Applications created:
  ZUW — Zurich Underwriting Platform  (active, intake approved, full asset set)
  ZCL — Zurich Claims Analytics       (active, no assets)
  ZEP — Zurich Experimental Platform  (proposed, pending — never submitted)

Usage:
  python tools/seed2.py [--base-url http://localhost:8000] \\
                        [--db-url postgresql://verity:verity@localhost:5432/verity]
"""
from __future__ import annotations

import argparse
import sys

import httpx
import psycopg
import psycopg.rows
from rich.console import Console
from rich.panel import Panel

# ── Constants ─────────────────────────────────────────────────────────────────

DEMO_CODES = ("ZUW", "ZCL", "ZEP")

# PERSONA A — author: proposes, assesses, submits, creates registry assets
PERSONA_A_ROLES = ["ai_governance", "business_owner", "engineer"]
# PERSONA B — approver: signs off on all approvals
PERSONA_B_ROLES = ["ai_governance", "business_owner", "compliance", "legal", "model_risk"]

console = Console()

# ── ZUW application payload ───────────────────────────────────────────────────

ZUW_ASSESSMENT = {
    "decision_context": {
        "decision_type": "underwriting",
        "consumer_effect": "coverage_or_eligibility",
        "annex_iii_high_risk": True,
        "solely_automated": False,
        "affected_populations": ["policyholders_consumers"],
        "deployment_scale": "production_wide",
    },
    "data_inventory": [
        {
            "name": "Loss Run History",
            "direction": "input",
            "data_type": "document",
            "source": "third_party",
            "classification": "tier3_confidential",
            "pii_presence": "indirect",
            "lawful_basis": "legitimate_interest",
            "retention": "7 years",
        },
        {
            "name": "Applicant Demographics",
            "direction": "input",
            "data_type": "tabular",
            "source": "consumer_provided",
            "classification": "tier4_pii_restricted",
            "pii_presence": "direct",
            "lawful_basis": "consent",
            "retention": "5 years",
        },
        {
            "name": "Risk Score Output",
            "direction": "output",
            "data_type": "derived",
            "source": "system_generated",
            "classification": "tier3_confidential",
            "pii_presence": "indirect",
        },
    ],
    "human_oversight": {
        "autonomy_level": "recommends_signoff",
        "stop_mechanism": True,
        "controls": [
            {
                "name": "Underwriter Review",
                "stage": "pre_decision",
                "responsible_role": "Underwriter",
                "trigger": "Model score outside confidence band",
                "can_override": True,
                "what_inspected": "Triage recommendation and supporting factors",
            },
            {
                "name": "Supervisor Escalation",
                "stage": "exception",
                "responsible_role": "Senior Underwriter",
                "trigger": "High-value account or borderline risk",
                "can_override": True,
            },
        ],
    },
}

# ── Model catalog ─────────────────────────────────────────────────────────────

MODEL_CATALOG = [
    {
        "model_code": "claude-sonnet-4-6",
        "provider": "anthropic",
        "modality": "chat",
        "price": {"input_price_per_1k": 3.0, "output_price_per_1k": 15.0, "currency_code": "usd"},
    },
    {
        "model_code": "claude-haiku-4-5-20251001",
        "provider": "anthropic",
        "modality": "chat",
        "price": {"input_price_per_1k": 0.8, "output_price_per_1k": 4.0, "currency_code": "usd"},
    },
]

MODEL_REFERENCES = [
    {"reference_code": "anthropic:balanced",       "name": "Anthropic Balanced",       "model_code": "claude-sonnet-4-6"},
    {"reference_code": "anthropic:classification", "name": "Anthropic Classification", "model_code": "claude-haiku-4-5-20251001"},
    {"reference_code": "anthropic:extraction",     "name": "Anthropic Extraction",     "model_code": "claude-haiku-4-5-20251001"},
]

# ── Inference profiles ─────────────────────────────────────────────────────────
# Name → CreateInferenceConfig payload. _model_ref is resolved to model_reference_id at seed time.

INFERENCE_PROFILES = {
    "agent_balanced": {
        "temperature": 0.2,
        "max_tokens": 4096,
        "params": {"top_p": 0.95},
        "_model_ref": "anthropic:balanced",
    },
    "classification_strict": {
        "temperature": 0.0,
        "max_tokens": 512,
        "params": {"top_p": 0.9},
        "_model_ref": "anthropic:classification",
    },
    "extraction_deterministic": {
        "temperature": 0.0,
        "max_tokens": 2048,
        "params": {},
        "_model_ref": "anthropic:extraction",
    },
}

# ── Prompt catalog ─────────────────────────────────────────────────────────────
# name → {display_name, description, blocks, user_companion: {key, display_name, description, blocks}}
# All blocks conform to the prompt-editor-architecture spec (specs/ui/prompt-editor-architecture.md):
#   prose  → {id, kind:"prose", text}
#   var    → {id, kind:"var", name, type, desc, eg?, opts?, req}
#   list   → {id, kind:"list", items}
#   code   → {id, kind:"code", lang, code, caption?}
#   table  → {id, kind:"table", headers, rows, caption?}
# No "role" field appears in any block — api_role_code lives on executable_prompt_assignment.

PROMPT_CATALOG = {
    "triage-system": {
        "display_name": "Triage Agent System Prompt",
        "description": "Defines triage agent role, tool-call sequence, output schema, and HITL escalation rules.",
        "blocks": [
            {"id": "s1", "kind": "prose", "text": (
                "You are the Submission Risk Triage Agent for a commercial lines underwriting platform. "
                "You assess D&O and GL submissions and produce a structured risk score before the underwriter reviews."
            )},
            {"id": "s2", "kind": "list", "items": [
                "Call get_submission_context to retrieve account details, coverage information, and submission specifics.",
                "Call get_loss_history to retrieve historical loss data.",
                "Call get_underwriting_guidelines to fetch applicable guidelines for the line of business.",
                "Reason across all retrieved data and produce your assessment.",
            ]},
            {"id": "s3", "kind": "code", "lang": "json", "caption": "Output schema — respond with valid JSON only", "code": (
                '{\n'
                '  "risk_score": "Green" | "Amber" | "Red",\n'
                '  "routing": "assign_to_uw" | "senior_review" | "decline",\n'
                '  "confidence": <float 0.0–1.0>,\n'
                '  "reasoning": "<plain-language narrative>",\n'
                '  "risk_factors": [{"factor": "<name>", "weight": "high|medium|low", "detail": "<string>"}]\n'
                '}'
            )},
            {"id": "s4", "kind": "list", "items": [
                "Never make a final coverage decision. Always route to a licensed underwriter.",
                "HITL required for any recommendation where estimated premium exceeds $500,000.",
                "Red score requires a specific decline rationale citing the relevant guideline section.",
                "Do not speculate beyond the data retrieved from tools.",
            ]},
        ],
        "user_companion": {
            "key": "triage-context",
            "display_name": "Triage Agent Context Template",
            "description": "User message template for triage agent with submission identifiers and tool-call instruction.",
            "blocks": [
                {"id": "u1", "kind": "prose", "text": "Triage the following submission."},
                {"id": "u2", "kind": "var", "name": "submission_id", "type": "string", "desc": "UUID of the submission to triage", "req": True},
                {"id": "u3", "kind": "var", "name": "named_insured",  "type": "string", "desc": "Legal name of the insured entity",                                "req": True},
                {"id": "u4", "kind": "var", "name": "lob",            "type": "enum",   "desc": "Line of business",                   "opts": ["DO", "GL"],         "req": True},
                {"id": "u5", "kind": "var", "name": "requested_limit","type": "number", "desc": "Requested coverage limit in USD",                                   "req": True},
                {"id": "u6", "kind": "prose", "text": "Retrieve all relevant context using your tools, then produce your risk assessment JSON."},
            ],
        },
    },
    "appetite-system": {
        "display_name": "Appetite Agent System Prompt",
        "description": "Defines appetite agent role, tool-call sequence, guidelines-citation requirement, and output schema.",
        "blocks": [
            {"id": "s1", "kind": "prose", "text": (
                "You are the Underwriting Appetite Assessment Agent. You evaluate whether a D&O or GL submission "
                "falls within the company's published underwriting appetite by reasoning against the relevant guidelines document."
            )},
            {"id": "s2", "kind": "list", "items": [
                "Call get_underwriting_guidelines with the submission's line of business.",
                "Call get_submission_context to retrieve the submission characteristics.",
                "Evaluate each material guideline section against the submission.",
                "Produce your determination with specific section citations.",
            ]},
            {"id": "s3", "kind": "code", "lang": "json", "caption": "Output schema — respond with valid JSON only", "code": (
                '{\n'
                '  "determination": "within_appetite" | "borderline" | "outside_appetite",\n'
                '  "confidence": <float 0.0–1.0>,\n'
                '  "guideline_citations": [\n'
                '    {"section": "<e.g. §3.2>", "text": "<quoted requirement>", "finding": "compliant|non_compliant|borderline", "note": "<string>"}\n'
                '  ],\n'
                '  "reasoning": "<plain-language narrative>"\n'
                '}'
            )},
            {"id": "s4", "kind": "list", "items": [
                "Cite section numbers. Do not make appetite determinations without a guideline citation.",
                "'borderline' requires at least one guideline section flagged borderline with a specific note.",
                "outside_appetite determination must cite the specific exclusion section.",
                "You assess appetite compliance only — risk scoring is performed by the triage agent.",
            ]},
        ],
        "user_companion": {
            "key": "appetite-context",
            "display_name": "Appetite Agent Context Template",
            "description": "User message template for appetite agent with submission context and LOB-specific guidance.",
            "blocks": [
                {"id": "u1", "kind": "prose", "text": "Assess underwriting appetite for the following submission."},
                {"id": "u2", "kind": "var", "name": "submission_id", "type": "string", "desc": "UUID of the submission to assess",    "req": True},
                {"id": "u3", "kind": "var", "name": "named_insured",  "type": "string", "desc": "Legal name of the insured entity",    "req": True},
                {"id": "u4", "kind": "var", "name": "lob",            "type": "enum",   "desc": "Line of business", "opts": ["DO", "GL"], "req": True},
                {"id": "u5", "kind": "prose", "text": "Retrieve the applicable guidelines and submission details using your tools, then produce your appetite determination JSON."},
            ],
        },
    },
    "doc-classifier-system": {
        "display_name": "Document Classifier System Prompt",
        "description": "Instructs the document classifier agent on type taxonomy, confidence rules, and JSON output format.",
        "blocks": [
            {"id": "s1", "kind": "prose", "text": (
                "You are the Insurance Document Classification Agent. You classify inbound insurance "
                "documents into one of the defined document types and provide routing guidance."
            )},
            {"id": "s2", "kind": "table", "caption": "Supported document types", "headers": ["Code", "Description"], "rows": [
                ["do_application",  "Directors & Officers liability application form"],
                ["gl_application",  "General Liability application form (ACORD 125 or equivalent)"],
                ["acord_25",        "ACORD 25 Certificate of Liability Insurance"],
                ["loss_runs",       "Loss run report from a prior carrier (any format)"],
                ["supplemental_do", "Supplemental D&O questionnaire"],
                ["financials",      "Financial statements (balance sheet, P&L, 10-K, annual report)"],
                ["board_resolution","Board resolution or minutes document"],
                ["other",           "Any document that does not fit the above types"],
            ]},
            {"id": "s3", "kind": "code", "lang": "json", "caption": "Output schema — respond with valid JSON only", "code": (
                '{\n'
                '  "document_type": "<one of the types above>",\n'
                '  "confidence": <float 0.0–1.0>,\n'
                '  "classification_notes": "<brief explanation of classification decision>",\n'
                '  "routing_recommendation": "<next processing step>"\n'
                '}'
            )},
            {"id": "s4", "kind": "list", "items": [
                "If confidence is below 0.70, set document_type to 'other' and note the ambiguity.",
                "Do not attempt to extract field values — classify only.",
                "One classification per invocation. Process one document at a time.",
            ]},
        ],
        "user_companion": {
            "key": "doc-classifier-context",
            "display_name": "Document Classifier Input Template",
            "description": "User message template for document classifier with document content placeholder.",
            "blocks": [
                {"id": "u1", "kind": "prose", "text": "Classify the following insurance document."},
                {"id": "u2", "kind": "var", "name": "document_text", "type": "string", "desc": "Full text content of the insurance document to classify", "req": True},
                {"id": "u3", "kind": "prose", "text": "Produce your classification JSON."},
            ],
        },
    },
    "field-extractor-system": {
        "display_name": "Field Extractor System Prompt",
        "description": "Instructs the field extractor task on the 23-field D&O schema, confidence thresholds, and output format.",
        "blocks": [
            {"id": "s1", "kind": "prose", "text": (
                "You are the D&O Application Field Extraction Task. You extract structured data fields "
                "from Directors & Officers liability application forms. You do not classify or summarise — "
                "you extract exactly the fields listed."
            )},
            {"id": "s2", "kind": "list", "items": [
                "named_insured", "fein", "state_of_incorporation", "public_company (bool)",
                "annual_revenue (number USD)", "employee_count (number)", "years_in_business (number)",
                "board_size (number)", "independent_directors (number)", "sic_code",
                "going_concern_opinion (bool)", "regulatory_investigation (bool)",
                "regulatory_investigation_detail", "prior_claims_count (number)",
                "prior_claims_total_incurred (number USD)", "effective_date", "expiration_date",
                "requested_limit (number USD)", "deductible (number USD)", "retroactive_date",
                "prior_carrier", "prior_premium (number USD)", "prior_cancellation (bool)",
            ]},
            {"id": "s3", "kind": "code", "lang": "json", "caption": "Output schema — respond with valid JSON only", "code": (
                '{\n'
                '  "fields": {\n'
                '    "<field_name>": {"value": <extracted value>, "confidence": <float 0.0–1.0>, "source_text": "<quoted text>"}\n'
                '  },\n'
                '  "low_confidence_fields": ["<field_name>", ...],\n'
                '  "unextractable_fields": ["<field_name>", ...],\n'
                '  "extraction_complete": <bool>\n'
                '}'
            )},
            {"id": "s4", "kind": "list", "items": [
                "Mark confidence < 0.80 fields in low_confidence_fields.",
                "Mark fields with no discernible source text in unextractable_fields.",
                "extraction_complete is true only when no required fields remain in unextractable_fields.",
                "Return null for fields that cannot be found — do not guess.",
            ]},
        ],
        "user_companion": {
            "key": "field-extractor-input",
            "display_name": "Field Extractor Input Template",
            "description": "User message template for field extractor with submission ID and document text placeholder.",
            "blocks": [
                {"id": "u1", "kind": "prose", "text": "Extract all required fields from the following D&O application."},
                {"id": "u2", "kind": "var", "name": "submission_id",  "type": "string", "desc": "UUID of the submission being processed",             "req": True},
                {"id": "u3", "kind": "var", "name": "document_text",  "type": "string", "desc": "Full text content of the D&O application form",      "req": True},
            ],
        },
    },
    "loss-run-system": {
        "display_name": "Loss Run Classifier System Prompt",
        "description": "Instructs the loss run classifier task on coverage-line extraction, trend assessment, and output format.",
        "blocks": [
            {"id": "s1", "kind": "prose", "text": (
                "You are the Loss Run Classification Task. You classify loss run documents and extract "
                "key statistics per coverage line for the underwriting risk assessment."
            )},
            {"id": "s2", "kind": "code", "lang": "json", "caption": "Output schema — respond with valid JSON only", "code": (
                '{\n'
                '  "coverage_lines": [\n'
                '    {\n'
                '      "line": "<GL|DO|Property|WC|Umbrella|Other>",\n'
                '      "policy_period_from": "<YYYY-MM-DD>",\n'
                '      "policy_period_to": "<YYYY-MM-DD>",\n'
                '      "total_claims": <integer>,\n'
                '      "total_incurred": <number USD>,\n'
                '      "total_paid": <number USD>,\n'
                '      "total_reserved": <number USD>,\n'
                '      "large_claims": [{"claim_id": "<string>", "incurred": <number>, "status": "open|closed", "description": "<string>"}],\n'
                '      "frequency_trend": "improving" | "stable" | "deteriorating",\n'
                '      "severity_trend": "improving" | "stable" | "deteriorating"\n'
                '    }\n'
                '  ],\n'
                '  "document_period": {"from": "<YYYY-MM-DD>", "to": "<YYYY-MM-DD>"},\n'
                '  "carrier": "<prior carrier name>",\n'
                '  "policy_number": "<string>",\n'
                '  "confidence": <float 0.0–1.0>\n'
                '}'
            )},
            {"id": "s3", "kind": "list", "items": [
                "Large claims threshold: any single claim with incurred > $100,000.",
                "Report each coverage line separately. Do not aggregate across lines.",
                "If the document period cannot be determined, set document_period values to null.",
                "confidence reflects overall extraction quality — set below 0.70 if key fields are missing.",
            ]},
        ],
        "user_companion": {
            "key": "loss-run-input",
            "display_name": "Loss Run Classifier Input Template",
            "description": "User message template for loss run classifier with document text placeholder.",
            "blocks": [
                {"id": "u1", "kind": "prose", "text": "Classify the following loss run document and extract statistics per coverage line."},
                {"id": "u2", "kind": "var", "name": "document_text", "type": "string", "desc": "Full text content of the loss run document", "req": True},
            ],
        },
    },
    "completeness-system": {
        "display_name": "Completeness Checker System Prompt",
        "description": "Instructs the completeness checker task on required field list, scoring, and routing recommendations.",
        "blocks": [
            {"id": "s1", "kind": "prose", "text": (
                "You are the Submission Completeness Checker Task. You validate that all required fields "
                "are present in a submission before routing it to the underwriter queue."
            )},
            {"id": "s2", "kind": "list", "items": [
                "named_insured", "fein", "annual_revenue", "line_of_business",
                "effective_date", "expiration_date", "requested_limit", "prior_carrier",
                "prior_premium", "loss_runs_present (bool)", "application_signed (bool)",
                "applicant_contact_name", "applicant_contact_email",
            ]},
            {"id": "s3", "kind": "code", "lang": "json", "caption": "Output schema — respond with valid JSON only", "code": (
                '{\n'
                '  "status": "complete" | "incomplete",\n'
                '  "completeness_score": <float 0.0–1.0>,\n'
                '  "present_fields": ["<field_name>", ...],\n'
                '  "missing_fields": ["<field_name>", ...],\n'
                '  "low_confidence_fields": ["<field_name>", ...],\n'
                '  "routing_recommendation": "route_to_uw" | "return_to_broker" | "escalate"\n'
                '}'
            )},
            {"id": "s4", "kind": "list", "items": [
                "status is 'complete' only when missing_fields is empty.",
                "completeness_score = present_fields count / total required fields count.",
                "routing_recommendation must be 'return_to_broker' if any required field is missing.",
                "Do not attempt to extract field values — evaluate presence only.",
            ]},
        ],
        "user_companion": {
            "key": "completeness-input",
            "display_name": "Completeness Checker Input Template",
            "description": "User message template for completeness checker with submission ID and JSON placeholder.",
            "blocks": [
                {"id": "u1", "kind": "prose", "text": "Check completeness for the following submission."},
                {"id": "u2", "kind": "var", "name": "submission_id",   "type": "string", "desc": "UUID of the submission to validate",                   "req": True},
                {"id": "u3", "kind": "var", "name": "submission_json", "type": "code",   "desc": "JSON object containing all submission field values",    "req": True},
                {"id": "u4", "kind": "prose", "text": "Produce your completeness assessment JSON."},
            ],
        },
    },
}

# ── Tool catalog ───────────────────────────────────────────────────────────────
# name → {display_name, description, transport_code, is_write_operation, data_classification_code}

TOOL_CATALOG = {
    "submission-context": {
        "display_name": "Get Submission Context",
        "description": (
            "Retrieves full submission context: account details, coverage information, LOB-specific "
            "data, and associated metadata for a given submission ID. Primary context source for "
            "triage and appetite agents."
        ),
        "transport_code": "http",
        "is_write_operation": False,
        "version": {
            "semver": "1.0.0",
            "data_classification_code": "tier3_confidential",
            "input_schema": {
                "type": "object",
                "properties": {
                    "submission_id": {"type": "string", "description": "UUID of the submission to retrieve"},
                },
                "required": ["submission_id"],
                "additionalProperties": False,
            },
        },
    },
    "underwriting-guidelines": {
        "display_name": "Get Underwriting Guidelines",
        "description": (
            "Retrieves the current underwriting guidelines document for a given line of business "
            "(D&O or GL). Returns the full guidelines text with section references. Used by the "
            "appetite agent for guideline-citation-based determinations."
        ),
        "transport_code": "http",
        "is_write_operation": False,
        "version": {
            "semver": "1.0.0",
            "data_classification_code": "tier2_internal",
            "input_schema": {
                "type": "object",
                "properties": {
                    "line_of_business": {"type": "string", "enum": ["DO", "GL"], "description": "Line of business code"},
                },
                "required": ["line_of_business"],
                "additionalProperties": False,
            },
        },
    },
    "loss-history": {
        "display_name": "Get Loss History",
        "description": (
            "Retrieves structured historical loss data for a submission: annual claim counts, "
            "total incurred, paid, and reserved amounts per coverage line. Used by the triage "
            "agent to assess frequency and severity trends."
        ),
        "transport_code": "http",
        "is_write_operation": False,
        "version": {
            "semver": "1.0.0",
            "data_classification_code": "tier3_confidential",
            "input_schema": {
                "type": "object",
                "properties": {
                    "submission_id": {"type": "string", "description": "UUID of the submission"},
                    "years_back": {"type": "integer", "description": "Number of years of history to retrieve", "default": 5},
                },
                "required": ["submission_id"],
                "additionalProperties": False,
            },
        },
    },
    "risk-score-api": {
        "display_name": "Risk Score API",
        "description": (
            "HTTP call to the actuarial risk scoring microservice. Returns a quantitative risk "
            "score and confidence band derived from the submission's exposure profile. Supplements "
            "the triage agent's qualitative assessment."
        ),
        "transport_code": "http",
        "is_write_operation": False,
        "version": {
            "semver": "1.0.0",
            "data_classification_code": "tier3_confidential",
            "input_schema": {
                "type": "object",
                "properties": {
                    "submission_id": {"type": "string", "description": "UUID of the submission"},
                    "exposure_profile": {"type": "object", "description": "Structured exposure data for actuarial scoring"},
                },
                "required": ["submission_id"],
                "additionalProperties": False,
            },
        },
    },
    "clearance-lookup": {
        "display_name": "Clearance Lookup",
        "description": (
            "Checks a submission against the exposure clearance register to detect duplicate or "
            "conflicting risks already written or declined. Prevents double-binding and flags "
            "accounts under exclusion."
        ),
        "transport_code": "http",
        "is_write_operation": False,
        "version": {
            "semver": "1.0.0",
            "data_classification_code": "tier3_confidential",
            "input_schema": {
                "type": "object",
                "properties": {
                    "named_insured":    {"type": "string", "description": "Legal name of the insured entity"},
                    "line_of_business": {"type": "string", "enum": ["DO", "GL"], "description": "Line of business code"},
                    "state":            {"type": "string", "description": "ISO 3166-2 US state code (e.g. CA, NY)"},
                },
                "required": ["named_insured", "line_of_business"],
                "additionalProperties": False,
            },
        },
    },
    "document-extractor": {
        "display_name": "Document Extractor",
        "description": (
            "Retrieves document content from the EDMS backend for a given document reference. "
            "Returns extracted text for text-mode tasks (field extractor, loss run classifier) "
            "or content blocks for vision-mode tasks (document classifier)."
        ),
        "transport_code": "http",
        "is_write_operation": False,
        "version": {
            "semver": "1.0.0",
            "data_classification_code": "tier3_confidential",
            "input_schema": {
                "type": "object",
                "properties": {
                    "document_ref": {"type": "string", "description": "EDMS document reference or UUID"},
                    "mode": {"type": "string", "enum": ["text", "vision"], "description": "Extraction mode", "default": "text"},
                },
                "required": ["document_ref"],
                "additionalProperties": False,
            },
        },
    },
}

# ── Executable definitions ─────────────────────────────────────────────────────
# Each entry fully describes one executable: its version shape, inference profile,
# prompt keys (→ PROMPT_CATALOG), tool names (→ TOOL_CATALOG), source/target
# bindings, and optional v2 scenario flag.

ZUW_AGENTS = [
    {
        "name": "triage-agent",
        "display_name": "Submission Risk Triage Agent",
        "description": (
            "Synthesises submission context, loss history, and underwriting guidelines into a "
            "structured risk score (Green/Amber/Red) with routing recommendation and risk-factor "
            "narrative. Delegates appetite compliance analysis to the appetite agent for ambiguous "
            "regulatory or guideline-boundary cases."
        ),
        "kind_code": "agent",
        "version": {
            "semver": "1.0.0",
            "governance_tier_code": "contextual",
            "capability_type_code": "classification",
            "trust_level_code": "trusted",
            "data_classification_code": "tier3_confidential",
            "inference_profile": "agent_balanced",
        },
        "prompts": {"system": "triage-system", "user": "triage-context"},
        "tools": ["submission-context", "underwriting-guidelines", "loss-history", "risk-score-api", "clearance-lookup"],
        "source_bindings": [],
        "target_bindings": [],
        "delegate_to": "appetite-agent",
    },
    {
        "name": "appetite-agent",
        "display_name": "Underwriting Appetite Assessment Agent",
        "description": (
            "Evaluates a D&O or GL submission against the current underwriting guidelines and "
            "produces a structured appetite determination (within_appetite / borderline / "
            "outside_appetite) with specific guideline section citations. Distinct from the "
            "triage agent: focuses exclusively on guidelines compliance, not overall risk scoring."
        ),
        "kind_code": "agent",
        "version": {
            "semver": "1.0.0",
            "governance_tier_code": "contextual",
            "capability_type_code": "validation",
            "trust_level_code": "trusted",
            "data_classification_code": "tier3_confidential",
            "inference_profile": "agent_balanced",
        },
        "prompts": {"system": "appetite-system", "user": "appetite-context"},
        "tools": ["submission-context", "underwriting-guidelines"],
        "source_bindings": [],
        "target_bindings": [],
    },
    {
        "name": "doc-classifier-agent",
        "display_name": "Document Classifier Agent",
        "description": (
            "Classifies inbound insurance documents into one of eight defined types "
            "(do_application, gl_application, acord_25, loss_runs, supplemental_do, financials, "
            "board_resolution, other) and produces a routing recommendation for downstream "
            "processing tasks."
        ),
        "kind_code": "agent",
        "version": {
            "semver": "1.0.0",
            "governance_tier_code": "contextual",
            "capability_type_code": "classification",
            "trust_level_code": "trusted",
            "data_classification_code": "tier2_internal",
            "inference_profile": "classification_strict",
        },
        "prompts": {"system": "doc-classifier-system", "user": "doc-classifier-context"},
        "tools": ["document-extractor"],
        "source_bindings": [
            {
                "name": "documents_content",
                "source_kind_code": "storage_object",
                "delivery_mode_code": "inline",
                "locator": {"method": "get_document_content_blocks", "arg": "input.documents"},
                "ordinal": 1,
            }
        ],
        "target_bindings": [],
        "v2_draft": True,
    },
]

ZUW_TASKS = [
    {
        "name": "field-extractor",
        "display_name": "D&O Field Extractor",
        "description": (
            "Extracts 23 structured fields from Directors & Officers liability application forms "
            "with per-field confidence scores. Flags low-confidence and unextractable fields for "
            "HITL review. Writes extracted fields back to EDMS as a JSON-derivative child document."
        ),
        "kind_code": "task",
        "version": {
            "semver": "1.0.0",
            "governance_tier_code": "contextual",
            "capability_type_code": "extraction",
            "trust_level_code": "trusted",
            "data_classification_code": "tier3_confidential",
            "inference_profile": "extraction_deterministic",
        },
        "prompts": {"system": "field-extractor-system", "user": "field-extractor-input"},
        "tools": [],
        "source_bindings": [
            {
                "name": "document_text",
                "source_kind_code": "storage_object",
                "delivery_mode_code": "extracted",
                "locator": {"method": "get_documents_text", "arg": "input.documents"},
                "ordinal": 1,
            }
        ],
        "target_bindings": [
            {
                "name": "extracted_fields_to_edms",
                "target_kind_code": "storage_object",
                "delivery_mode_code": "write_file",
                "write_mode_code": "create_or_version",
                "target_payload_field": "output.fields",
                "locator": {
                    "destination": "input.documents[0].id",
                    "transformation_type": "field_extraction",
                    "transformation_method": "verity:field_extractor",
                },
                "ordinal": 1,
            }
        ],
    },
    {
        "name": "loss-run-classifier",
        "display_name": "Loss Run Classifier",
        "description": (
            "Classifies loss run documents and extracts key statistics per coverage line: "
            "total claims, incurred, paid, reserved, large claims, and frequency/severity trends. "
            "Output feeds the triage agent's risk assessment."
        ),
        "kind_code": "task",
        "version": {
            "semver": "1.0.0",
            "governance_tier_code": "contextual",
            "capability_type_code": "classification",
            "trust_level_code": "trusted",
            "data_classification_code": "tier3_confidential",
            "inference_profile": "classification_strict",
        },
        "prompts": {"system": "loss-run-system", "user": "loss-run-input"},
        "tools": [],
        "source_bindings": [
            {
                "name": "document_text",
                "source_kind_code": "storage_object",
                "delivery_mode_code": "extracted",
                "locator": {"method": "get_documents_text", "arg": "input.documents"},
                "ordinal": 1,
            }
        ],
        "target_bindings": [],
        "v2_champion": True,
    },
    {
        "name": "completeness-checker",
        "display_name": "Completeness Checker",
        "description": (
            "Validates that all 13 required submission fields are present before routing to the "
            "underwriter queue. Returns completeness score, missing/low-confidence field lists, "
            "and a routing recommendation."
        ),
        "kind_code": "task",
        "version": {
            "semver": "1.0.0",
            "governance_tier_code": "behavioural",
            "capability_type_code": "validation",
            "trust_level_code": "trusted",
            "data_classification_code": "tier2_internal",
            "inference_profile": "extraction_deterministic",
        },
        "prompts": {"system": "completeness-system", "user": "completeness-input"},
        "tools": [],
        "source_bindings": [],
        "target_bindings": [],
    },
]


# ── HTTP client ───────────────────────────────────────────────────────────────

class SeedClient:
    """httpx.Client wrapper that logs every API call to the Rich console."""

    def __init__(self, base_url: str) -> None:
        self._client = httpx.Client(base_url=base_url, timeout=30)

    def login(self, roles: list[str], label: str) -> str:
        """POST /auth/mock then GET /me. Returns actor_id."""
        console.print(f"\n[bold cyan]↳ Login[/] [yellow]{label}[/] — {', '.join(sorted(roles))}")
        self._call("POST", "/auth/mock", json={"roles": sorted(roles)}, _silent=True)
        me = self._call("GET", "/me", _silent=True)
        actor_id = me["actor_id"]
        console.print(f"  [dim]actor_id: {actor_id}[/]")
        return actor_id

    def post(self, path: str, *, _label: str = "", **kwargs) -> dict:
        return self._call("POST", path, _label=_label, **kwargs)

    def get(self, path: str, *, _label: str = "", **kwargs) -> dict:
        return self._call("GET", path, _label=_label, **kwargs)

    def put(self, path: str, *, _label: str = "", **kwargs) -> dict:
        return self._call("PUT", path, _label=_label, **kwargs)

    def _call(self, method: str, path: str, *, _label: str = "", _silent: bool = False, **kwargs) -> dict:
        resp = self._client.request(method, path, **kwargs)
        if not _silent:
            color = "green" if resp.is_success else "red"
            tag = f"  [dim]{_label}[/]" if _label else ""
            console.print(f"  [{color}]{resp.status_code}[/] [bold]{method:<4}[/] {path}{tag}")
        if not resp.is_success:
            console.print(f"  [red bold]Error:[/] {resp.text[:300]}")
            resp.raise_for_status()
        ct = resp.headers.get("content-type", "")
        return resp.json() if "json" in ct else {}


# ── Teardown ──────────────────────────────────────────────────────────────────

def teardown(db_url: str) -> None:
    console.print(Panel("[bold red]TEARDOWN[/] — removing demo data", expand=False))
    codes = list(DEMO_CODES)
    with psycopg.connect(db_url) as conn:
        with conn.transaction():
            # signoffs must go before approval_requests (RESTRICT FK)
            conn.execute("""
                DELETE FROM core.approval_signoff
                WHERE approval_request_id IN (
                    SELECT ar.approval_request_id
                    FROM core.approval_request ar
                    JOIN core.application app ON ar.target_application_id = app.application_id
                    WHERE app.code = ANY(%(codes)s)
                )
            """, {"codes": codes})
            conn.execute("""
                DELETE FROM core.approval_signoff
                WHERE approval_request_id IN (
                    SELECT ar.approval_request_id
                    FROM core.approval_request ar
                    JOIN core.intake i ON ar.target_intake_id = i.intake_id
                    JOIN core.application app ON i.application_id = app.application_id
                    WHERE app.code = ANY(%(codes)s)
                )
            """, {"codes": codes})
            conn.execute("""
                DELETE FROM core.approval_request
                WHERE target_application_id IN (
                    SELECT application_id FROM core.application WHERE code = ANY(%(codes)s)
                )
                   OR target_intake_id IN (
                    SELECT i.intake_id FROM core.intake i
                    JOIN core.application app ON i.application_id = app.application_id
                    WHERE app.code = ANY(%(codes)s)
                )
            """, {"codes": codes})
            # compliance_exception references intake with RESTRICT — delete first
            conn.execute("""
                DELETE FROM core.compliance_exception
                WHERE scope_intake_id IN (
                    SELECT i.intake_id FROM core.intake i
                    JOIN core.application app ON i.application_id = app.application_id
                    WHERE app.code = ANY(%(codes)s)
                )
            """, {"codes": codes})
            # intakes (cascades: intake_entity_link, intake_requirement, intake_obligation)
            conn.execute("""
                DELETE FROM core.intake
                WHERE application_id IN (SELECT application_id FROM core.application WHERE code = ANY(%(codes)s))
            """, {"codes": codes})
            # champion_assignment and lifecycle_event must go before executable_version (RESTRICT)
            conn.execute("""
                DELETE FROM core.champion_assignment
                WHERE executable_version_id IN (
                    SELECT ev.executable_version_id
                    FROM core.executable_version ev
                    JOIN core.executable e ON ev.executable_id = e.executable_id
                    JOIN core.application app ON e.application_id = app.application_id
                    WHERE app.code = ANY(%(codes)s)
                )
            """, {"codes": codes})
            conn.execute("""
                DELETE FROM core.lifecycle_event
                WHERE executable_version_id IN (
                    SELECT ev.executable_version_id
                    FROM core.executable_version ev
                    JOIN core.executable e ON ev.executable_id = e.executable_id
                    JOIN core.application app ON e.application_id = app.application_id
                    WHERE app.code = ANY(%(codes)s)
                )
            """, {"codes": codes})
            # executable_version_delegation references executable_version (no cascade)
            conn.execute("""
                DELETE FROM core.executable_version_delegation
                WHERE parent_version_id IN (
                    SELECT ev.executable_version_id
                    FROM core.executable_version ev
                    JOIN core.executable e ON ev.executable_id = e.executable_id
                    JOIN core.application app ON e.application_id = app.application_id
                    WHERE app.code = ANY(%(codes)s)
                )
                   OR child_version_id IN (
                    SELECT ev.executable_version_id
                    FROM core.executable_version ev
                    JOIN core.executable e ON ev.executable_id = e.executable_id
                    JOIN core.application app ON e.application_id = app.application_id
                    WHERE app.code = ANY(%(codes)s)
                )
                   OR child_executable_id IN (
                    SELECT e.executable_id FROM core.executable e
                    JOIN core.application app ON e.application_id = app.application_id
                    WHERE app.code = ANY(%(codes)s)
                )
            """, {"codes": codes})
            # executable_version (cascades: prompt_assignment, tool_assignment, mcp_assignment,
            #                               source_binding, target_binding)
            conn.execute("""
                DELETE FROM core.executable_version
                WHERE executable_id IN (
                    SELECT e.executable_id FROM core.executable e
                    JOIN core.application app ON e.application_id = app.application_id
                    WHERE app.code = ANY(%(codes)s)
                )
            """, {"codes": codes})
            conn.execute("""
                DELETE FROM core.executable
                WHERE application_id IN (SELECT application_id FROM core.application WHERE code = ANY(%(codes)s))
            """, {"codes": codes})
            # prompts and tools
            conn.execute("""
                DELETE FROM core.prompt_version
                WHERE prompt_id IN (
                    SELECT p.prompt_id FROM core.prompt p
                    JOIN core.application app ON p.application_id = app.application_id
                    WHERE app.code = ANY(%(codes)s)
                )
            """, {"codes": codes})
            conn.execute("""
                DELETE FROM core.prompt
                WHERE application_id IN (SELECT application_id FROM core.application WHERE code = ANY(%(codes)s))
            """, {"codes": codes})
            conn.execute("""
                DELETE FROM core.tool_version
                WHERE tool_id IN (
                    SELECT t.tool_id FROM core.tool t
                    JOIN core.application app ON t.application_id = app.application_id
                    WHERE app.code = ANY(%(codes)s)
                )
            """, {"codes": codes})
            conn.execute("""
                DELETE FROM core.tool
                WHERE application_id IN (SELECT application_id FROM core.application WHERE code = ANY(%(codes)s))
            """, {"codes": codes})
            # data connectors created by this seed (global, identified by name)
            conn.execute("""
                DELETE FROM core.data_connector_version
                WHERE data_connector_id IN (
                    SELECT data_connector_id FROM core.data_connector WHERE name = 'edms'
                )
            """, {})
            conn.execute("DELETE FROM core.data_connector WHERE name = 'edms'", {})
            # inference configs: delete orphaned configs (executable_versions already gone)
            conn.execute("""
                DELETE FROM core.inference_config
                WHERE NOT EXISTS (
                    SELECT 1 FROM core.executable_version ev
                    WHERE ev.inference_config_id = core.inference_config.inference_config_id
                )
            """)
            # model catalog: FK order: model_reference_binding → model_reference → model_price → model
            _ref_codes = [r["reference_code"] for r in MODEL_REFERENCES]
            _model_codes = [m["model_code"] for m in MODEL_CATALOG]
            conn.execute("""
                DELETE FROM core.model_reference_binding
                WHERE model_id IN (SELECT model_id FROM core.model WHERE model_code = ANY(%(mc)s))
            """, {"mc": _model_codes})
            conn.execute("DELETE FROM core.model_reference WHERE reference_code = ANY(%(rc)s)", {"rc": _ref_codes})
            conn.execute("""
                DELETE FROM core.model_price
                WHERE model_id IN (SELECT model_id FROM core.model WHERE model_code = ANY(%(mc)s))
            """, {"mc": _model_codes})
            conn.execute("DELETE FROM core.model WHERE model_code = ANY(%(mc)s)", {"mc": _model_codes})
            # application perimeter + owner grant
            conn.execute("""DELETE FROM core.application_governance_domain WHERE application_id IN (SELECT application_id FROM core.application WHERE code = ANY(%(codes)s))""", {"codes": codes})
            conn.execute("""DELETE FROM core.application_jurisdiction WHERE application_id IN (SELECT application_id FROM core.application WHERE code = ANY(%(codes)s))""", {"codes": codes})
            conn.execute("""DELETE FROM core.application_regulatory_framework WHERE application_id IN (SELECT application_id FROM core.application WHERE code = ANY(%(codes)s))""", {"codes": codes})
            conn.execute("""DELETE FROM core.actor_app_role_grant WHERE application_id IN (SELECT application_id FROM core.application WHERE code = ANY(%(codes)s))""", {"codes": codes})
            conn.execute("DELETE FROM core.application WHERE code = ANY(%(codes)s)", {"codes": codes})
    console.print("  [green]✓ teardown complete[/]")


# ── Application helpers ───────────────────────────────────────────────────────

def _propose_app(client: SeedClient, *, code: str, name: str, description: str,
                 lob: str, data_classification: str, frameworks: list[str],
                 domains: list[str], jurisdictions: list[str],
                 business_owner_actor_id: str, affects_consumers: bool,
                 processes_pii: bool, consumer_facing: bool, justification: str) -> dict:
    return client.post("/applications", _label=f"propose {code}", json={
        "code": code,
        "name": name,
        "description": description,
        "line_of_business_code": lob,
        "data_classification_code": data_classification,
        "regulatory_framework_codes": frameworks,
        "governance_domain_codes": domains,
        "jurisdiction_codes": jurisdictions,
        "business_owner_actor_id": business_owner_actor_id,
        "affects_consumers": affects_consumers,
        "processes_pii": processes_pii,
        "consumer_facing": consumer_facing,
        "justification": justification,
    })


def _submit_and_approve_app(a: SeedClient, b: SeedClient, app_id: str, code: str) -> None:
    approval = a.post(f"/applications/{app_id}/submit", _label=f"submit {code}", json={})
    ar_id = approval["approval_request_id"]
    b.post(f"/approvals/{ar_id}/signoff",
           _label=f"approve {code} (ai_governance)",
           json={"decision_code": "approved"})


# ── Intake ────────────────────────────────────────────────────────────────────

def _seed_intake(a: SeedClient, b: SeedClient, app_id: str) -> str:
    """Create, assess (high tier), submit, and approve ZUW intake. Returns intake_id."""
    console.print("\n[bold]  Intake[/]")
    intake = a.post(f"/applications/{app_id}/intakes", _label="create intake", json={
        "title": "ZUW Underwriting AI Platform",
        "description": (
            "Governance intake for the AI-assisted underwriting platform covering triage, "
            "appetite assessment, and document classification capabilities for commercial "
            "property & casualty business."
        ),
    })
    intake_id = intake["intake_id"]

    a.put(f"/intakes/{intake_id}/assessment", _label="assess (→ high tier)", json=ZUW_ASSESSMENT)

    approval = a.post(f"/intakes/{intake_id}/submit", _label="submit intake", json={})
    ar_id = approval["approval_request_id"]

    required = approval.get("required_roles", [])
    n = len(required) or 5
    for i in range(n):
        result = b.post(f"/approvals/{ar_id}/signoff",
                        _label=f"signoff {i+1}/{n}",
                        json={"decision_code": "approved"})
        if result.get("status_code") == "approved":
            console.print(f"  [green]✓ intake approved[/] (quorum met at signoff {i+1})")
            break

    return intake_id


# ── Obligation resolution ─────────────────────────────────────────────────────

def _resolve_obligations(client: SeedClient, intake_id: str) -> None:
    """Satisfy all outstanding intake obligations by recording evidence for each unevidenced control."""
    console.print("\n[bold]  Obligations[/]")
    result = client.get(f"/intakes/{intake_id}/obligations", _label="get obligations")
    rollup = result.get("rollup", {})
    console.print(f"  [dim]total={rollup.get('total', 0)} outstanding={rollup.get('outstanding', 0)}[/]")
    for ob in result.get("obligations", []):
        if ob["status"] != "outstanding":
            continue
        ob_id = ob["intake_obligation_id"]
        for ctrl in ob.get("controls", []):
            if not ctrl["evidenced"]:
                client.post(f"/obligations/{ob_id}/evidence",
                            _label=f"evidence: {ob['requirement_code']} / {ctrl['control_code']}",
                            json={"control_code": ctrl["control_code"],
                                  "note": f"Seeded: {ob['requirement_code']}"})
    check = client.get(f"/intakes/{intake_id}/obligations", _label="verify", _silent=True)
    r2 = check.get("rollup", {})
    if r2.get("all_resolved"):
        console.print(f"  [green]✓ all {r2.get('total', 0)} obligations resolved[/]")
    else:
        console.print(f"  [yellow]⚠ {r2.get('outstanding', 0)} obligations still outstanding[/]")


# ── Asset lifecycle ───────────────────────────────────────────────────────────

LIFECYCLE_STAGES = ("candidate", "staging", "challenger", "champion")


def _advance_to_champion(client: SeedClient, version_id: str, tag: str) -> None:
    for stage in LIFECYCLE_STAGES:
        client.post(f"/versions/{version_id}/lifecycle",
                    _label=f"{tag} → {stage}",
                    json={"to_stage": stage})


# ── Asset sub-seeders ─────────────────────────────────────────────────────────

def _seed_connector(client: SeedClient) -> str:
    """Create the EDMS data connector + v1.0.0. Returns the connector_version_id."""
    console.print("\n[bold]  Data Connector[/]")
    connector = client.post("/connectors", _label="edms connector", json={
        "name": "edms",
        "connector_type_code": "http",
        "description": (
            "Enterprise Document Management System connector. Provides document text extraction "
            "and content-block delivery for tasks that declare document source bindings. "
            "Base URL resolved from EDMS_URL env var at runtime."
        ),
    })
    cv = client.post(f"/connectors/{connector['data_connector_id']}/versions",
                     _label="edms v1.0.0",
                     json={"semver": "1.0.0", "config": {}})
    cv_id = cv["data_connector_version_id"]
    console.print(f"  [green]✓ connector version id: {cv_id}[/]")
    return cv_id


def _seed_model_catalog(client: SeedClient) -> dict[str, str]:
    """Create models, prices, references, and bindings. Returns {reference_code: model_reference_id}."""
    console.print("\n[bold]  Model Catalog[/]")
    model_id_by_code: dict[str, str] = {}
    for m in MODEL_CATALOG:
        model = client.post("/models", _label=m["model_code"], json={
            "model_code": m["model_code"],
            "provider": m["provider"],
            "modality": m["modality"],
        })
        model_id_by_code[m["model_code"]] = model["model_id"]
        client.post(f"/models/{model['model_id']}/prices", _label=f"  price {m['model_code']}", json=m["price"])
        console.print(f"  [green]✓[/] {m['model_code']} → {model['model_id']}")

    ref_id_by_code: dict[str, str] = {}
    for r in MODEL_REFERENCES:
        ref = client.post("/model-references", _label=r["reference_code"], json={
            "reference_code": r["reference_code"],
            "name": r["name"],
        })
        ref_id_by_code[r["reference_code"]] = ref["model_reference_id"]
        model_id = model_id_by_code[r["model_code"]]
        client.post(f"/model-references/{ref['model_reference_id']}/bindings",
                    _label=f"  bind {r['reference_code']} → {r['model_code']}",
                    json={"model_id": model_id})
        console.print(f"  [green]✓[/] ref {r['reference_code']} → {ref['model_reference_id']}")
    return ref_id_by_code


def _seed_inference_configs(client: SeedClient, ref_ids: dict[str, str]) -> dict[str, str]:
    """Create inference configs wired to model references. Returns {profile_name: inference_config_id}."""
    console.print("\n[bold]  Inference Configs[/]")
    configs: dict[str, str] = {}
    for name, profile in INFERENCE_PROFILES.items():
        payload: dict = {
            "temperature": profile["temperature"],
            "max_tokens": profile["max_tokens"],
            "params": profile["params"],
        }
        ref_code = profile.get("_model_ref")
        if ref_code and ref_code in ref_ids:
            payload["model_references"] = [{"priority": 1, "model_reference_id": ref_ids[ref_code]}]
        cfg = client.post("/inference-configs", _label=name, json=payload)
        configs[name] = cfg["inference_config_id"]
        console.print(f"  [green]✓[/] {name} → {cfg['inference_config_id']}")
    return configs


def _seed_tools(client: SeedClient, app_id: str) -> dict[str, str]:
    """Create all tools + versions. Returns {tool_name: tool_version_id}."""
    console.print("\n[bold]  Tools[/]")
    tool_version_ids: dict[str, str] = {}
    for name, spec in TOOL_CATALOG.items():
        tool = client.post("/tools", _label=name, json={
            "name": name,
            "display_name": spec["display_name"],
            "description": spec["description"],
            "transport_code": spec["transport_code"],
            "application_id": app_id,
        })
        tv = client.post(f"/tools/{tool['tool_id']}/versions",
                         _label=f"  {name} v{spec['version']['semver']}",
                         json=spec["version"])
        tool_version_ids[name] = tv["tool_version_id"]
    return tool_version_ids


def _seed_prompts(client: SeedClient, app_id: str) -> dict[str, str]:
    """Create all prompts + versions. Returns {prompt_key: prompt_version_id}."""
    console.print("\n[bold]  Prompts[/]")
    pv_ids: dict[str, str] = {}

    for sys_key, spec in PROMPT_CATALOG.items():
        p = client.post("/prompts", _label=sys_key, json={
            "name": sys_key,
            "display_name": spec["display_name"],
            "description": spec["description"],
            "application_id": app_id,
        })
        pv = client.post(f"/prompts/{p['prompt_id']}/versions",
                         _label=f"  {sys_key} v1.0.0",
                         json={"semver": "1.0.0", "blocks": spec["blocks"]})
        pv_ids[sys_key] = pv["prompt_version_id"]

        companion = spec["user_companion"]
        user_key = companion["key"]
        up = client.post("/prompts", _label=user_key, json={
            "name": user_key,
            "display_name": companion["display_name"],
            "description": companion["description"],
            "application_id": app_id,
        })
        upv = client.post(f"/prompts/{up['prompt_id']}/versions",
                          _label=f"  {user_key} v1.0.0",
                          json={"semver": "1.0.0", "blocks": companion["blocks"]})
        pv_ids[user_key] = upv["prompt_version_id"]

    return pv_ids


def _user_key(sys_key: str) -> str:
    return PROMPT_CATALOG[sys_key]["user_companion"]["key"]


def _wire_version(client: SeedClient, version_id: str, exe_def: dict,
                  pv_ids: dict[str, str], tv_ids: dict[str, str],
                  edms_cv_id: str, label: str) -> None:
    """Attach prompts, tools, source bindings, and target bindings to one executable version."""

    # Prompt assignments
    sys_key = exe_def["prompts"]["system"]
    usr_key = exe_def["prompts"]["user"]
    client.post(f"/versions/{version_id}/prompt-assignments",
                _label=f"{label} sys prompt",
                json={"prompt_version_id": pv_ids[sys_key], "api_role_code": "system", "ordinal": 1})
    client.post(f"/versions/{version_id}/prompt-assignments",
                _label=f"{label} user prompt",
                json={"prompt_version_id": pv_ids[usr_key], "api_role_code": "user", "ordinal": 2})

    # Tool assignments
    for tool_name in exe_def.get("tools", []):
        client.post(f"/versions/{version_id}/tool-assignments",
                    _label=f"{label} tool:{tool_name}",
                    json={"tool_version_id": tv_ids[tool_name]})

    # Source bindings
    for sb in exe_def.get("source_bindings", []):
        payload = {
            "name": sb["name"],
            "source_kind_code": sb["source_kind_code"],
            "delivery_mode_code": sb["delivery_mode_code"],
            "data_connector_version_id": edms_cv_id,
            "locator": sb["locator"],
            "ordinal": sb.get("ordinal", 1),
        }
        client.post(f"/versions/{version_id}/source-bindings",
                    _label=f"{label} src:{sb['name']}",
                    json=payload)

    # Target bindings
    for tb in exe_def.get("target_bindings", []):
        payload = {
            "name": tb["name"],
            "target_kind_code": tb["target_kind_code"],
            "delivery_mode_code": tb["delivery_mode_code"],
            "write_mode_code": tb.get("write_mode_code"),
            "data_connector_version_id": edms_cv_id,
            "target_payload_field": tb.get("target_payload_field"),
            "locator": tb["locator"],
            "ordinal": tb.get("ordinal", 1),
        }
        client.post(f"/versions/{version_id}/target-bindings",
                    _label=f"{label} tgt:{tb['name']}",
                    json=payload)


# ── Assets ────────────────────────────────────────────────────────────────────

def _verify_db(db_url: str) -> None:
    """Print post-seed row counts for all tables touched by seed2."""
    console.print(Panel("[bold cyan]VERIFICATION[/] — post-seed row counts", expand=False))
    codes = list(DEMO_CODES)
    ref_codes = [r["reference_code"] for r in MODEL_REFERENCES]
    model_codes = [m["model_code"] for m in MODEL_CATALOG]

    def _count(conn, sql: str, params=None) -> int:
        row = conn.execute(sql, params or {}).fetchone()
        return row[0] if row else 0

    with psycopg.connect(db_url) as conn:
        app_filter = "WHERE code = ANY(%(c)s)"
        exe_filter = """
            JOIN core.executable e ON ev.executable_id = e.executable_id
            JOIN core.application app ON e.application_id = app.application_id
            WHERE app.code = ANY(%(c)s)"""
        intake_filter = """
            JOIN core.application app ON i.application_id = app.application_id
            WHERE app.code = ANY(%(c)s)"""

        rows = [
            ("core.application",           _count(conn, f"SELECT COUNT(*) FROM core.application {app_filter}", {"c": codes})),
            ("core.executable",            _count(conn, f"SELECT COUNT(*) FROM core.executable e JOIN core.application app ON e.application_id=app.application_id WHERE app.code=ANY(%(c)s)", {"c": codes})),
            ("core.executable_version",    _count(conn, f"SELECT COUNT(*) FROM core.executable_version ev {exe_filter}", {"c": codes})),
            ("core.source_binding",        _count(conn, f"SELECT COUNT(*) FROM core.source_binding sb JOIN core.executable_version ev ON sb.executable_version_id=ev.executable_version_id {exe_filter}", {"c": codes})),
            ("core.target_binding",        _count(conn, f"SELECT COUNT(*) FROM core.target_binding tb JOIN core.executable_version ev ON tb.executable_version_id=ev.executable_version_id {exe_filter}", {"c": codes})),
            ("core.prompt",                _count(conn, f"SELECT COUNT(*) FROM core.prompt p JOIN core.application app ON p.application_id=app.application_id WHERE app.code=ANY(%(c)s)", {"c": codes})),
            ("core.prompt_version",        _count(conn, f"SELECT COUNT(*) FROM core.prompt_version pv JOIN core.prompt p ON pv.prompt_id=p.prompt_id JOIN core.application app ON p.application_id=app.application_id WHERE app.code=ANY(%(c)s)", {"c": codes})),
            ("core.tool",                  _count(conn, f"SELECT COUNT(*) FROM core.tool t JOIN core.application app ON t.application_id=app.application_id WHERE app.code=ANY(%(c)s)", {"c": codes})),
            ("core.tool_version",          _count(conn, f"SELECT COUNT(*) FROM core.tool_version tv JOIN core.tool t ON tv.tool_id=t.tool_id JOIN core.application app ON t.application_id=app.application_id WHERE app.code=ANY(%(c)s)", {"c": codes})),
            ("core.inference_config",      _count(conn, "SELECT COUNT(*) FROM core.inference_config")),
            ("core.data_connector",        _count(conn, "SELECT COUNT(*) FROM core.data_connector WHERE name='edms'")),
            ("core.data_connector_version",_count(conn, "SELECT COUNT(*) FROM core.data_connector_version dcv JOIN core.data_connector dc ON dcv.data_connector_id=dc.data_connector_id WHERE dc.name='edms'")),
            ("core.approval_request",      _count(conn, f"SELECT COUNT(*) FROM core.approval_request ar WHERE ar.target_application_id IN (SELECT application_id FROM core.application WHERE code=ANY(%(c)s)) OR ar.target_intake_id IN (SELECT i.intake_id FROM core.intake i JOIN core.application app ON i.application_id=app.application_id WHERE app.code=ANY(%(c)s))", {"c": codes})),
            ("core.approval_signoff",      _count(conn, f"SELECT COUNT(*) FROM core.approval_signoff asf JOIN core.approval_request ar ON asf.approval_request_id=ar.approval_request_id WHERE ar.target_application_id IN (SELECT application_id FROM core.application WHERE code=ANY(%(c)s)) OR ar.target_intake_id IN (SELECT i.intake_id FROM core.intake i JOIN core.application app ON i.application_id=app.application_id WHERE app.code=ANY(%(c)s))", {"c": codes})),
            ("core.intake",                _count(conn, f"SELECT COUNT(*) FROM core.intake i {intake_filter}", {"c": codes})),
            ("core.intake_obligation",     _count(conn, f"SELECT COUNT(*) FROM core.intake_obligation io JOIN core.intake_obligation_resolution ior ON io.intake_obligation_resolution_id=ior.intake_obligation_resolution_id JOIN core.intake i ON ior.intake_id=i.intake_id {intake_filter}", {"c": codes})),
            ("audit.evidence",             _count(conn, f"SELECT COUNT(*) FROM audit.evidence ev JOIN core.intake i ON ev.intake_id=i.intake_id {intake_filter}", {"c": codes})),
            ("core.champion_assignment",   _count(conn, f"SELECT COUNT(*) FROM core.champion_assignment ca JOIN core.executable_version ev ON ca.executable_version_id=ev.executable_version_id {exe_filter}", {"c": codes})),
            ("core.model",                 _count(conn, "SELECT COUNT(*) FROM core.model WHERE model_code=ANY(%(mc)s)", {"mc": model_codes})),
            ("core.model_reference",       _count(conn, "SELECT COUNT(*) FROM core.model_reference WHERE reference_code=ANY(%(rc)s)", {"rc": ref_codes})),
        ]

    from rich.table import Table as RichTable
    t = RichTable(title="Post-seed counts", show_header=True, header_style="bold")
    t.add_column("Table", style="cyan")
    t.add_column("Rows", justify="right")
    for name, count in rows:
        t.add_row(name, str(count))
    console.print(t)

    # Verify no role field leaked into prompt blocks
    with psycopg.connect(db_url) as conn:
        role_leaks = conn.execute("SELECT COUNT(*) FROM core.prompt_version WHERE blocks::text LIKE '%\"role\"%'").fetchone()[0]
    if role_leaks == 0:
        console.print("[green]✓ No 'role' field found in any prompt_version.blocks[/]")
    else:
        console.print(f"[red bold]✗ {role_leaks} prompt_version rows contain 'role' in blocks — fix seed![/]")


def _seed_assets(client: SeedClient, app_id: str, intake_id: str) -> None:
    # Step 1: EDMS connector
    edms_cv_id = _seed_connector(client)

    # Step 2: Model catalog + inference configs
    ref_ids = _seed_model_catalog(client)
    cfg_ids = _seed_inference_configs(client, ref_ids)

    # Step 3: Tools
    tv_ids = _seed_tools(client, app_id)

    # Step 4: Prompts
    pv_ids = _seed_prompts(client, app_id)

    # Step 5: Executables — agents then tasks
    console.print("\n[bold]  Executables[/]")
    exe_id_by_name: dict[str, str] = {}

    for exe_def in ZUW_AGENTS + ZUW_TASKS:
        name = exe_def["name"]
        console.print(f"\n  [bold cyan]{name}[/]")

        exe = client.post("/executables", _label=name, json={
            "name": name,
            "display_name": exe_def["display_name"],
            "description": exe_def["description"],
            "kind_code": exe_def["kind_code"],
            "application_id": app_id,
        })
        exe_id = exe["executable_id"]
        exe_id_by_name[name] = exe_id

        # Version payload — extract inference_profile from version spec
        v_spec = {k: v for k, v in exe_def["version"].items() if k != "inference_profile"}
        profile_name = exe_def["version"].get("inference_profile")
        if profile_name and profile_name in cfg_ids:
            v_spec["inference_config_id"] = cfg_ids[profile_name]

        # Create v1
        v1 = client.post(f"/executables/{exe_id}/versions", _label=f"  {name} v1.0.0", json=v_spec)
        v1_id = v1["executable_version_id"]

        # Wire v1: prompts + tools + bindings
        _wire_version(client, v1_id, exe_def, pv_ids, tv_ids, edms_cv_id, label=f"{name} v1")

        # Link v1 to intake (required for lifecycle gate)
        client.post(f"/intakes/{intake_id}/links",
                    _label=f"  {name} → intake",
                    json={"executable_id": exe_id})

        # Advance v1 to champion
        _advance_to_champion(client, v1_id, f"  {name} v1")

        # v2 scenarios
        if exe_def.get("v2_champion"):
            v2_spec = {**v_spec, "semver": "2.0.0", "version_change_type_code": "major"}
            v2 = client.post(f"/executables/{exe_id}/versions", _label=f"  {name} v2.0.0", json=v2_spec)
            v2_id = v2["executable_version_id"]
            _wire_version(client, v2_id, exe_def, pv_ids, tv_ids, edms_cv_id, label=f"{name} v2")
            _advance_to_champion(client, v2_id, f"  {name} v2")
            console.print(f"    [green]✓ v1 deprecated · v2 champion[/]")

        elif exe_def.get("v2_draft"):
            v2_spec = {**v_spec, "semver": "2.0.0", "version_change_type_code": "major"}
            v2 = client.post(f"/executables/{exe_id}/versions", _label=f"  {name} v2.0.0 (draft)", json=v2_spec)
            v2_id = v2["executable_version_id"]
            _wire_version(client, v2_id, exe_def, pv_ids, tv_ids, edms_cv_id, label=f"{name} v2")
            console.print(f"    [green]✓ v2 draft wired[/]")

    # Step 6: Delegation — triage-agent v1 → appetite-agent (champion-tracking)
    console.print("\n[bold]  Delegations[/]")
    triage_id = exe_id_by_name.get("triage-agent")
    appetite_id = exe_id_by_name.get("appetite-agent")
    if triage_id and appetite_id:
        # Get triage v1 version id to post the delegation from it
        triage_versions = client.get(f"/executables/{triage_id}/versions", _label="triage versions", _silent=True)
        if isinstance(triage_versions, list) and triage_versions:
            # Pick the v1 version (first, semver 1.0.0)
            triage_v1_id = next(
                (v["executable_version_id"] for v in triage_versions if v.get("semver") == "1.0.0"),
                triage_versions[0]["executable_version_id"]
            )
            client.post(f"/versions/{triage_v1_id}/delegations",
                        _label="triage → appetite (champion-tracking)",
                        json={
                            "child_executable_id": appetite_id,
                            "scope": {},
                            "rationale": (
                                "Triage delegates detailed guideline-compliance analysis to the appetite "
                                "specialist agent when the submission's regulatory or appetite fit is "
                                "ambiguous. The appetite determination feeds into triage's final risk "
                                "score and routing recommendation."
                            ),
                            "notes": "FC-1 sub-agent delegation. Champion-tracking via child_executable_id.",
                        })
            console.print("  [green]✓ triage → appetite delegation registered[/]")


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Verity API-driven demo seed — full refresh")
    parser.add_argument("--base-url", default="http://localhost:8000",
                        help="Hub base URL (default: http://localhost:8000)")
    parser.add_argument("--db-url", default="postgresql://verity:verity@localhost:5432/verity",
                        help="Postgres URL for teardown SQL (default: verity/verity@localhost/verity)")
    args = parser.parse_args()

    console.print(Panel(
        f"[bold]Verity Demo Seed — Full Refresh[/]\n"
        f"base_url: {args.base_url}\n"
        f"codes:    {', '.join(DEMO_CODES)}",
        expand=False,
    ))

    teardown(args.db_url)

    a = SeedClient(args.base_url)
    b = SeedClient(args.base_url)

    console.print("\n[bold]Personas[/]")
    persona_a_id = a.login(PERSONA_A_ROLES, "PERSONA A — Author")
    persona_b_id = b.login(PERSONA_B_ROLES, "PERSONA B — Approver")

    # ── ZUW: full demo ────────────────────────────────────────────────────────
    console.print("\n[bold cyan]═══ ZUW: Zurich Underwriting Platform ═══[/]")
    zuw = _propose_app(a,
        code="ZUW",
        name="Zurich Underwriting Platform",
        description=(
            "AI-assisted underwriting platform for commercial property & casualty. "
            "Triage, appetite assessment, and document classification using governed LLM "
            "agents and tasks subject to NAIC Model Bulletin and EU AI Act requirements."
        ),
        lob="pc",
        data_classification="tier4_pii_restricted",
        frameworks=["eu_ai_act", "naic_model_bulletin_ai", "colorado_sb21_169", "nydfs"],
        domains=["model_risk", "fairness", "privacy", "human_oversight"],
        jurisdictions=["us_federal", "co", "ny"],
        business_owner_actor_id=persona_a_id,
        affects_consumers=True,
        processes_pii=True,
        consumer_facing=False,
        justification=(
            "Commercial P&C underwriting requires AI governance to comply with EU AI Act "
            "Annex III (insurance high-risk system) and NAIC Model Bulletin requirements. "
            "Automated triage recommendations affect coverage eligibility for policyholders."
        ),
    )
    zuw_id = zuw["application_id"]
    _submit_and_approve_app(a, b, zuw_id, "ZUW")

    intake_id = _seed_intake(a, b, zuw_id)
    _resolve_obligations(a, intake_id)
    _seed_assets(a, app_id=zuw_id, intake_id=intake_id)

    # ── ZCL: approved, no assets ──────────────────────────────────────────────
    console.print("\n[bold cyan]═══ ZCL: Zurich Claims Analytics ═══[/]")
    zcl = _propose_app(a,
        code="ZCL",
        name="Zurich Claims Analytics",
        description=(
            "AI analytics for claims triage and fraud detection in commercial lines. "
            "Application registered and approved; no production assets registered yet."
        ),
        lob="pc",
        data_classification="tier3_confidential",
        frameworks=["eu_ai_act", "naic_model_bulletin_ai"],
        domains=["model_risk", "fairness"],
        jurisdictions=["us_federal"],
        business_owner_actor_id=persona_a_id,
        affects_consumers=True,
        processes_pii=False,
        consumer_facing=False,
        justification=(
            "Claims AI requires governance review per NAIC Model Bulletin and EU AI Act "
            "to ensure fair treatment of claimants and auditability of triage decisions."
        ),
    )
    _submit_and_approve_app(a, b, zcl["application_id"], "ZCL")

    # ── ZEP: proposed only (pending governance review) ────────────────────────
    console.print("\n[bold cyan]═══ ZEP: Zurich Experimental Platform ═══[/]")
    _propose_app(a,
        code="ZEP",
        name="Zurich Experimental Platform",
        description=(
            "Sandbox for experimental AI capabilities under evaluation. "
            "Currently awaiting governance review before asset registration."
        ),
        lob="other",
        data_classification="tier2_internal",
        frameworks=["internal_only"],
        domains=["model_risk"],
        jurisdictions=["us_federal"],
        business_owner_actor_id=persona_a_id,
        affects_consumers=False,
        processes_pii=False,
        consumer_facing=False,
        justification="Experimental AI under internal governance evaluation — no consumer impact at this stage.",
    )

    _verify_db(args.db_url)

    console.print(Panel(
        "[bold green]✓ Seed complete[/]\n\n"
        "[bold]ZUW[/] active · intake approved (high tier, 9 obligations resolved) · "
        "2 models · 3 model references · 1 connector · 3 inference configs · 6 tools · 12 prompts · "
        "6 executables fully wired (prompts + tools + bindings + inference config)\n"
        "  Agents: triage-agent v1 champion, appetite-agent v1 champion, "
        "doc-classifier-agent v1 champion + v2 draft\n"
        "  Tasks: field-extractor v1 champion, loss-run-classifier v1→v2 champion, "
        "completeness-checker v1 champion\n"
        "  Delegation: triage-agent → appetite-agent (champion-tracking)\n"
        "[bold]ZCL[/] active · no assets\n"
        "[bold]ZEP[/] proposed / pending",
        expand=False,
    ))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        console.print(f"\n[red bold]Seed failed:[/] {e}")
        sys.exit(1)

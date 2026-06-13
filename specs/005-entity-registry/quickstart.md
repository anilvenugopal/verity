# Quickstart: Entity Model & Registry

**Feature**: 005-entity-registry

A manual walkthrough of the primary flows end-to-end using `curl` against a running local dev instance (`./dev up`). Run `./dev migrate` first to ensure the 0006 migration has been applied.

All requests use the demo session cookie. Adjust `COOKIE` to match your session.

```bash
export BASE=http://localhost:8000/api
export COOKIE="session=dev-session-token"
```

---

## Flow 1: Register an agent and promote it to champion

### Step 1 — Register the agent

```bash
curl -s -X POST "$BASE/registry/executables" \
  -H "Cookie: $COOKIE" \
  -H "Content-Type: application/json" \
  -d '{"name": "underwriting-assistant", "kind_code": "agent", "description": "UW decisioning agent"}' \
  | python3 -m json.tool
```

**Expected**: `201` with `executable_id`. Save it:
```bash
EXEC_ID="<executable_id from response>"
```

### Step 2 — Register a prompt and create version 1.0.0

```bash
curl -s -X POST "$BASE/registry/prompts" \
  -H "Cookie: $COOKIE" \
  -H "Content-Type: application/json" \
  -d '{"name": "uw-system-prompt", "description": "UW system instruction"}' \
  | python3 -m json.tool

PROMPT_ID="<prompt_id from response>"

curl -s -X POST "$BASE/registry/prompts/$PROMPT_ID/versions" \
  -H "Cookie: $COOKIE" \
  -H "Content-Type: application/json" \
  -d '{
    "semver": "1.0.0",
    "blocks": [{"type": "text", "content": "You are an underwriting assistant. Analyze the application and return a decision."}]
  }' | python3 -m json.tool

PROMPT_VER_ID="<prompt_version_id from response>"
```

**Expected**: `201` with `content_hash` populated.

### Step 3 — Create agent version 1.0.0

```bash
curl -s -X POST "$BASE/registry/executables/$EXEC_ID/versions" \
  -H "Cookie: $COOKIE" \
  -H "Content-Type: application/json" \
  -d '{
    "semver": "1.0.0",
    "governance_tier_code": "tier_2",
    "capability_type_code": "classification",
    "trust_level_code": "supervised"
  }' | python3 -m json.tool

VER_ID="<executable_version_id from response>"
```

**Expected**: `201` with `lifecycle_stage: "draft"`.

### Step 4 — Assign the prompt to the system role

```bash
curl -s -X POST "$BASE/registry/versions/$VER_ID/prompt-assignments" \
  -H "Cookie: $COOKIE" \
  -H "Content-Type: application/json" \
  -d '{"prompt_version_id": "'"$PROMPT_VER_ID"'", "api_role_code": "system", "ordinal": 1}' \
  | python3 -m json.tool
```

**Expected**: `201` with the assignment echoed back.

### Step 5 — Promote to champion

```bash
curl -s -X POST "$BASE/registry/versions/$VER_ID/promote" \
  -H "Cookie: $COOKIE" \
  -H "Content-Type: application/json" \
  -d '{"reason": "initial release"}' \
  | python3 -m json.tool
```

**Expected**: `200` with `lifecycle_stage: "champion"`.

### Step 6 — Resolve the current champion

```bash
curl -s "$BASE/registry/executables/$EXEC_ID/champion" \
  -H "Cookie: $COOKIE" | python3 -m json.tool
```

**Expected**: `200` with the 1.0.0 version detail.

### Step 7 — Verify champion atomicity: promote a second version

```bash
# Create version 2.0.0
curl -s -X POST "$BASE/registry/executables/$EXEC_ID/versions" \
  -H "Cookie: $COOKIE" -H "Content-Type: application/json" \
  -d '{"semver": "2.0.0", "governance_tier_code": "tier_2", "capability_type_code": "classification"}' \
  | python3 -m json.tool

VER2_ID="<version_id>"

# Assign a prompt to v2 too (required before promotion)
curl -s -X POST "$BASE/registry/versions/$VER2_ID/prompt-assignments" \
  -H "Cookie: $COOKIE" -H "Content-Type: application/json" \
  -d '{"prompt_version_id": "'"$PROMPT_VER_ID"'", "api_role_code": "system", "ordinal": 1}'

# Promote v2
curl -s -X POST "$BASE/registry/versions/$VER2_ID/promote" \
  -H "Cookie: $COOKIE" -H "Content-Type: application/json" \
  -d '{"reason": "upgraded to v2"}' | python3 -m json.tool

# Verify champion is now v2
curl -s "$BASE/registry/executables/$EXEC_ID/champion" \
  -H "Cookie: $COOKIE" | python3 -m json.tool
```

**Expected**: Champion resolves to 2.0.0. Version 1.0.0 is retired.

---

## Flow 2: Agent-only tool assignment

### Step 1 — Register a tool

```bash
curl -s -X POST "$BASE/registry/tools" \
  -H "Cookie: $COOKIE" -H "Content-Type: application/json" \
  -d '{"name": "ltv-calculator", "transport_code": "function", "description": "Computes LTV ratio"}' \
  | python3 -m json.tool

TOOL_ID="<tool_id>"

curl -s -X POST "$BASE/registry/tools/$TOOL_ID/versions" \
  -H "Cookie: $COOKIE" -H "Content-Type: application/json" \
  -d '{"semver": "1.0.0", "input_schema": {"type": "object", "properties": {"loan_amount": {"type": "number"}, "appraisal_value": {"type": "number"}}}, "data_classification_code": "sensitive"}' \
  | python3 -m json.tool

TOOL_VER_ID="<tool_version_id>"
```

### Step 2 — Assign tool to the agent version

```bash
curl -s -X POST "$BASE/registry/versions/$VER_ID/tool-assignments" \
  -H "Cookie: $COOKIE" -H "Content-Type: application/json" \
  -d '{"tool_version_id": "'"$TOOL_VER_ID"'"}' | python3 -m json.tool
```

**Expected**: `201` with the assignment.

### Step 3 — Attempt to assign a tool to a task version (should reject)

```bash
# First, create a task
curl -s -X POST "$BASE/registry/executables" \
  -H "Cookie: $COOKIE" -H "Content-Type: application/json" \
  -d '{"name": "risk-summary-task", "kind_code": "task"}' | python3 -m json.tool

TASK_ID="<task executable_id>"
curl -s -X POST "$BASE/registry/executables/$TASK_ID/versions" \
  -H "Cookie: $COOKIE" -H "Content-Type: application/json" \
  -d '{"semver": "1.0.0"}' | python3 -m json.tool

TASK_VER_ID="<task version_id>"

# Try to assign a tool to the task version — should fail with 409
curl -s -X POST "$BASE/registry/versions/$TASK_VER_ID/tool-assignments" \
  -H "Cookie: $COOKIE" -H "Content-Type: application/json" \
  -d '{"tool_version_id": "'"$TOOL_VER_ID"'"}' | python3 -m json.tool
```

**Expected**: `409` with message about tools being agent-only.

---

## Flow 3: Source and target bindings

```bash
# Add a structured source binding to the agent version
curl -s -X POST "$BASE/registry/versions/$VER_ID/source-bindings" \
  -H "Cookie: $COOKIE" -H "Content-Type: application/json" \
  -d '{
    "name": "application_data",
    "source_kind_code": "structured",
    "delivery_mode_code": "inline",
    "locator": {"fields": ["applicant_id", "loan_amount", "credit_score"]},
    "nullable": false,
    "ordinal": 1
  }' | python3 -m json.tool

# Add a structured target binding
curl -s -X POST "$BASE/registry/versions/$VER_ID/target-bindings" \
  -H "Cookie: $COOKIE" -H "Content-Type: application/json" \
  -d '{
    "name": "decision_output",
    "target_kind_code": "structured",
    "delivery_mode_code": "inline",
    "target_payload_field": "underwriting_decision",
    "ordinal": 1
  }' | python3 -m json.tool

# List bindings
curl -s "$BASE/registry/versions/$VER_ID/source-bindings" -H "Cookie: $COOKIE" | python3 -m json.tool
curl -s "$BASE/registry/versions/$VER_ID/target-bindings" -H "Cookie: $COOKIE" | python3 -m json.tool
```

**Expected**: Both bindings returned in list responses.

---

## Flow 4: Where-used reverse lookup

```bash
# Who uses the prompt version?
curl -s "$BASE/registry/prompt-versions/$PROMPT_VER_ID/used-by" \
  -H "Cookie: $COOKIE" | python3 -m json.tool
```

**Expected**: List containing the underwriting-assistant entry with its version semver.

---

## Flow 5: Model catalog and reference binding

```bash
# Register a model
curl -s -X POST "$BASE/registry/models" \
  -H "Cookie: $COOKIE" -H "Content-Type: application/json" \
  -d '{"model_code": "claude-sonnet-4-6", "provider": "anthropic"}' | python3 -m json.tool

MODEL_ID="<model_id>"

# Set initial pricing
curl -s -X POST "$BASE/registry/models/$MODEL_ID/prices" \
  -H "Cookie: $COOKIE" -H "Content-Type: application/json" \
  -d '{"input_price_per_1k": 3.00, "output_price_per_1k": 15.00, "currency_code": "usd"}' \
  | python3 -m json.tool

# Register a model reference
curl -s -X POST "$BASE/registry/model-references" \
  -H "Cookie: $COOKIE" -H "Content-Type: application/json" \
  -d '{"reference_code": "uw-primary", "name": "UW Primary Model"}' | python3 -m json.tool

REF_ID="<model_reference_id>"

# Bind the reference to the model
curl -s -X POST "$BASE/registry/model-references/$REF_ID/bindings" \
  -H "Cookie: $COOKIE" -H "Content-Type: application/json" \
  -d '{"model_id": "'"$MODEL_ID"'", "reason": "initial binding"}' | python3 -m json.tool
```

**Expected**: All `201`. List `/registry/model-references` to verify `current_model_code: "claude-sonnet-4-6"`.

---

## Flow 6: YAML export and round-trip import

```bash
# Export the agent version as YAML
curl -s "$BASE/registry/versions/$VER_ID/export" \
  -H "Cookie: $COOKIE" -H "Accept: application/x-yaml" > /tmp/uw_bundle.yaml

cat /tmp/uw_bundle.yaml

# Dry-run import (expect all no-ops)
curl -s -X POST "$BASE/registry/import/dry-run" \
  -H "Cookie: $COOKIE" \
  -H "Content-Type: application/x-yaml" \
  --data-binary @/tmp/uw_bundle.yaml | python3 -m json.tool
```

**Expected dry-run response**:
```json
{
  "created": 0,
  "updated": 0,
  "no_op": <N>,
  "errors": []
}
```

All entities are `no_op` — the round-trip is fully idempotent.

---

## Deviations to record

If any step produces an unexpected response, record it here before marking the quickstart complete:

| Step | Expected | Actual | Notes |
|------|----------|--------|-------|
| | | | |

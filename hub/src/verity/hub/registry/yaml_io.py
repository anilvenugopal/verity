"""YAML bundle export and import for the entity registry (feature 005 US5).

Bundle format (verity_registry_bundle v1):
  - executables with nested versions, assignments, and bindings
  - prompts with versions
  - tools
  - connectors

Import is idempotent by natural key:
  - prompts by content_hash
  - executables by (kind_code, name)
  - versions by (executable name, semver)
  - tools by name, connectors by name
"""
from __future__ import annotations

from uuid import UUID

import yaml
from psycopg import AsyncConnection
from psycopg.types.json import Json

from verity.hub.auth.models import AuthContext
from verity.hub.db import queries
from verity.hub.registry.models import ImportReport, ImportReportEntry, ImportReportError


async def export_version(conn: AsyncConnection, version_id: UUID) -> dict | None:
    v = await queries.get_version_detail(conn, version_id=version_id)
    if v is None:
        return None
    ex = await queries.get_executable_with_app(conn, executable_id=v["executable_id"])

    prompt_assignments = []
    async for pa in queries.list_prompt_assignments(conn, executable_version_id=version_id):
        pv = await queries.get_prompt_version(conn, prompt_version_id=pa["prompt_version_id"])
        prompt_assignments.append({
            "prompt_name": pa["prompt_name"],
            "prompt_semver": pa["prompt_semver"],
            "prompt_version_id": str(pa["prompt_version_id"]),
            "api_role": pa["api_role_code"],
            "ordinal": pa["ordinal"],
            "blocks": pv["blocks"] if pv else [],
        })

    tool_assignments = []
    async for ta in queries.list_tool_assignments(conn, executable_version_id=version_id):
        tool_assignments.append({
            "tool_name": ta["tool_name"],
            "tool_semver": ta["tool_semver"],
            "tool_version_id": str(ta["tool_version_id"]),
        })

    mcp_assignments = []
    async for ma in queries.list_mcp_assignments(conn, executable_version_id=version_id):
        mcp_assignments.append({
            "name": ma["name"],
            "semver": ma["semver"],
            "mcp_server_version_id": str(ma["mcp_server_version_id"]),
        })

    source_bindings = []
    async for sb in queries.list_source_bindings(conn, executable_version_id=version_id):
        source_bindings.append({
            "name": sb["name"],
            "source_kind": sb["source_kind_code"],
            "delivery_mode": sb["delivery_mode_code"],
            "media_type": sb["media_type"],
            "locator": sb["locator"] or {},
            "nullable": sb["nullable"],
            "ordinal": sb["ordinal"],
        })

    target_bindings = []
    async for tb in queries.list_target_bindings(conn, executable_version_id=version_id):
        target_bindings.append({
            "name": tb["name"],
            "target_kind": tb["target_kind_code"],
            "delivery_mode": tb["delivery_mode_code"],
            "write_mode": tb["write_mode_code"],
            "target_payload_field": tb["target_payload_field"],
            "locator": tb["locator"] or {},
            "ordinal": tb["ordinal"],
        })

    inference_config = None
    if v.get("inference_config_id"):
        cfg = await queries.get_inference_config(conn, inference_config_id=v["inference_config_id"])
        if cfg:
            chain = [r async for r in queries.get_inference_config_chain(
                conn, inference_config_id=v["inference_config_id"]
            )]
            inference_config = {
                "max_tokens": cfg["max_tokens"],
                "temperature": float(cfg["temperature"]) if cfg["temperature"] is not None else None,
                "model_references": [
                    {"priority": r["priority"], "reference_code": r["reference_code"],
                     "resolved_model_code": r.get("resolved_model_code")}
                    for r in chain
                ],
            }

    return {
        "verity_registry_bundle": {
            "version": "1",
            "executables": [
                {
                    "id": str(v["executable_id"]),
                    "kind": ex["kind_code"],
                    "name": ex["name"],
                    "display_name": ex["display_name"],
                    "application_id": str(ex["application_id"]) if ex["application_id"] else None,
                    "versions": [
                        {
                            "semver": v["semver"],
                            "governance_tier": v.get("governance_tier_code"),
                            "capability_type": v.get("capability_type_code"),
                            "trust_level": v.get("trust_level_code"),
                            "data_classification": v.get("data_classification_code"),
                            "inference_config": inference_config,
                            "prompt_assignments": prompt_assignments,
                            "tool_assignments": tool_assignments,
                            "mcp_assignments": mcp_assignments,
                            "source_bindings": source_bindings,
                            "target_bindings": target_bindings,
                        }
                    ],
                }
            ],
        }
    }


def bundle_to_yaml(data: dict) -> str:
    return yaml.safe_dump(data, default_flow_style=False, allow_unicode=True)


def parse_bundle(yaml_str: str) -> dict:
    data = yaml.safe_load(yaml_str)
    if not isinstance(data, dict) or "verity_registry_bundle" not in data:
        raise ValueError("malformed bundle: missing top-level 'verity_registry_bundle' key")
    return data


async def import_bundle(conn: AsyncConnection, bundle: dict, dry_run: bool,
                         ctx: AuthContext) -> ImportReport:
    report = ImportReport()
    b = bundle["verity_registry_bundle"]

    for prompt in b.get("prompts", []):
        for pv in prompt.get("versions", []):
            entity_type = "prompt_version"
            name = f"{prompt['name']}@{pv['semver']}"
            try:
                existing = await _find_prompt_version_by_hash(conn, pv.get("content_hash", ""))
                if existing:
                    report.no_op += 1
                    report.entries.append(ImportReportEntry(entity_type=entity_type, name=name, action="no_op"))
                else:
                    if not dry_run:
                        await _import_prompt_version(conn, prompt, pv, ctx)
                    report.created += 1
                    report.entries.append(ImportReportEntry(entity_type=entity_type, name=name, action="created"))
            except Exception as exc:
                report.errors.append(ImportReportError(entity_type=entity_type, name=name, error=str(exc)))
                report.entries.append(ImportReportEntry(entity_type=entity_type, name=name, action="error"))

    for ex in b.get("executables", []):
        for ver in ex.get("versions", []):
            entity_type = "executable_version"
            name = f"{ex['name']}@{ver['semver']}"
            try:
                existing = await _find_executable_version(conn, ex["kind"], ex["name"], ver["semver"])
                if existing:
                    report.no_op += 1
                    report.entries.append(ImportReportEntry(entity_type=entity_type, name=name, action="no_op"))
                else:
                    if not dry_run:
                        await _import_executable_version(conn, ex, ver, ctx)
                    report.created += 1
                    report.entries.append(ImportReportEntry(entity_type=entity_type, name=name, action="created"))
            except Exception as exc:
                report.errors.append(ImportReportError(entity_type=entity_type, name=name, error=str(exc)))
                report.entries.append(ImportReportEntry(entity_type=entity_type, name=name, action="error"))

    for tool in b.get("tools", []):
        for tv in tool.get("versions", []):
            entity_type = "tool_version"
            name = f"{tool['name']}@{tv['semver']}"
            try:
                existing = await _find_tool_version(conn, tool["name"], tv["semver"])
                if existing:
                    report.no_op += 1
                    report.entries.append(ImportReportEntry(entity_type=entity_type, name=name, action="no_op"))
                else:
                    if not dry_run:
                        await _import_tool_version(conn, tool, tv, ctx)
                    report.created += 1
                    report.entries.append(ImportReportEntry(entity_type=entity_type, name=name, action="created"))
            except Exception as exc:
                report.errors.append(ImportReportError(entity_type=entity_type, name=name, error=str(exc)))
                report.entries.append(ImportReportEntry(entity_type=entity_type, name=name, action="error"))

    return report


# ── private helpers ────────────────────────────────────────────────────────────

async def _find_prompt_version_by_hash(conn: AsyncConnection, content_hash: str) -> bool:
    if not content_hash:
        return False
    # Collect outer results fully before opening inner query (avoids concurrent cursor conflict)
    prompts = [r async for r in queries.list_prompts(conn, application_id=None)]
    for p in prompts:
        pvs = [pv async for pv in queries.list_prompt_versions(conn, prompt_id=p["prompt_id"])]
        for pv in pvs:
            if pv["content_hash"] == content_hash:
                return True
    return False


async def _import_prompt_version(conn: AsyncConnection, prompt: dict, pv: dict,
                                  ctx: AuthContext) -> None:
    import hashlib
    import json
    existing_prompt = None
    prompts = [p async for p in queries.list_prompts(conn, application_id=None)]
    for p in prompts:
        if p["name"] == prompt["name"]:
            existing_prompt = p
            break
    if "display_name" not in prompt or prompt["display_name"] is None:
        raise ValueError(f"bundle entry '{prompt['name']}' is missing required field 'display_name'")
    if "application_id" not in prompt or prompt["application_id"] is None:
        raise ValueError(f"bundle entry '{prompt['name']}' is missing required field 'application_id'")
    if existing_prompt is None:
        existing_prompt = await queries.create_prompt(
            conn, name=prompt["name"],
            display_name=prompt["display_name"],
            description=prompt.get("description"),
            created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role,
            application_id=prompt["application_id"],
        )
    blocks = pv.get("blocks", [])
    content_hash = hashlib.sha256(json.dumps(blocks, sort_keys=True).encode()).hexdigest()
    await queries.create_prompt_version(
        conn, prompt_id=existing_prompt["prompt_id"], semver=pv["semver"],
        blocks=Json(blocks), content_hash=content_hash,
        created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role,
    )


async def _find_executable_version(conn: AsyncConnection, kind_code: str, name: str,
                                    semver: str) -> bool:
    # Collect outer results fully before opening inner query (avoids concurrent cursor conflict)
    execs = [r async for r in queries.list_executables_filtered(conn, kind_code=kind_code, application_id=None)]
    for row in execs:
        if row["name"] == name:
            versions = [v async for v in queries.list_executable_versions(conn, executable_id=row["executable_id"])]
            for v in versions:
                if v["semver"] == semver:
                    return True
    return False


async def _import_executable_version(conn: AsyncConnection, ex: dict, ver: dict,
                                      ctx: AuthContext) -> None:
    existing_ex = None
    execs = [r async for r in queries.list_executables_filtered(conn, kind_code=ex["kind"], application_id=None)]
    for row in execs:
        if row["name"] == ex["name"]:
            existing_ex = row
            break
    if "display_name" not in ex or ex["display_name"] is None:
        raise ValueError(f"bundle entry '{ex['name']}' is missing required field 'display_name'")
    if "application_id" not in ex or ex["application_id"] is None:
        raise ValueError(f"bundle entry '{ex['name']}' is missing required field 'application_id'")
    if existing_ex is None:
        existing_ex = await queries.create_executable(
            conn, kind_code=ex["kind"], name=ex["name"],
            display_name=ex["display_name"],
            description=None,
            created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role,
            application_id=ex["application_id"],
        )
    async with conn.transaction():
        v = await queries.create_version_full(
            conn, executable_id=existing_ex["executable_id"], kind_code=ex["kind"],
            semver=ver["semver"],
            governance_tier_code=ver.get("governance_tier"),
            capability_type_code=ver.get("capability_type"),
            trust_level_code=ver.get("trust_level"),
            data_classification_code=ver.get("data_classification"),
            inference_config_id=None, input_schema=None, output_schema=None,
            version_change_type_code=None, cloned_from_version_id=None,
            created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role,
        )
        await queries.insert_lifecycle_event(
            conn, version_id=v["executable_version_id"], from_state=None, to_state="draft",
            approval_request_id=None, rationale="imported",
            detail=Json({"event": "import"}),
            actor_id=ctx.principal.actor_id, acting_role_code=ctx.acting_role,
        )


async def _find_tool_version(conn: AsyncConnection, name: str, semver: str) -> bool:
    # Collect outer results fully before opening inner query (avoids concurrent cursor conflict)
    tools = [t async for t in queries.list_tools(conn, application_id=None)]
    for t in tools:
        if t["name"] == name:
            versions = [tv async for tv in queries.list_tool_versions(conn, tool_id=t["tool_id"])]
            for tv in versions:
                if tv["semver"] == semver:
                    return True
    return False


async def _import_tool_version(conn: AsyncConnection, tool: dict, tv: dict,
                                ctx: AuthContext) -> None:
    existing_tool = None
    tools = [t async for t in queries.list_tools(conn, application_id=None)]
    for t in tools:
        if t["name"] == tool["name"]:
            existing_tool = t
            break
    if "display_name" not in tool or tool["display_name"] is None:
        raise ValueError(f"bundle entry '{tool['name']}' is missing required field 'display_name'")
    if "application_id" not in tool or tool["application_id"] is None:
        raise ValueError(f"bundle entry '{tool['name']}' is missing required field 'application_id'")
    if existing_tool is None:
        existing_tool = await queries.create_tool(
            conn, name=tool["name"],
            display_name=tool["display_name"],
            description=tool.get("description"),
            transport_code=tool.get("transport_code", "http"),
            created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role,
            application_id=tool["application_id"],
        )
    await queries.create_tool_version(
        conn, tool_id=existing_tool["tool_id"], semver=tv["semver"],
        input_schema=Json(tv.get("input_schema") or {}),
        config=Json(tv.get("config") or {}),
        data_classification_code=tv.get("data_classification_code"),
        created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role,
    )

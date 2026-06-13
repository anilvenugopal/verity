"""Registry service (005): entity registration, composition, champion promotion,
bindings, model catalog. Extends the minimal 003 asset primitive.

All multi-step writes use async with conn.transaction().
champion_assignment is append-only — never UPDATE or DELETE rows.
SCD-2 closes (model_price, model_reference_binding) use UPDATE valid_to inside
a transaction paired with the new INSERT.
"""
from __future__ import annotations

import hashlib
import json
from datetime import datetime
from uuid import UUID

import psycopg.errors
from fastapi import HTTPException
from psycopg import AsyncConnection
from psycopg.types.json import Json
from pydantic import TypeAdapter

from verity.hub.auth.models import AuthContext
from verity.hub.db import queries
from verity.hub.obligation import service as obligation_service
from verity.hub.registry.models import (
    ConnectorSummary,
    ConnectorVersionSummary,
    CreateDelegation,
    DelegationSummary,
    ExecutableDetail,
    ExecutableSummary,
    ExecutableVersion,
    ExecutableVersionDetail,
    ExecutableVersionSummary,
    ImportReport,
    InferenceConfigChainEntry,
    InferenceConfigDetail,
    IntakeAssetLink,
    McpAssignment,
    McpServerVersionSummary,
    ModelPrice,
    ModelReferenceBinding,
    ModelReferenceSummary,
    ModelSummary,
    PromptAssignment,
    PromptBlock,
    PromptSummary,
    PromptVersionDetail,
    PromptVersionSummary,
    compile_blocks,
    SourceBinding,
    TargetBinding,
    ToolAssignment,
    ToolSummary,
    ToolVersionDetail,
    ToolVersionSummary,
    UsedByEntry,
)

_GATED = {"challenger", "champion"}
_block_list_adapter: TypeAdapter[list[PromptBlock]] = TypeAdapter(list[PromptBlock])
_EARLY = {None, "draft", "candidate"}


class RegistryGateBlock(Exception):
    """409 — promotion blocked (not_linked / intake_not_approved / outstanding_obligation)."""

    def __init__(self, reason: str, requirement_code: str | None = None) -> None:
        self.reason = reason
        self.requirement_code = requirement_code
        detail = f"promotion blocked: {reason}" + (f" ({requirement_code})" if requirement_code else "")
        super().__init__(detail)


# ── Executables ───────────────────────────────────────────────────────────────

async def create_executable(conn: AsyncConnection, name: str, kind_code: str, ctx: AuthContext,
                             display_name: str, description: str | None = None,
                             application_id: UUID | None = None):
    row = await queries.create_executable(
        conn, kind_code=kind_code, name=name, display_name=display_name,
        description=description, application_id=application_id,
        created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role,
    )
    return ExecutableSummary(executable_id=row["executable_id"], kind_code=row["kind_code"],
                              name=row["name"], display_name=row.get("display_name"),
                              description=description, version_count=0,
                              application_id=application_id)


async def list_executables(conn: AsyncConnection, kind_code: str | None = None,
                            application_id: UUID | None = None) -> list[ExecutableSummary]:
    rows = [r async for r in queries.list_executables_filtered(
        conn, kind_code=kind_code, application_id=application_id)]
    return [ExecutableSummary(**r) for r in rows]


async def get_executable_detail(conn: AsyncConnection, executable_id: UUID) -> ExecutableDetail | None:
    row = await queries.get_executable_detail(conn, executable_id=executable_id)
    if row is None:
        return None
    versions = [
        ExecutableVersionSummary(
            executable_version_id=v["executable_version_id"],
            executable_id=executable_id,
            semver=v["semver"],
            lifecycle_stage=v["lifecycle_state_code"],
            governance_tier_code=v.get("governance_tier_code"),
            capability_type_code=v.get("capability_type_code"),
        )
        async for v in queries.list_executable_versions(conn, executable_id=executable_id)
    ]
    return ExecutableDetail(**row, versions=versions)


async def list_versions(conn: AsyncConnection, executable_id: UUID) -> list[ExecutableVersionSummary]:
    return [
        ExecutableVersionSummary(
            executable_version_id=r["executable_version_id"],
            executable_id=executable_id,
            semver=r["semver"],
            lifecycle_stage=r["lifecycle_state_code"],
        )
        async for r in queries.list_executable_versions(conn, executable_id=executable_id)
    ]


async def get_version_detail(conn: AsyncConnection, version_id: UUID) -> ExecutableVersionDetail | None:
    row = await queries.get_version_detail(conn, version_id=version_id)
    if row is None:
        return None
    return ExecutableVersionDetail(**row)


async def create_version(conn: AsyncConnection, executable_id: UUID, ctx: AuthContext,
                          body=None) -> ExecutableVersionDetail | None:
    ex = await queries.get_executable(conn, executable_id=executable_id)
    if ex is None:
        return None
    if body is None or body.semver is None:
        n = (await queries.version_count(conn, executable_id=executable_id))["n"]
        semver = f"0.{n + 1}.0"
        gov_tier = cap_type = trust_level = data_class = ic_id = in_schema = out_schema = change_type = cloned = None
    else:
        semver = body.semver
        gov_tier = body.governance_tier_code
        cap_type = body.capability_type_code
        trust_level = body.trust_level_code
        data_class = body.data_classification_code
        ic_id = body.inference_config_id
        in_schema = Json(body.input_schema) if body.input_schema is not None else None
        out_schema = Json(body.output_schema) if body.output_schema is not None else None
        change_type = body.version_change_type_code
        cloned = body.cloned_from_version_id
    async with conn.transaction():
        v = await queries.create_version_full(
            conn, executable_id=executable_id, kind_code=ex["kind_code"], semver=semver,
            governance_tier_code=gov_tier, capability_type_code=cap_type,
            trust_level_code=trust_level, data_classification_code=data_class,
            inference_config_id=ic_id,
            input_schema=in_schema, output_schema=out_schema,
            version_change_type_code=change_type, cloned_from_version_id=cloned,
            created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role,
        )
        await queries.insert_lifecycle_event(
            conn, version_id=v["executable_version_id"], from_state=None, to_state="draft",
            approval_request_id=None, rationale="created", detail=Json({"event": "initial draft"}),
            actor_id=ctx.principal.actor_id, acting_role_code=ctx.acting_role,
        )
    return ExecutableVersionDetail(
        executable_version_id=v["executable_version_id"], executable_id=executable_id,
        kind_code=v["kind_code"], semver=semver, lifecycle_stage="draft",
        governance_tier_code=gov_tier, capability_type_code=cap_type,
        trust_level_code=trust_level, data_classification_code=data_class,
        inference_config_id=ic_id,
    )


async def advance_lifecycle(conn: AsyncConnection, version_id: UUID, to_stage: str,
                             ctx: AuthContext) -> ExecutableVersion | None:
    """None => version not found (404); raises RegistryGateBlock (409) when gate denies.

    When to_stage == 'champion', delegates to the atomic promote() path which enforces
    the gate. Callers should prefer POST /versions/{id}/promote directly (which also
    enforces the prompt-assignment gate), but this path is preserved for backward compat.
    """
    v = await queries.get_version(conn, version_id=version_id)
    if v is None:
        return None
    cur = await queries.current_state(conn, version_id=version_id)
    current = cur["lifecycle_state_code"] if cur else None
    if to_stage in _GATED:
        link = await queries.link_for_executable(conn, executable_id=v["executable_id"])
        if link is None:
            raise RegistryGateBlock("not_linked")
        if link["intake_status_code"] != "approved":
            raise RegistryGateBlock("intake_not_approved")
        oblig = await obligation_service.get_obligation_set(conn, link["intake_id"])
        if not oblig.rollup.all_resolved:
            outstanding = next((o.requirement_code for o in oblig.obligations if o.status == "outstanding"), None)
            raise RegistryGateBlock("outstanding_obligation", outstanding)
    if to_stage == "champion":
        async with conn.transaction():
            ev = await queries.insert_lifecycle_event(
                conn, version_id=version_id, from_state=current, to_state="champion",
                approval_request_id=None, rationale="champion promotion",
                detail=Json({"event": "champion"}),
                actor_id=ctx.principal.actor_id, acting_role_code=ctx.acting_role,
            )
            await queries.revoke_champion(
                conn, executable_id=v["executable_id"],
                actor_id=ctx.principal.actor_id, acting_role_code=ctx.acting_role,
            )
            await queries.insert_champion_promotion(
                conn, version_id=version_id,
                lifecycle_event_id=ev["lifecycle_event_id"],
                reason="promoted",
                actor_id=ctx.principal.actor_id, acting_role_code=ctx.acting_role,
            )
    else:
        async with conn.transaction():
            await queries.insert_lifecycle_event(
                conn, version_id=version_id, from_state=current, to_state=to_stage,
                approval_request_id=None, rationale="lifecycle advance",
                detail=Json({"from": current, "to": to_stage}),
                actor_id=ctx.principal.actor_id, acting_role_code=ctx.acting_role,
            )
    return ExecutableVersion(executable_version_id=version_id, executable_id=v["executable_id"],
                              semver=v["semver"], lifecycle_stage=to_stage)


async def promote(conn: AsyncConnection, version_id: UUID, reason: str | None,
                   ctx: AuthContext) -> ExecutableVersionDetail | None:
    """Atomic champion promotion with SCD-2 semantics."""
    v = await queries.get_version(conn, version_id=version_id)
    if v is None:
        return None
    count_row = await queries.count_prompt_assignments(conn, executable_version_id=version_id)
    if count_row["n"] == 0:
        raise HTTPException(422, "version has no prompt assignments — cannot promote")
    async with conn.transaction():
        ev = await queries.insert_lifecycle_event(
            conn, version_id=version_id,
            from_state=None, to_state="champion",
            approval_request_id=None, rationale="champion promotion",
            detail=Json({"event": "champion"}),
            actor_id=ctx.principal.actor_id, acting_role_code=ctx.acting_role,
        )
        await queries.revoke_champion(
            conn, executable_id=v["executable_id"],
            actor_id=ctx.principal.actor_id, acting_role_code=ctx.acting_role,
        )
        await queries.insert_champion_promotion(
            conn, version_id=version_id,
            lifecycle_event_id=ev["lifecycle_event_id"],
            reason=reason or "promoted",
            actor_id=ctx.principal.actor_id, acting_role_code=ctx.acting_role,
        )
    return await get_version_detail(conn, version_id)


async def resolve_champion(conn: AsyncConnection, executable_id: UUID,
                             as_of: datetime | None = None) -> ExecutableVersionDetail | None:
    if as_of is None:
        row = await queries.champion_current(conn, executable_id=executable_id)
    else:
        row = await queries.champion_as_of(conn, executable_id=executable_id, as_of=as_of)
    if row is None:
        return None
    return ExecutableVersionDetail(executable_id=executable_id, **row)


# ── Intake links ──────────────────────────────────────────────────────────────

async def link(conn: AsyncConnection, intake_id: UUID, executable_id: UUID,
               requirement_id: UUID | None, ctx: AuthContext) -> None:
    if await queries.get_executable(conn, executable_id=executable_id) is None:
        raise ValueError("unknown asset")
    if await queries.link_for_executable(conn, executable_id=executable_id) is not None:
        raise ValueError("asset is already linked to an intake")
    top = await queries.asset_top_stage(conn, executable_id=executable_id)
    if top is not None and top["top_stage"] not in _EARLY:
        raise ValueError("asset is past the early lifecycle stage and can no longer be linked")
    async with conn.transaction():
        await queries.insert_link(
            conn, intake_id=intake_id, intake_requirement_id=requirement_id,
            executable_id=executable_id,
            created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role,
        )


async def unlink(conn: AsyncConnection, link_id: UUID, ctx: AuthContext) -> None:
    async with conn.transaction():
        await queries.delete_link(conn, link_id=link_id)


async def list_intake_links(conn: AsyncConnection, intake_id: UUID) -> list[IntakeAssetLink]:
    return [IntakeAssetLink(**r) async for r in queries.list_intake_links(conn, intake_id=intake_id)]


# ── Prompts ───────────────────────────────────────────────────────────────────

async def create_prompt(conn: AsyncConnection, name: str, display_name: str,
                         description: str | None, application_id: UUID | None,
                         ctx: AuthContext) -> PromptSummary:
    row = await queries.create_prompt(
        conn, name=name, display_name=display_name, description=description,
        application_id=application_id,
        created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role,
    )
    return PromptSummary(prompt_id=row["prompt_id"], name=row["name"],
                          display_name=row.get("display_name"),
                          description=row.get("description"),
                          application_id=application_id, version_count=0)


async def list_prompts(conn: AsyncConnection, application_id: UUID | None = None) -> list[PromptSummary]:
    return [PromptSummary(**r) async for r in queries.list_prompts(conn, application_id=application_id)]


async def get_prompt(conn: AsyncConnection, prompt_id: UUID) -> PromptSummary | None:
    row = await queries.get_prompt(conn, prompt_id=prompt_id)
    if row is None:
        return None
    versions = await list_prompt_versions(conn, prompt_id)
    return PromptSummary(**{**row, "version_count": len(versions)})


async def create_prompt_version(conn: AsyncConnection, prompt_id: UUID, semver: str,
                                 blocks: list[PromptBlock], ctx: AuthContext) -> PromptVersionSummary | None:
    if await queries.get_prompt(conn, prompt_id=prompt_id) is None:
        return None
    blocks_data = [b.model_dump() for b in blocks]
    content_hash = hashlib.sha256(
        json.dumps(blocks_data, sort_keys=True).encode()
    ).hexdigest()
    row = await queries.create_prompt_version(
        conn, prompt_id=prompt_id, semver=semver,
        blocks=Json(blocks_data), content_hash=content_hash,
        created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role,
    )
    return PromptVersionSummary(
        prompt_version_id=row["prompt_version_id"], prompt_id=row["prompt_id"],
        semver=row["semver"], content_hash=row["content_hash"],
    )


async def list_prompt_versions(conn: AsyncConnection, prompt_id: UUID) -> list[PromptVersionSummary]:
    return [
        PromptVersionSummary(prompt_version_id=r["prompt_version_id"], prompt_id=r["prompt_id"],
                              semver=r["semver"], content_hash=r["content_hash"])
        async for r in queries.list_prompt_versions(conn, prompt_id=prompt_id)
    ]


# ── Tools ─────────────────────────────────────────────────────────────────────

async def get_tool(conn: AsyncConnection, tool_id: UUID) -> ToolSummary | None:
    row = await queries.get_tool(conn, tool_id=tool_id)
    if row is None:
        return None
    return ToolSummary(**row)


async def create_tool(conn: AsyncConnection, name: str, display_name: str, transport_code: str,
                       description: str | None, application_id: UUID | None, ctx: AuthContext) -> ToolSummary:
    row = await queries.create_tool(
        conn, name=name, display_name=display_name, description=description,
        transport_code=transport_code, application_id=application_id,
        created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role,
    )
    return ToolSummary(tool_id=row["tool_id"], name=row["name"], display_name=display_name,
                        transport_code=row["transport_code"], description=description,
                        application_id=application_id)


async def list_tools(conn: AsyncConnection, application_id: UUID | None = None) -> list[ToolSummary]:
    return [ToolSummary(**r) async for r in queries.list_tools(conn, application_id=application_id)]


async def get_executable_intake_link(conn: AsyncConnection, executable_id: UUID):
    from .models import IntakeLink
    row = await queries.link_for_executable(conn, executable_id=executable_id)
    if row is None:
        return None
    return IntakeLink(intake_id=row["intake_id"], intake_title=row["intake_title"],
                      intake_status_code=row["intake_status_code"])


async def create_tool_version(conn: AsyncConnection, tool_id: UUID, semver: str,
                               input_schema, config, data_class: str | None,
                               ctx: AuthContext) -> ToolVersionSummary | None:
    if await queries.get_tool(conn, tool_id=tool_id) is None:
        return None
    row = await queries.create_tool_version(
        conn, tool_id=tool_id, semver=semver,
        input_schema=Json(input_schema) if input_schema is not None else None,
        config=Json(config) if config is not None else Json({}),
        data_classification_code=data_class,
        created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role,
    )
    return ToolVersionSummary(
        tool_version_id=row["tool_version_id"], tool_id=row["tool_id"],
        semver=row["semver"], data_classification_code=row["data_classification_code"],
    )


async def list_tool_versions(conn: AsyncConnection, tool_id: UUID) -> list[ToolVersionSummary]:
    return [
        ToolVersionSummary(tool_version_id=r["tool_version_id"], tool_id=r["tool_id"],
                            semver=r["semver"], data_classification_code=r.get("data_classification_code"))
        async for r in queries.list_tool_versions(conn, tool_id=tool_id)
    ]


# ── MCP Servers ───────────────────────────────────────────────────────────────

async def create_mcp_server_version(conn: AsyncConnection, name: str, semver: str,
                                     config: dict | None, ctx: AuthContext) -> McpServerVersionSummary:
    existing = await queries.get_mcp_server_by_name(conn, name=name)
    async with conn.transaction():
        if existing is None:
            server = await queries.create_mcp_server(
                conn, name=name, transport_code="mcp",
                created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role,
            )
            mcp_server_id = server["mcp_server_id"]
        else:
            mcp_server_id = existing["mcp_server_id"]
        row = await queries.create_mcp_server_version(
            conn, mcp_server_id=mcp_server_id, semver=semver,
            config=Json(config or {}),
            created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role,
        )
    return McpServerVersionSummary(
        mcp_server_version_id=row["mcp_server_version_id"], name=name, semver=row["semver"],
    )


async def list_mcp_servers(conn: AsyncConnection) -> list[McpServerVersionSummary]:
    return [
        McpServerVersionSummary(
            mcp_server_version_id=r["mcp_server_version_id"], name=r["name"], semver=r["semver"],
        )
        async for r in queries.list_mcp_servers(conn)
    ]


# ── Data Connectors ───────────────────────────────────────────────────────────

async def create_connector(conn: AsyncConnection, name: str, connector_type_code: str,
                             description: str | None, ctx: AuthContext) -> ConnectorSummary:
    row = await queries.create_connector(
        conn, name=name, connector_type_code=connector_type_code, description=description,
        created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role,
    )
    return ConnectorSummary(data_connector_id=row["data_connector_id"],
                             name=row["name"], connector_type_code=row["connector_type_code"])


async def list_connectors(conn: AsyncConnection) -> list[ConnectorSummary]:
    return [ConnectorSummary(**r) async for r in queries.list_connectors(conn)]


async def create_connector_version(conn: AsyncConnection, data_connector_id: UUID, semver: str,
                                    config: dict | None, ctx: AuthContext) -> ConnectorVersionSummary | None:
    if await queries.get_connector(conn, data_connector_id=data_connector_id) is None:
        return None
    row = await queries.create_connector_version(
        conn, data_connector_id=data_connector_id, semver=semver,
        config=Json(config or {}),
        created_by_actor_id=ctx.principal.actor_id, created_role_code=ctx.acting_role,
    )
    return ConnectorVersionSummary(
        data_connector_version_id=row["data_connector_version_id"],
        data_connector_id=row["data_connector_id"], semver=row["semver"],
    )


async def list_connector_versions(conn: AsyncConnection, data_connector_id: UUID) -> list[ConnectorVersionSummary]:
    return [
        ConnectorVersionSummary(data_connector_version_id=r["data_connector_version_id"],
                                 data_connector_id=r["data_connector_id"], semver=r["semver"])
        async for r in queries.list_connector_versions(conn, data_connector_id=data_connector_id)
    ]


# ── Inference Configs ─────────────────────────────────────────────────────────

async def create_inference_config(conn: AsyncConnection, max_tokens: int | None,
                                   temperature: float | None, params: dict | None,
                                   model_refs: list, ctx: AuthContext) -> InferenceConfigDetail:
    async with conn.transaction():
        row = await queries.create_inference_config(
            conn, max_tokens=max_tokens, temperature=temperature,
            params=Json(params or {}),
        )
        cfg_id = row["inference_config_id"]
        for entry in model_refs:
            await queries.add_inference_config_model(
                conn, inference_config_id=cfg_id,
                model_reference_id=entry.model_reference_id, priority=entry.priority,
            )
    return await get_inference_config(conn, cfg_id)


async def get_inference_config(conn: AsyncConnection, config_id: UUID) -> InferenceConfigDetail | None:
    row = await queries.get_inference_config(conn, inference_config_id=config_id)
    if row is None:
        return None
    chain = [
        InferenceConfigChainEntry(
            priority=r["priority"],
            model_reference_id=r["model_reference_id"],
            reference_code=r["reference_code"],
            resolved_model_code=r.get("resolved_model_code"),
        )
        async for r in queries.get_inference_config_chain(conn, inference_config_id=config_id)
    ]
    return InferenceConfigDetail(
        inference_config_id=row["inference_config_id"],
        max_tokens=row["max_tokens"],
        temperature=float(row["temperature"]) if row["temperature"] is not None else None,
        params=row["params"] or {},
        model_references=chain,
    )


# ── Composition: Prompt Assignments ──────────────────────────────────────────

async def add_prompt_assignment(conn: AsyncConnection, version_id: UUID, prompt_version_id: UUID,
                                 api_role_code: str, ordinal: int,
                                 ctx: AuthContext) -> PromptAssignment | None:
    row = await queries.add_prompt_assignment(
        conn, executable_version_id=version_id, prompt_version_id=prompt_version_id,
        api_role_code=api_role_code, ordinal=ordinal,
    )
    if row is None:
        return None
    pv = await queries.get_prompt_version(conn, prompt_version_id=prompt_version_id)
    p = await queries.get_prompt(conn, prompt_id=pv["prompt_id"])
    return PromptAssignment(
        executable_version_id=version_id, prompt_version_id=prompt_version_id,
        prompt_id=pv["prompt_id"], prompt_name=p["name"], prompt_semver=pv["semver"],
        api_role_code=api_role_code, ordinal=ordinal,
    )


async def list_prompt_assignments(conn: AsyncConnection, version_id: UUID) -> list[PromptAssignment]:
    return [PromptAssignment(**r) async for r in queries.list_prompt_assignments(conn, executable_version_id=version_id)]


async def remove_prompt_assignment(conn: AsyncConnection, version_id: UUID, prompt_version_id: UUID,
                                    api_role_code: str, ctx: AuthContext) -> None:
    await queries.remove_prompt_assignment(
        conn, executable_version_id=version_id,
        prompt_version_id=prompt_version_id, api_role_code=api_role_code,
    )


# ── Composition: Tool Assignments ─────────────────────────────────────────────

async def add_tool_assignment(conn: AsyncConnection, version_id: UUID, tool_version_id: UUID,
                               ctx: AuthContext) -> ToolAssignment | None:
    v = await queries.get_version(conn, version_id=version_id)
    if v is None:
        return None
    try:
        await queries.add_tool_assignment(
            conn, executable_version_id=version_id, tool_version_id=tool_version_id,
            executable_kind_code=v["kind_code"],
        )
    except psycopg.errors.CheckViolation:
        raise HTTPException(409, "tools are agent-only")
    rows = [r async for r in queries.list_tool_assignments(conn, executable_version_id=version_id)
            if r["tool_version_id"] == tool_version_id]
    if not rows:
        return None
    return ToolAssignment(**rows[0])


async def list_tool_assignments(conn: AsyncConnection, version_id: UUID) -> list[ToolAssignment]:
    return [ToolAssignment(**r) async for r in queries.list_tool_assignments(conn, executable_version_id=version_id)]


async def remove_tool_assignment(conn: AsyncConnection, version_id: UUID, tool_version_id: UUID,
                                  ctx: AuthContext) -> None:
    await queries.remove_tool_assignment(
        conn, executable_version_id=version_id, tool_version_id=tool_version_id,
    )


# ── Composition: MCP Assignments ──────────────────────────────────────────────

async def add_mcp_assignment(conn: AsyncConnection, version_id: UUID, mcp_server_version_id: UUID,
                              ctx: AuthContext) -> McpAssignment | None:
    v = await queries.get_version(conn, version_id=version_id)
    if v is None:
        return None
    try:
        await queries.add_mcp_assignment(
            conn, executable_version_id=version_id, mcp_server_version_id=mcp_server_version_id,
            executable_kind_code=v["kind_code"],
        )
    except psycopg.errors.CheckViolation:
        raise HTTPException(409, "MCP servers are agent-only")
    rows = [r async for r in queries.list_mcp_assignments(conn, executable_version_id=version_id)
            if r["mcp_server_version_id"] == mcp_server_version_id]
    if not rows:
        return None
    return McpAssignment(**rows[0])


async def list_mcp_assignments(conn: AsyncConnection, version_id: UUID) -> list[McpAssignment]:
    return [McpAssignment(**r) async for r in queries.list_mcp_assignments(conn, executable_version_id=version_id)]


async def remove_mcp_assignment(conn: AsyncConnection, version_id: UUID, mcp_server_version_id: UUID,
                                 ctx: AuthContext) -> None:
    await queries.remove_mcp_assignment(
        conn, executable_version_id=version_id, mcp_server_version_id=mcp_server_version_id,
    )


# ── Source Bindings ───────────────────────────────────────────────────────────

async def create_source_binding(conn: AsyncConnection, version_id: UUID, body,
                                 ctx: AuthContext) -> SourceBinding:
    if body.source_kind_code == "storage_object" and body.data_connector_version_id is None:
        raise HTTPException(422, "storage_object source requires data_connector_version_id")
    row = await queries.create_source_binding(
        conn, executable_version_id=version_id, name=body.name,
        source_kind_code=body.source_kind_code,
        data_connector_version_id=body.data_connector_version_id,
        delivery_mode_code=body.delivery_mode_code, media_type=body.media_type,
        locator=Json(body.locator), nullable=body.nullable, ordinal=body.ordinal,
    )
    return SourceBinding(**row)


async def list_source_bindings(conn: AsyncConnection, version_id: UUID) -> list[SourceBinding]:
    return [SourceBinding(**r) async for r in queries.list_source_bindings(conn, executable_version_id=version_id)]


async def delete_source_binding(conn: AsyncConnection, version_id: UUID,
                                 binding_id: UUID, ctx: AuthContext) -> None:
    await queries.delete_source_binding(conn, source_binding_id=binding_id, executable_version_id=version_id)


# ── Target Bindings ───────────────────────────────────────────────────────────

async def create_target_binding(conn: AsyncConnection, version_id: UUID, body,
                                 ctx: AuthContext) -> TargetBinding:
    if body.target_kind_code == "storage_object":
        if body.data_connector_version_id is None or body.write_mode_code is None:
            raise HTTPException(422, "storage_object target requires data_connector_version_id and write_mode_code")
    row = await queries.create_target_binding(
        conn, executable_version_id=version_id, name=body.name,
        target_kind_code=body.target_kind_code,
        data_connector_version_id=body.data_connector_version_id,
        delivery_mode_code=body.delivery_mode_code, write_mode_code=body.write_mode_code,
        target_payload_field=body.target_payload_field,
        locator=Json(body.locator), ordinal=body.ordinal,
    )
    return TargetBinding(**row)


async def list_target_bindings(conn: AsyncConnection, version_id: UUID) -> list[TargetBinding]:
    return [TargetBinding(**r) async for r in queries.list_target_bindings(conn, executable_version_id=version_id)]


async def delete_target_binding(conn: AsyncConnection, version_id: UUID,
                                 binding_id: UUID, ctx: AuthContext) -> None:
    await queries.delete_target_binding(conn, target_binding_id=binding_id, executable_version_id=version_id)


# ── Model Catalog ─────────────────────────────────────────────────────────────

async def create_model(conn: AsyncConnection, model_code: str, provider: str,
                        modality: str, ctx: AuthContext) -> ModelSummary:
    row = await queries.create_model(conn, model_code=model_code, provider=provider, modality=modality)
    return ModelSummary(model_id=row["model_id"], model_code=row["model_code"],
                         provider=row["provider"], modality=row["modality"],
                         model_status_code=row["model_status_code"])


async def list_models(conn: AsyncConnection) -> list[ModelSummary]:
    result = []
    async for r in queries.list_models(conn):
        price = None
        if r.get("model_price_id") is not None:
            price = ModelPrice(
                model_price_id=r["model_price_id"],
                input_price_per_1k=float(r["input_price_per_1k"]),
                output_price_per_1k=float(r["output_price_per_1k"]),
                currency_code=r["currency_code"],
                valid_from=str(r["price_valid_from"]),
                valid_to="2099-12-31T00:00:00+00:00",
            )
        result.append(ModelSummary(
            model_id=r["model_id"], model_code=r["model_code"],
            provider=r["provider"], modality=r["modality"],
            model_status_code=r["model_status_code"], current_price=price,
        ))
    return result


async def add_model_price(conn: AsyncConnection, model_id: UUID, input_price: float,
                           output_price: float, currency_code: str, ctx: AuthContext) -> ModelPrice:
    async with conn.transaction():
        await queries.close_current_model_price(conn, model_id=model_id)
        row = await queries.add_model_price(
            conn, model_id=model_id, input_price_per_1k=input_price,
            output_price_per_1k=output_price, currency_code=currency_code,
        )
    return ModelPrice(
        model_price_id=row["model_price_id"],
        input_price_per_1k=float(row["input_price_per_1k"]),
        output_price_per_1k=float(row["output_price_per_1k"]),
        currency_code=row["currency_code"],
        valid_from=str(row["valid_from"]),
        valid_to=str(row["valid_to"]),
    )


async def list_model_prices(conn: AsyncConnection, model_id: UUID) -> list[ModelPrice]:
    return [
        ModelPrice(
            model_price_id=r["model_price_id"],
            input_price_per_1k=float(r["input_price_per_1k"]),
            output_price_per_1k=float(r["output_price_per_1k"]),
            currency_code=r["currency_code"],
            valid_from=str(r["valid_from"]),
            valid_to=str(r["valid_to"]),
        )
        async for r in queries.list_model_prices(conn, model_id=model_id)
    ]


async def create_model_reference(conn: AsyncConnection, reference_code: str, name: str,
                                  description: str | None, ctx: AuthContext) -> ModelReferenceSummary:
    row = await queries.create_model_reference(
        conn, reference_code=reference_code, name=name, description=description,
    )
    return ModelReferenceSummary(
        model_reference_id=row["model_reference_id"],
        reference_code=row["reference_code"], name=row["name"],
    )


async def list_model_references(conn: AsyncConnection) -> list[ModelReferenceSummary]:
    return [ModelReferenceSummary(**r) async for r in queries.list_model_references(conn)]


async def bind_model_reference(conn: AsyncConnection, model_reference_id: UUID, model_id: UUID,
                                reason: str | None, ctx: AuthContext) -> ModelReferenceBinding:
    async with conn.transaction():
        await queries.close_current_reference_binding(conn, model_reference_id=model_reference_id)
        row = await queries.bind_model_reference(
            conn, model_reference_id=model_reference_id, model_id=model_id,
            reason=reason, bound_by_actor_id=ctx.principal.actor_id, bound_role_code=ctx.acting_role,
        )
    # Fetch the binding back with model_code via list (which does the join)
    bindings = [r async for r in queries.list_model_reference_bindings(
        conn, model_reference_id=model_reference_id)
        if str(r["model_reference_binding_id"]) == str(row["model_reference_binding_id"])]
    model_code = bindings[0]["model_code"] if bindings else ""
    return ModelReferenceBinding(
        model_reference_binding_id=row["model_reference_binding_id"],
        model_reference_id=row["model_reference_id"],
        model_id=row["model_id"],
        model_code=model_code,
        valid_from=str(row["valid_from"]),
        valid_to=str(row["valid_to"]),
        reason=reason,
    )


async def list_model_reference_bindings(conn: AsyncConnection, model_reference_id: UUID) -> list[ModelReferenceBinding]:
    return [
        ModelReferenceBinding(
            model_reference_binding_id=r["model_reference_binding_id"],
            model_reference_id=r["model_reference_id"],
            model_id=r["model_id"],
            model_code=r["model_code"],
            valid_from=str(r["valid_from"]),
            valid_to=str(r["valid_to"]),
            reason=r.get("reason"),
        )
        async for r in queries.list_model_reference_bindings(conn, model_reference_id=model_reference_id)
    ]


# ── Where-Used ────────────────────────────────────────────────────────────────

async def where_used_prompt_version(conn: AsyncConnection, prompt_version_id: UUID) -> list[UsedByEntry]:
    return [UsedByEntry(**r) async for r in queries.where_used_prompt_version(conn, prompt_version_id=prompt_version_id)]


async def where_used_tool_version(conn: AsyncConnection, tool_version_id: UUID) -> list[UsedByEntry]:
    return [UsedByEntry(**r) async for r in queries.where_used_tool_version(conn, tool_version_id=tool_version_id)]


async def where_used_mcp_version(conn: AsyncConnection, mcp_server_version_id: UUID) -> list[UsedByEntry]:
    return [UsedByEntry(**r) async for r in queries.where_used_mcp_version(conn, mcp_server_version_id=mcp_server_version_id)]


# ── Prompt / Tool version detail ─────────────────────────────────────────────

async def get_prompt_version_detail(conn: AsyncConnection, prompt_version_id: UUID) -> PromptVersionDetail:
    row = await queries.get_prompt_version(conn, prompt_version_id=prompt_version_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Prompt version not found")
    raw_blocks = row["blocks"] if row["blocks"] is not None else []
    typed_blocks = _block_list_adapter.validate_python(raw_blocks)
    return PromptVersionDetail(
        prompt_version_id=row["prompt_version_id"],
        prompt_id=row["prompt_id"],
        semver=row["semver"],
        content_hash=row["content_hash"],
        blocks=typed_blocks,
        compiled=compile_blocks(typed_blocks),
    )


async def get_tool_version_detail(conn: AsyncConnection, tool_version_id: UUID) -> ToolVersionDetail:
    row = await queries.get_tool_version_detail(conn, tool_version_id=tool_version_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Tool version not found")
    return ToolVersionDetail(
        tool_version_id=row["tool_version_id"],
        tool_id=row["tool_id"],
        tool_name=row["tool_name"],
        transport_code=row["transport_code"],
        description=row.get("description"),
        semver=row["semver"],
        input_schema=row.get("input_schema"),
        data_classification_code=row.get("data_classification_code"),
    )


async def list_executables_by_model(conn: AsyncConnection, model_id: UUID) -> list[UsedByEntry]:
    return [UsedByEntry(**r) async for r in queries.list_executables_by_model(conn, model_id=model_id)]


# ── Sub-agent Delegations ────────────────────────────────────────────────────

def _delegation_row(r: dict) -> DelegationSummary:
    return DelegationSummary(
        delegation_id=r["delegation_id"],
        parent_version_id=r["parent_version_id"],
        child_executable_id=r.get("child_executable_id"),
        child_name=r.get("child_name"),
        child_kind=r.get("child_kind"),
        child_version_id=r.get("child_version_id"),
        scope=r["scope"] if r["scope"] is not None else {},
        rationale=r.get("rationale"),
        notes=r.get("notes"),
        created_at=str(r["created_at"]),
    )


async def list_delegations(conn: AsyncConnection, version_id: UUID) -> list[DelegationSummary]:
    return [_delegation_row(r) async for r in queries.list_delegations_for_parent(conn, parent_version_id=version_id)]


async def create_delegation(conn: AsyncConnection, version_id: UUID, body: CreateDelegation, ctx: "AuthContext") -> DelegationSummary:
    version_row = await queries.get_version_detail(conn, version_id=version_id)
    if version_row is None:
        raise HTTPException(status_code=404, detail="Version not found")
    if version_row["kind_code"] != "agent":
        raise HTTPException(status_code=422, detail="Tasks cannot delegate — only agent versions may have delegation authorizations")
    row = await queries.insert_delegation(
        conn,
        parent_version_id=version_id,
        child_executable_id=body.child_executable_id,
        child_version_id=body.child_version_id,
        scope=Json(body.scope),
        rationale=body.rationale,
        notes=body.notes,
    )
    # re-fetch to get the child_name JOIN resolved
    rows = await list_delegations(conn, version_id)
    return next(r for r in rows if str(r.delegation_id) == str(row["delegation_id"]))


async def delete_delegation(conn: AsyncConnection, version_id: UUID, delegation_id: UUID, ctx: "AuthContext") -> None:
    await queries.delete_delegation(conn, delegation_id=delegation_id, parent_version_id=version_id)

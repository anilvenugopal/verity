"""Registry HTTP routes (005): full entity registration, composition, champion
promotion, bindings, model catalog, and YAML I/O. Extends the 003 asset primitive."""
from __future__ import annotations

from datetime import datetime
from uuid import UUID

import psycopg.errors
from fastapi import APIRouter, Body, Depends, HTTPException, Request, Response
from psycopg import AsyncConnection

from verity.hub.auth.dependencies import require_action
from verity.hub.auth.models import AuthContext
from verity.hub.registry import service
from verity.hub.registry.models import (
    ConnectorSummary,
    ConnectorVersionSummary,
    CreateConnector,
    CreateConnectorVersion,
    CreateDelegation,
    CreateExecutable,
    CreateExecutableVersion,
    CreateInferenceConfig,
    CreateMcpAssignment,
    CreateMcpServerVersion,
    CreateModel,
    CreateModelPrice,
    CreateModelReference,
    CreateModelReferenceBinding,
    CreatePrompt,
    CreatePromptAssignment,
    CreatePromptVersion,
    CreateSourceBinding,
    CreateTargetBinding,
    CreateTool,
    CreateToolAssignment,
    CreateToolVersion,
    DelegationSummary,
    ExecutableDetail,
    ExecutableSummary,
    ExecutableVersionDetail,
    ExecutableVersionSummary,
    ImportReport,
    InferenceConfigDetail,
    IntakeAssetLink,
    IntakeLink,
    LifecycleAdvance,
    LinkInput,
    McpAssignment,
    McpServerVersionSummary,
    ModelPrice,
    ModelReferenceBinding,
    ModelReferenceSummary,
    ModelSummary,
    PromoteInput,
    PromptAssignment,
    PromptSummary,
    PromptVersionDetail,
    PromptVersionSummary,
    SourceBinding,
    TargetBinding,
    ToolAssignment,
    ToolSummary,
    ToolVersionDetail,
    ToolVersionSummary,
    UsedByEntry,
)

router = APIRouter(tags=["registry"])


async def get_conn(request: Request):
    async with request.app.state.pool.connection() as conn:
        yield conn


# ── Executables ───────────────────────────────────────────────────────────────

@router.get("/executables", response_model=list[ExecutableSummary])
async def list_executables(
    kind: str | None = None,
    application_id: UUID | None = None,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[ExecutableSummary]:
    return await service.list_executables(conn, kind_code=kind, application_id=application_id)


@router.post("/executables", response_model=ExecutableSummary, status_code=201)
async def create_executable(
    body: CreateExecutable,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> ExecutableSummary:
    try:
        return await service.create_executable(
            conn, body.name, body.kind_code, ctx,
            display_name=body.display_name, description=body.description,
            application_id=body.application_id,
        )
    except psycopg.errors.UniqueViolation:
        raise HTTPException(409, "executable name already exists for this kind")


@router.get("/executables/{executable_id}", response_model=ExecutableDetail)
async def get_executable_detail(
    executable_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> ExecutableDetail:
    detail = await service.get_executable_detail(conn, executable_id)
    if detail is None:
        raise HTTPException(404, "executable not found")
    return detail


@router.get("/executables/{executable_id}/intake-link", response_model=IntakeLink)
async def get_executable_intake_link(
    executable_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> IntakeLink:
    result = await service.get_executable_intake_link(conn, executable_id)
    if result is None:
        raise HTTPException(404, "no intake link for this executable")
    return result


@router.get("/executables/{executable_id}/versions", response_model=list[ExecutableVersionSummary])
async def list_versions(
    executable_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[ExecutableVersionSummary]:
    return await service.list_versions(conn, executable_id)


@router.post("/executables/{executable_id}/versions", response_model=ExecutableVersionDetail, status_code=201)
async def create_version(
    executable_id: UUID,
    body: CreateExecutableVersion = Body(default=CreateExecutableVersion()),
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> ExecutableVersionDetail:
    try:
        v = await service.create_version(conn, executable_id, ctx, body)
    except psycopg.errors.UniqueViolation:
        raise HTTPException(409, "duplicate semver")
    if v is None:
        raise HTTPException(404, "executable not found")
    return v


@router.get("/executables/{executable_id}/champion", response_model=ExecutableVersionDetail)
async def get_champion(
    executable_id: UUID,
    as_of: datetime | None = None,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> ExecutableVersionDetail:
    row = await service.resolve_champion(conn, executable_id, as_of)
    if row is None:
        raise HTTPException(404, "no champion")
    return row


@router.get("/versions/{version_id}", response_model=ExecutableVersionDetail)
async def get_version_detail(
    version_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> ExecutableVersionDetail:
    row = await service.get_version_detail(conn, version_id)
    if row is None:
        raise HTTPException(404, "version not found")
    return row


@router.post("/versions/{version_id}/lifecycle", response_model=ExecutableVersionDetail)
async def advance_lifecycle(
    version_id: UUID,
    body: LifecycleAdvance,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("promote_registry")),
) -> ExecutableVersionDetail:
    try:
        v = await service.advance_lifecycle(conn, version_id, body.to_stage, ctx)
    except service.RegistryGateBlock as gb:
        raise HTTPException(409, str(gb)) from gb
    if v is None:
        raise HTTPException(404, "version not found")
    detail = await service.get_version_detail(conn, version_id)
    return detail or ExecutableVersionDetail(
        executable_version_id=v.executable_version_id,
        executable_id=v.executable_id,
        semver=v.semver,
        lifecycle_stage=v.lifecycle_stage,
    )


@router.post("/versions/{version_id}/promote", response_model=ExecutableVersionDetail)
async def promote_version(
    version_id: UUID,
    body: PromoteInput = Body(default=PromoteInput()),
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("promote_registry")),
) -> ExecutableVersionDetail:
    try:
        v = await service.promote(conn, version_id, body.reason, ctx)
    except service.RegistryGateBlock as gb:
        raise HTTPException(409, str(gb)) from gb
    if v is None:
        raise HTTPException(404, "version not found")
    return v


# ── Intake links ──────────────────────────────────────────────────────────────

@router.post("/intakes/{intake_id}/links", status_code=201)
async def link_asset(
    intake_id: UUID, body: LinkInput,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("link_asset")),
) -> dict:
    try:
        await service.link(conn, intake_id, body.executable_id, body.intake_requirement_id, ctx)
    except ValueError as exc:
        raise HTTPException(409, str(exc)) from exc
    return {"ok": True}


@router.delete("/links/{link_id}", status_code=204)
async def unlink_asset(
    link_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("link_asset")),
) -> None:
    await service.unlink(conn, link_id, ctx)


@router.get("/intakes/{intake_id}/links", response_model=list[IntakeAssetLink])
async def list_links(
    intake_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[IntakeAssetLink]:
    return await service.list_intake_links(conn, intake_id)


# ── Prompts ───────────────────────────────────────────────────────────────────

@router.get("/prompts", response_model=list[PromptSummary])
async def list_prompts(
    application_id: UUID | None = None,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[PromptSummary]:
    return await service.list_prompts(conn, application_id=application_id)


@router.post("/prompts", response_model=PromptSummary, status_code=201)
async def create_prompt(
    body: CreatePrompt,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> PromptSummary:
    try:
        return await service.create_prompt(
            conn, body.name, body.display_name, body.description, body.application_id, ctx,
        )
    except psycopg.errors.UniqueViolation:
        raise HTTPException(409, "prompt name already exists")


@router.get("/prompts/{prompt_id}", response_model=PromptSummary)
async def get_prompt(
    prompt_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> PromptSummary:
    result = await service.get_prompt(conn, prompt_id)
    if result is None:
        raise HTTPException(404, "prompt not found")
    return result


@router.get("/prompts/{prompt_id}/versions", response_model=list[PromptVersionSummary])
async def list_prompt_versions(
    prompt_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[PromptVersionSummary]:
    return await service.list_prompt_versions(conn, prompt_id)


@router.post("/prompts/{prompt_id}/versions", response_model=PromptVersionSummary, status_code=201)
async def create_prompt_version(
    prompt_id: UUID, body: CreatePromptVersion,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> PromptVersionSummary:
    try:
        pv = await service.create_prompt_version(conn, prompt_id, body.semver, body.blocks, ctx)
    except psycopg.errors.UniqueViolation:
        raise HTTPException(409, "duplicate semver")
    if pv is None:
        raise HTTPException(404, "prompt not found")
    return pv


@router.get("/prompt-versions/{prompt_version_id}/used-by", response_model=list[UsedByEntry])
async def prompt_version_used_by(
    prompt_version_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[UsedByEntry]:
    return await service.where_used_prompt_version(conn, prompt_version_id)


# ── Tools ─────────────────────────────────────────────────────────────────────

@router.get("/tools", response_model=list[ToolSummary])
async def list_tools(
    application_id: UUID | None = None,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[ToolSummary]:
    return await service.list_tools(conn, application_id=application_id)


@router.post("/tools", response_model=ToolSummary, status_code=201)
async def create_tool(
    body: CreateTool,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> ToolSummary:
    try:
        return await service.create_tool(
            conn, body.name, body.display_name, body.transport_code,
            body.description, body.application_id, ctx,
        )
    except psycopg.errors.UniqueViolation:
        raise HTTPException(409, "tool name already exists")


@router.get("/tools/{tool_id}", response_model=ToolSummary)
async def get_tool(
    tool_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> ToolSummary:
    result = await service.get_tool(conn, tool_id)
    if result is None:
        raise HTTPException(404, "tool not found")
    return result


@router.get("/tools/{tool_id}/versions", response_model=list[ToolVersionSummary])
async def list_tool_versions(
    tool_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[ToolVersionSummary]:
    return await service.list_tool_versions(conn, tool_id)


@router.post("/tools/{tool_id}/versions", response_model=ToolVersionSummary, status_code=201)
async def create_tool_version(
    tool_id: UUID, body: CreateToolVersion,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> ToolVersionSummary:
    try:
        tv = await service.create_tool_version(
            conn, tool_id, body.semver, body.input_schema, body.config,
            body.data_classification_code, ctx,
        )
    except psycopg.errors.UniqueViolation:
        raise HTTPException(409, "duplicate semver")
    if tv is None:
        raise HTTPException(404, "tool not found")
    return tv


@router.get("/tool-versions/{tool_version_id}/used-by", response_model=list[UsedByEntry])
async def tool_version_used_by(
    tool_version_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[UsedByEntry]:
    return await service.where_used_tool_version(conn, tool_version_id)


# ── MCP Servers ───────────────────────────────────────────────────────────────

@router.get("/mcp-servers", response_model=list[McpServerVersionSummary])
async def list_mcp_servers(
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[McpServerVersionSummary]:
    return await service.list_mcp_servers(conn)


@router.post("/mcp-servers", response_model=McpServerVersionSummary, status_code=201)
async def create_mcp_server_version(
    body: CreateMcpServerVersion,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> McpServerVersionSummary:
    try:
        return await service.create_mcp_server_version(conn, body.name, body.semver, body.config, ctx)
    except psycopg.errors.UniqueViolation:
        raise HTTPException(409, "duplicate semver for this MCP server")


@router.get("/mcp-versions/{mcp_version_id}/used-by", response_model=list[UsedByEntry])
async def mcp_version_used_by(
    mcp_version_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[UsedByEntry]:
    return await service.where_used_mcp_version(conn, mcp_version_id)


# ── Data Connectors ───────────────────────────────────────────────────────────

@router.get("/connectors", response_model=list[ConnectorSummary])
async def list_connectors(
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[ConnectorSummary]:
    return await service.list_connectors(conn)


@router.post("/connectors", response_model=ConnectorSummary, status_code=201)
async def create_connector(
    body: CreateConnector,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> ConnectorSummary:
    try:
        return await service.create_connector(conn, body.name, body.connector_type_code, body.description, ctx)
    except psycopg.errors.UniqueViolation:
        raise HTTPException(409, "connector name already exists")


@router.get("/connectors/{connector_id}/versions", response_model=list[ConnectorVersionSummary])
async def list_connector_versions(
    connector_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[ConnectorVersionSummary]:
    return await service.list_connector_versions(conn, connector_id)


@router.post("/connectors/{connector_id}/versions", response_model=ConnectorVersionSummary, status_code=201)
async def create_connector_version(
    connector_id: UUID, body: CreateConnectorVersion,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> ConnectorVersionSummary:
    try:
        cv = await service.create_connector_version(conn, connector_id, body.semver, body.config, ctx)
    except psycopg.errors.UniqueViolation:
        raise HTTPException(409, "duplicate semver")
    if cv is None:
        raise HTTPException(404, "connector not found")
    return cv


# ── Inference Configs ─────────────────────────────────────────────────────────

@router.post("/inference-configs", response_model=InferenceConfigDetail, status_code=201)
async def create_inference_config(
    body: CreateInferenceConfig,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> InferenceConfigDetail:
    return await service.create_inference_config(
        conn, body.max_tokens, body.temperature, body.params, body.model_references, ctx,
    )


@router.get("/inference-configs/{config_id}", response_model=InferenceConfigDetail)
async def get_inference_config(
    config_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> InferenceConfigDetail:
    cfg = await service.get_inference_config(conn, config_id)
    if cfg is None:
        raise HTTPException(404, "inference config not found")
    return cfg


# ── Composition: Prompt Assignments ──────────────────────────────────────────

@router.get("/versions/{version_id}/prompt-assignments", response_model=list[PromptAssignment])
async def list_prompt_assignments(
    version_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[PromptAssignment]:
    return await service.list_prompt_assignments(conn, version_id)


@router.post("/versions/{version_id}/prompt-assignments", response_model=PromptAssignment, status_code=201)
async def add_prompt_assignment(
    version_id: UUID, body: CreatePromptAssignment,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> PromptAssignment:
    try:
        pa = await service.add_prompt_assignment(
            conn, version_id, body.prompt_version_id, body.api_role_code, body.ordinal, ctx,
        )
    except psycopg.errors.UniqueViolation:
        raise HTTPException(409, "assignment already exists")
    if pa is None:
        raise HTTPException(409, "assignment already exists (idempotent)")
    return pa


@router.delete("/versions/{version_id}/prompt-assignments/{prompt_version_id}/{api_role}", status_code=204)
async def remove_prompt_assignment(
    version_id: UUID, prompt_version_id: UUID, api_role: str,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> None:
    await service.remove_prompt_assignment(conn, version_id, prompt_version_id, api_role, ctx)


# ── Composition: Tool Assignments ─────────────────────────────────────────────

@router.get("/versions/{version_id}/tool-assignments", response_model=list[ToolAssignment])
async def list_tool_assignments(
    version_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[ToolAssignment]:
    return await service.list_tool_assignments(conn, version_id)


@router.post("/versions/{version_id}/tool-assignments", response_model=ToolAssignment, status_code=201)
async def add_tool_assignment(
    version_id: UUID, body: CreateToolAssignment,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> ToolAssignment:
    ta = await service.add_tool_assignment(conn, version_id, body.tool_version_id, ctx)
    if ta is None:
        raise HTTPException(404, "version or tool version not found")
    return ta


@router.delete("/versions/{version_id}/tool-assignments/{tool_version_id}", status_code=204)
async def remove_tool_assignment(
    version_id: UUID, tool_version_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> None:
    await service.remove_tool_assignment(conn, version_id, tool_version_id, ctx)


# ── Composition: MCP Assignments ──────────────────────────────────────────────

@router.get("/versions/{version_id}/mcp-assignments", response_model=list[McpAssignment])
async def list_mcp_assignments(
    version_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[McpAssignment]:
    return await service.list_mcp_assignments(conn, version_id)


@router.post("/versions/{version_id}/mcp-assignments", response_model=McpAssignment, status_code=201)
async def add_mcp_assignment(
    version_id: UUID, body: CreateMcpAssignment,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> McpAssignment:
    ma = await service.add_mcp_assignment(conn, version_id, body.mcp_server_version_id, ctx)
    if ma is None:
        raise HTTPException(404, "version or MCP version not found")
    return ma


@router.delete("/versions/{version_id}/mcp-assignments/{mcp_version_id}", status_code=204)
async def remove_mcp_assignment(
    version_id: UUID, mcp_version_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> None:
    await service.remove_mcp_assignment(conn, version_id, mcp_version_id, ctx)


# ── Source Bindings ───────────────────────────────────────────────────────────

@router.get("/versions/{version_id}/source-bindings", response_model=list[SourceBinding])
async def list_source_bindings(
    version_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[SourceBinding]:
    return await service.list_source_bindings(conn, version_id)


@router.post("/versions/{version_id}/source-bindings", response_model=SourceBinding, status_code=201)
async def create_source_binding(
    version_id: UUID, body: CreateSourceBinding,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> SourceBinding:
    try:
        return await service.create_source_binding(conn, version_id, body, ctx)
    except psycopg.errors.UniqueViolation:
        raise HTTPException(409, "binding name already exists for this version")


@router.delete("/versions/{version_id}/source-bindings/{binding_id}", status_code=204)
async def delete_source_binding(
    version_id: UUID, binding_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> None:
    await service.delete_source_binding(conn, version_id, binding_id, ctx)


# ── Target Bindings ───────────────────────────────────────────────────────────

@router.get("/versions/{version_id}/target-bindings", response_model=list[TargetBinding])
async def list_target_bindings(
    version_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[TargetBinding]:
    return await service.list_target_bindings(conn, version_id)


@router.post("/versions/{version_id}/target-bindings", response_model=TargetBinding, status_code=201)
async def create_target_binding(
    version_id: UUID, body: CreateTargetBinding,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> TargetBinding:
    try:
        return await service.create_target_binding(conn, version_id, body, ctx)
    except psycopg.errors.UniqueViolation:
        raise HTTPException(409, "binding name already exists for this version")


@router.delete("/versions/{version_id}/target-bindings/{binding_id}", status_code=204)
async def delete_target_binding(
    version_id: UUID, binding_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> None:
    await service.delete_target_binding(conn, version_id, binding_id, ctx)


# ── Model Catalog ─────────────────────────────────────────────────────────────

@router.get("/models", response_model=list[ModelSummary])
async def list_models(
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[ModelSummary]:
    return await service.list_models(conn)


@router.get("/models/{model_id}", response_model=ModelSummary)
async def get_model(
    model_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> ModelSummary:
    models = await service.list_models(conn)
    m = next((m for m in models if str(m.model_id) == str(model_id)), None)
    if m is None:
        raise HTTPException(404, "model not found")
    return m


@router.post("/models", response_model=ModelSummary, status_code=201)
async def create_model(
    body: CreateModel,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> ModelSummary:
    try:
        return await service.create_model(conn, body.model_code, body.provider, body.modality, ctx)
    except psycopg.errors.UniqueViolation:
        raise HTTPException(409, "model_code already exists")


@router.get("/models/{model_id}/prices", response_model=list[ModelPrice])
async def list_model_prices(
    model_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[ModelPrice]:
    return await service.list_model_prices(conn, model_id)


@router.post("/models/{model_id}/prices", response_model=ModelPrice, status_code=201)
async def add_model_price(
    model_id: UUID, body: CreateModelPrice,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> ModelPrice:
    return await service.add_model_price(
        conn, model_id, body.input_price_per_1k, body.output_price_per_1k, body.currency_code, ctx,
    )


@router.get("/model-references", response_model=list[ModelReferenceSummary])
async def list_model_references(
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[ModelReferenceSummary]:
    return await service.list_model_references(conn)


@router.post("/model-references", response_model=ModelReferenceSummary, status_code=201)
async def create_model_reference(
    body: CreateModelReference,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> ModelReferenceSummary:
    try:
        return await service.create_model_reference(
            conn, body.reference_code, body.name, body.description, ctx,
        )
    except psycopg.errors.UniqueViolation:
        raise HTTPException(409, "reference_code already exists")


@router.get("/model-references/{ref_id}/bindings", response_model=list[ModelReferenceBinding])
async def list_model_reference_bindings(
    ref_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> list[ModelReferenceBinding]:
    return await service.list_model_reference_bindings(conn, ref_id)


@router.post("/model-references/{ref_id}/bindings", response_model=ModelReferenceBinding, status_code=201)
async def bind_model_reference(
    ref_id: UUID, body: CreateModelReferenceBinding,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> ModelReferenceBinding:
    return await service.bind_model_reference(conn, ref_id, body.model_id, body.reason, ctx)


# ── YAML I/O ──────────────────────────────────────────────────────────────────

@router.get("/versions/{version_id}/export")
async def export_version(
    version_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("view")),
) -> Response:
    from verity.hub.registry.yaml_io import bundle_to_yaml, export_version as svc_export
    data = await svc_export(conn, version_id)
    if data is None:
        raise HTTPException(404, "version not found")
    return Response(content=bundle_to_yaml(data), media_type="application/x-yaml")


@router.post("/import/dry-run", response_model=ImportReport)
async def import_dry_run(
    request: Request,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> ImportReport:
    from verity.hub.registry.yaml_io import import_bundle, parse_bundle
    body = await request.body()
    try:
        bundle = parse_bundle(body.decode())
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
    return await import_bundle(conn, bundle, dry_run=True, ctx=ctx)


@router.post("/import", response_model=ImportReport)
async def import_apply(
    request: Request,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> ImportReport:
    from verity.hub.registry.yaml_io import import_bundle, parse_bundle
    body = await request.body()
    try:
        bundle = parse_bundle(body.decode())
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
    return await import_bundle(conn, bundle, dry_run=False, ctx=ctx)


# ── Prompt version detail (with blocks) ───────────────────────────────────────

@router.get("/prompt-versions/{prompt_version_id}", response_model=PromptVersionDetail)
async def get_prompt_version_detail(
    prompt_version_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
) -> PromptVersionDetail:
    return await service.get_prompt_version_detail(conn, prompt_version_id)


# ── Tool version detail (with input_schema) ───────────────────────────────────

@router.get("/tool-versions/{tool_version_id}", response_model=ToolVersionDetail)
async def get_tool_version_detail(
    tool_version_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
) -> ToolVersionDetail:
    return await service.get_tool_version_detail(conn, tool_version_id)


# ── Sub-agent Delegations ─────────────────────────────────────────────────────

@router.get("/versions/{version_id}/delegations", response_model=list[DelegationSummary])
async def list_delegations(
    version_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
) -> list[DelegationSummary]:
    return await service.list_delegations(conn, version_id)


@router.post("/versions/{version_id}/delegations", response_model=DelegationSummary, status_code=201)
async def create_delegation(
    version_id: UUID,
    body: CreateDelegation,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> DelegationSummary:
    return await service.create_delegation(conn, version_id, body, ctx)


@router.delete("/versions/{version_id}/delegations/{delegation_id}", status_code=204)
async def delete_delegation(
    version_id: UUID,
    delegation_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
    ctx: AuthContext = Depends(require_action("author_registry")),
) -> None:
    await service.delete_delegation(conn, version_id, delegation_id, ctx)


# ── Model used-by ─────────────────────────────────────────────────────────────

@router.get("/models/{model_id}/executables", response_model=list[UsedByEntry])
async def list_executables_by_model(
    model_id: UUID,
    conn: AsyncConnection = Depends(get_conn),
) -> list[UsedByEntry]:
    return await service.list_executables_by_model(conn, model_id)

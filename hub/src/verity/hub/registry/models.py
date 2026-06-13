"""Pydantic boundary models for the full entity registry (005)."""
from __future__ import annotations

from datetime import datetime
from typing import Annotated, Any, Literal, Union
from uuid import UUID

from pydantic import BaseModel, Field, model_validator


# ── Prompt block schema (mirrors specs/ui/prompt-editor-architecture.md) ─────

class ProseBlock(BaseModel):
    id: str
    kind: Literal["prose"]
    text: str

    def render(self) -> str:
        return self.text


class VarBlock(BaseModel):
    id: str
    kind: Literal["var"]
    name: str
    type: Literal["string", "number", "code", "enum", "boolean"]
    desc: str
    eg: str | None = None
    opts: list[str] | None = None
    req: bool = True

    def render(self) -> str:
        return f"{{{self.name}}}"


class ListBlock(BaseModel):
    id: str
    kind: Literal["list"]
    items: list[str]

    def render(self) -> str:
        return "\n".join(f"{i + 1}. {item}" for i, item in enumerate(self.items))


class TableBlock(BaseModel):
    id: str
    kind: Literal["table"]
    headers: list[str]
    rows: list[list[str]]
    caption: str | None = None

    def render(self) -> str:
        sep = "| " + " | ".join("---" for _ in self.headers) + " |"
        header = "| " + " | ".join(self.headers) + " |"
        body = "\n".join("| " + " | ".join(row) + " |" for row in self.rows)
        parts = [header, sep, body]
        if self.caption:
            parts.append(f"*{self.caption}*")
        return "\n".join(parts)


class CodeBlock(BaseModel):
    id: str
    kind: Literal["code"]
    lang: str
    code: str
    caption: str | None = None

    def render(self) -> str:
        lines = [f"```{self.lang}", self.code, "```"]
        if self.caption:
            lines.append(f"*{self.caption}*")
        return "\n".join(lines)


PromptBlock = Annotated[
    Union[ProseBlock, VarBlock, ListBlock, TableBlock, CodeBlock],
    Field(discriminator="kind"),
]


def compile_blocks(blocks: list[PromptBlock]) -> str:
    """Compile a block list to a template string with {var} placeholders.

    Pure function — same blocks always produce the same string.
    Harness uses: compile_blocks(blocks).format(**run_context)
    """
    return "\n\n".join(b.render() for b in blocks)


# ── Executables ───────────────────────────────────────────────────────────────

class CreateExecutable(BaseModel):
    name: str = Field(min_length=1)
    display_name: str = Field(min_length=1)
    kind_code: Literal["agent", "task"]
    description: str | None = None
    application_id: UUID | None = None


class ExecutableSummary(BaseModel):
    executable_id: UUID
    kind_code: str
    name: str
    display_name: str | None = None
    description: str | None = None
    version_count: int = 0
    champion_version_id: UUID | None = None
    champion_semver: str | None = None
    champion_governance_tier_code: str | None = None
    champion_capability_type_code: str | None = None
    application_id: UUID | None = None
    application_code: str | None = None
    application_name: str | None = None
    updated_at: datetime | None = None


class Executable(BaseModel):
    executable_id: UUID
    kind_code: str
    name: str
    display_name: str | None = None
    description: str | None = None
    version_count: int = 0
    application_id: UUID | None = None
    application_code: str | None = None
    application_name: str | None = None


class ExecutableVersionSummary(BaseModel):
    executable_version_id: UUID
    executable_id: UUID
    semver: str | None = None
    lifecycle_stage: str | None = None
    governance_tier_code: str | None = None
    capability_type_code: str | None = None
    created_at: datetime | None = None


class ExecutableVersionDetail(BaseModel):
    executable_version_id: UUID
    executable_id: UUID
    kind_code: str | None = None
    semver: str | None = None
    lifecycle_stage: str | None = None
    governance_tier_code: str | None = None
    capability_type_code: str | None = None
    trust_level_code: str | None = None
    data_classification_code: str | None = None
    inference_config_id: UUID | None = None
    input_schema: dict[str, Any] | None = None
    output_schema: dict[str, Any] | None = None
    cloned_from_version_id: UUID | None = None


class ExecutableDetail(ExecutableSummary):
    versions: list[ExecutableVersionSummary] = []


class CreateExecutableVersion(BaseModel):
    semver: str | None = None
    governance_tier_code: str | None = None
    capability_type_code: str | None = None
    trust_level_code: str | None = None
    data_classification_code: str | None = None
    inference_config_id: UUID | None = None
    input_schema: dict[str, Any] | None = None
    output_schema: dict[str, Any] | None = None
    version_change_type_code: Literal["major", "minor", "patch"] | None = None
    cloned_from_version_id: UUID | None = None


class ExecutableVersion(BaseModel):
    executable_version_id: UUID
    executable_id: UUID
    semver: str | None = None
    lifecycle_stage: str | None = None


class LifecycleAdvance(BaseModel):
    to_stage: Literal["candidate", "staging", "challenger", "champion", "deprecated"]


class PromoteInput(BaseModel):
    reason: str | None = None


# ── Intake links (carried forward from 003) ───────────────────────────────────

class LinkInput(BaseModel):
    executable_id: UUID
    intake_requirement_id: UUID | None = None


class IntakeAssetLink(BaseModel):
    intake_entity_link_id: UUID
    executable_id: UUID
    name: str
    kind_code: str
    top_stage: str | None = None


class IntakeLink(BaseModel):
    intake_id: UUID
    intake_title: str
    intake_status_code: str


# ── Prompts ───────────────────────────────────────────────────────────────────

class CreatePrompt(BaseModel):
    name: str = Field(min_length=1)
    display_name: str = Field(min_length=1)
    description: str | None = None
    application_id: UUID | None = None


class PromptSummary(BaseModel):
    prompt_id: UUID
    name: str
    display_name: str | None = None
    description: str | None = None
    version_count: int = 0
    latest_version_id: UUID | None = None
    application_id: UUID | None = None
    application_code: str | None = None
    application_name: str | None = None
    updated_at: datetime | None = None


class CreatePromptVersion(BaseModel):
    semver: str
    blocks: list[PromptBlock]


class PromptVersionSummary(BaseModel):
    prompt_version_id: UUID
    prompt_id: UUID
    semver: str
    content_hash: str
    created_at: datetime | None = None


# ── Tools ─────────────────────────────────────────────────────────────────────

class CreateTool(BaseModel):
    name: str = Field(min_length=1)
    display_name: str = Field(min_length=1)
    transport_code: str
    description: str | None = None
    application_id: UUID | None = None


class ToolSummary(BaseModel):
    tool_id: UUID
    name: str
    display_name: str | None = None
    transport_code: str
    description: str | None = None
    is_write_operation: bool = False
    latest_version_id: UUID | None = None
    application_id: UUID | None = None
    application_code: str | None = None
    application_name: str | None = None
    updated_at: datetime | None = None


class CreateToolVersion(BaseModel):
    semver: str
    input_schema: dict[str, Any] | None = None
    config: dict[str, Any] | None = None
    data_classification_code: str | None = None


class ToolVersionSummary(BaseModel):
    tool_version_id: UUID
    tool_id: UUID
    semver: str
    data_classification_code: str | None = None
    created_at: datetime | None = None


# ── MCP Servers ───────────────────────────────────────────────────────────────

class CreateMcpServerVersion(BaseModel):
    name: str
    semver: str
    config: dict[str, Any] | None = None


class McpServerVersionSummary(BaseModel):
    mcp_server_version_id: UUID
    name: str
    semver: str


# ── Data Connectors ───────────────────────────────────────────────────────────

class CreateConnector(BaseModel):
    name: str
    connector_type_code: str
    description: str | None = None


class ConnectorSummary(BaseModel):
    data_connector_id: UUID
    name: str
    connector_type_code: str


class CreateConnectorVersion(BaseModel):
    semver: str
    config: dict[str, Any] | None = None


class ConnectorVersionSummary(BaseModel):
    data_connector_version_id: UUID
    data_connector_id: UUID
    semver: str


# ── Inference Configs ─────────────────────────────────────────────────────────

class InferenceConfigModelEntry(BaseModel):
    priority: int
    model_reference_id: UUID


class CreateInferenceConfig(BaseModel):
    max_tokens: int | None = None
    temperature: float | None = None
    params: dict[str, Any] | None = None
    model_references: list[InferenceConfigModelEntry] = []


class InferenceConfigChainEntry(BaseModel):
    priority: int
    model_reference_id: UUID
    reference_code: str
    resolved_model_code: str | None = None


class InferenceConfigDetail(BaseModel):
    inference_config_id: UUID
    max_tokens: int | None = None
    temperature: float | None = None
    params: dict[str, Any] = {}
    model_references: list[InferenceConfigChainEntry] = []


# ── Composition Assignments ───────────────────────────────────────────────────

class CreatePromptAssignment(BaseModel):
    prompt_version_id: UUID
    api_role_code: str
    ordinal: int = 1


class PromptAssignment(BaseModel):
    executable_version_id: UUID
    prompt_version_id: UUID
    prompt_id: UUID
    prompt_name: str
    prompt_semver: str
    api_role_code: str
    ordinal: int
    created_at: datetime | None = None


class CreateToolAssignment(BaseModel):
    tool_version_id: UUID


class ToolAssignment(BaseModel):
    executable_version_id: UUID
    tool_version_id: UUID
    tool_id: UUID
    tool_name: str
    tool_semver: str
    created_at: datetime | None = None


class CreateMcpAssignment(BaseModel):
    mcp_server_version_id: UUID


class McpAssignment(BaseModel):
    executable_version_id: UUID
    mcp_server_version_id: UUID
    name: str
    semver: str


# ── Source and Target Bindings ────────────────────────────────────────────────

class CreateSourceBinding(BaseModel):
    name: str
    source_kind_code: Literal["storage_object", "task_output", "structured", "inline_content"]
    data_connector_version_id: UUID | None = None
    delivery_mode_code: Literal["inline", "reference", "download", "extracted"] = "inline"
    media_type: str | None = None
    locator: dict[str, Any] = {}
    nullable: bool = False
    ordinal: int = 1


class SourceBinding(BaseModel):
    source_binding_id: UUID
    executable_version_id: UUID
    name: str
    source_kind_code: str
    data_connector_version_id: UUID | None = None
    delivery_mode_code: str
    media_type: str | None = None
    locator: dict[str, Any] = {}
    nullable: bool
    ordinal: int


class CreateTargetBinding(BaseModel):
    name: str
    target_kind_code: Literal["storage_object", "task_output", "structured"]
    data_connector_version_id: UUID | None = None
    delivery_mode_code: str = "write_file"
    write_mode_code: Literal["create", "overwrite", "create_or_version"] | None = None
    target_payload_field: str | None = None
    media_type: str | None = None
    locator: dict[str, Any] = {}
    ordinal: int = 1


class TargetBinding(BaseModel):
    target_binding_id: UUID
    executable_version_id: UUID
    name: str
    target_kind_code: str
    data_connector_version_id: UUID | None = None
    delivery_mode_code: str
    write_mode_code: str | None = None
    target_payload_field: str | None = None
    locator: dict[str, Any] = {}
    ordinal: int


# ── Model Catalog ─────────────────────────────────────────────────────────────

class CreateModel(BaseModel):
    model_code: str
    provider: str
    modality: str = "chat"


class ModelPrice(BaseModel):
    model_price_id: UUID
    input_price_per_1k: float
    output_price_per_1k: float
    currency_code: str
    valid_from: str
    valid_to: str


class ModelSummary(BaseModel):
    model_id: UUID
    model_code: str
    provider: str
    modality: str
    model_status_code: str
    context_window: int | None = None
    current_price: ModelPrice | None = None


class CreateModelPrice(BaseModel):
    input_price_per_1k: float
    output_price_per_1k: float
    currency_code: str = "usd"


class CreateModelReference(BaseModel):
    reference_code: str
    name: str
    description: str | None = None


class ModelReferenceSummary(BaseModel):
    model_reference_id: UUID
    reference_code: str
    name: str
    current_model_code: str | None = None


class CreateModelReferenceBinding(BaseModel):
    model_id: UUID
    reason: str | None = None


class ModelReferenceBinding(BaseModel):
    model_reference_binding_id: UUID
    model_reference_id: UUID
    model_id: UUID
    model_code: str
    valid_from: str
    valid_to: str
    reason: str | None = None


# ── Prompt/Tool version detail (with content) ─────────────────────────────────

class PromptVersionDetail(BaseModel):
    prompt_version_id: UUID
    prompt_id: UUID
    semver: str
    content_hash: str
    blocks: list[PromptBlock]
    compiled: str = Field(description="Pre-compiled template string with {var} placeholders. Computed in the service layer; never stored in the database.")


class ToolVersionDetail(BaseModel):
    tool_version_id: UUID
    tool_id: UUID
    tool_name: str
    transport_code: str
    description: str | None = None
    semver: str
    input_schema: dict[str, Any] | None = None
    data_classification_code: str | None = None


# ── Sub-agent Delegations ─────────────────────────────────────────────────────

class DelegationSummary(BaseModel):
    delegation_id: UUID
    parent_version_id: UUID
    child_executable_id: UUID | None = None
    child_name: str | None = None
    child_kind: str | None = None
    child_version_id: UUID | None = None
    scope: dict[str, Any] = {}
    rationale: str | None = None
    notes: str | None = None
    created_at: str


class CreateDelegation(BaseModel):
    child_executable_id: UUID | None = None
    child_version_id: UUID | None = None
    scope: dict[str, Any] = {}
    rationale: str | None = None
    notes: str | None = None

    @model_validator(mode="after")
    def check_child_exclusive(self) -> "CreateDelegation":
        set_count = sum([self.child_executable_id is not None, self.child_version_id is not None])
        if set_count != 1:
            raise ValueError("Exactly one of child_executable_id or child_version_id must be set")
        return self


# ── Where-Used ────────────────────────────────────────────────────────────────

class UsedByEntry(BaseModel):
    executable_id: UUID
    executable_name: str
    kind_code: str
    executable_version_id: UUID
    semver: str


# ── YAML Import/Export ────────────────────────────────────────────────────────

class ImportReportEntry(BaseModel):
    entity_type: str
    name: str
    action: Literal["created", "updated", "no_op", "error"]


class ImportReportError(BaseModel):
    entity_type: str
    name: str
    error: str


class ImportReport(BaseModel):
    created: int = 0
    updated: int = 0
    no_op: int = 0
    errors: list[ImportReportError] = []
    entries: list[ImportReportEntry] = []

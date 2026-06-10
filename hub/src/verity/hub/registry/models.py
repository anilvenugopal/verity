"""Boundary models for the minimal registry primitive + intake↔asset linking (003 US2)."""
from __future__ import annotations

from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


class CreateExecutable(BaseModel):
    name: str = Field(min_length=1)
    kind_code: Literal["agent", "task"]


class Executable(BaseModel):
    executable_id: UUID
    kind_code: str
    name: str
    version_count: int = 0


class ExecutableVersion(BaseModel):
    executable_version_id: UUID
    executable_id: UUID
    semver: str | None = None
    lifecycle_stage: str | None = None


class LifecycleAdvance(BaseModel):
    to_stage: Literal["candidate", "staging", "challenger", "champion", "deprecated"]


class LinkInput(BaseModel):
    executable_id: UUID
    intake_requirement_id: UUID | None = None


class IntakeAssetLink(BaseModel):
    intake_entity_link_id: UUID
    executable_id: UUID
    name: str
    kind_code: str
    top_stage: str | None = None

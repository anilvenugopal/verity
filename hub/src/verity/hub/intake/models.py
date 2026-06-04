"""Pydantic v2 boundary models for the intake slice.

Field names mirror the canonical schema columns verbatim (naming gate). `*Create` models are the
request bodies (no attribution — that is server-resolved from the AuthContext, never the client,
per D6 / FR-018); the read models mirror the `RETURNING` column sets.
"""
from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, model_validator


class ApplicationCreate(BaseModel):
    name: str = Field(min_length=1)
    description: str | None = None


class Application(BaseModel):
    application_id: UUID
    name: str
    description: str | None = None
    created_at: datetime


class IntakeCreate(BaseModel):
    title: str = Field(min_length=1)
    description: str | None = None


class IntakeClassify(BaseModel):
    """Set/refresh classification (US2). Any subset of the three codes; codes are validated
    against their reference vocabularies by FK at write time (D-INT-7), not duplicated here."""

    ai_risk_tier_code: str | None = None
    naic_materiality_code: str | None = None
    materiality_tier_code: str | None = None

    @model_validator(mode="after")
    def _at_least_one(self) -> "IntakeClassify":
        if not (self.ai_risk_tier_code or self.naic_materiality_code or self.materiality_tier_code):
            raise ValueError("at least one classification code is required")
        return self


class RequirementCreate(BaseModel):
    requirement_kind_code: str = Field(min_length=1)
    title: str = Field(min_length=1)
    body: str = Field(min_length=1)


class Requirement(BaseModel):
    intake_requirement_id: UUID
    intake_id: UUID
    requirement_kind_code: str
    requirement_status_code: str
    title: str
    body: str
    created_at: datetime
    # embedding (vector(384)) is left null this slice (D-INT-6) and not exposed at the boundary.


class IntakeStatusChange(BaseModel):
    """Change an intake's status (US3). `to_status_code` is validated against
    reference.intake_status by FK; legal-transition gating is deferred (D-INT-2)."""

    to_status_code: str = Field(min_length=1)
    reason: str | None = None


class Intake(BaseModel):
    intake_id: UUID
    application_id: UUID
    title: str
    description: str | None = None
    intake_status_code: str
    ai_risk_tier_code: str | None = None
    naic_materiality_code: str | None = None
    materiality_tier_code: str | None = None
    created_at: datetime

"""Pydantic v2 boundary models for the intake slice.

Field names mirror the canonical schema columns verbatim (naming gate). `*Create` models are the
request bodies (no attribution — that is server-resolved from the AuthContext, never the client,
per D6 / FR-018); the read models mirror the `RETURNING` column sets.
"""
from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


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

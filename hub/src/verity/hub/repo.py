"""Thin repository helpers over raw SQL (ADR-0012).

These kill the repetitive 70% (building INSERT column lists from Pydantic models, mapping rows
back) without becoming an ORM: no identity map, no lazy loading, no query generation beyond
trivial column interpolation. Hand-written SQL in db/queries/*.sql remains the norm for reads
and anything non-trivial.
"""
from __future__ import annotations

from typing import Any

from pydantic import BaseModel


def build_insert(table: str, model: BaseModel, *, returning: str = "*") -> tuple[str, dict[str, Any]]:
    """Build a parameterised INSERT from a Pydantic model's set (non-None) fields.

    Column names come from the model fields, so they are reviewable and match the schema;
    values are bound as named params (never string-formatted).
    """
    data = model.model_dump(exclude_none=True)
    if not data:
        raise ValueError("nothing to insert")
    cols = ", ".join(data)
    placeholders = ", ".join(f"%({c})s" for c in data)
    return f"INSERT INTO {table} ({cols}) VALUES ({placeholders}) RETURNING {returning}", data


def row_to_model(model_cls: type[BaseModel], row: dict[str, Any] | None) -> BaseModel | None:
    return model_cls(**row) if row else None

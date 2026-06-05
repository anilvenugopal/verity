"""Application onboarding (Slice 2): governed propose → AI-Governance approval → active.

Captures identity (TLA), ownership, and the compliance perimeter (FR-IN-015…018); supersedes the
thin Slice-1 instant create. Raw SQL via aiosql, no ORM (ADR-0012); action-gated, fail-closed.
"""

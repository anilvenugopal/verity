"""Intake slice: application onboarding → intake → (classification, status, requirements).

Action-gated, fail-closed routes (user-authentication.md); every write records actor + acting
role server-side (D6). Raw SQL via aiosql, no ORM (ADR-0012).
"""

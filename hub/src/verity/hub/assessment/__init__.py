"""Intake assessment (Slice 3): the four-tab questionnaire (capture + inherent tier + ceiling).

Stored as versioned jsonb on core.intake_impact_assessment (SCD-2). Computes the intake's inherent
risk tier (US2) and enforces the app data-classification ceiling (US3). Obligation resolution +
access records + mitigations are deferred (unseeded compliance metamodel). Raw SQL, no ORM.
"""

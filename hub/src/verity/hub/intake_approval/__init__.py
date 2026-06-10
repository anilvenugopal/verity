"""Intake approval (Slice 4): submit an assessed intake → the FR-IN-005 tier quorum → approved.

Reuses the Slice-2 approval primitive (approval_request/approval_signoff) for the request + sign-offs,
the Slice-3 computed tier for the quorum, and the Slice-1 audited change_status to approve the intake.
"""

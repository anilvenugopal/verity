"""The minimal, reusable approval primitive (open request → sign-offs → resolve).

Generic over kind/target (core.approval_request + core.approval_signoff); per-kind quorum and
resolution side effects live in the calling slice. First user: application onboarding (US2).
"""

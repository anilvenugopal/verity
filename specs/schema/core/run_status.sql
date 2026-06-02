-- core.run_status  ·  subject: runs  ·  (enum)

-- 07-runs.sql — Verity v2 hardened schema · RUN/EXECUTION STATE, DISPATCH, QUOTAS
-- Event-sourced run state (runtime schema), the NATS transactional outbox, and
-- per-D-clarify configurable quotas. Re-applied per D1 (run_* native enums),
-- D3 (runtime state = core-tier; runtime schema), D4 (event-sourced + current view),
-- D6 (actor attribution), and the A/B run-mode clarification.

-- runtime schema for execution state (Tier-1 transactional, read live)
CREATE TYPE core.run_status            AS ENUM ('submitted', 'claimed', 'heartbeat', 'released');

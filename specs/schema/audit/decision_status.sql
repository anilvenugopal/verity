-- audit.decision_status  ·  subject: decisions  ·  (enum)

-- 06-decisions.sql — Verity v2 hardened schema · DECISION/INVOCATION LOGS,
-- the AUDIT (Tier-2) fact stream, evidence, the shared status_transition log,
-- and core MODEL + price. Re-applied per D1 (hot-path enums kept native),
-- D3 (Tier-2 -> audit schema), D4 (append-only + shared transition log),
-- D6 (actor attribution incl. automation actors), ADR-0004/0007/0008.
--
-- Tier-2 audit tables are append-only, RANGE-partitioned by month (BRIN on time),
-- and are NOT FK targets — they carry SOFT uuid references to core (validated at the
-- API layer). Two partitions are shown (2026_06/2026_07); a partition-management job
-- (pg_partman or a CronJob) creates future months ahead of time.
CREATE TYPE audit.decision_status   AS ENUM ('complete', 'error', 'partial');

-- audit.harness_heartbeat  ·  subject: deploy  ·  (table)

CREATE TABLE audit.harness_heartbeat (
    harness_heartbeat_id  uuid       NOT NULL DEFAULT uuidv7(),
    harness_instance_id   uuid       NOT NULL,                  -- soft ref -> core.harness_instance
    heartbeat_kind_code   text       NOT NULL,                  -- minor | major
    health_status_code    text       NOT NULL,                  -- healthy | degraded | down | unknown
    running_image_digest  text,                                  -- what version it is actually running
    running_packages      jsonb,                                 -- major: catalog of loaded packages (drift detection)
    metrics               jsonb,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_harness_heartbeat PRIMARY KEY (harness_heartbeat_id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE audit.harness_heartbeat IS
'The Tier-2, partitioned stream of agent->portal heartbeats. Minor heartbeats are frequent and light (liveness plus the coordinator lease refresh); major heartbeats are periodic and carry the running-package catalog used for deployment drift detection. Only the coordinator emits them, one per cluster, which is what keeps the volume bounded at fleet scale (D8, ADR-0010).

@tier 2
@lifecycle append-only
@subject deploy
@partitioned RANGE(created_at)
@status reference.heartbeat_kind
@status reference.health_status
@decision D8
@adr 0010';
CREATE INDEX ix_harness_heartbeat_instance_time ON audit.harness_heartbeat (harness_instance_id, created_at DESC);
CREATE TABLE audit.harness_heartbeat_2026_06 PARTITION OF audit.harness_heartbeat FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.harness_heartbeat_2026_07 PARTITION OF audit.harness_heartbeat FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
COMMENT ON COLUMN audit.harness_heartbeat.harness_heartbeat_id IS
'Identity of the heartbeat (with created_at, the partition key).';
COMMENT ON COLUMN audit.harness_heartbeat.harness_instance_id IS
'The instance/coordinator that sent it; soft ref because Tier-2 is not an FK target. @ref core.harness_instance soft';
COMMENT ON COLUMN audit.harness_heartbeat.heartbeat_kind_code IS
'minor (liveness + lease refresh) or major (adds the running-package catalog). @status reference.heartbeat_kind';
COMMENT ON COLUMN audit.harness_heartbeat.health_status_code IS
'Reported health — healthy/degraded/down/unknown. @status reference.health_status';
COMMENT ON COLUMN audit.harness_heartbeat.running_image_digest IS
'The harness image the instance is actually running; compared to desired for image drift.';
COMMENT ON COLUMN audit.harness_heartbeat.running_packages IS
'Major-heartbeat catalog of loaded packages (name/version/digest), compared to core.deployment for package drift.';
COMMENT ON COLUMN audit.harness_heartbeat.metrics IS
'Lightweight runtime metrics on the heartbeat — queue depth, worker and run counts.';
COMMENT ON COLUMN audit.harness_heartbeat.created_at IS
'When the heartbeat was received; the partition key and the ordering for "latest". @actor coordinator';

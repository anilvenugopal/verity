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
COMMENT ON TABLE audit.harness_heartbeat IS 'tier:2 append-only (partitioned). Agent->portal heartbeats: minor (frequent/light) + major (running-package catalog -> drift detection). D8.';
CREATE INDEX ix_harness_heartbeat_instance_time ON audit.harness_heartbeat (harness_instance_id, created_at DESC);
CREATE TABLE audit.harness_heartbeat_2026_06 PARTITION OF audit.harness_heartbeat FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.harness_heartbeat_2026_07 PARTITION OF audit.harness_heartbeat FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');

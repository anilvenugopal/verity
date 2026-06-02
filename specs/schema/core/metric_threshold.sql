-- core.metric_threshold  ·  subject: validation  ·  (table)

CREATE TABLE core.metric_threshold (
    metric_threshold_id uuid NOT NULL DEFAULT uuidv7(), executable_version_id uuid,
    metric_type_code text NOT NULL, threshold numeric(8,4) NOT NULL, comparator text NOT NULL DEFAULT '>=',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_metric_threshold PRIMARY KEY (metric_threshold_id),
    CONSTRAINT fk_metric_threshold_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_metric_threshold_metric FOREIGN KEY (metric_type_code) REFERENCES reference.metric_type (code));

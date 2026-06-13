-- core.metric_threshold  ·  subject: validation  ·  (table)

CREATE TABLE core.metric_threshold (
    metric_threshold_id uuid NOT NULL DEFAULT uuidv7(), executable_version_id uuid,
    metric_type_code text NOT NULL, threshold numeric(8,4) NOT NULL, comparator text NOT NULL DEFAULT '>=',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_metric_threshold PRIMARY KEY (metric_threshold_id),
    CONSTRAINT fk_metric_threshold_version FOREIGN KEY (executable_version_id) REFERENCES core.executable_version (executable_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_metric_threshold_metric FOREIGN KEY (metric_type_code) REFERENCES reference.metric_type (code));
COMMENT ON TABLE core.metric_threshold IS
'A pass/fail threshold for a metric on an executable_version (or a global default when version is null): the comparator and value a metric must satisfy. Used to gate promotion on validation results (C9).

@tier 1
@lifecycle mutable
@subject validation
@status reference.metric_type';
COMMENT ON COLUMN core.metric_threshold.metric_threshold_id IS
'Identity of the threshold.';
COMMENT ON COLUMN core.metric_threshold.executable_version_id IS
'The version the threshold applies to; null = a global default. @ref core.executable_version hard';
COMMENT ON COLUMN core.metric_threshold.metric_type_code IS
'The metric this gates. @status reference.metric_type';
COMMENT ON COLUMN core.metric_threshold.threshold IS
'The threshold value.';
COMMENT ON COLUMN core.metric_threshold.comparator IS
'Comparison operator, e.g. >=.';
COMMENT ON COLUMN core.metric_threshold.created_at IS
'When set.';

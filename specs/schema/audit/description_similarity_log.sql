-- audit.description_similarity_log  ·  subject: validation  ·  (table)

CREATE TABLE audit.description_similarity_log (
    description_similarity_log_id uuid NOT NULL DEFAULT uuidv7(),
    subject_kind text NOT NULL, subject_id uuid NOT NULL,   -- soft polymorphic
    similar_to_id uuid NOT NULL, similarity numeric(6,5) NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_description_similarity_log PRIMARY KEY (description_similarity_log_id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE audit.description_similarity_log IS 'tier:2 append-only (partitioned). pgvector similarity hits (dedup/recommendation). C9.';
CREATE TABLE audit.description_similarity_log_2026_06 PARTITION OF audit.description_similarity_log FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.description_similarity_log_2026_07 PARTITION OF audit.description_similarity_log FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');

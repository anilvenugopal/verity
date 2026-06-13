-- audit.description_similarity_log  ·  subject: validation  ·  (table)

CREATE TABLE audit.description_similarity_log (
    description_similarity_log_id uuid NOT NULL DEFAULT uuidv7(),
    subject_kind text NOT NULL, subject_id uuid NOT NULL,   -- soft polymorphic
    similar_to_id uuid NOT NULL, similarity numeric(6,5) NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_description_similarity_log PRIMARY KEY (description_similarity_log_id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE audit.description_similarity_log IS
'Append-only log of pgvector similarity hits used for de-duplication and recommendation (e.g. near-duplicate requirements or entities). Tier-2, partitioned; subject_kind/subject_id are soft polymorphic refs (C9).

@tier 2
@lifecycle append-only
@subject validation
@partitioned RANGE(created_at)';
CREATE TABLE audit.description_similarity_log_2026_06 PARTITION OF audit.description_similarity_log FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit.description_similarity_log_2026_07 PARTITION OF audit.description_similarity_log FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
COMMENT ON COLUMN audit.description_similarity_log.description_similarity_log_id IS
'Identity of the hit (with created_at, the partition key).';
COMMENT ON COLUMN audit.description_similarity_log.subject_kind IS
'What kind of thing was compared (soft polymorphic with subject_id).';
COMMENT ON COLUMN audit.description_similarity_log.subject_id IS
'The thing compared; soft ref interpreted by subject_kind.';
COMMENT ON COLUMN audit.description_similarity_log.similar_to_id IS
'The thing it was found similar to.';
COMMENT ON COLUMN audit.description_similarity_log.similarity IS
'Cosine similarity score.';
COMMENT ON COLUMN audit.description_similarity_log.created_at IS
'When recorded; the partition key.';

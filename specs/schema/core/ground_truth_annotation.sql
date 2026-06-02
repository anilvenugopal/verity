-- core.ground_truth_annotation  ·  subject: validation  ·  (table)

CREATE TABLE core.ground_truth_annotation (
    ground_truth_annotation_id uuid NOT NULL DEFAULT uuidv7(), ground_truth_record_id uuid NOT NULL,
    gt_annotator_type_code text NOT NULL, annotator_actor_id uuid, annotation jsonb NOT NULL,
    is_authoritative boolean NOT NULL DEFAULT false, created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_ground_truth_annotation PRIMARY KEY (ground_truth_annotation_id),
    CONSTRAINT fk_gta_record FOREIGN KEY (ground_truth_record_id) REFERENCES core.ground_truth_record (ground_truth_record_id) ON DELETE CASCADE,
    CONSTRAINT fk_gta_annotator_type FOREIGN KEY (gt_annotator_type_code) REFERENCES reference.gt_annotator_type (code),
    CONSTRAINT fk_gta_annotator_actor FOREIGN KEY (annotator_actor_id) REFERENCES core.actor (actor_id));
CREATE UNIQUE INDEX uq_gt_annotation_authoritative ON core.ground_truth_annotation (ground_truth_record_id) WHERE is_authoritative;

-- core.ground_truth_dataset  ·  subject: validation  ·  (table)

CREATE TABLE core.ground_truth_dataset (
    ground_truth_dataset_id uuid NOT NULL DEFAULT uuidv7(), name text NOT NULL, description text,
    gt_dataset_status_code text NOT NULL DEFAULT 'collecting', gt_quality_tier_code text NOT NULL DEFAULT 'silver',
    gt_source_type_code text NOT NULL, labeling_guide text, iaa_score numeric(5,4),
    superseded_by_dataset_id uuid, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    created_by_actor_id uuid NOT NULL, created_role_code text NOT NULL,
    CONSTRAINT pk_ground_truth_dataset PRIMARY KEY (ground_truth_dataset_id),
    CONSTRAINT fk_gtd_status FOREIGN KEY (gt_dataset_status_code) REFERENCES reference.gt_dataset_status (code),
    CONSTRAINT fk_gtd_quality FOREIGN KEY (gt_quality_tier_code) REFERENCES reference.gt_quality_tier (code),
    CONSTRAINT fk_gtd_source FOREIGN KEY (gt_source_type_code) REFERENCES reference.gt_source_type (code),
    CONSTRAINT fk_gtd_superseded FOREIGN KEY (superseded_by_dataset_id) REFERENCES core.ground_truth_dataset (ground_truth_dataset_id) ON DELETE SET NULL,
    CONSTRAINT fk_gtd_created_by FOREIGN KEY (created_by_actor_id) REFERENCES core.actor (actor_id),
    CONSTRAINT fk_gtd_created_role FOREIGN KEY (created_role_code) REFERENCES reference.role (code));
COMMENT ON TABLE core.ground_truth_dataset IS 'tier:1. A ground-truth dataset; status mutable (D4). C9.';

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
COMMENT ON TABLE core.ground_truth_dataset IS
'A ground-truth dataset used to validate executables: a labeled set with a quality tier (bronze/silver/gold), a source type, a labeling guide, and an inter-annotator agreement score. status is mutable; a superseded dataset points at its replacement (C9, D4).

@tier 1
@lifecycle mutable
@subject validation
@status reference.gt_dataset_status
@status reference.gt_quality_tier
@status reference.gt_source_type
@decision D4';
COMMENT ON COLUMN core.ground_truth_dataset.ground_truth_dataset_id IS
'Identity of the dataset.';
COMMENT ON COLUMN core.ground_truth_dataset.name IS
'Dataset name.';
COMMENT ON COLUMN core.ground_truth_dataset.description IS
'What it covers.';
COMMENT ON COLUMN core.ground_truth_dataset.gt_dataset_status_code IS
'Mutable collection/curation status. @status reference.gt_dataset_status';
COMMENT ON COLUMN core.ground_truth_dataset.gt_quality_tier_code IS
'Quality tier — bronze/silver/gold. @status reference.gt_quality_tier';
COMMENT ON COLUMN core.ground_truth_dataset.gt_source_type_code IS
'Where the labels came from. @status reference.gt_source_type';
COMMENT ON COLUMN core.ground_truth_dataset.labeling_guide IS
'Guidance given to annotators.';
COMMENT ON COLUMN core.ground_truth_dataset.iaa_score IS
'Inter-annotator agreement score.';
COMMENT ON COLUMN core.ground_truth_dataset.superseded_by_dataset_id IS
'The dataset that replaces this one, if any; set null if that is purged. @ref core.ground_truth_dataset hard';
COMMENT ON COLUMN core.ground_truth_dataset.created_at IS
'When created.';
COMMENT ON COLUMN core.ground_truth_dataset.updated_at IS
'When last updated.';
COMMENT ON COLUMN core.ground_truth_dataset.created_by_actor_id IS
'Who created it. @ref core.actor hard';
COMMENT ON COLUMN core.ground_truth_dataset.created_role_code IS
'The capacity they acted in. @status reference.role';

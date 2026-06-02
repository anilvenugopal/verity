-- core.package_harness_compatibility  ·  subject: deploy  ·  (table)

CREATE TABLE core.package_harness_compatibility (
    package_id            uuid       NOT NULL,
    variant_code          text       NOT NULL,                  -- compatible harness variant
    min_harness_version   text,                                  -- declared loosely; deploy resolves+pins a digest
    max_harness_version   text,
    CONSTRAINT pk_package_harness_compatibility PRIMARY KEY (package_id, variant_code),
    CONSTRAINT fk_phc_package FOREIGN KEY (package_id) REFERENCES core.package (package_id) ON DELETE CASCADE,
    CONSTRAINT fk_phc_variant FOREIGN KEY (variant_code) REFERENCES reference.harness_variant (code));
COMMENT ON TABLE core.package_harness_compatibility IS 'tier:1. Package <-> harness variant + version range it can run on. Declared loosely; the deploy gate resolves & pins an exact image_digest. D8/ADR-0006.';

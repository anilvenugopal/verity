-- core.package_harness_compatibility  ·  subject: deploy  ·  (table)

CREATE TABLE core.package_harness_compatibility (
    package_id            uuid       NOT NULL,
    variant_code          text       NOT NULL,                  -- compatible harness variant
    min_harness_version   text,                                  -- declared loosely; deploy resolves+pins a digest
    max_harness_version   text,
    CONSTRAINT pk_package_harness_compatibility PRIMARY KEY (package_id, variant_code),
    CONSTRAINT fk_phc_package FOREIGN KEY (package_id) REFERENCES core.package (package_id) ON DELETE CASCADE,
    CONSTRAINT fk_phc_variant FOREIGN KEY (variant_code) REFERENCES reference.harness_variant (code));
COMMENT ON TABLE core.package_harness_compatibility IS
'Declares which harness variant and version range a package can run on. The declaration is loose (a range); the deploy gate is what resolves and pins one exact image_digest, so an incompatible package-on-image combination can never be deployed (ADR-0006).

@tier 1
@lifecycle mutable
@subject deploy
@status reference.harness_variant
@decision D8
@adr 0006';
COMMENT ON COLUMN core.package_harness_compatibility.package_id IS
'The package whose compatibility this declares. @ref core.package hard';
COMMENT ON COLUMN core.package_harness_compatibility.variant_code IS
'A harness variant the package can run on. @status reference.harness_variant';
COMMENT ON COLUMN core.package_harness_compatibility.min_harness_version IS
'Lower bound of the compatible version range; the deploy gate resolves it to a concrete pinned digest.';
COMMENT ON COLUMN core.package_harness_compatibility.max_harness_version IS
'Upper bound of the compatible version range, or open if unset.';

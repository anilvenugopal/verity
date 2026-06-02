-- core.regulatory_framework  ·  subject: compliance  ·  (table)

-- 05-compliance.sql — Verity v2 hardened schema · core COMPLIANCE (ADR-0008)
-- The three-axis, two-bridge control/evidence metamodel. Per D7: ALL evolving
-- axes are EFFECTIVE-DATED (SCD-2 versions; valid_from/valid_to) so any past
-- obligation/evidence resolves "as-of". evidence (the fact stream) is Tier-2 and
-- lives in the audit domain (06). Compliance FKs from intake are wired at the end.
--
-- SCD-2 pattern here: <table>_id uuid PK = one VERSION row; <thing>_code = the stable
-- logical key; valid_from/valid_to (NULL = current). A partial unique on the code WHERE
-- valid_to IS NULL guarantees one current version. FKs reference the version surrogate,
-- which PINS the as-of version (reproducibility, ADR-0009).

-- Framework identity is stable (one row + window); its PROVISIONS amend (SCD-2).
CREATE TABLE core.regulatory_framework (
    framework_code       text        NOT NULL,
    name                 text        NOT NULL,
    authority            text,                                  -- issuing body
    effective_start_date date        NOT NULL DEFAULT current_date,
    effective_end_date   date,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_regulatory_framework PRIMARY KEY (framework_code),
    CONSTRAINT ck_regulatory_framework_window CHECK (effective_end_date IS NULL OR effective_end_date >= effective_start_date));
COMMENT ON TABLE core.regulatory_framework IS 'tier:1. Left axis: a regulatory framework (NAIC, EU AI Act, SR 11-7…). Stable identity + validity window. ADR-0008.';

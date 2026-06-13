-- core.regulatory_framework  ·  subject: compliance  ·  (table)

-- 05-compliance.sql — Verity v2 hardened schema · core COMPLIANCE (ADR-0008)
-- The three-axis, two-bridge control/evidence metamodel. Per D7: ALL evolving
-- axes are EFFECTIVE-DATED (SCD-2 versions; valid_from/valid_to) so any past
-- obligation/evidence resolves "as-of". evidence (the fact stream) is Tier-2 and
-- lives in the audit domain (06). Compliance FKs from intake are wired at the end.
--
-- SCD-2 pattern here: <table>_id uuid PK = one VERSION row; <thing>_code = the stable
-- logical key; valid_from/valid_to (NULL = current). A partial unique on the code WHERE
-- valid_to = '2099-12-31 00:00:00+00' guarantees one current version. FKs reference the version surrogate,
-- which PINS the as-of version (reproducibility, ADR-0009).

-- Framework identity is stable (one row + window); its PROVISIONS amend (SCD-2).
CREATE TABLE core.regulatory_framework (
    framework_code       text        NOT NULL,
    name                 text        NOT NULL,
    authority            text,                                  -- issuing body
    effective_start_date date        NOT NULL DEFAULT current_date,
    effective_end_date   date NOT NULL DEFAULT '2099-12-31',
    created_at           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_regulatory_framework PRIMARY KEY (framework_code),
    CONSTRAINT ck_regulatory_framework_window CHECK (effective_end_date >= effective_start_date));
COMMENT ON TABLE core.regulatory_framework IS
'Left axis of the compliance metamodel (ADR-0008): a regulatory framework such as NAIC, the EU AI Act, or SR 11-7. The framework has a stable identity (framework_code) and a validity window; it is the framework''s PROVISIONS that amend over time (SCD-2).

@tier 1
@lifecycle mutable
@subject compliance
@adr 0008';
COMMENT ON COLUMN core.regulatory_framework.framework_code IS
'Stable logical key and primary key of the framework.';
COMMENT ON COLUMN core.regulatory_framework.name IS
'Framework name.';
COMMENT ON COLUMN core.regulatory_framework.authority IS
'Issuing body.';
COMMENT ON COLUMN core.regulatory_framework.effective_start_date IS
'Start of the frameworks validity window.';
COMMENT ON COLUMN core.regulatory_framework.effective_end_date IS
'End of the window; the open end (2099-12-31) means current.';
COMMENT ON COLUMN core.regulatory_framework.created_at IS
'When registered.';

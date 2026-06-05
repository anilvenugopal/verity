-- reference.application_status  ·  subject: intake  ·  (table)

-- application_status: the onboarded application's lifecycle (pending<active; suspended/retired).
-- pending = proposed, awaiting AI-Governance (+ business-owner) approval; active = approved and
-- may own promotable intakes/assets; suspended = temporary hold; retired = terminal.
CREATE TABLE reference.application_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_application_status PRIMARY KEY (code), CONSTRAINT uq_application_status_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.application_status IS
'Lifecycle state of an onboarded application: pending (proposed, awaiting approval) -> active (approved; may own promotable intakes/assets) ; suspended (temporary hold) ; retired (terminal). A non-active application MUST NOT own promotable intakes/assets (FR-IN-015).

@lifecycle reference
@subject intake';

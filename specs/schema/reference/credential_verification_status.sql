-- reference.credential_verification_status  ·  subject: deploy  ·  (table)

-- Result of the coordinator's test-connection for an app data-source credential
-- (core.harness_app_credential). Reported to the hub via the Harness Gateway API.
CREATE TABLE reference.credential_verification_status (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_credential_verification_status PRIMARY KEY (code), CONSTRAINT uq_credential_verification_status_sort UNIQUE (sort_order));
INSERT INTO reference.credential_verification_status (code, label, sort_order) VALUES
    ('unverified','Unverified',1),('verified','Verified',2),('failed','Failed',3),('expired','Expired',4);
COMMENT ON TABLE reference.credential_verification_status IS
'Result of the coordinator''s test-connection for an app data-source credential (unverified/verified/failed/expired).

@lifecycle reference
@subject deploy';

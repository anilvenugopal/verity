-- reference.quota_period  ·  subject: runs  ·  (table)

CREATE TABLE reference.quota_period (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_quota_period PRIMARY KEY (code), CONSTRAINT uq_quota_period_sort UNIQUE (sort_order));
INSERT INTO reference.quota_period (code, label, sort_order) VALUES ('daily','Daily',1),('weekly','Weekly',2),('monthly','Monthly',3);
COMMENT ON TABLE reference.quota_period IS
'The window a quota budget resets over (daily/weekly/monthly).

@lifecycle reference
@subject runs';

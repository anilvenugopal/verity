-- reference.currency  ·  subject: decisions  ·  (table)

CREATE TABLE reference.currency (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_currency PRIMARY KEY (code), CONSTRAINT uq_currency_sort UNIQUE (sort_order));
INSERT INTO reference.currency (code, label, sort_order) VALUES ('usd','US Dollar',1),('eur','Euro',2),('gbp','British Pound',3);

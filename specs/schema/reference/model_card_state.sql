-- reference.model_card_state  ·  subject: validation  ·  (table)

CREATE TABLE reference.model_card_state (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_model_card_state PRIMARY KEY (code), CONSTRAINT uq_model_card_state_sort UNIQUE (sort_order));
INSERT INTO reference.model_card_state (code,label,sort_order) VALUES ('draft',1),('in_review',2),('approved',3),('superseded',4);

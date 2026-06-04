-- reference.model_card_state  ·  subject: validation  ·  (table)

CREATE TABLE reference.model_card_state (code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL, grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date, effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT pk_model_card_state PRIMARY KEY (code), CONSTRAINT uq_model_card_state_sort UNIQUE (sort_order));
INSERT INTO reference.model_card_state (code,label,sort_order) VALUES ('draft','Draft',1),('in_review','In Review',2),('approved','Approved',3),('superseded','Superseded',4);
COMMENT ON TABLE reference.model_card_state IS
'Review state of a model card (draft/in_review/approved/superseded).

@lifecycle reference
@subject validation';

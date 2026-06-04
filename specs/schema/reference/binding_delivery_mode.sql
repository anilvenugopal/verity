-- reference.binding_delivery_mode  ·  subject: registry  ·  (table)

-- binding_delivery_mode: HOW a resolved source/target is delivered (the fix for base64-only).
CREATE TABLE reference.binding_delivery_mode (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date NOT NULL DEFAULT '2099-12-31', is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_binding_delivery_mode PRIMARY KEY (code), CONSTRAINT uq_binding_delivery_mode_sort UNIQUE (sort_order));

COMMENT ON TABLE reference.binding_delivery_mode IS
'How a resolved Source/Target binding payload is delivered (inline/reference/download/extracted/write_file) — the fix for v1 base64-only delivery.

@lifecycle reference
@subject registry';

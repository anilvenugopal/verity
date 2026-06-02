-- reference.binding_delivery_mode  ·  subject: registry  ·  (table)

-- binding_delivery_mode: HOW a resolved source/target is delivered (the fix for base64-only).
CREATE TABLE reference.binding_delivery_mode (
    code text NOT NULL, label text NOT NULL, description text, sort_order integer NOT NULL,
    grouping text, parent_code text, effective_start_date date NOT NULL DEFAULT current_date,
    effective_end_date date, is_active boolean NOT NULL DEFAULT true, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT pk_binding_delivery_mode PRIMARY KEY (code), CONSTRAINT uq_binding_delivery_mode_sort UNIQUE (sort_order));
INSERT INTO reference.binding_delivery_mode (code, label, sort_order, description) VALUES
    ('inline','Inline content',1,'base64/text content block (vision/small files)'),
    ('reference','By reference',2,'signed URL / object handle; tool streams it (large files)'),
    ('download','Download to workdir',3,'harness fetches the file to the run working dir'),
    ('extracted','Extracted to structured',4,'parse the file into structured fields'),
    ('write_file','Write file',5,'target: write the output as a file to the backend');

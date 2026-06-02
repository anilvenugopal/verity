-- reference.executable_kind  ·  subject: registry  ·  (table)

-- NOTE: app_team_role (per-application: app_demo_owner/sre/dev/lead/ops) is added
-- with the intake/application domain (it pairs with application-scoped grants).

-- REGISTRY-domain vocabularies (used by 02-registry.sql)
-- All follow the reference pattern; columns elided for brevity are the
-- standard set (description, grouping, parent_code, effective_*, is_active,
-- metadata, created_at/updated_at). Helper below keeps them consistent.

-- executable_kind carries two extra typed columns (packaging is gated by these; D5/D8)
CREATE TABLE reference.executable_kind (
    code                 text        NOT NULL,
    label                text        NOT NULL,
    description          text,
    sort_order           integer      NOT NULL,
    is_packaged          boolean      NOT NULL DEFAULT true,   -- does a champion of this kind produce a package?
    package_format       text,                                  -- e.g. 'vtx','vax' (NULL when not packaged)
    effective_start_date date        NOT NULL DEFAULT current_date,
    effective_end_date   date,
    is_active            boolean      NOT NULL DEFAULT true,
    metadata             jsonb        NOT NULL DEFAULT '{}'::jsonb,
    created_at           timestamptz  NOT NULL DEFAULT now(),
    updated_at           timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_executable_kind PRIMARY KEY (code),
    CONSTRAINT uq_executable_kind_sort UNIQUE (sort_order)
);
COMMENT ON TABLE reference.executable_kind IS 'Vocabulary: kinds of executable (agent, task, future). is_packaged/package_format decouple "governed" from "packaged" (D5/D8). New kind = new row, no schema change.';
INSERT INTO reference.executable_kind (code, label, sort_order, is_packaged, package_format) VALUES
    ('agent', 'Agent', 1, true, 'vax'),
    ('task',  'Task',  2, true, 'vtx');

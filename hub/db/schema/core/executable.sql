-- core.executable  ·  subject: registry  ·  (table)

-- 02-registry.sql — Verity v2 hardened schema · core REGISTRY
-- The entity/composition model (D5): the `executable` supertype, its
-- immutable versions, the reusable component tables, and Source/Target
-- bindings. Re-applied per D1-D6.

-- ┌───────────────────────────────────────────────────────────────────┐
-- │ THE `executable` SUPERTYPE — what it is and why (D5)                │
-- │                                                                     │
-- │ An "executable" is the GOVERNED, VERSIONED, PROMOTABLE unit that    │
-- │ the harness runs. Today there are two KINDS: `agent` and `task`.    │
-- │   • an AGENT  (kind='agent') = multi-step, may use tools + MCP      │
-- │   • a TASK    (kind='task')  = single LLM step, no tools/MCP        │
-- │ Both are *executables* — they are versioned, promoted draft→champion│
-- │ packaged, and deployed the SAME way. So lifecycle, champion,        │
-- │ bindings, packaging, and deployment all point at ONE thing:         │
-- │ `executable_version` — never at "agent OR task" separately.         │
-- │                                                                     │
-- │ WHY a supertype instead of two tables: it is EXTENSIBLE. A future   │
-- │ kind (say 'workflow') is added by INSERTing one row into            │
-- │ reference.executable_kind — no change to lifecycle/champion/deploy. │
-- │ The KIND is DATA (kind_code), not hardcoded structure.              │
-- │                                                                     │
-- │ WHAT is NOT an executable: prompts, tools, data connectors, MCP     │
-- │ servers. Those are reusable COMPONENTS used *inside* an executable  │
-- │ version (see assignments below). They are versioned (for exact      │
-- │ historic reproduction) but have NO lifecycle/champion of their own. │
-- │                                                                     │
-- │ Example: agent "underwriting-assistant" (executable, kind=agent)    │
-- │   ├─ executable_version 1.2.0  ── champion                          │
-- │   │     ├─ uses prompt_version "uw-system-prompt" 3.1 (role=system) │
-- │   │     ├─ uses tool_version "calc-ltv" 1.0      (agent-only)       │
-- │   │     ├─ Source Binding: latest filing PDF from the vault         │
-- │   │     └─ Target Binding: write the rated opinion (structured)     │
-- │   └─ packaged as .vax, deployed to prod (separate, see 08-…)        │
-- └───────────────────────────────────────────────────────────────────┘
CREATE TABLE core.executable (
    executable_id       uuid        NOT NULL DEFAULT uuidv7(),
    kind_code           text        NOT NULL,                 -- agent | task | (future) -> reference.executable_kind
    name                text        NOT NULL,
    display_name        text,
    description         text,
    application_id      uuid,
    created_at          timestamptz  NOT NULL DEFAULT now(),
    updated_at          timestamptz  NOT NULL DEFAULT now(),
    created_by_actor_id uuid        NOT NULL,
    created_role_code   text        NOT NULL,                 -- acting capacity (D6)
    CONSTRAINT pk_executable PRIMARY KEY (executable_id),
    CONSTRAINT fk_executable_kind FOREIGN KEY (kind_code)
        REFERENCES reference.executable_kind (code) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_created_by FOREIGN KEY (created_by_actor_id)
        REFERENCES core.actor (actor_id) ON DELETE RESTRICT,
    CONSTRAINT fk_executable_created_role FOREIGN KEY (created_role_code)
        REFERENCES reference.role (code) ON DELETE RESTRICT,
    CONSTRAINT uq_executable_kind_name UNIQUE (kind_code, name),
    -- composite unique so child tables can pin the kind via FK (agent-only enforcement)
    CONSTRAINT uq_executable_id_kind UNIQUE (executable_id, kind_code),
    CONSTRAINT ck_executable_name_not_blank CHECK (length(btrim(name)) > 0)
);
CREATE UNIQUE INDEX uq_executable_app_kind_display ON core.executable (application_id, kind_code, display_name) WHERE application_id IS NOT NULL;
COMMENT ON TABLE core.executable IS
'The supertype for everything the harness governs and runs: the versioned, promotable unit. Today two kinds — agent (multi-step, may use tools/MCP) and task (single LLM step) — but the kind is data (reference.executable_kind), so a new kind is added by inserting a reference row, not by changing lifecycle, champion, or deploy. Prompts, tools, connectors and MCP servers are NOT executables; they are reusable components used inside a version (D5).

@tier 1
@lifecycle mutable
@subject registry
@status reference.executable_kind
@decision D5';
COMMENT ON COLUMN core.executable.executable_id IS
'Identity of the governed unit; lifecycle, champion, packaging and deployment all resolve through its versions.';
COMMENT ON COLUMN core.executable.kind_code IS
'agent or task (or a future kind) — the discriminator, kept as data so new kinds need no structural change. @status reference.executable_kind';
COMMENT ON COLUMN core.executable.name IS
'Technical name; unique within a kind.';
COMMENT ON COLUMN core.executable.display_name IS
'Human-readable label shown in the UI.';
COMMENT ON COLUMN core.executable.application_id IS
'Owning application. @ref core.application hard';
COMMENT ON COLUMN core.executable.description IS
'Free-text description of the executable.';
COMMENT ON COLUMN core.executable.created_at IS
'When the executable was created.';
COMMENT ON COLUMN core.executable.updated_at IS
'When it was last updated.';
COMMENT ON COLUMN core.executable.created_by_actor_id IS
'Who created it. @ref core.actor hard';
COMMENT ON COLUMN core.executable.created_role_code IS
'The capacity they acted in (D6). @status reference.role';

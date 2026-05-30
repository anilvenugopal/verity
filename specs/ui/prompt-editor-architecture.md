# Prompt Editor — Architecture Document

## What this is

A structured rich-text editor for AI prompt templates. Prompts are composed as a sequence of typed blocks — prose, variables, lists, tables, and code — rather than raw text. Each block carries metadata. The document is versioned, and blame (who last changed each block and why) is derived from version history, exactly like `git blame`.

---

## Block types

Every document is an ordered array of block objects. Each block has an `id`, a `kind`, and kind-specific fields.

| kind | Purpose | Key fields |
|---|---|---|
| `prose` | Plain instructional text | `text: string` |
| `var` | A named placeholder filled at runtime | `name`, `type`, `desc`, `eg`, `opts`, `req` |
| `list` | Numbered list of items | `items: string[]` |
| `table` | Reference table | `headers: string[]`, `rows: string[][]`, `caption?` |
| `code` | Syntax-highlighted code example | `lang`, `code: string`, `caption?` |

Variable types: `string | number | code | enum | boolean`

Supported code languages: `typescript`, `javascript`, `python`, `sql`, `bash`, `json`, `go`, `rust`, `yaml`, `text`

---

## Compiled output

When the author clicks "compile", the document renders to a flat string for use as an LLM system prompt or few-shot template:

- `prose` → plain text
- `var` → `{variable_name}` placeholder
- `list` → numbered lines (`1. item\n2. item`)
- `table` → GitHub-flavoured markdown table with optional caption line
- `code` → fenced code block (` ```lang\n...\n``` `)

Blocks are joined with `\n\n` to preserve paragraph structure. Newlines within blocks (code, list, table) are preserved exactly.

---

## Blame model

Blame is **not stored** in the document. It is computed by diffing adjacent versions — identical to `git blame`.

Each block has a `content_hash` (SHA-256 of its JSON). When a new version is saved, the system walks backwards through version history for each block. The version where the block's `content_hash` last changed is the blame version for that block. The author, commit message, and timestamp of that version surface in the UI.

This means:
- A block untouched for 10 versions blames the original author
- A block edited in version 7 blames version 7's author, regardless of later saves
- Renaming a variable (changing `name`) creates a new hash — blame resets
- Reordering blocks without editing their content does not change their blame

---

## Database schema

### Core tables

```sql
-- One row per named template
CREATE TABLE prompt_templates (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id             uuid NOT NULL REFERENCES orgs(id),
  name               text NOT NULL,
  description        text,
  current_version_id uuid,          -- FK updated after each save
  created_by         uuid NOT NULL REFERENCES users(id),
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

-- One row per save — the full document is stored as JSONB
-- Never mutated. Append-only.
CREATE TABLE prompt_template_versions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id     uuid NOT NULL REFERENCES prompt_templates(id),
  version_number  integer NOT NULL,
  document        jsonb NOT NULL,         -- full block array
  commit_msg      text NOT NULL,          -- required on every save
  authored_by     uuid NOT NULL REFERENCES users(id),
  authored_at     timestamptz NOT NULL DEFAULT now(),
  parent_version_id uuid REFERENCES prompt_template_versions(id),
  UNIQUE (template_id, version_number)
);

-- Materialised index of nodes — rebuilt on each save
-- Enables queries like "find all templates using variable X"
CREATE TABLE prompt_template_nodes (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id   uuid NOT NULL REFERENCES prompt_templates(id),
  version_id    uuid NOT NULL REFERENCES prompt_template_versions(id),
  node_id       text NOT NULL,     -- the block's id field ("s1", "s2", ...)
  kind          text NOT NULL,
  position      integer NOT NULL,
  var_name      text,              -- populated when kind = var
  var_type      text,
  var_required  boolean,
  content_hash  text NOT NULL,     -- SHA-256(JSON.stringify(block))
  UNIQUE (version_id, node_id)
);
```

### Save flow (one transaction)

```
1. Increment version_number for this template
2. INSERT prompt_template_versions (full document JSONB + commit_msg)
3. INSERT prompt_template_nodes (one row per block, with content_hash)
4. UPDATE prompt_templates SET current_version_id = new version id
```

All four operations in a single Postgres transaction. If any fails, nothing is committed.

### Blame query (computed at load time)

```sql
-- Walk the version chain backwards using a recursive CTE
WITH RECURSIVE chain AS (
  SELECT id, version_number, authored_by, authored_at, commit_msg, parent_version_id
  FROM prompt_template_versions
  WHERE id = :current_version_id
  UNION ALL
  SELECT v.id, v.version_number, v.authored_by, v.authored_at, v.commit_msg, v.parent_version_id
  FROM prompt_template_versions v
  JOIN chain c ON v.id = c.parent_version_id
)
SELECT chain.*, u.display_name AS author_name
FROM chain
JOIN users u ON chain.authored_by = u.id
ORDER BY version_number ASC;
```

For each block in the current version, walk the chain backwards and find the version where `content_hash` differs from the previous version. That version is the blame.

This query is O(depth × block_count) — acceptable for prompt templates which are short documents with shallow history. Cache the result in Redis with a short TTL (5 minutes) keyed by `version_id`.

---

## Backend options

The React frontend calls a plain JSON REST API. The backend language does not matter — no TypeScript-specific protocol is required.

### Option A — FastAPI (Python) — recommended

Natural fit if your team is Python-first. Async, Pydantic validation, automatic OpenAPI docs.

**Dependencies:**
```
fastapi
uvicorn
asyncpg          # async Postgres driver
python-jose      # JWT auth
```

**Pydantic models:**

```python
from pydantic import BaseModel
from typing import Literal
import uuid

class Block(BaseModel):
    id: str
    kind: Literal["prose","var","list","table","code"]
    text: str | None = None        # prose
    name: str | None = None        # var
    type: str | None = None        # var
    desc: str | None = None        # var
    eg: str | None = None          # var
    opts: list[str] | None = None  # var enum
    req: bool = True               # var
    items: list[str] | None = None # list
    headers: list[str] | None = None  # table
    rows: list[list[str]] | None = None  # table
    caption: str | None = None     # table, code
    code: str | None = None        # code
    lang: str | None = None        # code

class SaveRequest(BaseModel):
    template_id: uuid.UUID
    document: list[Block]
    commit_msg: str

class BlameInfo(BaseModel):
    author: str
    sha: str       # first 7 chars of version UUID
    age: str       # "2d ago" — computed server-side
    msg: str

class LoadResponse(BaseModel):
    document: list[Block]
    blame: dict[str, BlameInfo]   # node_id → blame
```

**Endpoints:**

```python
@app.get("/templates/{template_id}", response_model=LoadResponse)
async def load_template(template_id: uuid.UUID, db=Depends(get_db)):
    version = await db.fetchrow("""
        SELECT pv.id, pv.document
        FROM prompt_templates pt
        JOIN prompt_template_versions pv ON pv.id = pt.current_version_id
        WHERE pt.id = $1
    """, template_id)
    blame = await compute_blame(db, version["id"])
    return LoadResponse(
        document=[Block(**b) for b in version["document"]],
        blame=blame
    )

@app.post("/templates/{template_id}/versions")
async def save_version(
    template_id: uuid.UUID,
    body: SaveRequest,
    current_user=Depends(get_current_user),
    db=Depends(get_db)
):
    async with db.transaction():
        row = await db.fetchrow(
            "SELECT COALESCE(MAX(version_number),0)+1 AS next "
            "FROM prompt_template_versions WHERE template_id=$1",
            template_id
        )
        parent = await db.fetchval(
            "SELECT current_version_id FROM prompt_templates WHERE id=$1",
            template_id
        )
        version_id = await db.fetchval("""
            INSERT INTO prompt_template_versions
              (template_id, version_number, document, commit_msg, authored_by, parent_version_id)
            VALUES ($1,$2,$3,$4,$5,$6) RETURNING id
        """, template_id, row["next"],
             json.dumps([b.dict() for b in body.document]),
             body.commit_msg, current_user.id, parent)

        for i, block in enumerate(body.document):
            content_hash = hashlib.sha256(
                json.dumps(block.dict(), sort_keys=True).encode()
            ).hexdigest()
            await db.execute("""
                INSERT INTO prompt_template_nodes
                  (template_id, version_id, node_id, kind, position,
                   var_name, var_type, var_required, content_hash)
                VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
                ON CONFLICT (version_id, node_id)
                DO UPDATE SET content_hash=EXCLUDED.content_hash
            """, template_id, version_id, block.id, block.kind, i,
                 block.name, block.type, block.req, content_hash)

        await db.execute(
            "UPDATE prompt_templates SET current_version_id=$1, updated_at=now() WHERE id=$2",
            version_id, template_id
        )
    return {"version_id": str(version_id), "version_number": row["next"]}
```

**Blame computation (Python):**

```python
import hashlib, json
from datetime import datetime, timezone

def time_ago(dt: datetime) -> str:
    delta = datetime.now(timezone.utc) - dt
    if delta.days >= 1: return f"{delta.days}d ago"
    hours = delta.seconds // 3600
    if hours >= 1: return f"{hours}h ago"
    return f"{delta.seconds // 60}m ago"

async def compute_blame(db, current_version_id: uuid.UUID) -> dict:
    versions = await db.fetch("""
        WITH RECURSIVE chain AS (
          SELECT id, version_number, authored_by, authored_at, commit_msg, parent_version_id
          FROM prompt_template_versions WHERE id=$1
          UNION ALL
          SELECT v.id, v.version_number, v.authored_by, v.authored_at,
                 v.commit_msg, v.parent_version_id
          FROM prompt_template_versions v JOIN chain c ON v.id=c.parent_version_id
        )
        SELECT chain.*, u.display_name AS author_name
        FROM chain JOIN users u ON chain.authored_by=u.id
        ORDER BY version_number ASC
    """, current_version_id)

    current_nodes = await db.fetch(
        "SELECT node_id, content_hash FROM prompt_template_nodes WHERE version_id=$1",
        current_version_id
    )

    blame = {}
    for node in current_nodes:
        blame_version = versions[-1]
        for i in range(len(versions) - 2, -1, -1):
            prev = await db.fetchrow(
                "SELECT content_hash FROM prompt_template_nodes "
                "WHERE version_id=$1 AND node_id=$2",
                versions[i]["id"], node["node_id"]
            )
            if not prev or prev["content_hash"] != node["content_hash"]:
                blame_version = versions[i + 1]
                break
        blame[node["node_id"]] = BlameInfo(
            author=blame_version["author_name"],
            sha=str(blame_version["id"])[:7],
            age=time_ago(blame_version["authored_at"]),
            msg=blame_version["commit_msg"],
        )
    return blame
```

### Option B — Node.js + tRPC

Use if the team prefers TypeScript end-to-end. tRPC eliminates the API contract layer — server procedure types flow directly to the React client with no codegen step.

```typescript
// server/routers/templates.ts
export const templatesRouter = router({
  load: publicProcedure
    .input(z.object({ templateId: z.string().uuid() }))
    .query(async ({ input, ctx }) => {
      const version = await ctx.db.query(...)
      const blame = await computeBlame(ctx.db, version.id)
      return { document: version.document, blame }
    }),

  save: protectedProcedure
    .input(z.object({
      templateId: z.string().uuid(),
      document: z.array(BlockSchema),
      commitMsg: z.string().min(1),
    }))
    .mutation(async ({ input, ctx }) => {
      // same transaction logic as Python version above
    }),
})
```

**React client (tRPC):**
```typescript
const { data } = trpc.templates.load.useQuery({ templateId })
const save = trpc.templates.save.useMutation()
```

### Choosing between them

| Factor | FastAPI (Python) | Node + tRPC |
|---|---|---|
| Team language | Python-first | TypeScript-first |
| Type safety | Pydantic + openapi-typescript | End-to-end via tRPC |
| API contract | OpenAPI / REST | tRPC (TypeScript only) |
| Async support | Native (asyncio) | Native (event loop) |
| Third-party integrations | Larger ML/AI ecosystem | Larger JS ecosystem |
| Deployment | Uvicorn / Gunicorn | Node / Bun |

The database schema, blame algorithm, and block model are identical in both. The choice is purely about your team's preference and existing stack.

**React side with Python backend** — replace tRPC calls with plain fetch or SWR:

```typescript
// Load
const { data } = useSWR(`/api/templates/${templateId}`, fetcher)

// Save
await fetch(`/api/templates/${templateId}/versions`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ document, commit_msg: commitMsg }),
})
```

Optional: generate TypeScript types from FastAPI's OpenAPI schema using `openapi-typescript` for compile-time safety without tRPC.

---

## React component architecture

```
App
├── Toolbar                    — compile toggle, contributor avatars
├── Editor (scrollable)
│   └── for each block:
│       ├── SegRow             — gutter + content area
│       │   ├── GutterBar      — coloured blame bar, click to show tooltip
│       │   └── block renderer:
│       │       ├── prose      — <p> with serif font
│       │       ├── VarChip    — inline node, click opens popover
│       │       ├── list       — <ul> with items
│       │       ├── TableBlock — <table> with header/row rendering
│       │       └── CodeBlock  — line numbers, lang badge, copy button
│       └── InsertZone         — hover to reveal ⊕ insert handle
│           └── AddPanel       — mode picker → form → insert
├── RightPanel
│   ├── Variables index        — all var blocks, click to open popover
│   └── Blame log              — deduplicated commits, click to highlight
└── BlameTooltip               — fixed bottom overlay on blame click
```

### State model

All state lives in the top-level `App` component. No external state library needed at this scale.

```typescript
const [doc, setDoc] = useState<Block[]>(INITIAL)
const [activeBlame, setActiveBlame] = useState<BlameInfo | null>(null)
const [editingVar, setEditingVar] = useState<string | null>(null)   // block id
const [insertAfter, setInsertAfter] = useState<number | null>(null) // index
const [compiled, setCompiled] = useState(false)
```

`doc` is the single source of truth. All mutations go through `setDoc`. The compiled view is derived from `doc` — no separate state.

---

## Production upgrade path (TipTap)

The React artifact uses plain `useState` for the document array — good for prototyping, not for production editing.

| Concern | Prototype | Production |
|---|---|---|
| Document model | `useState<Block[]>` | ProseMirror schema via TipTap v2 |
| Variable blocks | Inline React state | TipTap custom `InlineNode` (atom, no cursor inside) |
| Code blocks | Textarea in a block | TipTap node with embedded CodeMirror 6 |
| Undo/redo | Not implemented | ProseMirror history extension |
| Collaboration | Not implemented | Y.js + TipTap collab extension |
| Blame gutter | Computed from mock data | Computed from `prompt_template_nodes` at load time |
| Persistence | In-memory | REST (FastAPI) or tRPC (Node) → Postgres |

### Variable node in TipTap

```typescript
const PromptVariable = Node.create({
  name: 'promptVariable',
  group: 'inline',
  inline: true,
  atom: true,       // cursor cannot enter — behaves like a single character
  draggable: true,

  addAttributes() {
    return {
      name:     { default: '' },
      type:     { default: 'string' },
      required: { default: true },
      desc:     { default: '' },
      example:  { default: '' },
      options:  { default: [] },
    }
  },

  renderHTML({ node }) {
    return ['span', {
      class: 'prompt-var',
      'data-name': node.attrs.name,
      'data-type': node.attrs.type,
    }, `{${node.attrs.name}}`]
  },

  addNodeView() {
    return ReactNodeViewRenderer(VarChipNodeView)
    // VarChipNodeView = VarChip component adapted as a TipTap node view
  }
})
```

---

## Referring to this from another Claude chat

Paste the following at the start of a new conversation:

---

**Context for Claude:**

I'm building a prompt editor application. The two key files are:

1. **`prompt-editor-v2.jsx`** — React artifact. A structured document editor for AI prompt templates with:
   - Block types: prose, variable `{}` nodes, list, table, code
   - Git-style inline blame (coloured gutter bars, click for commit info)
   - Light mode design
   - Variable chips are first-class inline objects with type, description, example, and enum options
   - Code blocks with line numbers, language badge, and copy button (10 languages supported)
   - Insert zones between every block (prose, variable, list, table, code)
   - Compile view: flat string with `{variable}` placeholders, markdown tables, fenced code blocks, newlines preserved
   - Right panel: variable index + blame log

2. **`prompt-editor-architecture.md`** — Architecture document covering:
   - Block type schema (prose, var, list, table, code)
   - Compiled output format
   - Blame computation model (derived from version history via SHA-256 content hashes, not stored)
   - Postgres schema: `prompt_templates`, `prompt_template_versions`, `prompt_template_nodes`
   - Save flow (single Postgres transaction, 4 steps)
   - Blame SQL query (recursive CTE walking version chain)
   - Two backend options: FastAPI/Python (REST) or Node/tRPC (TypeScript) — same schema for both
   - React component tree
   - TipTap + CodeMirror 6 upgrade path for production

**Backend decision:** Python (FastAPI) is the preferred backend. The React frontend uses plain `fetch` / SWR calls to a REST API. Pydantic models validate all request/response shapes. asyncpg for async Postgres access.

**Current state:** The React artifact is a working prototype using `useState` for the document array. The next steps are:
- [ ] Wire to FastAPI backend (endpoints: `GET /templates/:id`, `POST /templates/:id/versions`)
- [ ] Add save flow UI (commit message input, save button)
- [ ] Compute and serve real blame from version history (recursive CTE + content_hash diff)
- [ ] Replace `useState<Block[]>` with TipTap ProseMirror document model
- [ ] Add CodeMirror 6 embedded in code blocks (replacing textarea)
- [ ] Add undo/redo via ProseMirror history extension

---

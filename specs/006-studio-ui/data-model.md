# Data Model: Studio — Authoring Canvas (006)

This feature introduces no database entities and no API schema changes. All data model work is client-side React state.

## Client-Side State Entities

### StudioSession

Owned by `StudioCanvas.tsx`. Cleared on component unmount (navigation away).

| Field | Type | Source |
|-------|------|--------|
| `version` | `ExecutableVersion` | `GET /api/versions/:vid` |
| `agent` | `{ name, kind_code, application_id, application_code }` | `GET /api/executables/:id` |
| `prompts` | `PromptAssignment[]` | `GET /api/versions/:vid/prompt-assignments` |
| `tools` | `ToolAssignment[]` | `GET /api/versions/:vid/tool-assignments` (agent only) |
| `libraryPrompts` | `PromptSummary[]` | `GET /api/registry/prompts?application_id=` |
| `libraryTools` | `ToolSummary[]` | `GET /api/registry/tools?application_id=` (agent only) |
| `selectedLibraryItem` | `{ kind: 'prompt' \| 'tool'; id: string } \| null` | local |
| `assignForm` | `AssignFormState \| null` | local |

`AssignFormState`:

| Field | Type | Notes |
|-------|------|-------|
| `kind` | `'prompt' \| 'tool'` | Which tab the selection came from |
| `targetId` | `string` | `prompt_id` or `tool_id` of the selected library item |
| `latestVersionId` | `string` | Auto-resolved from library item |
| `apiRole` | `'system' \| 'user' \| 'assistant'` | Prompt-only; default `'system'` |
| `ordinal` | `number` | Prompt-only; default 1 |

---

### BlockEditState

Owned by `BlockEditor.tsx`. Cleared on unmount.

| Field | Type | Source |
|-------|------|--------|
| `prompt` | `PromptSummary` | `GET /api/registry/prompts/:id` |
| `sourceVersion` | `PromptVersionDetail` | `GET /api/registry/prompt-versions/:vid` |
| `editBlocks` | `EditBlock[]` | Copied from `sourceVersion.blocks` on mount |
| `isReadOnly` | `boolean` | `sourceVersion.prompt_version_id !== prompt.latest_version_id` |
| `semverDialogOpen` | `boolean` | local |
| `semverInput` | `string` | local |
| `semverError` | `string \| null` | local |

`EditBlock` extends `PromptBlock` with an additional `_localId: string` field (UUID generated at add time) used as the React list key. `_localId` is stripped before submission to the API.

---

### DiffViewState

Owned by `PromptDiff.tsx`.

| Field | Type | Source |
|-------|------|--------|
| `prompt` | `PromptSummary` | `GET /api/registry/prompts/:id` |
| `versions` | `PromptVersionSummary[]` | `GET /api/registry/prompts/:id/versions` |
| `baseVid` | `string` | URL param or second-latest version default |
| `headVid` | `string` | URL param or latest version default |
| `baseBlocks` | `PromptBlock[] \| null` | `GET /api/registry/prompt-versions/:baseVid` |
| `headBlocks` | `PromptBlock[] \| null` | `GET /api/registry/prompt-versions/:headVid` |
| `diffEntries` | `DiffEntry[]` | Computed client-side via `computeDiff(baseBlocks, headBlocks)` |

---

## Derived Types (lcs.ts)

```typescript
export type DiffStatus = 'added' | 'removed' | 'unchanged'

export interface DiffEntry {
  block: PromptBlock
  status: DiffStatus
}
```

## Block Equality Rule

Two `PromptBlock` values are equal if:
1. `a.kind === b.kind`
2. All kind-specific content fields match:
   - `prose`: `a.text === b.text`
   - `var`: `a.name === b.name && a.type === b.type && a.desc === b.desc && a.req === b.req && JSON.stringify(a.opts) === JSON.stringify(b.opts) && a.eg === b.eg`
   - `list`: `JSON.stringify(a.items) === JSON.stringify(b.items)`
   - `table`: `a.caption === b.caption && JSON.stringify(a.headers) === JSON.stringify(b.headers) && JSON.stringify(a.rows) === JSON.stringify(b.rows)`
   - `code`: `a.lang === b.lang && a.code === b.code && a.caption === b.caption`

The ephemeral `id` field (from `PromptBlockBase`) is NOT compared — it is a DB-assigned UUID and differs between versions even for identical content.

## No New Database Entities

This feature creates no migrations, no new SQL files, and no new aiosql query files. The backend schema is untouched.

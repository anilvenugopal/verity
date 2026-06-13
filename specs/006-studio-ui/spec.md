# Feature Specification: Studio — Authoring Canvas

**Feature Branch**: `006-studio-ui`

**Created**: 2026-06-13

**Status**: Draft

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Compose an agent version from the Studio canvas (Priority: P1)

A developer has created a new agent version and wants to assemble its composition from reusable prompts and tools. They navigate from the agent version detail page to the Studio canvas. The Studio opens with the agent version's current manifest in the centre composition panel. The library panel on the left shows all prompts and tools available in the application. The developer selects a prompt version, configures its API role and ordinal, and adds it to the manifest. They then add a tool. Both additions are confirmed with toast notifications. The developer can also remove assignments directly from the composition panel.

**Why this priority**: The compose canvas is the primary authoring gesture for the entity registry — without it the Studio has no core value. It is the Wave 2 demo gate: "author an agent/task."

**Independent Test**: Open the Studio for any agent version with no prompt assignments; add one prompt and one tool; verify they appear in the composition panel and in the version's composition API response.

**Acceptance Scenarios**:

1. **Given** an agent version with no assignments, **When** a developer selects a prompt from the Library and assigns it with role `system` and ordinal `1`, **Then** the composition panel shows the assignment and the prompt-assignments API response reflects the change.
2. **Given** an agent version with one tool assignment, **When** a developer clicks Remove on that tool, **Then** the assignment disappears from the manifest and a success toast appears.
3. **Given** a task version in the Studio, **When** the developer views the Library, **Then** the Tools tab is absent (tasks are prompt-only per FR-RG-007).
4. **Given** a developer assigns a prompt whose ordinal conflicts with an existing assignment, **When** they submit, **Then** the system rejects with a clear error toast and the manifest is unchanged.

---

### User Story 2 — Author a new prompt version using the block editor (Priority: P2)

A developer wants to refine a prompt. They open the prompt's latest version in the block editor. The editor displays all existing blocks in order — prose sections, variable slots, lists, tables, and code blocks — each rendered according to its kind. The developer adds a new variable block, reorders a prose block, edits a list item, and clicks "Save as new version." A version dialog appears asking for a new semver. The developer enters `1.1.0` and saves. The new version appears in the prompt's version history with its full block sequence and a content hash.

**Why this priority**: Prompts are the primary governed artifact. The block editor is the only way to author or modify prompt content within the portal; without it developers must use the raw API.

**Independent Test**: Open the block editor for any seeded prompt version; add a VarBlock named `claimant_id`; save as a new semver; verify the new version appears in the prompt's version list and contains the added block with the correct content hash.

**Acceptance Scenarios**:

1. **Given** a prompt with existing blocks, **When** a developer opens the block editor, **Then** all blocks render in the correct order with kind-specific presentation (prose as paragraph, var as chip, list as numbered items, table with caption and grid, code with language label and monospace content).
2. **Given** the block editor in edit mode, **When** a developer adds a prose block and clicks "Save as new version," **Then** a semver entry dialog appears before any API call is made.
3. **Given** a semver that already exists (`1.0.0`), **When** the developer submits, **Then** the save is rejected, the editor retains all in-memory edits, and an error toast is shown.
4. **Given** a completed save, **Then** the new version is immediately navigable from the prompt detail page and its compiled preview string matches the saved block sequence.
5. **Given** a prompt version that is not the latest, **When** the developer opens it in the editor, **Then** the editor renders in read-only mode with a notice directing the developer to the latest version.

---

### User Story 3 — Compare two prompt versions using the diff viewer (Priority: P3)

A developer wants to understand what changed between `v1.4.0` and `v1.5.0` of a prompt after an unexpected test failure. From the prompt detail page they click "Compare versions." A toolbar with two version pickers appears. They select `v1.4.0` as base and `v1.5.0` as head. The diff view renders the block sequence: unchanged blocks are neutral, removed blocks are red, and added blocks are green. A summary stat shows `+2 added · −1 removed · 4 unchanged`. A left-rail block navigator allows jumping to changed sections.

**Why this priority**: Closes the audit loop for prompt changes — surfaces what changed and when, connecting failed tests or decision-log anomalies to specific prompt edits.

**Independent Test**: Create two versions of a prompt where v2 adds one prose block; open the diff viewer for those two versions; verify the added block is green, the stat reads `+1 added`, and all other blocks are neutral.

**Acceptance Scenarios**:

1. **Given** two prompt versions, **When** a developer opens the diff viewer and selects them, **Then** added blocks are green, removed blocks are red, and unchanged blocks are neutral.
2. **Given** the diff toolbar, **When** a developer swaps base and head, **Then** colours invert (previously-added become red, previously-removed become green) without a full page reload.
3. **Given** two identical versions, **When** the developer opens the diff viewer, **Then** all blocks are neutral and the stat reads `0 changes`.
4. **Given** a prompt with only one version, **When** the developer views the prompt detail page, **Then** the "Compare versions" action is disabled with the tooltip "Need at least two versions to compare."

---

### Edge Cases

- What happens when a prompt has only one version? The diff viewer action is disabled with a descriptive tooltip.
- How does the block editor handle an empty prompt version (zero blocks)? An empty state with an "Add your first block" prompt is shown; the Add block toolbar remains active.
- What happens if a save-as-new-version request fails mid-flight? The editor retains all in-memory edits and surfaces a retry action via error toast.
- What happens when two developers edit the same agent version in the Studio simultaneously? The second save wins; the first developer sees a stale manifest on next refresh (no real-time conflict resolution in v1).
- What if the library panel returns zero prompts for an application? An empty state is shown; the search field is still rendered.

---

## Requirements *(mandatory)*

### Functional Requirements

**Compose Canvas**

- **FR-ST-001**: The portal MUST provide a Studio canvas accessible via an "Open in Studio" action on any agent or task version detail page.
- **FR-ST-002**: The Studio MUST render a three-panel layout: Library panel (left, ~220px), Composition panel (centre, flex), and Properties panel (right, ~280px); horizontal drag handles between panels MUST allow width adjustment within minimum and maximum bounds.
- **FR-ST-003**: The Library panel MUST display two tabs — Prompts and Tools — each listing components scoped to the version's owning application, with an inline text search field that filters client-side.
- **FR-ST-004**: Selecting a prompt in the Library MUST open an inline assignment form with fields for API role (`system`, `user`, `assistant`) and ordinal; submitting MUST call `POST /api/registry/versions/:vid/prompt-assignments` and update the Composition panel on success.
- **FR-ST-005**: Selecting a tool in the Library MUST open an inline assignment form; submitting MUST call `POST /api/registry/versions/:vid/tool-assignments` and update the Composition panel on success. The Tools tab MUST be absent on task version pages.
- **FR-ST-006**: The Composition panel MUST provide a remove action per assignment row; the remove action MUST call the corresponding `DELETE` endpoint and refresh the manifest on success.
- **FR-ST-007**: The Composition panel MUST render prompt assignments grouped by API role (system / user / assistant), each row showing prompt name, semver badge, and ordinal; tool assignments MUST show tool name, transport chip, and data classification badge.
- **FR-ST-008**: Every assignment add or remove operation MUST surface a toast notification on success and on failure; failure toasts MUST include the error reason from the API response.
- **FR-ST-009**: The Properties panel MUST show the executable version's metadata (semver, lifecycle stage, champion badge, owning application); when a Library item is focused it MUST also show that component's description, latest semver, and version count.

**Prompt Block Editor**

- **FR-ST-010**: The portal MUST provide a block editor accessible from any prompt version detail page; the "Edit blocks" action MUST be available only on the latest version card; earlier versions MUST open the editor in read-only mode.
- **FR-ST-011**: The block editor MUST render existing blocks in order by kind: prose (paragraph text with line breaks preserved), var (inline chip showing name, type, and required/optional indicator), list (numbered items), table (caption + column headers + data rows), code (language label + monospace pre-formatted content).
- **FR-ST-012**: The block editor MUST provide an "Add block" toolbar with five buttons — `+ prose`, `+ {variable}`, `+ list`, `+ table`, `+ code` — each opening a kind-specific inline form for entering content before insertion at the end of the block sequence.
- **FR-ST-013**: Each block row MUST provide: an edit action (opens inline form pre-populated with current content), a delete action (requires a single confirmation click), and up/down reorder controls (disabled at sequence boundaries).
- **FR-ST-014**: The block editor MUST display a read-only compiled preview pane showing the assembled prompt string with `{variable_name}` placeholders, updated live as blocks are added, edited, reordered, or deleted.
- **FR-ST-015**: The "Save as new version" action MUST: (a) require the developer to enter a semantic version number in a modal dialog; (b) call `POST /api/registry/prompts/:id/versions` with the full ordered block sequence; (c) on success, navigate to the new version's detail page and show a success toast.
- **FR-ST-016**: If the submitted semver already exists, the save MUST be rejected; the editor MUST remain open with all in-memory edits intact and an error toast MUST be shown.
- **FR-ST-017**: Each block MUST display version-level attribution: the prompt version's `created_by` display name and `created_at` timestamp (not per-block granularity).

**Composition Diff Viewer**

- **FR-ST-018**: The portal MUST provide a "Compare versions" action on any prompt detail page; when the prompt has fewer than two versions the action MUST be disabled with the tooltip "Need at least two versions to compare."
- **FR-ST-019**: The diff viewer MUST present a toolbar with two version selectors (base and head); on initial open, base defaults to the second-latest version and head to the latest.
- **FR-ST-020**: The diff viewer MUST render block sequences as a unified inline diff: blocks present only in head are highlighted green (added), blocks present only in base are highlighted red (removed), and blocks in both are neutral (unchanged). Comparison is block-level, not character-level within a block.
- **FR-ST-021**: Each block entry in the diff MUST show its kind label (Prose / Variable / List / Table / Code) and a status badge (Added / Removed / Unchanged).
- **FR-ST-022**: The diff toolbar MUST display a summary stat: `+N added · −M removed · K unchanged`.
- **FR-ST-023**: A left-rail block navigator MUST list all blocks by kind; clicking a navigator entry MUST scroll the diff view to that block; changed blocks MUST be visually distinguished in the navigator.
- **FR-ST-024**: Swapping base and head MUST re-render the diff with inverted colour coding without a full page reload.

### Key Entities

- **Studio Session**: Transient in-memory state for a single executable version's composition; not persisted until an explicit save action; cleared on navigation away.
- **Block Edit State**: The in-progress ordered list of blocks being composed before saving as a new prompt version; each block carries its kind, content fields, and a local ephemeral key for React rendering.
- **Diff Entry**: A computed record `{ block, status: 'added' | 'removed' | 'unchanged' }` derived client-side from two fetched block sequences via a longest-common-subsequence algorithm; blocks are equal if kind and all content fields match exactly.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer can add a prompt version to an agent version's composition manifest from the Studio canvas in 3 clicks or fewer (open Studio → select prompt → submit assignment form).
- **SC-002**: The block editor renders all five block kinds without errors or data loss for any prompt version in the seeded dataset.
- **SC-003**: A new prompt version created via the block editor is immediately accessible in the prompt detail page and its compiled preview string is consistent with the stored block sequence.
- **SC-004**: The diff viewer correctly categorises every block as added, removed, or unchanged for any two versions of the same prompt, with zero false positives in the unchanged category.
- **SC-005**: 100% of the existing pytest suite continues to pass after delivery; no backend schema changes, migrations, or new API endpoints are introduced by this feature.
- **SC-006**: A developer can reach the diff view for a specific prompt in 3 clicks or fewer from the prompt list (prompt list → prompt detail → compare versions).

---

## Assumptions

- This feature is entirely React/TypeScript; no new backend API endpoints, schema migrations, or SQL queries are required. All data access uses registry API endpoints shipped in feature 005.
- Blame metadata is version-level (`created_by` display name + `created_at` from the `prompt_version` row), not per-block granularity. Per-block blame tracking requires extending the PromptBlock discriminated union schema and is deferred.
- Block comparison for the diff viewer is performed client-side using a longest-common-subsequence (LCS) algorithm on the block sequence.
- The Studio canvas does not support drag-and-drop block reordering in v1; up/down button controls are sufficient.
- The Studio canvas does not support real-time collaborative editing; last write wins.
- The diff viewer is scoped to prompt block-sequence diffs only. Comparing agent/task version composition manifests (which prompts and tools are assigned) is a distinct concept and is deferred.
- The block editor always produces a new immutable version on save; there is no draft/autosave mechanism and in-memory state is lost on navigation away.
- The Library panel populates from the application-scoped endpoints already used by the registry list pages (`/api/registry/prompts?application_id=...`, `/api/registry/tools?application_id=...`).
- The test-and-inspect panel (submit a run, view output) is explicitly deferred until feature 008 (Harness runtime) ships.
- The save-to-test-suite modal is explicitly deferred until feature 011 (Eval & testing harness) ships.

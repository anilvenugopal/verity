# Quickstart: Studio — Authoring Canvas (006)

Prerequisites: dev instance running (`./dev up`), demo seed applied (`./dev demo`), logged in as a mock user with `author_registry` role.

## Flow 1 — Open the Studio canvas for an agent version

1. Navigate to `/registry/agents` → click the `triage-agent` row.
2. On the agent detail page, click the latest version row (e.g. `v1.0.0`).
3. On the version detail page, click **"Open in Studio"** (top-right of the composition section).
4. Verify: three-panel Studio canvas loads at `/registry/agents/:id/versions/:vid/studio`.
   - Left panel shows **Prompts** and **Tools** tabs.
   - Centre panel shows existing prompt assignments grouped by role.
   - Right panel shows version semver, lifecycle badge, and owning application.

## Flow 2 — Assign a prompt from the Library

1. (From Flow 1) In the Library panel, click **Prompts** tab.
2. Type `triage` in the search field — filter applies immediately.
3. Click the `triage-system` prompt row.
4. The Properties panel updates with the prompt's description and latest semver.
5. An inline assignment form appears below the row: role = `system` (default), ordinal = `1`.
6. Click **Assign**. Verify: success toast; composition panel updates with the new assignment.

## Flow 3 — Remove an assignment

1. (From Flow 2) In the Composition panel, find the assigned prompt row.
2. Click the **Remove** (×) button on the row.
3. Verify: success toast; row disappears from composition panel.

## Flow 4 — Open the block editor for a prompt version

1. Navigate to `/registry/prompts` → click `triage-system`.
2. On the prompt detail page, click the latest version card header to expand it.
3. Click **"Edit blocks"** on the latest version card.
4. Verify: block editor loads at `/registry/prompts/:id/versions/:vid/edit`.
   - All existing blocks render in order (at least one prose block).
   - A compiled preview pane on the right shows `{variable_name}` placeholders.
   - The "Add block" toolbar is visible.

## Flow 5 — Add a variable block and save as a new version

1. (From Flow 4) Click **`+ {variable}`** in the Add block toolbar.
2. In the inline form:
   - Name: `claimant_id`
   - Type: `string`
   - Description: `Unique claimant identifier from the intake record`
   - Required: checked
3. Click **Insert**. Verify: VarBlock chip `{claimant_id}` appears at the end of the block list; compiled preview updates to include `{claimant_id}`.
4. Click **"Save as new version"**.
5. In the semver dialog, enter `0.0.2`. Click **Save**.
6. Verify: success toast; browser navigates to the new version detail page at `…/versions/<new_vid>`; the new version appears in the prompt version list; content hash is present.

## Flow 6 — Compare two prompt versions

1. Navigate to `/registry/prompts` → click `triage-system`.
2. Verify the prompt detail page shows version count ≥ 2 (after Flow 5).
3. Click **"Compare versions"**.
4. Verify: diff viewer loads at `/registry/prompts/:id/diff`.
   - Base picker defaults to `v0.0.1`; Head picker defaults to `v0.0.2`.
   - The `{claimant_id}` VarBlock appears in **green** (added).
   - All prior blocks appear in **neutral** (unchanged).
   - Diff stat reads `+1 added · −0 removed · N unchanged`.
5. Click **Swap** (or exchange the base/head selectors). Verify: `{claimant_id}` block is now **red** (removed); stat reads `+0 added · −1 removed`.

## Deviations Table

| Flow | Step | Expected | Actual | Resolved? |
|------|------|----------|--------|-----------|
| — | — | — | — | — |

*(Fill in during T028-equivalent walkthrough after implementation)*

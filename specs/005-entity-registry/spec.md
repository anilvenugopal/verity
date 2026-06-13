# Feature Specification: Entity Model & Registry

**Feature Branch**: `005-entity-registry`

**Created**: 2026-06-11

**Status**: Draft

**Input**: Entity registration, versioning, composition, bindings, config resolution, YAML portability, and model catalog for the Verity governance backend.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Register and manage registry entities (Priority: P1)

An AI developer registers the building blocks of an AI application — agents, tasks, prompts, tools, data connectors, MCP servers, and inference configurations — into the governance registry. Each component has an identity and a description. Components that can evolve over time (agents, tasks, prompts, tools) get discrete, immutable versions. Components that are configuration-only (inference configs, data connectors, MCP servers) are managed as single, updatable records.

**Why this priority**: Everything in the registry downstream (composition, promotion, packaging, deployment) depends on registered entities existing first. Without this, no other story can proceed.

**Independent Test**: An AI developer can register an agent, create a prompt, register a tool, and list all three back via the registry API — without any other features being present.

**Acceptance Scenarios**:

1. **Given** no agent named "underwriting-assistant" exists, **When** an AI developer registers it with a name and description, **Then** it appears in the registry with a unique identifier and `created_at` timestamp.
2. **Given** an agent named "underwriting-assistant" already exists, **When** the developer tries to register another agent with the same name, **Then** the system rejects the request with a clear duplicate-name error.
3. **Given** a registered agent, **When** the developer creates a first version (e.g., 1.0.0) with a governance tier and capability type, **Then** the version is stored as a draft, immutable thereafter, with a SCD-2 validity window opened.
4. **Given** a registered prompt "uw-system-prompt", **When** the developer creates version 1.0.0 with typed prompt blocks, **Then** a content hash is computed and stored for future blame/diff.
5. **Given** any registry entity, **When** the developer requests it by ID, **Then** the response includes the entity metadata and its current (open) version.

---

### User Story 2 — Compose an agent version with its components (Priority: P2)

An AI developer assembles a specific version of an agent or task by assigning exact component versions: which prompt versions fill which API roles (system, user, assistant), which tool versions the agent is authorised to call, and which MCP server versions it may access. Tasks may only use prompts; tools and MCP servers are agent-exclusive.

**Why this priority**: An uncomposed version has no prompts, tools, or MCP servers — it cannot be resolved, packaged, or run. Composition is the second essential step before any downstream feature is usable.

**Independent Test**: An AI developer can create an agent version, assign a prompt version to the `system` role, assign a tool version, and retrieve the full composition manifest back — without champion promotion or bindings.

**Acceptance Scenarios**:

1. **Given** an agent version and a prompt version, **When** the developer assigns the prompt to the `system` role, **Then** the assignment is stored and the composition manifest reflects it.
2. **Given** the same agent version, **When** the developer assigns a second prompt to the `user` role with ordinal 1, **Then** both prompt assignments appear in the manifest, ordered by role and ordinal.
3. **Given** a task version (not an agent), **When** the developer attempts to assign a tool to it, **Then** the system rejects the request with a clear error stating tools are agent-only.
4. **Given** an agent version with a prompt and a tool assigned, **When** the developer requests the composition manifest, **Then** the manifest lists all assigned components with their exact version IDs.
5. **Given** a component assigned to a version, **When** the developer removes the assignment, **Then** it no longer appears in the manifest and the version itself is unchanged.

---

### User Story 3 — Promote a version to champion (Priority: P3)

A governance reviewer promotes a draft agent or task version to `champion` status — making it the active version that the harness resolves when no explicit version is requested. Promotion is atomic: the old champion is retired in the same operation. The champion state is SCD-2 tracked so that past runs can reconstruct which version was champion at the time they ran.

**Why this priority**: Without champion promotion, the harness has no way to resolve which version to run. Packaging and deployment (feature 007) depend on champion state. Promotion is the key governance gate.

**Independent Test**: An AI developer can promote an agent version to champion, verify the old champion is retired, and confirm that resolving the agent by name without a version returns the new champion — all independently testable.

**Acceptance Scenarios**:

1. **Given** a draft agent version with at least one prompt assigned, **When** a governance reviewer promotes it to champion, **Then** the version's lifecycle state becomes `champion` and a `valid_from` timestamp is recorded.
2. **Given** an existing champion version, **When** a new version is promoted to champion, **Then** the old champion's `valid_to` is set to the promotion timestamp in the same atomic operation — no gap, no overlap.
3. **Given** an application with a registered agent, **When** the harness resolves the agent by name with no version specified, **Then** it receives the current champion version.
4. **Given** a historical timestamp before the latest promotion, **When** the harness resolves the agent as-of that timestamp, **Then** it receives the version that was champion at that point in time.
5. **Given** an agent version that is currently champion, **When** the developer attempts to delete it, **Then** the system rejects the deletion and explains that champion versions cannot be removed.

---

### User Story 4 — Define Source and Target data bindings (Priority: P4)

An AI developer defines how data flows into and out of an agent or task version using a declarative binding grammar. Source bindings describe where the input data comes from (a field on the incoming request, a constant, or a fetched connector response). Target bindings describe where the output data is written (a field on the response payload). Bindings are stored per-version and included in the deployment bundle.

**Why this priority**: Bindings are required for the harness to route data to/from a version at runtime. Without them the harness cannot wire inputs or capture outputs.

**Independent Test**: A developer can define a source binding of type `input.<path>` and a target binding on a version, then retrieve both back — independently testable without promotion or packaging.

**Acceptance Scenarios**:

1. **Given** an executable version, **When** the developer creates a source binding with `source_kind_code = 'structured'` and a `locator` describing the input field path, **Then** the binding is stored and returned in the version's binding manifest.
2. **Given** the same version, **When** the developer creates a source binding with `source_kind_code = 'storage_object'` and a valid `data_connector_version_id`, **Then** the binding is stored with the connector reference and returned in the manifest.
3. **Given** a source binding with `source_kind_code = 'storage_object'` submitted without a `data_connector_version_id`, **When** the developer attempts to save it, **Then** the system rejects it with a 422 error identifying the missing field.
4. **Given** an executable version with both source and target bindings, **When** the developer requests the binding manifest, **Then** all source and target bindings are returned, ordered by creation.
5. **Given** a target binding with write mode `replace` on field `output.underwriting_decision`, **When** the developer deletes it, **Then** it no longer appears in the binding manifest.

---

### User Story 5 — Export and import a registry bundle as YAML (Priority: P5)

An AI developer exports one or more executable versions — together with their component assignments, bindings, and inference configs — as a portable YAML bundle. The bundle can be imported into another Verity instance (or the same one) via a dry-run that reports what would change, and an apply that actually imports. Import is idempotent: re-importing an identical bundle makes no changes.

**Why this priority**: YAML portability is required for multi-environment workflows (dev → staging → prod) and disaster recovery. It does not block the core registry or runtime, so it is lower priority than P1–P4.

**Independent Test**: A developer can export a single agent version as YAML, modify nothing, re-import it, and observe that the dry-run reports zero changes — independently testable.

**Acceptance Scenarios**:

1. **Given** a champion agent version with prompts and tools assigned, **When** the developer requests a YAML export, **Then** the response is a valid YAML document containing the version, its assignments, and its bindings.
2. **Given** a YAML export, **When** the developer submits it to the dry-run import endpoint, **Then** the response lists which entities would be created, updated, or skipped — with no changes applied.
3. **Given** an identical YAML bundle imported twice, **When** the second import runs, **Then** the result reports all entities as `no-op` (no changes applied).
4. **Given** a YAML bundle referencing an entity name that conflicts with an existing entity of a different kind, **When** the import runs, **Then** it is rejected with a clear conflict error listing the entity name and kinds involved.
5. **Given** a YAML bundle with a version whose content hash already exists in the registry, **When** the import runs, **Then** the version is treated as `no-op` and not re-created.

---

### User Story 6 — Manage the model catalog and pricing (Priority: P6)

An operator registers provider models (e.g., `claude-sonnet-4-6`) into the model catalog and maintains their pricing windows. Pricing is SCD-2: a new pricing window closes the old one rather than overwriting it, so historical cost calculations remain stable. A governance reviewer can register named model references (stable logical aliases like `reasoning-primary`) and bind them to concrete models. Changing the underlying model only requires updating the binding — no executable version needs re-promotion.

**Why this priority**: The model catalog is a shared reference dependency for inference configs and cost reporting. It does not block agent/task registration but must exist before inference configs can reference models.

**Independent Test**: An operator can register a model, set an initial price window, and retrieve the current price — independently testable.

**Acceptance Scenarios**:

1. **Given** no model `claude-sonnet-4-6` exists, **When** the operator registers it with provider `anthropic`, **Then** it appears in the model catalog with a unique identifier.
2. **Given** a registered model with a price window of $3.00/$15.00 per 1k tokens, **When** the operator records a new price window of $2.50/$10.00, **Then** the old window is closed and the new window opens atomically.
3. **Given** a historical run timestamp before the price change, **When** cost is computed for that run, **Then** it uses the price window that was open at the run's execution time.
4. **Given** a model reference `reasoning-primary` bound to `claude-sonnet-4-6`, **When** an operator rebinds it to `claude-opus-4-8`, **Then** the old binding closes and the new one opens — and all inference configs pointing at `reasoning-primary` automatically resolve to `claude-opus-4-8` from that moment forward.
5. **Given** an attempt to deregister a model that is referenced by an active inference config, **When** the operator submits the deletion, **Then** the system rejects it and lists the referencing configs.

---

### User Story 7 — Browse and navigate the entity registry (Priority: P7)

A governance reviewer or developer opens the web portal to browse the entity registry — viewing lists of agents, tasks, prompts, tools, and the model catalog. They can navigate into any entity to see its versions, and from a version's detail page follow links to the components it depends on. They can also navigate from a prompt or tool to see which agent and task versions depend on it (where-used).

**Why this priority**: The API backend is complete before the portal layer; this is the read-only browse surface over already-stored data.

**Independent Test**: Navigate to `/registry/agents`, open an agent, open a version, follow a link to an assigned prompt — all navigable without any write actions.

**Acceptance Scenarios**:

1. **Given** the registry contains agents and tasks, **When** a reviewer opens the registry, **Then** they see separate lists for agents and tasks showing name, champion semver badge, and lifecycle stage.
2. **Given** an agent in the list, **When** the reviewer clicks it, **Then** they see the agent detail — all versions, champion badge, and a link to the related intake if one exists.
3. **Given** an agent version detail page, **When** the reviewer views the composition manifest, **Then** prompt and tool assignments appear as clickable links leading to the respective component detail pages.
4. **Given** a prompt detail page, **When** the reviewer views it, **Then** a "Used by" section lists every agent and task version that includes this prompt, with navigation links to each version detail page.
5. **Given** the Ctrl+J command palette, **When** the reviewer types an agent or prompt name, **Then** the entity appears as a result and navigates to its detail page.

---

### User Story 8 — Manage composition, champion promotion, and inference config from the portal (Priority: P8)

An AI developer manages the composition of an agent or task version directly from the portal — assigning and removing prompt and tool assignments, configuring inference settings inline (model reference priority, temperature, token limits), and promoting a version to champion. Tools and MCP servers remain agent-only; the UI enforces this by omitting the tool assignment section from task version pages.

**Why this priority**: Builds on US7 (navigation must exist before write actions).

**Independent Test**: Open an agent version, assign a prompt version via the portal form, configure inference settings, promote to champion — testable without YAML or model catalog write UI.

**Acceptance Scenarios**:

1. **Given** an agent version detail page, **When** the developer opens the "Assign Prompt" action, **Then** they can search for a prompt version, specify the API role and ordinal, and save — the manifest updates immediately.
2. **Given** an agent version with a tool assignment, **When** the developer removes the tool via the portal, **Then** the manifest updates without a full page reload and a success toast confirms the action.
3. **Given** a version detail page, **When** the developer opens the inference config section, **Then** they see editable fields for max_tokens, temperature, and a model reference priority list (add/remove/reorder references).
4. **Given** a composed version with at least one prompt, **When** a governance reviewer clicks "Promote to champion", **Then** the version becomes champion, the previous champion is retired, and the UI reflects the updated state with a success toast.
5. **Given** a task version detail page, **When** a developer looks for the tool assignment section, **Then** the section is absent — tools are not offered as an option for tasks.

---

### Edge Cases

- What happens when a developer tries to create a new version of an agent using a semver that already exists? → Rejected with a duplicate-version error.
- What happens when a developer assigns the same prompt version to the same role twice? → Idempotent: second assignment is a no-op or returns the existing assignment.
- What happens when the only prompt version assigned to a version is removed, and then promotion is attempted? → Promotion is rejected; a version must have at least one prompt assignment before it can be promoted.
- What happens when a YAML import bundle references a prompt version by content hash and that hash exists but under a different name? → Import treats it as a hash match and skips re-creation; the name discrepancy is surfaced as a warning.
- What happens when a developer requests the champion version of an agent that has never been promoted? → Returns a clear "no champion" response, not a 404.
- What happens when a `storage_object` source binding references a `data_connector_version_id` that is later decommissioned? → The binding is stored; liveness of the referenced connector is a deployment-time check, not a write-time hard block. The binding remains in the manifest but will fail at harness resolution time.

---

## Requirements *(mandatory)*

### Functional Requirements

**Entity Registration**

- **FR-RG-001**: The system MUST allow an authorised developer to register an executable entity (agent or task) with a unique name per kind, a description, and an owning application.
- **FR-RG-002**: The system MUST allow an authorised developer to register a prompt, tool, data connector, MCP server, or inference config as a named, reusable component.
- **FR-RG-003**: The system MUST allow an authorised developer to create an immutable version of an executable (agent or task) or component (prompt, tool) with a semantic version number.
- **FR-RG-004**: The system MUST enforce that a semantic version within an entity is unique; attempting to create a duplicate semver MUST be rejected.
- **FR-RG-005**: The system MUST record a content hash for every prompt version to enable blame, diff, and exact historic reproduction.

**Composition**

- **FR-RG-006**: The system MUST allow an authorised developer to assign a prompt version to an executable version in a specified API role (system, user, assistant) with an ordinal.
- **FR-RG-007**: The system MUST allow an authorised developer to assign a tool version to an agent version; the system MUST reject tool assignment to a task version.
- **FR-RG-008**: The system MUST allow an authorised developer to assign an MCP server version to an agent version; the system MUST reject MCP assignment to a task version.
- **FR-RG-009**: The system MUST allow an authorised developer to remove any component assignment from an executable version.

**Champion Lifecycle**

- **FR-RG-010**: The system MUST allow an authorised reviewer to promote a draft executable version to `champion` status.
- **FR-RG-011**: When a version is promoted to champion, the system MUST atomically close the previous champion's validity window and open the new one — with no gap and no overlap.
- **FR-RG-012**: The system MUST allow resolving the current champion of an executable by name; and resolving the champion as-of a historical timestamp.
- **FR-RG-013**: The system MUST prevent deletion of any version that is currently the champion. *(Implementation note: satisfied by design — the API exposes no `DELETE /versions/:id` endpoint; the DB FK from `champion_assignment → executable_version` also blocks deletion at the database level.)*

**Source/Target Bindings**

- **FR-RG-014**: The system MUST allow an authorised developer to create a source binding on an executable version by specifying a `source_kind_code` (one of `structured`, `storage_object`, `task_output`, `inline_content`), a `delivery_mode_code`, and a `locator` (jsonb describing the field path, query, or content reference).
- **FR-RG-015**: The system MUST allow an authorised developer to create a target binding on an executable version specifying `target_kind_code`, output field path, write mode, and optional `data_connector_version_id`.
- **FR-RG-016**: The system MUST validate source and target bindings at write time: a `storage_object` kind MUST include a `data_connector_version_id`; a `storage_object` target binding MUST also include a `write_mode_code`. Invalid combinations MUST be rejected with a 422 error.
- **FR-RG-017**: The system MUST allow retrieval of all source and target bindings for a given executable version.

**Data Classification**

- **FR-RG-018**: The system MUST allow an authorised operator to set a data classification label on a tool version indicating the sensitivity of data the tool may access.

**Where-Used**

- **FR-RG-019**: The system MUST provide a reverse-lookup: given a component version (prompt, tool, MCP server), return all executable versions that include it in their composition.

**Model Catalog**

- **FR-VM-001**: The system MUST allow an authorised operator to register a provider model with a unique model code and provider name.
- **FR-VM-002**: The system MUST allow an authorised operator to record a price window (input/output per 1k tokens, currency) for a registered model; recording a new price MUST close the prior window atomically.
- **FR-VM-003**: Historical cost computations MUST use the price window that was open at the time of the run, not the current price. _(Deferred — this feature delivers the SCD-2 price-window data foundation; the query-time cost computation against `audit.model_invocation_log` is scoped to the analytics/decision-log feature; see Assumptions §4.)_
- **FR-VM-004**: The system MUST allow an authorised reviewer to register a named model reference (a stable logical alias) and bind it to a concrete model with a validity window.
- **FR-VM-005**: The system MUST allow an authorised reviewer to rebind a model reference to a different concrete model; the rebinding MUST close the prior binding atomically so all inference configs using the reference resolve to the new model from that point forward.

**YAML Portability**

- **FR-YM-001**: The system MUST allow an authorised developer to export one or more executable versions with their full composition (prompt assignments, tool assignments, MCP assignments, bindings, inference config) as a portable YAML bundle.
- **FR-YM-002**: The system MUST provide a dry-run import endpoint that reports which entities would be created, updated, or skipped — without applying any changes.
- **FR-YM-003**: The system MUST allow an authorised developer to apply a YAML bundle import; the operation MUST be idempotent (re-importing an unchanged bundle produces no changes).
- **FR-YM-004**: The system MUST reject a YAML import that would create a name collision with an existing entity of a different kind.
- **FR-YM-005**: The system MUST treat a version whose content hash already exists as a no-op during import.

**Registry Portal — Browse**

- **FR-UI-001**: The portal MUST provide browsable list pages for agents, tasks, prompts, and tools, each showing name, champion semver (if any), and lifecycle stage.
- **FR-UI-002**: The portal MUST provide a detail page for each executable showing all versions with lifecycle stage, champion badge, and a linked intake chip if an intake exists.
- **FR-UI-003**: The portal MUST provide a version detail page showing the composition manifest (prompt, tool, and MCP assignments), source/target bindings, and an inline inference config section.
- **FR-UI-004**: The portal MUST render composition manifest entries as clickable links navigating to the component's own detail page.
- **FR-UI-005**: The portal MUST provide a "Used by" section on prompt and tool detail pages listing all executable versions that include the component, with links to each version detail page.
- **FR-UI-006**: The portal MUST provide a model catalog page listing models with current price, and a model detail page showing price history and which model references are currently bound to the model.

**Registry Portal — Write**

- **FR-UI-007**: The portal MUST allow an authorised developer to assign and remove prompt and tool versions from an agent version's composition manifest; the tool assignment section MUST be absent on task version pages.
- **FR-UI-008**: The portal MUST allow an authorised developer to set or update the inference config (model reference priority list, max_tokens, temperature) on any executable version inline.
- **FR-UI-009**: The portal MUST allow an authorised reviewer to promote an executable version to champion via a single confirm action; success and failure MUST surface as toast notifications.

**Registry Portal — Discovery**

- **FR-UI-010**: The portal Ctrl+J command palette MUST include searchable entries for agents, tasks, prompts, and tools.
- **FR-UI-011**: The portal help system MUST include pages covering: registry entity types reference, composing a version, the full AI asset lifecycle, and navigating connected assets.

### Key Entities

- **Executable**: A governed, promotable unit that the harness runs. Has a kind (`agent` or `task`) and a name unique per kind. Agents may use tools and MCP servers; tasks may not.
- **Executable Version**: An immutable snapshot of an executable at a point in time — its governance classification, inference config reference, and I/O schemas. Carries SCD-2 temporal validity windows.
- **Prompt / Prompt Version**: A reusable prompt component with ordered typed blocks. Versions are immutable and content-hashed.
- **Tool / Tool Version**: A reusable callable component (agent-only). Versions carry an input schema, configuration, and a data classification label.
- **MCP Server / MCP Server Version**: A managed context protocol server an agent may connect to (agent-only).
- **Data Connector / Data Connector Version**: A named external data source an agent may fetch from via source bindings.
- **Inference Config**: An agent/task-level configuration object specifying model reference(s) and inference parameters. Unversioned — updates apply in place.
- **Model**: A provider model identity (e.g., `claude-sonnet-4-6`). Stable identifier; pricing is separate.
- **Model Price**: A SCD-2 price window for a model (input/output per 1k tokens).
- **Model Reference**: A stable logical alias (e.g., `reasoning-primary`) that inference configs point at instead of a concrete model.
- **Model Reference Binding**: A SCD-2 window mapping a model reference to a concrete model.
- **Source Binding**: A declarative expression describing where an executable version's input data comes from.
- **Target Binding**: A declarative expression describing where an executable version's output data is written.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer can register a new agent, create a version, assign a prompt, and promote to champion in under 5 API calls with no manual schema changes.
- **SC-002**: All registry read operations (list, detail, composition manifest) respond in under 500ms at the data volumes expected for a single insurance application (hundreds of entity versions, not millions).
- **SC-003**: Champion promotion is atomic — no period exists where an entity has zero champions or two simultaneous open champions, verifiable by a constraint check on the temporal windows.
- **SC-004**: A YAML round-trip (export then import with no changes) produces a dry-run report of 100% no-ops — zero diff between the exported state and the re-imported state.
- **SC-005**: The where-used reverse lookup returns results in under 200ms for a component used across up to 50 executable versions.
- **SC-006**: Historical config resolution (as-of a given timestamp) returns a deterministic, frozen snapshot consistent with what the harness used at that time — verifiable by comparing with the decision log snapshot.
- **SC-007**: 100% of existing pytest suite continues to pass after the feature is delivered (no regressions in prior features).
- **SC-008**: A reviewer can navigate from the registry agent list to a specific version's composition manifest in 3 clicks or fewer.

---

## Assumptions

- The application (`application_id`) that owns a registry entity already exists; feature 001 (application onboarding) is a prerequisite and is shipped.
- The schema tables for executables, prompts, tools, data connectors, MCP servers, inference configs, models, model references, source bindings, and target bindings are already defined in `specs/schema/verity_schema.sql`; this feature delivers the API and business logic layer on top of the existing schema.
- Lifecycle promotion (draft → champion) uses the existing `reference.lifecycle_state` reference data; no new state machine rows are required.
- Source and target bindings use structured fields (`source_kind_code`, `locator` jsonb, `delivery_mode_code`) rather than a free-text DSL expression string. The v2 schema encodes binding intent as typed, validated fields; the PCR §1 DSL grammar notation is superseded by the hardened schema design (ADR-0005).
- YAML portability covers the entity model only (executables, components, bindings, inference configs, model references); deployment artifacts (`.vtx`/`.vax` packaging) are out of scope and belong to feature 007.
- Authentication and authorization use the existing actor/role model from feature 001; this feature does not introduce new roles, only applies the existing `app_team_developer` and `governance_reviewer` role checks to new endpoints.
- Multi-application import isolation: during YAML import, entity names are scoped to the target application; cross-application name collisions are not checked.
- Registry portal pages (browse, compose write actions, champion promotion, and inference config editing) are in scope for this feature. YAML import/export UI wizard and multi-environment deploy tooling remain deferred.
- Historical cost computation (FR-VM-003) requires the SCD-2 price-window data delivered by this feature, but the query that computes cost-per-run from `audit.model_invocation_log` belongs to the analytics/decision-log feature. This feature delivers the data foundation; the computation is deferred.

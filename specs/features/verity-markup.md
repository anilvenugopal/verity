# Feature Spec — Verity Markup (document evidence annotation surface)

- **Status:** Deferred — backlog. **Not** an active slice and **not** next in sequence.
- **Sequencing:** Comes well after the intake slice and the core platform work —
  **registry → compose → harness → packaging/deployment** (and more) land first. This doc
  exists so the re-authored design is captured against the metamodel; it receives a
  Spec Kit feature **number only when it is actually scheduled** (do not assign one now).
- **Created:** 2026-06-04
- **Related:** [[0014-unified-annotation-and-feedback-model]],
  [[0013-evaluation-observability-tooling-boundaries]], [[verity_v2_pcr]],
  [[0003-harness-governance-api]], [[0004-storage-architecture]],
  [[0007-decision-log-scale-and-portable-analytics]],
  [[0011-repository-topology-and-harness-release-boundary]],
  [[user-authentication]], [[constitution]]
- **Builds on (component spec):** `001-verity-governance-service` — the ground-truth dataset
  model (FR-TV-003), validation runs (FR-TV-004), per-field HITL overrides (FR-DL-007), the
  decision log (FR-DL-001/006), and tool data-classification (FR-RG-013). This feature
  **consumes** those; it does not re-state or re-define them.
- **Purpose:** A browser-based surface for capturing **document-anchored evidence
  annotations** — selecting text or drawing bounding boxes on a source document and binding
  each selection to a schema field, with optional AI assistance. It is the human (and
  human-validated-AI) labeling/review UI for the **unified annotation primitive**
  ([[0014-unified-annotation-and-feedback-model]]). It serves two governance contexts on one
  surface: **design-time ground-truth labeling** and **execution-time HITL review** of a
  decision's field outputs. Its distinguishing contribution is **visual provenance** — "show
  me, in the document, where this value came from."

> **Re-authoring note (Principle III — no silent capability loss).** This re-authors the
> standalone "Verity Markup" PRD (a Docker-Compose app with its own `users` / `documents` /
> `schemas` / `annotations` / `ai_tasks` tables and direct Claude calls) onto Verity's
> metamodel and architecture. The PRD's standalone-stack assumptions are **DROPPED** (they
> conflict with [[0011-repository-topology-and-harness-release-boundary]] and the API-only
> boundary); its capabilities are **KEPT** and re-expressed against governance entities. The
> disposition table at the end maps every PRD construct to its Verity-native form.

---

## Clarifications

### Session 2026-06-04

- Q: Where does Verity Markup persist annotations? → A: Nowhere of its own. In the
  ground-truth context it writes `ground_truth_record` annotations; in the HITL context it
  writes per-field HITL overrides (FR-DL-007). Both via the governance API. There is no
  Verity-Markup-private store.
- Q: How does AI extraction call the model? → A: As a **governed executable invocation** (a
  `task`/`agent` run) producing a `decision_log` + `model_invocation_log` row — never a
  direct, unlogged model call. Confidence/reasoning are read from that decision.
- Q: Where does it run, given customer PDFs? → A: **Spoke-side / in the customer
  environment** when operating on customer documents; results flow to governance via the
  API. A hub-side mode is permitted only for synthetic/non-sensitive documents.
- Q: Whose identity annotates? → A: `core.actor` resolved server-side from the authenticated
  principal (D6); the PRD's `users` table is dropped.

---

## User Scenarios & Testing *(mandatory)*

User journeys are prioritized P1–P3, each independently testable. P1 is the core
evidence-capture loop (the reason the surface exists). P2 is AI-assisted extraction and the
two governance contexts it feeds. P3 is the document/page processing substrate and
schema-versioning resilience.

### User Story 1 — Capture field evidence by annotating a document (Priority: P1)

A labeler opens a source document and a target field schema side by side, selects a field,
draws a box (or selects text) over the value in the document, and the system captures an
**annotation** carrying the extracted text and a **source locator** (page, bbox,
`source_text`, `extraction_method`). The labeler can accept, override, clear, or comment on
any field; every field ends in an explicit, attributed, reviewed state.

**Why this priority**: Without document-anchored evidence capture there is no surface — this
is the minimum viable loop and the feature's whole point (visual provenance).

**Independent Test**: Load a digital PDF and a JSON-Schema field set, draw a box over a
value, confirm an annotation is created with the resolved text + page + bbox +
`extraction_method = user`, attributed to the acting actor; override the value and confirm
the original source locator is retained while the value changes.

**Acceptance Scenarios**:

1. **Given** a ready page and a selected field, **When** the labeler draws a bounding box
   over a value, **Then** an annotation is captured with `result.label` = the extracted
   text, a source locator `{page, bbox, source_text, extraction_method}`, `annotator_kind =
   human`, and the resolved actor/role — **appended**, never mutating any prior annotation on
   that field.
2. **Given** a digital page, **When** the labeler selects text instead of drawing, **Then**
   the selection's bounding box is computed and the same annotation shape is captured;
   text-selection MUST be disabled on `ocr` pages (draw-box only).
3. **Given** an annotated field, **When** the labeler overrides the value, **Then** a new
   annotation is appended with `extraction_method = user` carrying the corrected value and
   the retained source locator; the prior annotation remains in history.
4. **Given** an annotated field, **When** the labeler adds a comment, **Then** the comment is
   stored as the annotation's `explanation` (never a separate mutable note).
5. **Given** any field with at least one annotation, **When** the labeler opens its
   provenance, **Then** the corresponding bounding box on the document highlights and the
   panel shows page, bbox, `extraction_method`, score/confidence, annotator, and timestamp.
6. **Given** any caller, **When** they attempt to annotate without the authorizing action,
   **Then** the request is denied fail-closed and nothing is captured (FR-AUTHZ-001).

### User Story 2 — Assist with AI extraction and feed the right governance context (Priority: P2)

A labeler triggers AI extraction on unmapped fields; the system runs a **governed extraction
executable** that returns per-field value, source text, confidence, and reasoning; matched
values resolve to a source locator and appear as `annotator_kind = llm` annotations requiring
human validation. Depending on context, confirmed annotations land as **ground-truth labels**
(design-time) or **HITL overrides** (execution-time review of a decision).

**Why this priority**: AI assistance is the throughput multiplier, and binding it to the two
governance contexts is what makes the surface a governance tool rather than a viewer.

**Independent Test**: With several unmapped fields, trigger AI extraction; confirm a
`decision_log` + `model_invocation_log` row is produced for the run, that returned fields
appear as `llm` annotations with confidence + reasoning, that none require mutation of an
existing value, and that confirming them writes to `ground_truth_record` annotations (in
labeling context) or HITL overrides anchored by `decision_log_id` + `output_path` (in review
context).

**Acceptance Scenarios**:

1. **Given** unmapped fields, **When** AI extraction is triggered, **Then** a governed
   executable run is submitted (FR-RN-002), exactly one `decision_log` and one
   `model_invocation_log` row are produced (FR-DL-001/006), and the model is never called
   outside the governed path.
2. **Given** an AI result for a field, **When** its `source_text` matches a page-cache block,
   **Then** the annotation resolves a source locator (page + bbox); when no match is found,
   the annotation is captured **without** a locator and flagged "value found, evidence
   unlocated" rather than dropped.
3. **Given** AI-sourced fields, **When** the labeler reviews them, **Then** each carries a
   confidence-tiered indicator (≥0.85 high / 0.65–0.85 medium / <0.65 low) and Claude's
   reasoning as the annotation `explanation`, and **MUST require explicit human acceptance**
   before the record/decision can be marked complete (human-validates-machine, echoing
   [[0009-obligation-reasoning-ontology]]).
4. **Given** a field that already has any annotation (human or AI), **When** AI extraction
   runs, **Then** that field is **excluded** — AI never overwrites an existing value.
5. **Given** the labeling context, **When** an AI/human annotation is confirmed
   authoritative, **Then** it is written as the record's authoritative `ground_truth_record`
   annotation (FR-TV-003: exactly one authoritative annotation per record/field).
6. **Given** the review context (a real decision), **When** a human corrects a field,
   **Then** a per-field HITL override is written anchored by `decision_log_id` +
   `output_path` (FR-DL-007), additively, never mutating the decision row.
7. **Given** an AI extraction run, **When** the governed model path is unreachable, **Then**
   the run terminates as failed, no annotations are written, and the surface shows the failure
   without partial corruption.

### User Story 3 — Process documents and survive schema change (Priority: P3)

The system ingests documents through Verity's storage abstraction, processes pages (digital
text extraction or OCR), caches the result, and prefetches neighbours. When a target schema is
superseded, affected labeled records are re-validated and flagged for review rather than
silently breaking.

**Why this priority**: It is the substrate that makes Stories 1–2 work and keeps prior labels
trustworthy across schema evolution — valuable, but it presupposes the capture loop.

**Independent Test**: Register a document via the storage abstraction, navigate pages and
confirm per-page processing status transitions to `ready` with `method ∈ {digital, ocr}`;
publish a superseding schema version and confirm previously-`ready` labeled records are
re-validated and flagged (`flagged_low` still-valid / `flagged_high` now-invalid).

**Acceptance Scenarios**:

1. **Given** a document reference (provider/container/key per FR-TV-003), **When** a page is
   opened, **Then** the page is processed once and cached; `method` is auto-detected
   (`digital` vs `ocr`); already-cached pages are not reprocessed.
2. **Given** an open document, **When** a page is navigating, **Then** annotation tools are
   disabled until the page status is `ready`, and neighbour pages (±1 immediate, ±2
   background) are queued.
3. **Given** a labeled record bound to schema version N, **When** version N+1 is published,
   **Then** the record is re-validated against N+1: still-valid → flagged for low-priority
   review; now-invalid → flagged for high-priority review; with the flag reason recorded.
4. **Given** a flagged record, **When** the labeler resolves it, **Then** a new record version
   supersedes the prior one (`superseded_by` lineage, FR-TV-003), and the prior version is
   retained read-only.

### Edge Cases

- **Evidence unlocated:** an AI (or pasted) value with no matching document region is kept as
  an annotation with a null source locator and a "needs evidence" flag — never silently
  dropped and never fabricated to a bbox.
- **Scanned/illegible page:** OCR confidence is carried on the page-cache block and on the
  annotation score; low-confidence regions are visually marked.
- **Multi-region value:** a value spanning two boxes is captured as one annotation with an
  ordered set of source locators (not two competing annotations).
- **Adjudication disagreement:** two human annotators disagree on a field → both annotations
  coexist (append-only); resolution is an adjudicator annotation (`annotator_kind = human`,
  adjudicator role), per the ground-truth lifecycle — not a mutation.
- **Document residency:** a customer document MUST NOT be sent to a hub-side surface; the
  spoke-side surface is mandatory for customer data (FR-MK-026).
- **Context mismatch:** attempting to write a HITL override against a non-existent or
  non-terminal decision MUST be rejected (FR-DL-007 anchoring).

---

## Requirements *(mandatory)*

All MUST statements. Every operation is gated by the DB-managed action matrix and fails
closed ([[user-authentication]]); annotator identity and role are server-resolved (D6). The
annotation **tables and primitive shape** are owned by the governance schema and
[[0014-unified-annotation-and-feedback-model]]; this feature specifies the **surface
behaviour**, not new storage.

### Capability area: API boundary, identity & residency

- **FR-MK-001**: The surface MUST persist nothing of its own. All reads/writes go through the
  governance API (FR-API-001); there is no Verity-Markup-private database, identity table, or
  document store.
- **FR-MK-002**: Annotator identity MUST be the `core.actor` resolved from the authenticated
  principal; `annotated_by` / `mapped_by` MUST never be client-supplied.
- **FR-MK-003**: Every surface action MUST map to an action code and be authorized
  fail-closed. Labeling, adjudication, and HITL override are **distinct** authorizations (a
  labeler MAY annotate but not adjudicate; adjudication requires the adjudicator grant).
- **FR-MK-026**: When operating on **customer documents**, the surface and its page processing
  MUST run **spoke-side / in the customer environment**; results flow to governance via the
  API. A hub-side mode is permitted only for synthetic/non-sensitive documents. Document data
  classification (FR-RG-013) MUST gate which surface may load it.

### Capability area: Annotation & evidence capture (the primitive)

- **FR-MK-004**: A field annotation MUST conform to the unified primitive
  ([[0014-unified-annotation-and-feedback-model]]): a **target** (record+field in labeling
  context; `decision_log_id` + `output_path` in review context), an **annotator**
  (`annotator_kind` + actor/role), a **result** (`label` and/or `score` + `explanation`), and
  an optional **source locator**.
- **FR-MK-005**: The **source locator** MUST carry `{document reference, page, bbox,
  source_text, extraction_method}`, where `extraction_method` is the reference vocabulary
  `digital | ocr | auto | ai | user` (extensible as data, not DDL). A value MAY carry an
  ordered set of locators for a multi-region selection.
- **FR-MK-006**: Annotations MUST be **append-only**. Accept/override/clear/comment are all
  expressed as new appended annotations or status assertions; no annotation is mutated or
  deleted. "Current value" for a field is a projection over its annotations.
- **FR-MK-007**: The surface MUST support, per field: **accept** (assert the current
  annotation authoritative/confirmed), **override** (append a `user` annotation with a new
  value, retaining the prior source locator), **clear** (append a cleared-state assertion),
  and **comment** (append/extend the `explanation`).
- **FR-MK-008**: Drawing a bounding box or selecting text MUST resolve the underlying text
  from the page cache and return `{text, confirmed_bbox, score, extraction_method}`;
  text-selection MUST be available only on `digital` pages.
- **FR-MK-009**: Opening a field's provenance MUST highlight its source region(s) on the
  document and display page, bbox, `extraction_method`, score, annotator (kind + actor),
  timestamp, and (for AI) reasoning.

### Capability area: AI-assisted extraction (governed)

- **FR-MK-010**: AI extraction MUST run as a **governed executable invocation** (a
  `task`/`agent` run, FR-RN-002) over the document + the target field schema + the list of
  unmapped fields, producing exactly one `decision_log` and one `model_invocation_log` row
  (FR-DL-001/006). The surface MUST NOT call any model directly.
- **FR-MK-011**: AI extraction MUST run only on fields with **no existing annotation**
  (unmapped or explicitly cleared); fields with any human/AI value MUST be excluded and never
  overwritten.
- **FR-MK-012**: Each AI field result MUST yield an `annotator_kind = llm` annotation carrying
  value (`label`), confidence (`score`), reasoning (`explanation`), and — when `source_text`
  matches a page-cache block — a resolved source locator; an unmatched result is captured with
  a null locator and a "needs evidence" flag.
- **FR-MK-013**: AI-sourced annotations MUST require **explicit human acceptance** before the
  record/decision can be marked complete; the surface MUST tier confidence visually (high
  ≥0.85 / medium 0.65–0.85 / low <0.65) and expose the reasoning.
- **FR-MK-014**: AI extraction MUST be **asynchronous and resumable**: the run is tracked via
  governed run state (FR-RN-001/003), partial field results are committed as annotations as
  they complete (not held to the end), and the surface reflects progress on return/navigation;
  a model-path failure terminates the run without writing partial values.

### Capability area: Operating contexts (labeling vs review)

- **FR-MK-015**: In the **ground-truth labeling** context, confirmed authoritative annotations
  MUST be written as `ground_truth_record` annotations through the lifecycle `collecting →
  labeling → adjudicating → ready` (FR-TV-003), preserving **exactly one authoritative
  annotation per record/field**, with `annotator_kind ∈ {human, llm}` and the adjudicator role
  resolving disagreements.
- **FR-MK-016**: In the **execution HITL review** context, per-field corrections MUST be
  written as HITL overrides anchored by both the technical axis (`decision_log_id` +
  `output_path`) and the business axis (FR-DL-007), additively, never mutating the decision
  row, with the source locator carried where the original decision recorded one.
- **FR-MK-017**: The surface MUST make the active context explicit and MUST NOT allow a
  labeling annotation to be written against a decision target, or a HITL override against a
  ground-truth record.

### Capability area: Schema-driven form

- **FR-MK-018**: The target field set MUST be rendered from a **JSON Schema** that is the
  executable's output schema / target-binding shape (not a Verity-Markup-private schema
  table), supporting string, number, integer, boolean, date, and enum (dropdown) field types
  with inline validation.
- **FR-MK-019**: Required vs optional fields MUST be visually distinct, and the surface MUST
  show field-completion progress (e.g. "N of M fields annotated").
- **FR-MK-020**: Marking a record/decision complete MUST validate the assembled field values
  against the JSON Schema; a validation failure MUST block completion with a field-labeled
  reason list.

### Capability area: Document & page processing

- **FR-MK-021**: A document MUST be referenced through Verity's storage abstraction
  (provider/container/key per FR-TV-003); the surface MUST NOT assume a specific object store
  or local filesystem.
- **FR-MK-022**: Pages MUST be processed on demand, auto-detecting `digital` vs `ocr`, caching
  extracted text blocks with bboxes and per-block confidence; cached pages MUST NOT be
  reprocessed; neighbours (±1 immediate, ±2 background) SHOULD be prefetched.
- **FR-MK-023**: Annotation tools MUST be disabled on a page whose status is not `ready`, and
  the surface MUST show processing status without blocking interaction with already-ready
  content or the form.

### Capability area: Lifecycle, versioning & output

- **FR-MK-024**: A labeled record/review MUST follow draft → complete, with completed
  artifacts retained and **superseded** (not overwritten) on edit (`superseded_by` lineage,
  FR-TV-003); prior versions remain read-only and auditable.
- **FR-MK-025**: On target-schema supersession, affected completed records MUST be re-validated
  and **flagged** — still-valid → low-priority review; now-invalid → high-priority review —
  with the flag reason recorded; resolution creates a new superseding version.
- **FR-MK-027**: The surface MUST support producing a **dual-layer export** for a completed
  artifact — schema-compliant field values **plus** the per-field annotation provenance
  (source locators, methods, confidences, reasoning, annotator) — as a read-derived view over
  the governance store; it MUST NOT be a separate source of truth.

### Key Entities

This feature introduces **no new storage**; it operates over existing governance entities. For
reference:

- **Annotation** (owned by [[0014-unified-annotation-and-feedback-model]]): target +
  annotator(kind, actor) + result(label/score/explanation) + optional source locator;
  append-only.
- **Source locator** (new value object on the annotation): document ref, page, bbox,
  `source_text`, `extraction_method` (reference vocabulary). The feature's distinguishing data.
- **Ground-truth record / annotation** (FR-TV-003): the labeling-context target.
- **HITL override** (FR-DL-007): the review-context target.
- **Page cache** (processing substrate): per-document, per-page extracted blocks with
  bboxes/confidence and `method`; rebuildable, not a system-of-record.
- **Extraction executable + decision/model-invocation log** (FR-DL-001/006): the governed AI
  extraction path.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of AI extractions occur through the governed model path — every AI run has a
  corresponding `decision_log` + `model_invocation_log` row; zero direct model calls.
- **SC-002**: 100% of human/AI field values that are confirmed carry an attributed actor and
  (for document-sourced values) a resolvable source locator; values without evidence are
  explicitly flagged, never silently locator-less.
- **SC-003**: A reviewer can navigate from any annotated field to its highlighted evidence
  region in the document in a single action.
- **SC-004**: No annotation is ever mutated or deleted — corrections are 100% additive
  (verified by append-only audit).
- **SC-005**: 100% of customer-document processing runs spoke-side; no customer document is
  transmitted to a hub-side surface.
- **SC-006**: On schema supersession, 100% of affected completed records are re-validated and
  flagged (none silently broken).

## Assumptions

- The unified annotation primitive (ADR-0014) and its tables exist or are delivered alongside;
  this feature consumes them and does not define storage.
- Ground-truth datasets, validation runs, HITL overrides, and the decision log (001 FR-TV/
  FR-DL) are available through the governance API.
- The extraction executable is a governed `task`/`agent` registered through the registry; the
  surface invokes it, it is not bespoke to this feature.
- Browser-side rendering/canvas is a thin client over the governance API; all algorithmic work
  (extraction, OCR, matching, validation) is server-side and governed.
- Out of scope (carried from the PRD, plus Verity deltas): a schema-builder UI, real-time
  multi-user collaboration on one document, mobile support, and any standalone Docker-Compose
  deployment — the surface ships within the hub portal and/or as a spoke-side companion per
  [[0011-repository-topology-and-harness-release-boundary]].

---

## Disposition — PRD construct → Verity-native form

| PRD construct (standalone "Verity Markup") | Disposition | Verity-native form |
|---|---|---|
| `users` table | DROP | `core.actor` + role grants (D6) |
| `documents` table + MinIO key | CHANGE | document reference via storage abstraction (provider/container/key, FR-TV-003) |
| `schemas` / `schema_versions` | CHANGE | executable output schema / target-binding (JSON Schema), versioned in the registry |
| `annotations` table (data + provenance blobs) | CHANGE | unified annotation primitive (ADR-0014); ground-truth annotation (labeling) / HITL override (review) |
| `provenance.method` enum | KEEP (as reference data) | `reference.extraction_method` vocabulary (`digital/ocr/auto/ai/user`) |
| per-field `bbox` provenance | KEEP (elevated) | **source locator** value object on the annotation — the feature's differentiator |
| `ai_tasks` table + direct Claude calls + token tracking | CHANGE | governed executable run → `decision_log` + `model_invocation_log` (FR-DL-001/006); run state via FR-RN-001 |
| draft/complete/flagged status + `parent_id` versioning | CHANGE | record version supersession (`superseded_by`, FR-TV-003); flag-on-schema-change |
| schema-diff flagging | KEEP | re-validation + flagging on target-schema supersession (FR-MK-025) |
| dual-layer JSON export | KEEP | read-derived export over governance store (FR-MK-027), not a separate SoR |
| Docker-Compose / Postgres / MinIO standalone stack | DROP | hub portal + spoke-side companion; API-only; k8s/Helm ([[0011-repository-topology-and-harness-release-boundary]]) |
| no roles / all users equal | CHANGE | action-matrix authorization; labeler / adjudicator / HITL-override as distinct grants |

> **When scheduled** (not now): assign the next free Spec Kit feature number, run
> `/speckit.plan` scoped to this doc to produce `plan.md` + `data-model.md` (confirming the
> source-locator schema and the `reference.extraction_method` seed), then `/speckit.tasks`.
> The annotation primitive tables are a prerequisite owned by the governance schema work
> ([[0014-unified-annotation-and-feedback-model]]) and by the registry/compose/harness slices
> that precede this feature.
</content>

# ADR-0014 — Unified annotation & feedback model (ground-truth labeling, HITL override, judge scores) with document-anchored provenance

- **Status:** Accepted
- **Date:** 2026-06-04
- **Deciders:** Product Owner (Anil)
- **Related:** [[0013-evaluation-observability-tooling-boundaries]], [[0003-harness-governance-api]],
  [[0004-storage-architecture]], [[0007-decision-log-scale-and-portable-analytics]],
  [[0008-compliance-control-evidence-model]], [[0009-obligation-reasoning-ontology]],
  [[0011-repository-topology-and-harness-release-boundary]]

---

## Context

Three closely-related "someone (or something) assessed this" facts are modelled separately
across the metamodel:

- **Ground-truth annotation** — design-time labels on a `ground_truth_record`, accruing through
  the `collecting → labeling → adjudicating → ready` lifecycle with silver/gold quality tiers
  and inter-annotator agreement.
- **HITL override** — execution-time, per-field human correction of a decision, anchored by
  `decision_log_id` + `output_path`, additive and non-mutating.
- **Judge / metric scores** — LLM-as-judge and heuristic scores produced by the embedded
  evaluation library ([[0013-evaluation-observability-tooling-boundaries]]).

These are the **same primitive**: a typed assessment of a target (a record, a decision, a field)
by an annotator (a human, an LLM, or a deterministic evaluator), carrying a label and/or score
and an explanation. Modelling them three different ways duplicates the identity, provenance,
append-only-audit, and idempotent-ingest plumbing, and invites drift.

Two external inputs sharpened the design:

1. **Phoenix's annotation model** — typed annotation *configs* (categorical / continuous /
   freeform, each with a direction); a unified `annotator_kind` (HUMAN / LLM / CODE); a
   `result` shape of `{label, score, explanation}`; append-with-identifier semantics so many
   annotators coexist on one target; and annotation *queues* with multi-annotator disagreement
   surfacing in the UI. (Phoenix deliberately has **no** formal adjudication — it leans on
   filter-and-export.)
2. **The "Verity Markup" PRD** — a document-extraction surface that captures, per field, a
   provenance record including `method` (digital / ocr / auto / ai / user), confidence,
   reasoning, comment, and — distinctively — a **bounding box into the source document**, with
   accept / override / clear review actions and confidence tiering. As a standalone app it
   ships its own `users` / `documents` / `schemas` / `annotations` / `ai_tasks` metamodel and
   direct model calls, which conflict with the actor model (D6), the decision-log
   system-of-record ([[0004-storage-architecture]]), and the API-only governed model path
   ([[0003-harness-governance-api]]) — the same "second store / second metamodel" hazard called
   out for third-party platforms in [[0013-evaluation-observability-tooling-boundaries]].

This ADR unifies the three facts under one primitive, adopts the useful Phoenix structure, and
makes **document-anchored visual provenance** a first-class (optional) extension — while keeping
Verity's richer adjudication/quality-tier lifecycle, which Phoenix lacks.

## Decision

**Model human labels, LLM-judge scores, deterministic-metric scores, and HITL field overrides
as one append-only annotation primitive — distinguished by annotator kind and target — and
extend it with optional document-anchored provenance.**

1. **One annotation primitive.** A single conceptual shape — an append-only *annotation* fact —
   covers all four cases. An annotation has a **target** (e.g. `ground_truth_record` + field, or
   `decision_log_id` + `output_path`, or an execution run), an **annotator**, a **result**
   (`label` and/or `score` + `explanation`), and **metadata**.

2. **Typed annotation configs, not enums.** A `result`'s shape is governed by an annotation
   *config*: **categorical** (a defined value-set), **continuous** (a numeric range with a
   maximize/minimize/none direction), or **freeform** (text). Value-sets, kinds, and direction
   live in **reference tables** (D1 — values are data, not DDL). The **explanation is always
   carried** — for a regulator, "flagged, and here is why" is the point.

3. **Annotator is an actor (D6), server-resolved.** Every annotation records the
   `annotator_kind` (`human` / `llm` / `code`, a reference vocabulary) and the resolved actor +
   role — never client-supplied. LLM and code annotators are **automation actors** under the
   existing unified actor model, so a judge's score and a human's label are attributable the
   same way.

4. **Append-only and idempotent.** Annotations are additive facts; they **never mutate the
   target** (preserving decision-log immutability — [[0007-decision-log-scale-and-portable-analytics]]).
   Many annotators coexist on one target; "current"/"resolved" is a projection. An
   **identifier / idempotency key** makes ingest retry-safe (pairs with the
   `write_idempotency_key` of [[0003-harness-governance-api]]); we adopt Phoenix's
   same-name-different-identifier coexistence semantics for dedupe, but the **underlying store
   stays append-only** (an in-UI "edit" appends a new annotation, it does not overwrite).

5. **Two lifecycle contexts share the primitive.**
   - **Design-time ground-truth labeling** — annotations accrete on a `ground_truth_record`
     through `collecting → labeling → adjudicating → ready`, with silver/gold quality tiers and
     inter-annotator agreement. **Verity keeps its adjudication lifecycle** (Phoenix has none);
     Phoenix contributes only the queue/config/disagreement UX.
   - **Execution-time HITL + automated scoring** — HITL field overrides and judge/metric scores
     are annotations on a `decision_log` row + `output_path`, additive and non-mutating
     (restating the HITL model and [[0013-evaluation-observability-tooling-boundaries]] §2/§5).

6. **Document-anchored provenance — first-class, optional extension.** An annotation MAY carry a
   **source locator**: `{document ref, page, bbox, source_text, extraction_method}`, where
   `extraction_method` (`digital` / `ocr` / `auto` / `ai` / `user`, …) is a reference vocabulary.
   This makes "show me the evidence for this value" a **visual click into the source document** —
   an explainability/audit differentiator that complements the decision log's
   `source_resolutions`. Required for document-extraction use cases; optional elsewhere.

7. **Governed model path for LLM annotators.** Any LLM annotation — a judge *or* AI
   document-extraction — runs through the **governed inference path** and is logged as a
   `model_invocation` ([[0003-harness-governance-api]], [[0013-evaluation-observability-tooling-boundaries]]);
   never a free-standing external call with its own token tracking. Where customer data is
   involved, the annotation/extraction surface runs **spoke-side or in the customer
   environment**, and results flow to governance **via the API**.

8. **Adopt the Phoenix UX patterns, in the Verity portal.** Annotation **queues / work-lists**
   for labeling and adjudication; **multi-annotator disagreement** surfacing; **confidence-tiered
   review** (accept / override / clear / comment). These are surfaced in the **Verity portal**;
   business / governance / audit users see only the portal (consistent with
   [[0013-evaluation-observability-tooling-boundaries]] §4).

9. **Scope & phasing.** The commitment here is the **primitive + the two contexts + the optional
   document provenance**. The document-extraction surface (re-authored from the Verity Markup
   PRD) is a **portal module / spoke-side companion**, scoped first to underwriting intake /
   `app-alpha`. Exact tables, the annotation-config reference set, and the source-locator schema
   are confirmed in the testing/validation and annotation **component/feature specs** — the
   binding decision here is the *unification and the provenance extension*, not the table DDL.

## Consequences

**Positive**
- One identity, provenance, append-only-audit, and idempotent-ingest path serves labeling,
  HITL, and judge scores — no triplicated plumbing, no drift.
- A human label, an Opik judge score, and a heuristic metric are *the same fact* with different
  `annotator_kind` — so disagreement, agreement, and "human-validates-the-machine" (echoing the
  recommend→validate seam of [[0009-obligation-reasoning-ontology]]) fall out naturally.
- Document-anchored provenance turns the audit story from a query into a click — a genuine,
  regulator-facing differentiator nothing in Opik/Phoenix offers.
- Verity Markup's value is captured **without** importing its standalone metamodel or its
  direct model calls; it becomes a governed portal capability.

**Negative / costs**
- A generalization pass over the existing `ground_truth_annotation` / HITL-override tables and
  new reference vocabularies (annotation kind, annotator kind, extraction method) to author.
- The document-extraction surface (PDF render, OCR, canvas, schema-driven form) is real
  build effort, and running it spoke-side adds a customer-environment deployment surface.
- Carrying explanations and source locators on every annotation increases write volume on the
  audit tier (latency-tolerant per [[0004-storage-architecture]], but real).

## Alternatives considered

- **Keep three separate models** (`ground_truth_annotation`, HITL override, judge scores).
  *Rejected* — they are the same fact; separate models duplicate identity/provenance/audit
  plumbing and drift apart.
- **Adopt the Phoenix / Verity-Markup metamodels as-is.** *Rejected* — a second store plus its
  own identity, provenance, and direct-model-call path conflict with the actor model (D6), the
  decision-log SoR, and API-only ([[0003-harness-governance-api]]); re-author the concepts onto
  Verity's metamodel instead (same lesson as [[0013-evaluation-observability-tooling-boundaries]]).
- **Mutable, editable/deletable annotations** (Phoenix's UI default). *Rejected* for the
  system-of-record — annotations are append-only facts; "current" is a projection and an edit is
  a new appended annotation.
- **Phoenix-style filter-and-export instead of adjudication.** *Rejected as the process* — keep
  Verity's adjudication / inter-annotator-agreement / silver-gold lifecycle; borrow only the
  queue/disagreement UX.

## Notes

This relates to D1 (reference/SKOS vocabularies for the new kinds), D6 (actor for every
annotator), [[0007-decision-log-scale-and-portable-analytics]] (append-only immutability),
[[0009-obligation-reasoning-ontology]] (the recommend→human-validate seam, which the
human-validates-machine-annotation flow mirrors), and [[0013-evaluation-observability-tooling-boundaries]]
(judges *are* annotations). The Verity Markup PRD is re-authored into a Spec Kit feature spec on
this primitive — it is currently written for a standalone Docker-Compose app, which conflicts
with the k8s / contract topology of [[0011-repository-topology-and-harness-release-boundary]].
Much of this is generalization of existing HITL-override and ground-truth-annotation structure
rather than net-new schema; the component spec confirms the final tables.
</content>

# ADR-0009 — Obligation determination & evidence mapping via ontology + reasoning (human-validated, relational system-of-record)

- **Status:** Accepted
- **Date:** 2026-05-31
- **Deciders:** Product Owner (Anil)
- **Related:** [[0008-compliance-control-evidence-model]], [[0004-storage-architecture]],
  [[0005-schema-hardening]], [[0003-harness-governance-api]]

---

## Context

[[0008-compliance-control-evidence-model]] establishes the three-axis model: regulatory
frameworks/provisions → canonical requirements (in governance domains, with cumulative tier
ladders) → controls + evidence. Two hard questions sit on top of it:

1. **Obligation determination** — given an intake's attributes (risk tier, governance
   domains, data classification, jurisdiction…), *which* canonical requirements apply, and
   *at what target tier*?
2. **Evidence mapping** — which captured artifacts (decision logs, model cards, test
   results, deployment records) satisfy which obligation, at which phase?

These are knowledge-and-inference problems. Encoding them only as imperative code is
brittle, hard to explain to an examiner, and does not scale across many overlapping
frameworks. The product direction is to model the regulatory knowledge as an **ontology**
and use a **reasoner** to *infer* obligations and *recommend* evidence mappings, and to
allow **SPARQL** queries across the governance data — while the hardened relational schema
([[0005-schema-hardening]]) remains the auditable system-of-record ([[0004-storage-architecture]]).

This ADR decides how the semantic layer relates to the relational store. (RDF = data as
`subject–predicate–object` triples; ontology/OWL = the classes, properties, and logical
axioms; a reasoner infers new triples from the axioms; SPARQL = the query language for the
graph. SKOS = the standard for code-lists/taxonomies with broader/narrower relations.)

## Decision

Adopt a **layered architecture**: relational system-of-record, a semantic access/derivation
layer on top, and a human-validated write-back loop.

1. **PostgreSQL remains the system of record.** Governance data is never primarily stored in
   a triplestore. The graph is a *view of* and a *reasoner over* the relational SoR, not a
   competing store. (Governance cannot be eventually-consistent or lose FK integrity/audit.)
2. **SPARQL access = a virtual knowledge graph (OBDA/R2RML).** A mapping exposes the
   `core` / `reference` / `compliance` (metamodel) tables as a virtual RDF graph; SPARQL is
   translated to SQL at query time — **no data duplication**, with lightweight (OWL 2 QL)
   reasoning.
3. **Heavy reasoning = an optional triplestore/reasoner used as a *derivation engine*.** It
   loads the metamodel + the intake's attributes, runs the full reasoner, and **recommends**
   the obligation set and evidence mappings. Recommendations are **written back to Postgres**
   with provenance.
4. **Human-validated write-back (hard rule).** The reasoner **never auto-commits** an
   obligation or mapping as authoritative. It *recommends*; a human *validates*
   (`mapping_source`/`derivation_method = human_validated`); only then is it an authoritative
   SoR record. The **derivation chain is captured** (which axioms/provisions led to each
   obligation) so every result is **explainable under examination**.
5. **Scope.** Reasoning and SPARQL target the **metamodel** (`core` / `reference` /
   `compliance` + resolved obligations and evidence *summaries*) — **not** the raw
   high-volume `audit` logs (those stay relational/columnar per [[0004-storage-architecture]]).
6. **Engine choice is deferred** to the compliance/reasoning component spec (the virtual-KG
   engine, e.g. Ontop; the triplestore/reasoner, e.g. Stardog/GraphDB/Jena). The binding
   decision here is the *layering and the human-validated seam*, not the product — mirroring
   ADR-0004's "reference choice, not a hard commitment."

**Database implications adopted now** (most are free given the hardening + design rulings):

- **Stable IRIs** for every row, derived from `schema.table.<uuid>` and reference `code`s — a
  documented URI scheme; no schema change (UUID PKs + reference codes already provide them).
- **Generalized provenance** on reasoner-derivable records (obligations, provision↔requirement
  and requirement↔control mappings, evidence↔obligation links): `derivation_method`
  (`manual` / `reasoner_recommended` / `human_validated`), `ontology_version`, `confidence`,
  `validated_by_actor_id` (actor per D6). This generalizes the existing `mapping_source`.
- **Reference tables are SKOS vocabularies** — `parent_code` is `skos:broader`/`narrower`,
  `sort_order`/`label` carry over. No change; documented alignment.
- **Relations stay explicit** (no catch-all JSON where a relation belongs) — already a
  hardening rule; it is what makes the relational→RDF mapping clean.
- **Ontology versioning** (a small `ontology_version` reference) so a derivation is
  reproducible as-of; pairs with the compliance-model effective-dating (D7) for true as-of
  obligation resolution.

## Consequences

**Positive**
- Reasoning + SPARQL are achievable with **very little new schema** — the hardening,
  reference-table (SKOS), actor, and effective-dating decisions already made the data clean,
  globally-identifiable, and temporally-resolvable.
- **Explainable** obligation determination (axiom chains + provenance) — defensible under
  regulatory examination, which a black-box would not be.
- The relational SoR keeps FK integrity, audit, and every other consumer; the semantic layer
  is additive and the engine is swappable behind the seam.
- A genuine product differentiator (semantic compliance) without betting the SoR on it.

**Negative / costs**
- An R2RML/ontology mapping to author and maintain; if a triplestore is used, a
  derivation/sync pipeline plus the human-validation workflow.
- Ontology authoring is a specialized skill; axiom errors mis-derive obligations (mitigated
  by the mandatory human-validation gate and explainability).
- SPARQL-over-translated-SQL needs performance care; scope discipline (no reasoning over raw
  logs) must be enforced.

## Alternatives considered

- **Triplestore as the system of record.** *Rejected* — loses FK integrity, the audit trail,
  and the relational design; governance records cannot be eventually-consistent.
- **Hardcoded rules only.** *Rejected as the sole model* — brittle and not explainable as a
  knowledge model across many frameworks. (Rules remain a valid *first implementation* under
  the same recommend→validate seam, before a full ontology is warranted.)
- **Postgres-native graph (Apache AGE).** *Rejected for this purpose* — AGE is openCypher /
  property-graph, **not** RDF/SPARQL, and has no standard OWL reasoner.
- **LLM-only obligation determination.** *Rejected as the authority* — not deterministically
  explainable. An LLM may *assist* recommendation under the same human-validated seam
  (consistent with `mapping_source = semantic_recommended`).

## Notes

Phasing: start with **rule/LLM recommendation + human validation over the relational model**
(already supported by `mapping_source`); add the **virtual KG** for SPARQL; introduce a
**triplestore reasoner** if/when axiom complexity justifies it. The component spec confirms
the engines, the IRI scheme, and the ontology itself. The DB implications above are inputs to
the schema re-apply (provenance columns + `ontology_version`), and relate to the design
decisions register (D1 reference/SKOS, D6 actor for `validated_by`, D7 effective-dating for
as-of reasoning).

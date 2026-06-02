# ADR-0005 — Schema hardening is the top-priority concern

- **Status:** Accepted
- **Date:** 2026-05-29
- **Deciders:** Product Owner (Anil)
- **Related:** [[0001-rebuild-vs-refactor]], [[0004-storage-architecture]]

---

## Context

v1's 81-table schema is correct and complete, but it accreted over time: naming is
inconsistent across tables and columns, some structures carry tech debt from earlier
iterations, and transactional tables mix append and update patterns. The PCR assumed
v1's `schema.sql` would be carried forward *verbatim* as canonical. The product
direction overrides this: **the schema is the foundation of everything, so it must be
hardened, not inherited as-is.** This is the single highest-priority concern for v2.

## Decision

Treat v1's schema as a **reference input to a clean redesign**, not as the canonical
artifact. The hardened v2 schema is governed by these rules:

1. **Consistent naming.** One naming convention applied uniformly across tables,
   columns, enums, indexes, foreign keys, and views. No legacy inconsistencies carried
   forward (e.g. the v1 binding terms are renamed for consistency — see the binding
   grammar contract).
2. **Proper structure.** Every table has a clear primary key, explicit and named
   foreign keys, correct types, NOT NULL where warranted, and check constraints that
   encode real invariants. No catch-all JSON where a relation belongs (and vice versa).
3. **Insert-only / append-only transactions.** Transactional records are appended, not
   mutated in place; current state is a view over the latest event
   (per [[0004-storage-architecture]]). The v1 event-sourced run model is the pattern
   to generalize.
4. **Tiering aware.** The schema distinguishes Tier-1 system-of-record tables from
   Tier-2 bulk-log tables ([[0004-storage-architecture]]) so the split is explicit in
   the model, not an afterthought.
5. **No silent capability loss.** Every governance capability, constraint, and view in
   v1 maps to a v2 equivalent or is explicitly recorded as dropped-with-reason in the
   v1-capability-inventory. Schema hardening must not quietly lose behavior — the same
   "lost in translation" guard that applies to the code applies to the schema.

The hardened schema is itself a reviewed spec artifact (`specs/schema/`), produced by
auditing v1 table-by-table against these rules, with the v1 SQL and the v1 test suite as
the behavioral reference.

## Consequences

**Positive**
- The foundation is clean; downstream services aren't building on inconsistent ground.
- Naming consistency makes the API, the models, and the SQL far easier to reason about.
- Insert-only + tiering are designed in, not retrofitted.

**Negative / costs**
- Schema work is front-loaded and gates implementation — by design, since everything
  depends on it.
- Every rename ripples into models, queries, and API field names; the
  v1-capability-inventory + traceability links are how we keep the mapping honest.
- Risk of *over*-redesign. Mitigation: hardening means consistency/structure/insert-only,
  **not** re-imagining the governance metamodel. The lifecycle (since amended to 6 states —
  shadow folded into a challenger run-mode; see ADR-0006), decision log,
  entity model, and I/O grammar keep their semantics; only their expression is cleaned.

## Alternatives considered

**Carry v1 schema verbatim (PCR's original stance).** *Rejected* — it imports the
naming inconsistencies and tech debt that motivated the rebuild, onto the most
load-bearing layer.

**Incrementally clean the schema during feature work.** *Rejected* — piecemeal renames
across a live schema reproduce the v1 churn this rebuild exists to escape. The schema is
hardened up front as a reviewed artifact.

# ADR-0007 — Decision-log scale and customer-portable analytics

- **Status:** Accepted
- **Date:** 2026-05-30
- **Deciders:** Product Owner (Anil)
- **Related:** [[0004-storage-architecture]], [[0003-harness-governance-api]],
  [[0005-schema-hardening]], [[0002-execution-model]]

---

## Context

[[0004-storage-architecture]] set the two-tier shape — thin Postgres system-of-record
(Tier-1) plus a columnar bulk-log store (Tier-2, reference: Iceberg on object storage +
DuckDB), insert-only, all behind the governance API — and deliberately left the query
**engine** as a non-binding reference choice. This ADR extends it for the scale and
portability requirements that the distributed, multi-application model
([[0002-execution-model]]) imposes:

- **Many writers.** Every application's harness writes decision logs and
  model-invocation logs concurrently; the write path must absorb high, bursty,
  multi-tenant volume.
- **Many readers, latency-tolerant.** The UI's decision-log detail can tolerate latency;
  reports can run as asynchronous jobs. Neither analytics read is on the live invocation
  or status path.
- **Cost-efficiency and scale** are explicit goals for this tier.
- **Customer data portability.** Customers must be able to port their reporting data into
  **their own data warehouse** (Snowflake / BigQuery / Redshift / Databricks / …).

## Decision

**Commit to the analytics *seam* and the *portable format*; leave the query engine an open
decision.** Concretely, extending [[0004-storage-architecture]]:

1. **Canonical decision log is the append-only audit truth.** Decision and
   model-invocation logs are append-only and written via the governance API's
   **batched/async ingest** ([[0003-harness-governance-api]]) so many concurrent app
   writers never bottleneck on a synchronous hop. This is the system-of-record for audit.
2. **Analytics is a separate read tier, never in the status/invocation path.** UI detail
   reads tolerate latency (canonical log or a near-real-time projection); reporting runs
   as asynchronous **jobs** against the analytical tier (consistent with PCR §3.4 — "the
   analytics store is never in the status path").
3. **Portable columnar substrate.** The analytical tier persists logs in an **open
   columnar format — Apache Iceberg / Parquet on object storage** — which is cheap,
   horizontally scalable, and engine-agnostic. ADR-0004 already named this Tier-2; this
   ADR makes the open format the **portability contract**, not just an implementation
   detail.
4. **Customer-portable export seam.** Verity provides a documented export path so a
   customer lands their own decision/reporting data in their warehouse — either by reading
   the open Iceberg/Parquet tables directly or via a CDC/export job. The binding contract
   is the pipeline shape: **canonical append-only log → columnar analytics projection →
   portable export.** The **query/reporting engine remains an open decision**
   (DuckDB / Trino / ClickHouse / warehouse-native), confirmed in the storage & reporting
   component spec.

## Consequences

**Positive**
- Object-storage + columnar compression keeps the high-volume tier cost-efficient and
  independently scalable from the system of record.
- Read and write scale decouple: async ingest for writers, job-based analytics for
  readers, neither touching the invocation path.
- Customer warehouse portability becomes a product differentiator and is designed in via
  the open format, not bolted on per-customer.
- The query engine stays swappable behind the seam.

**Negative / costs**
- An export seam plus per-tenant isolation of exported data is real work to build and
  secure.
- The export schema/format becomes a **contract customers depend on** — it must be
  versioned and evolved compatibly.
- Two stores to keep consistent (inherited from [[0004-storage-architecture]]); "current
  state" remains a projection.

## Alternatives considered

- **Single Postgres for analytics too.** *Rejected* — does not meet the cost/scale target
  at multi-application volume and is awkward to port into customer warehouses.
- **Proprietary analytics engine with no open format.** *Rejected* — defeats customer
  portability, which is a committed capability here.
- **Bespoke per-customer export pipelines.** *Rejected* — not scalable; standardize on the
  open Iceberg/Parquet substrate and a single documented export seam.

## Notes

This ADR does not re-decide the Tier-1/Tier-2 split or insert-only model — those are
[[0004-storage-architecture]]. It adds the multi-tenant scale framing, the
reporting-as-jobs read model, and the **customer-portable export** commitment. Engine
selection is tracked as an open decision and resolved in the component spec; portability
itself is committed, not deferred.

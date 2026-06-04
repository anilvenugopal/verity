# contract/ — the hub↔harness contract (the linchpin)

The single versioned contract between the hub and everything that talks to it. **This is the
only component other components may depend on** (ADR-0011 import-boundary rule).

Owns:
- `gateway-openapi.yaml` — OpenAPI 3.1 for the **Harness Gateway API** (register, claim,
  release, heartbeat, ack) and the portal API surface.
- `nats/` — JSON Schemas for the NATS payloads (`verity.runs.pending`,
  `verity.cluster.{id}.commands`, `verity.events.{run_id}`, heartbeats).
- `package/` — the `.vtx`/`.vax` package-manifest schema.
- (later) generated clients/SDKs published as a versioned package.

Rules:
- Hub-owned (governance is the authority — ADR-0003); `hub/`, `harness/`, `app-alpha/` consume
  a **pinned** version.
- A breaking change is a versioned bump; **contract tests run on both sides** so drift fails CI.

Status: skeleton (Phase 2). See [ADR-0010](../specs/adrs/0010-harness-runtime-federated-coordinator.md),
[ADR-0011](../specs/adrs/0011-repository-topology-and-harness-release-boundary.md).

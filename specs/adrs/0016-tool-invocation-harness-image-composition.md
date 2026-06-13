# ADR-0016 — Tool invocation routing and harness image composition

- **Status:** Accepted
- **Date:** 2026-06-09
- **Deciders:** Product Owner (Anil)
- **Related:** [[0002-execution-model]], [[0003-harness-governance-api]],
  [[0006-packages-and-governed-deployment]], [[0010-harness-runtime-federated-coordinator]],
  [[0011-repository-topology-and-harness-release-boundary]],
  [[0015-message-broker-dispatch-invocation]]

---

## Context

[[0010-harness-runtime-federated-coordinator]] and [[0015-message-broker-dispatch-invocation]]
fix how work reaches the harness and how the application gets results back. Neither addresses
what happens inside the worker during execution when Claude produces a `tool_use` block.

Tool call execution is **synchronous on the critical path**: the worker must execute the
tool and return the result before the next model call. Tool latency is execution latency.
The harness must therefore have a complete, correct answer to:

1. Where do tool implementations live — inside the harness image, inside the package
   (`vtx`/`.vax`), or in the application's own services?
2. How does the harness know which tools it is allowed to call, and what prevents it from
   calling tools the package did not declare?
3. How does the worker resolve *where* an application-side tool is at runtime, without
   holding a registry credential mid-run?
4. What components must the harness image contain, and what are the versioning
   consequences?

These are the questions this ADR closes.

---

## Decision

### 1. Three tool categories with different execution homes

Tool calls fall into three categories. The harness handles all three, but the
**implementation** of each lives in a different place.

**Category A — Application-side tools (MCP servers)**

Business logic tools (`lookup_policy`, `query_underwriting_data`, `get_customer_profile`,
etc.) are implemented by the application team. They run as **MCP servers** in or alongside
the application's own cluster — not inside the harness image and not inside the
`.vtx`/`.vax` package. The harness contains an **MCP protocol client** that routes
`tool_use` requests to the registered MCP server and returns the result to Claude. The
harness does not implement the tool; it is a protocol router.

MCP servers are **registered entities in the governance metamodel** (Phase 2 — Registry
& Compose). A package's `tool_authorizations` in the manifest declares which registered
MCP servers — and which specific tools within them — the package is permitted to call.
The harness enforces this at runtime (§2).

The hub is **not in the path** for Category A tool calls. Traffic is in-cluster (or
within the application's network): worker → MCP server → application services → back. No
governance hop.

**Category B — Standard connectors (harness image)**

Common data-access patterns — SQL queries against a declared connector, REST calls
against a declared API binding, object store reads — are implemented as a **connector
framework** baked into the harness image. The package's `source_binding` and `write_target`
declarations govern which connectors are active and with what parameters. Credentials
follow the Model B pattern ([[0010]] §7): the hub stores the credential name and
verification status only; the value lives in the application's secrets manager and is
injected into the worker pod at startup via ESO/k8s Secret.

The hub is not in the path for Category B tool calls.

**Category C — Governance tools (built-in, always present)**

These run inside the harness, are not configurable by the package, and are not callable
by Claude via `tool_use`:

- **Write-target suppressor** — enforces shadow/challenger read-only mode; suppresses
  Target Binding writes when the package's lifecycle state requires it ([[0006]]).
- **HITL override detector** — detects and pauses execution awaiting a human override
  decision.
- **Decision log assembler** — accumulates the canonical decision record throughout the
  run.
- **Quota enforcer** — checks the coordinator-local SQLite quota cache before each model
  call.

Category C components add no per-tool-call hub traffic.

### 2. Tool authorization enforcer is a mandatory harness gate

Before the worker executes any tool call (Category A or B), the **tool authorization
enforcer** checks the call against the `tool_authorizations` section of the loaded
`.vtx`/`.vax` manifest:

- Is this tool registered for this package?
- Is the specific tool name within the MCP server's authorized scope?
- Does the connector match a declared `source_binding` or `write_target`?

If the check fails, **the harness refuses the call and returns an authorization error to
Claude** — it does not execute the tool regardless of what the model requested. This gate
is non-bypassable: it runs before any network call is made.

This is a security and governance control: a model cannot be prompted into calling a tool
the package governance did not authorize, even if the model generates a well-formed
`tool_use` block for it.

### 3. MCP endpoint resolution at claim time, not at tool-call time

The coordinator, when claiming a run, calls the Hub Gateway API to resolve **which MCP
servers are registered for this package in this cluster**. The gateway returns the MCP
server endpoint list alongside the run's job details. The coordinator injects this
configuration into the worker at dispatch time.

The worker holds the resolved endpoint list for the duration of the run. It does not
make registry lookups mid-run. This keeps the hub out of the per-tool-call hot path and
makes tool routing deterministic for the life of a single run — the endpoint list cannot
change under a running job.

### 4. Connector versioning is harness image versioning

The connector framework is baked into the harness image. A package that declares a SQL
connector gets the SQL connector implementation that ships with the harness image it runs
on. Package×image compatibility ([[0006]]) implicitly gates connector availability: if a
package requires a connector type not present in the pinned harness image, the image
compatibility check at deploy time rejects the combination.

Adding a new connector type requires:
1. A new harness image version containing the connector.
2. A new compatibility record in the governance metamodel.
3. A `patch` command (Deployment roll, not `deploy_package`) to update running clusters.

This is intentional: connector implementations are versioned and auditable. A run's exact
connector behaviour is reproducible by running the same package on the same image digest
— consistent with the audit-replay requirement ([[0006]] §2).

### 5. Harness image composition

The harness image ([[0011]] §1 — one image, role by config) must contain:

| Component | Purpose |
|---|---|
| **Anthropic SDK** | Claude API calls (model invocation) |
| **Model reference chain resolver** | Walks `inference_config_model` by priority at run time; on exhausted retries against priority-N, tries priority-N+1; see ADR-0019 |
| **MCP protocol client** | Routes Category A tool calls to registered MCP servers. `stdio` is the v1-ported transport; `sse` and `http` are net-new scope required for cluster-deployed MCP servers per §4 topology — not present in v1 |
| **Connector framework** | Category B: SQL, REST, object store connectors |
| **Tool authorization enforcer** | Gate on every tool call against `tool_authorizations` |
| **Write-target suppressor** | Category C: enforces shadow/challenger Target Binding suppression |
| **HITL override detector** | Category C: pause execution for human review |
| **Decision log assembler** | Category C: accumulates the canonical governance record |
| **Quota enforcer** | Category C: checks coordinator-local quota cache |
| **Coordinator process** | Leader election, dispatch, command handling (VERITY_ROLE=coordinator) |
| **Worker process** | Claim, execute, report (VERITY_ROLE=worker) |
| **Operator process** | k8s Deployment lifecycle (VERITY_ROLE=operator; on Linux, merged into coordinator) |

These are all load-bearing components whose versions are tied to the image digest. A
package manifest that pins an image digest by implication pins the exact version of every
component on this list.

---

## Consequences

**Positive**
- The hub is completely absent from the tool-call hot path. Tool latency is pure
  application + LLM latency, with no governance overhead.
- The tool authorization enforcer provides a hard governance gate that cannot be
  circumvented by model behaviour.
- MCP is an open standard; the application team authors MCP servers in any language and
  framework without coupling to Verity internals.
- Connector versioning through image versioning gives reproducible audit replay ([[0006]]
  §2): the same image digest on replay means the same connector behaviour.
- MCP endpoint resolution at claim time, not per-call, removes the hub from the hot path
  while keeping resolution authoritative.

**Negative / costs**
- Adding a new connector type is not self-service for the application team — it requires
  a Verity harness image release and a cluster `patch`. The Verity release cadence gates
  connector availability.
- MCP servers are additional processes the application team must operate, deploy, and
  secure in their cluster. Verity does not operate them.
- The tool authorization enforcer adds a check on every tool call. This is O(1) against
  an in-memory manifest, so the overhead is negligible, but it is a component to maintain
  and test.
- The image composition list is extensive — the harness image is not a thin executor.
  Image size, build times, and supply-chain signing surface are all larger than a minimal
  image would be.

## Alternatives considered

**Tool implementations shipped in the `.vtx`/`.vax` package (Python code the worker
executes).** Would make tools part of the governed artifact. *Rejected*: running
application-authored code inside the harness process creates a security boundary problem
— the harness would execute arbitrary code with its own credentials and filesystem
access. MCP over a network protocol is the correct isolation boundary.

**Hub-proxied tool calls (harness calls hub, hub calls tool or MCP server).** Would give
the hub visibility of every tool call. *Rejected*: the hub is in the hot path of every
tool round-trip, adding latency proportional to tool count and adding hub load
proportional to execution volume. Tool calls are the highest-frequency event in a
multi-tool run.

**Dynamic connector loading (connectors as loadable plugins, not baked into image).**
Would allow new connectors without image rebuilds. *Rejected for now*: dynamic loading
breaks the image-digest reproducibility guarantee — two runs on the same image digest
could load different connector versions if plugins are fetched from a registry at runtime.
Baked-into-image connectors are auditable and reproducible. Plugin loading can be
reconsidered once the audit-replay requirement is fully delivered.

**Per-call MCP endpoint resolution (worker looks up the registry on every tool call).**
Would give the most up-to-date endpoint on every call. *Rejected*: the hub is in the hot
path of every tool call, and endpoint changes mid-run would make run behaviour
non-deterministic from the governance record's perspective. Claim-time resolution is
sufficient — MCP server endpoints are stable during a run's lifetime.

---

## Amendment — 2026-06-10 (ADR-0018)

**Harbor is the named publish target for harness images.** §4's connector release path
("build → cosign sign → publish to registry") and §5's image composition discussion both
reference "the registry" without naming it. That registry is **Harbor**
([[0018-artifact-registry-harbor]]).

The full release pipeline for a new harness image version is:
`build (buildx multi-arch)` → `scan (Harbor/Trivy gate)` → `cosign sign` →
`promote to verity/harness in Harbor`. The image digest that [[0006]] requires packages
to pin is the digest Harbor assigns at push time.

Cosign signatures are stored as OCI referrer artifacts in Harbor alongside the image
manifest; no separate signature storage side-channel is needed.

## Notes

The governance metamodel additions for MCP server registration — `mcp_server`,
`mcp_server_version`, and `tool_authorization` join tables — are Phase 2 (Registry &
Compose) schema work. This ADR fixes the *architecture* (MCP as the application-side tool
pattern, claim-time resolution, authorization enforcer); the data model details are in
the Registry component spec.

The connector framework's initial connector set (SQL via psycopg, REST via httpx, S3 via
boto3-compatible) is an implementation decision for the harness component spec.

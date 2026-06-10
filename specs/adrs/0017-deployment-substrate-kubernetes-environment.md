# ADR-0017 — Deployment substrate: target Kubernetes environment, base image, network policies, and service account wiring

- **Status:** Accepted
- **Date:** 2026-06-09
- **Deciders:** Product Owner (Anil)
- **Related:** [[0002-execution-model]], [[0006-packages-and-governed-deployment]],
  [[0010-harness-runtime-federated-coordinator]], [[0011-repository-topology-and-harness-release-boundary]],
  [[0015-message-broker-dispatch-invocation]], [[0016-tool-invocation-harness-image-composition]]

---

## Context

The harness is application-hosted ([[0002-execution-model]]): it runs in the **customer's
cluster**, not in Verity's infrastructure. The hub platform runs in **Verity's own cluster**.
These are different substrates with different owners, different constraints, and different
lifecycle management, but both require concrete decisions that the PCR left open:

> *"Target K8s environment — determines base image constraints, network policies, service
> account wiring."*

The open decision was framed as "pick a cloud provider" but the real question is
different for each substrate:

- **Hub platform** (Verity-operated): which managed K8s service and Postgres HA solution
  does the reference IaC target?
- **Customer substrate** (app team-operated): what does the harness Helm chart assume
  about the cluster it runs on? What makes it portable across customer environments?

Two substrates, two answers. This ADR covers both, plus the shared concerns of base image
construction, network policy approach, and service account wiring that apply to the
harness regardless of substrate.

---

## Decision

### 1. Two substrates with different owners and different requirements

**Hub platform** — Verity operates this. Choices are Verity's to make and control.
The reference IaC targets **EKS** (Amazon Elastic Kubernetes Service). The Helm charts
are written for any CNCF-conformant K8s; EKS is the reference implementation for the
`infra/` IaC modules. CloudNativePG runs the governance database on this cluster.

**Customer substrate** — the app team operates this. Verity does not control it. The
harness Helm chart makes **no distribution-specific assumptions by default**. It targets
any CNCF-conformant Kubernetes. The `infra/` directory ships **reference substrate IaC
modules** for the common platforms (EKS, GKE, AKS, bare Linux); the customer's infra
team applies or adapts them. Verity publishes the **substrate-requirements spec** ([[0011]]
§1a) — the prerequisites Verity requires of any substrate before the operator is
installed.

**Local development** uses Docker Desktop Kubernetes or kind/k3d. The same Helm chart
runs with `networkPolicy.enabled: false`, single-arch image, a local MinIO instance, and
a mock Hub Gateway. CI's deploy-target test suite ([[0011]] §3) provisions an ephemeral
kind/k3d cluster for every harness PR.

### 2. Base image: Debian slim, multi-arch, non-root, cosign-signed

```dockerfile
FROM python:3.12-slim-bookworm
RUN useradd --uid 1000 --no-create-home --shell /sbin/nologin verity
USER verity
```

**OS: `python:3.12-slim-bookworm` (Debian slim).** Alpine uses musl libc, which causes
subtle incompatibilities with native Python extensions (psycopg, cryptography). Debian
slim is universally compatible, has a well-understood CVE feed, and is what enterprise
security scanners expect.

**Architecture: multi-arch** (`linux/amd64` + `linux/arm64`). EKS Graviton instances
are ARM64. Apple Silicon (developer laptops running Docker Desktop) is ARM64. A
single-arch AMD64 image either fails to pull on ARM nodes or forces the customer to
configure node selectors. Docker buildx multi-arch builds cost nothing at CI time.

**User: non-root (uid=1000).** OpenShift admission controllers enforce non-root
containers by default. Standard K8s does not enforce this, but it is a security best
practice and a prerequisite for regulated environments. Baking the non-root user into
the image means it works everywhere including OpenShift without per-cluster configuration.

**Signing: cosign.** The image is signed with cosign in the harness CI pipeline and the
signature is published to the same registry alongside the image digest. [[0006]] requires
digest pinning; cosign provides the attestation that the image at a given digest was
built by Verity's pipeline. Enterprise admission controllers (Kyverno, OPA Gatekeeper)
can enforce cosign signature verification as a deployment gate.

### 3. Network policy: standard K8s baseline, Cilium FQDN as opt-in

The harness worker requires exactly four outbound routes:

| Destination | Why |
|---|---|
| Hub Gateway API | Claim / release / heartbeat / status relay |
| Anthropic API (`api.anthropic.com`) | LLM calls |
| Object store (MinIO endpoint) | Bundle pull, log upload via pre-signed URL |
| Application's MCP servers | Category A tool calls ([[0016]]) |

Everything else should be blocked.

The constraint is that standard Kubernetes `NetworkPolicy` is L3/L4 only — it matches on
IP addresses and ports, not hostnames. The Anthropic API and the Hub Gateway are accessed
by hostname; their IP ranges are not static.

**Policy: disabled by default; standard K8s L3/L4 when enabled; Cilium FQDN as opt-in.**

```yaml
# Helm values
networkPolicy:
  enabled: false    # false = no policy created (safe default for clusters with no enforcing CNI)
  cilium: false     # true = Cilium CiliumNetworkPolicy with FQDN egress rules
```

When `networkPolicy.enabled: true` and `cilium: false`: the chart installs a standard
`NetworkPolicy` that denies all egress by default and allows the hub Gateway CIDR, the
object store CIDR, and port 443 to `0.0.0.0/0` (the practical fallback when the external
API IPs are not stable). The Helm chart `values.yaml` documents the specific CIDRs to
set for common cloud environments.

When `networkPolicy.cilium: true`: the chart installs a `CiliumNetworkPolicy` with FQDN
egress rules (`toFQDNs: [{matchName: "api.anthropic.com"}]`). This is the clean,
hostname-stable policy and the recommended setting for any cluster running Cilium. GKE
Dataplane V2 is Cilium-based. EKS and AKS can run Cilium instead of their default CNI.

`networkPolicy.enabled: false` is the safe default because many customer clusters have a
CNI that does not enforce `NetworkPolicy` (Flannel without a policy enforcer, some bare
bare-metal setups). An unenforceable policy silently does nothing; the default avoids
false security confidence.

### 4. Operator RBAC: namespace-scoped, minimal permissions

The operator is the **only** harness component that holds k8s API access
([[0010-harness-runtime-federated-coordinator]] §2). It gets a `Role` (namespace-scoped,
not `ClusterRole`) with exactly the permissions it needs:

```yaml
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: ["autoscaling"]
    resources: ["horizontalpodautoscalers"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["get", "list", "watch", "create", "update"]
```

The coordinator and workers get `ServiceAccount` resources with **no Role or ClusterRole
binding**. They hold no k8s API access. A compromised worker cannot read secrets,
enumerate pods, or modify Deployments.

The harness namespace is created by the Helm chart; `helm install` is the app team's only
interaction with the cluster API. After enrollment the operator manages everything inside
that namespace autonomously.

### 5. Image pull credentials: static secret default, Workload Identity opt-in

The harness image lives in Verity's image registry. The customer cluster needs credentials
to pull it.

**Default: `imagePullSecrets`** — a standard k8s Secret containing the registry
credential, provided as a Helm value. Works on every K8s distribution. The secret is
static and rotated by the Verity release process (new credentials delivered as a `patch`
command via the hub command channel).

**Opt-in: cloud Workload Identity** — for customers running on managed K8s with
cloud-native IAM, the operator's `ServiceAccount` can be annotated to bind to a cloud
IAM role with registry pull access:

| Platform | Mechanism | Helm value |
|---|---|---|
| EKS | IRSA (IAM Roles for Service Accounts) | `operator.serviceAccount.annotations.eks.amazonaws.com/role-arn` |
| GKE | Workload Identity | `operator.serviceAccount.annotations.iam.gke.io/gcp-service-account` |
| AKS | Azure Workload Identity | `operator.serviceAccount.annotations.azure.workload.identity/client-id` |

Workload Identity is preferable to a static secret for cloud deployments; it eliminates
a long-lived credential from the cluster.

### 6. Application credentials: ESO is the infra team's responsibility

Worker pods need the application's data source credentials (MCP server keys, database
passwords, connector credentials) at runtime. These are injected via k8s Secrets
populated by **External Secrets Operator (ESO)**.

Verity's role is to:
- Document the expected k8s Secret names and keys in the **substrate-requirements spec**.
- Ship reference ESO `ClusterSecretStore` configurations for the common secrets managers
  in the `infra/` reference modules.

The **infra team's role** (the customer's infrastructure team, [[0011]] §1a) is to:
- Install and configure ESO in the cluster.
- Create the `ClusterSecretStore` pointing at their secrets manager (AWS Secrets Manager,
  GCP Secret Manager, Azure Key Vault, HashiCorp Vault, etc.).
- Create the `ExternalSecret` resources that populate the Secrets the harness expects.

Verity never holds, proxies, or has visibility into the **values** of application
credentials ([[0010]] §7, Model B). The hub stores only the credential name and
verification status. The value lives in the customer's secrets manager and is read
in-memory by the worker at job time.

ESO configuration is explicitly **not** included in the harness Helm chart. It is
infra-team work, not app-team work, and it varies per secrets manager.

---

## Consequences

**Positive**
- Multi-arch images work on Graviton, Apple Silicon, and standard AMD64 cloud nodes
  without node selectors or per-cluster configuration.
- Non-root base image works on OpenShift and passes most enterprise security policy
  controllers without modification.
- Cosign signing enables admission controller enforcement and supply-chain attestation
  for regulated customers.
- NetworkPolicy disabled by default prevents false security confidence on non-enforcing
  CNIs; Cilium opt-in gives clean hostname-based rules for customers who can use it.
- Namespace-scoped operator RBAC contains the blast radius of a compromised data-plane
  component.
- ESO delegation keeps application secrets out of Verity's hands entirely; the credential
  boundary is clean and defensible under regulatory examination.

**Negative / costs**
- Multi-arch builds require buildx configuration in CI and roughly double the image build
  and push time.
- Standard K8s NetworkPolicy with CIDR-based rules requires CIDRs to be maintained
  per-environment (hub Gateway IPs, MinIO IPs). Fragile without FQDN support.
- ESO is a prerequisite that the infra team must provision before the app team can
  install the operator. This is a coordination dependency between two teams.
- The reference IaC targets EKS; customers on other managed K8s platforms must adapt
  the reference modules themselves (until GKE, AKS, and on-prem reference modules are
  built out in `infra/`).

## Alternatives considered

**Alpine as base OS.** Smaller image. *Rejected* — musl libc incompatibilities with
psycopg and the cryptography library (used for mTLS cert handling) cause runtime failures
that are hard to diagnose. Debian slim's size penalty is acceptable.

**Single-arch (AMD64 only).** Simpler CI. *Rejected* — ARM64 is required for
EKS Graviton (cost-optimized production fleets) and for developer laptops on Apple
Silicon. Forcing AMD64 nodes for the harness adds cost and configuration burden to
app teams.

**Require Cilium / mandate FQDN NetworkPolicy.** Would give the cleanest egress rules.
*Rejected as a requirement* — too prescriptive for customer clusters where CNI choice
is already made. Opt-in is the correct model; standard K8s L3/L4 is the portable
baseline.

**Include ESO configuration in the harness Helm chart.** Would simplify day-one setup.
*Rejected* — ESO `ClusterSecretStore` configuration is secrets-manager-specific and
cluster-global (not namespaced to the harness). Bundling it into the harness chart
would require the chart to have cluster-wide API access to create `ClusterSecretStore`
resources, which violates the namespace-scoped RBAC constraint. It would also conflate
Verity's app-team deliverable with the infra team's substrate responsibility.

**ClusterRole for operator (cluster-wide permissions).** Would simplify multi-namespace
deployments. *Rejected* — least privilege is a hard requirement in the security model.
The operator manages exactly one namespace; a `Role` is sufficient and correct.

**On-prem bare-metal as the primary hub platform target.** Would maximise portability.
*Rejected as primary* — managed K8s (EKS) reduces the operational burden on the Verity
team for the hub platform. On-prem is supported via the CNCF-portable chart but not the
primary reference IaC.

---

## Amendment — 2026-06-10 (ADR-0018)

**Harbor is the named image registry.** §5 states "the harness image lives in Verity's
image registry" and describes `imagePullSecrets` for pulling from it without naming the
registry. That registry is **Harbor** ([[0018-artifact-registry-harbor]]).

Concretely:
- The harness Helm chart exposes `image.registry` as a value; the default is
  `registry.verity.io` (Harbor's external DNS alias).
- The enrollment `patch` command delivers updated `imagePullSecrets` referencing the
  current Harbor credential. App teams do not manage these credentials manually.
- For air-gapped customers, `image.registry` is set to their local Harbor replica.
  The cosign signatures replicate alongside the image via Harbor's OCI referrers support
  ([[0018]] §5).
- The Workload Identity opt-in (IRSA / GKE Workload Identity / AKS Workload Identity)
  in §5 applies only when the customer uses a cloud-managed registry mirror (ECR, GCR,
  ACR) rather than a local Harbor replica. It does not apply to Verity's Harbor directly.

## Notes

The **substrate-requirements spec** (referenced in [[0011]] §1a) documents the
prerequisites Verity requires of any customer substrate before `helm install
verity-operator` is run: outbound-443-only egress, a dedicated namespace + operator RBAC
preconditions, a storage class for the artifact-cache PVC, ESO installed and configured,
and the enrollment token material. This spec is published as part of the harness release.

The reference `infra/` substrate modules (Terraform + Helm) provide the EKS, GKE, AKS,
and Linux implementations of these prerequisites. They are the app team's starting point,
not a black box — customers adapt them to their own security baselines.

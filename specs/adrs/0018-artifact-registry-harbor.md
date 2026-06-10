# ADR-0018 — Artifact registry: Harbor for OCI images and Helm charts

- **Status:** Accepted
- **Date:** 2026-06-10
- **Deciders:** Product Owner (Anil)
- **Related:** [[0011-repository-topology-and-harness-release-boundary]],
  [[0015-message-broker-dispatch-invocation]],
  [[0016-tool-invocation-harness-image-composition]],
  [[0017-deployment-substrate-kubernetes-environment]]

---

## Context

Several earlier ADRs reference "the registry" without naming it:

- [[0011]] §1 says the harness CI pipeline "signs images (cosign) → registry".
- [[0016]] §4 describes the connector release path: "build → cosign sign → publish to registry".
- [[0017]] §5 says "the harness image lives in Verity's image registry" and describes
  `imagePullSecrets` for pulling from it — without specifying what that registry is.

[[0015]] §5 fixed the **object store** for log artifacts as **MinIO** (S3-compatible API,
blob storage). MinIO is the correct answer for that workload — unstructured blobs with
prefix-based lifecycle policies. But MinIO is an object store, not an artifact registry:
it has no concept of OCI manifests, Helm index files, image layers, tag immutability,
vulnerability scanning, or cosign signature referrers. It cannot serve `docker pull` or
`helm pull` natively and was never intended to.

The distinction is load-bearing:

| Concern | MinIO | Harbor |
|---|---|---|
| Log artifacts (JSON, JSONL, Parquet) | ✓ | — |
| Container images (OCI manifest + layers) | ✗ | ✓ |
| Helm charts (OCI or classic index) | ✗ | ✓ |
| Cosign signature referrers API | ✗ | ✓ |
| Vulnerability scanning (Trivy) | ✗ | ✓ |
| Per-repository RBAC | ✗ | ✓ |
| Pull-through proxy / replication | ✗ | ✓ |

The open decision is: which registry serves OCI images (harness, operator, hub) and Helm
charts? This ADR closes it.

---

## Decision

**Harbor** is the artifact registry for all OCI images and Helm charts produced and
consumed by the Verity platform. MinIO remains the object store for log artifacts and
analytics data. The two are complementary, not competing.

### 1. Why Harbor over alternatives

**Harbor** is the appropriate choice for this stack:

- **CNCF graduated** — aligns with the CNCF-conformant infrastructure stance already
  adopted in [[0017]]. It is the standard enterprise choice, not a niche tool.
- **Cosign native** — Harbor 2.5+ implements the Sigstore [referrers API][oras-referrers],
  storing cosign signatures as OCI artifacts referenced from the signed manifest. The
  harness CI pipeline (`cosign sign`) works without any additional storage side-channel.
  Admission controllers (Kyverno, OPA Gatekeeper) can query Harbor to verify signatures
  before allowing a pull.
- **Trivy built-in** — Harbor ships a Trivy adapter. Every push triggers an automatic
  scan; the CI pipeline can also enforce a push-time scan gate (reject on CRITICAL/HIGH
  with an available fix). No additional scanning infrastructure is required.
- **OCI + Helm** — Harbor hosts both OCI images and Helm charts (OCI-based Helm
  `oci://` protocol and the classic chart museum `index.yaml` for clients that do not
  support OCI Helm). One registry, two artifact types.
- **OIDC / RBAC** — Harbor integrates with any OIDC provider. It can share the same IdP
  as the hub platform (the same Dex/Keycloak instance provisioned by `infra/`), giving
  consistent identity across the governance API and the registry.
- **Pull-through proxy** — Harbor can proxy and cache upstream registries (docker.io,
  ghcr.io, public.ecr.aws). The hub platform CI pipeline and the harness base image build
  pull through Harbor rather than directly from upstream, avoiding DockerHub rate limits
  and providing a local cache.
- **Harbor-to-Harbor replication** — customers who operate air-gapped or on-prem
  environments can run their own Harbor instance and configure it to replicate from
  Verity's Harbor. The `imagePullSecrets` credential in [[0017]] §5 is then a credential
  for their local replica, not for Verity's registry directly.

**Rejected alternatives:**

- **Docker Registry v2 (distribution)**: raw protocol only; no UI, no scanning, no RBAC,
  no cosign referrers API. Operational overhead without governance features.
- **Zot** (CNCF sandbox): lightweight OCI-only registry with minimal UI. No Trivy
  integration, no RBAC, no pull-through proxy. Acceptable for simple image serving; not
  sufficient for this platform's supply-chain and access-control requirements.
- **Nexus Repository OSS / Artifactory OSS**: heavier to operate; OSS tiers restrict
  features that Harbor provides free. Adding PyPI/npm support is not a current
  requirement. Both introduce more operational surface for no current gain.
- **GHCR / ECR / GCR as primary**: ties the supply chain to a specific cloud or to
  GitHub. The hub platform is CNCF-portable ([[0017]]); the registry should be
  self-hosted and not a cloud-provider dependency. GHCR/ECR remain valid pull-through
  sources or customer-side mirrors.

### 2. Project layout in Harbor

```
registry.verity.internal/          # internal DNS; public-facing alias TBD
  verity/
    harness        ← harness image (coordinator + worker + operator; one image, role by config)
    hub            ← hub API, verity-relay images
    proxy/
      docker.io    ← pull-through cache: upstream Docker Hub
      ghcr.io      ← pull-through cache: GitHub Container Registry
```

**Helm charts** are hosted as OCI artifacts:

```
oci://registry.verity.internal/verity/charts/verity-operator
oci://registry.verity.internal/verity/charts/verity-hub
```

Classic `helm pull` (`index.yaml`) is also served via Harbor's chart museum endpoint for
clients that do not support OCI Helm.

Projects follow Harbor's **public/private** model: `verity/harness` and
`verity/charts/verity-operator` are **public** (any authenticated pull, no per-image
credential required for enrolled customers). Internal images (`verity/hub`) are private
to Verity's CI/CD pipeline.

### 3. CI pipeline integration

The harness (and hub) release pipeline steps, in order:

1. **Build** — `docker buildx build --platform linux/amd64,linux/arm64` ([[0017]] §2).
2. **Scan** — push to a staging project, trigger Trivy scan via Harbor API; fail the
   pipeline on CRITICAL or HIGH severity CVE with an available fix.
3. **Sign** — `cosign sign` using Verity's signing key (stored in the CI secrets
   manager). Harbor stores the signature as an OCI referrer artifact co-located with the
   image manifest.
4. **Promote** — tag with the release version (`vMAJOR.MINOR.PATCH`) and `stable`.
   The digest is the canonical identifier ([[0006]]); the tag is a human-readable alias.
5. **Publish Helm chart** — `helm package` then `helm push` to the OCI Helm endpoint.

The scan gate (step 2) is a CI hard stop, not a post-publish advisory. An image with
known-fixable critical vulnerabilities does not reach `verity/harness`.

### 4. Admission controller enforcement (opt-in, recommended)

For customers who use Kyverno or OPA Gatekeeper, the Verity substrate-requirements spec
([[0011]] §1a) documents a **recommended** policy:

```yaml
# Kyverno ClusterPolicy example (informational — not shipped in harness Helm chart)
spec:
  rules:
    - name: verify-harness-image-signature
      match:
        resources: { kinds: ["Pod"] }
        namespaces: ["verity-*"]
      verifyImages:
        - imageReferences: ["registry.verity.internal/verity/harness:*"]
          attestors:
            - entries:
                - keyless:
                    subject: "https://github.com/verity/verity-harness/.github/workflows/release.yml@refs/heads/main"
                    issuer: "https://token.actions.githubusercontent.com"
```

This policy prevents any pod in the `verity-*` namespace from running an unsigned or
externally-sourced harness image. It is opt-in because not all customer clusters run
Kyverno; it is documented, not silently absent.

### 5. Air-gap and replication

Customers with air-gapped clusters follow this path:

1. Provision a local Harbor instance in their cluster (or a reachable internal zone).
2. Configure a **Harbor replication rule** to pull from `registry.verity.internal/verity/`
   to their local project on a schedule or on tag push (trigger: new `stable` tag).
3. Configure the harness Helm chart `image.registry` value to point at their local Harbor.
4. The cosign signatures replicate alongside the image via Harbor's OCI referrers support;
   their local Kyverno policy verifies the Verity signing key against the replicated
   signature.

No Verity involvement is required after the replication rule is set up. The enrolled
cluster's `imagePullSecrets` ([[0017]] §5) reference the local Harbor, not Verity's
registry.

### 6. Harbor deployment in `infra/`

Harbor runs in the hub platform cluster (Verity-operated). It is provisioned by the
`infra/hub-platform` IaC modules alongside CloudNativePG, NATS, and MinIO.

```
infra/
  hub-platform/
    harbor/        ← Harbor Helm values + Terraform outputs (DNS, TLS, OIDC config)
```

Harbor's storage backend for image layers uses the same MinIO instance that serves log
artifacts — Harbor supports an S3-compatible backend natively. The two workloads use
separate MinIO buckets (`harbor-registry` vs. `verity-artifacts`).

Harbor uses **CloudNativePG** (already on the hub platform) as its database backend.
No additional Postgres instance is required.

### 7. Registry DNS and TLS

| Name | Use |
|---|---|
| `registry.verity.internal` | Internal cluster DNS (hub platform) |
| `registry.verity.io` | External alias for enrolled customers and CI (TLS via cert-manager + Let's Encrypt or internal CA) |

The `infra/hub-platform/harbor/` module provisions the DNS record and the `Certificate`
resource. TLS termination is at the Harbor ingress; cert-manager manages rotation.

---

## Consequences

**Positive**
- One registry technology for all OCI images and Helm charts; MinIO stays a pure blob
  store. The concerns are cleanly separated and neither does the other's job.
- Cosign signatures are stored natively in Harbor — no separate signature storage side
  channel; `cosign verify` works against the Harbor OCI referrers API.
- Trivy scanning is built-in and triggered on push; no separate scanner to operate.
- Harbor-to-Harbor replication enables air-gap without Verity involvement post-setup.
- OIDC integration shares IdP with the hub platform; one identity surface.
- Pull-through proxy for upstream registries eliminates DockerHub rate-limit failures in
  CI and provides a local cache for base image pulls during Kubernetes node scale-out.

**Negative / costs**
- Harbor is a non-trivial service to operate: it runs a core service, a job service, a
  Trivy adapter, a notary (optional), and a Portal UI. It is not a single binary.
- MinIO as Harbor's storage backend is a dependency — a MinIO outage affects both log
  artifact reads and image layer pulls. These should share infrastructure but can be
  isolated by MinIO bucket policies if needed.
- Harbor uses CloudNativePG as its database; schema migrations on Harbor upgrades must be
  coordinated with the CloudNativePG upgrade schedule.
- The external DNS alias (`registry.verity.io`) must be publicly resolvable and TLS-valid
  for enrolled customer clusters to pull images. Cert-manager handles rotation, but the
  DNS record is a platform dependency.

## Notes

Harbor is deployed as part of the `infra/hub-platform` release. Its provisioning is the
infra team's responsibility. App teams interact with it only indirectly (via
`imagePullSecrets` delivered by the enrollment `patch` command). The harness Helm chart
references `image.registry` as a value — customers can point this at a local Harbor
replica without any chart modification.

The **substrate-requirements spec** ([[0011]] §1a) should document that the enrollment
`patch` command delivers updated `imagePullSecrets` referencing the current registry
credential. Customers should not manually manage these credentials; the operator rotation
mechanism handles them.

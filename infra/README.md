# infra/ — infrastructure-as-code (infra-team persona)

Provisioning, not deployment. Owned by the **infrastructure team** persona: provisions the
**substrate** that everything else runs on — and ships reference modules customers' infra teams
apply (ADR-0011 §1a).

Owns:
- **Hub platform** IaC: k8s + CloudNativePG + NATS + MinIO + the image registry.
- **Reference customer substrate** modules: a k8s cluster module and a Linux box module.
- The **substrate-requirements spec** — the infra↔harness contract: outbound-443-only egress,
  a namespace + operator RBAC, a storage class for the artifact-cache PVC, ESO for customer
  secrets, the mTLS enrollment material (and systemd/podman prerequisites on Linux).

CI's deploy-target tests provision an **ephemeral** substrate (kind for k8s, a VM/container for
Linux) — the test double for what this provisions in production.

Hub-only features (the intake slice and everything else that is just hub + Postgres) need no new
infra: they run on the **Postgres substrate** this provisions — the local `pg` dev stack
(`dev stack up pg`, a pgvector container) standing in for production **CloudNativePG**.

Status: not started.

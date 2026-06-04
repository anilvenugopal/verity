# harness/ — the application-hosted execution harness (Verity-published)

Builds the **harness image** (coordinator + worker — one image, role by config), the
**operator** image, the **Helm chart**, and the systemd/podman packaging. Digest-pinned,
cosign-signed, pushed to the hosted registry. Releases independently of the hub.

Runs in the *customer's* environment, **API-only** (ADR-0003): outbound to the Harness Gateway
API + NATS, never the hub database. Federated coordinator + stateless workers; island-mode
resilient (ADR-0010).

Consumes a **pinned** `../contract/` version (gateway client, NATS payloads, package manifest).
Tested by one behavioral suite over two substrates — Linux (systemd/podman) and Kubernetes
(kind) — plus the package×image compatibility matrix (ADR-0006/0011).

Status: not started (sequence: after the hub foundation + the run/dispatch walking skeleton).

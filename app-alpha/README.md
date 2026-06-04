# app-alpha/ — the demo app-team example (underwriting)

A realistic *app team's* repo: a containerized **underwriting** business app + the harness
install + enrollment + the end-to-end scenarios. Doubles as the acceptance environment and the
demo. R1 runs the harness on **Linux** (container image); R2 adds **Kubernetes** (ADR-0011).

The R1 scenario is built by **re-authoring** `../verity_legacy/uw_demo` into v2 data (legacy is
read-only — reference, never import): its prompts → `prompt_version`s; its underwriting ontology
→ the compliance metamodel; its seed → an `application` + `intake` + registry seed; its labeled
cases → ground-truth/validation data.

Consumes (does not build) the operator/Helm chart from `harness/` and a pinned `../contract/`.
Provisioning of its substrate (the Linux box / cluster) is `infra/`'s job, not this repo's.

Status: not started (after the loop closes: registry → lifecycle → package → deploy → run).

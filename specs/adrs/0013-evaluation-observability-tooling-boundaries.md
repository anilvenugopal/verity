# ADR-0013 — Third-party evaluation & observability tooling boundaries (embed the metrics, own the record)

- **Status:** Accepted
- **Date:** 2026-06-04
- **Deciders:** Product Owner (Anil)
- **Related:** [[0003-harness-governance-api]], [[0004-storage-architecture]],
  [[0006-packages-and-governed-deployment]], [[0007-decision-log-scale-and-portable-analytics]],
  [[0008-compliance-control-evidence-model]], [[0009-obligation-reasoning-ontology]],
  [[0010-harness-runtime-federated-coordinator]]

---

## Context

Verity needs four adjacent capabilities: **compose-time / batched suite execution**,
**ground-truth & validation**, **observability / decision logging**, and (raised separately)
**prompt optimization**. Mature open-source tooling exists for all of these, and the question
is buy-vs-build — and, where we buy, *where the tool is allowed to live* given the
architecture's hard constraints:

- **DSPy** and **TextGrad** — design-time prompt optimizers (DSPy: instruction + few-shot
  search against a metric; TextGrad: LLM "textual-gradient" feedback loops).
- **Arize Phoenix** — LLM observability + eval; **Elastic License 2.0** (ELv2, which restricts
  offering the software as a managed service); native OpenTelemetry + the **OpenInference**
  semantic conventions for LLM spans.
- **Comet Opik** — LLM eval + observability; **Apache-2.0**; self-hostable (Docker / Helm);
  tracing, datasets, experiments, prompt management, **LLM-as-judge + heuristic metrics**,
  **online evaluation rules**, and guardrails.

These collide with load-bearing decisions already made. The **decision log is the immutable,
append-only system-of-record** ([[0004-storage-architecture]], [[0007-decision-log-scale-and-portable-analytics]]),
written **API-only from the spoke** (the harness holds no DB credential — [[0003-harness-governance-api]]),
and linked into the governance metamodel (decision → executable_version → intake →
canonical_requirement → evidence — [[0008-compliance-control-evidence-model]]). Champion
packages are **frozen and digest-pinned** ([[0006-packages-and-governed-deployment]]).
Testing/validation is already a **first-class Tier-1 metamodel** (test suites, ground-truth
datasets with silver/gold tiers + inter-annotator agreement, validation/evaluation runs, model
cards). Many customers **air-gap**; the portal is the **owned user surface**.

The consequence: no external trace/eval store can *be* the system-of-record, and the spoke
cannot write governance-relevant data to a second store out-of-band. The useful question is
therefore not "library instead of decision log" but "**which tool as a *library* or
*developer/ops tool* feeding our own record**."

## Decision

**Buy the evaluation muscle as plumbing; keep the system-of-record, the metamodel, the
ground-truth lifecycle, and the user experience built in-house.**

1. **System-of-record stays Verity's.** No external trace/eval platform is authoritative for
   decisions, validation results, or ground truth. Those remain in the Tier-1 / Tier-2 stores
   behind the governance API ([[0004-storage-architecture]], [[0007-decision-log-scale-and-portable-analytics]]).

2. **Embed Opik's metric/judge library inside the validation/evaluation engine.** Use Opik
   (Apache-2.0) as a *dependency*, not a platform — its heuristic metrics and LLM-as-judge
   metrics (hallucination, faithfulness, relevance, moderation, custom-rubric `GEval`, …) fill
   the judge slots in `validation_run` / `evaluation_run`. Verity's own scores
   (precision/recall/F1, Cohen's kappa, confusion matrix, fairness) stay native. Results write
   to **Verity's** tables. **Judges MUST call the governed model endpoint** (Opik metrics
   accept an injected LLM client) — so judge invocations are themselves logged and governed —
   and **never** Comet cloud. Scoring runs **where the data lives**: spoke-side for sensitive
   ground truth (reported back via the gateway, API-only preserved), hub-side permitted for
   synthetic/sample ground truth.

3. **Adopt OpenInference (OTel semantic conventions) as the wire format** for execution events
   and `model_invocation` spans. This lets a customer optionally point a self-hosted,
   OTel-compatible tool (Opik or any other) at the spoke for **engineering/ops debugging only**.
   The decision log remains the SoR; spans are a parallel operational signal — **one-way
   (Verity → tool), never authoritative, never read back into the governance path.**

4. **Opik-the-platform is permitted only off the governance path.** Two places: (a) a
   **dev/compose sandbox workbench** for prompt/agent iteration, fed **synthetic/sample data
   only**; (b) the **optional customer-self-hosted ops sidecar** of (3). It never stores
   governance data, never serves audit, and is **never surfaced to business / governance /
   audit users** — they see only the Verity portal.

5. **Borrow the online-evaluation / guardrail pattern, don't run the engine.** Continuous
   champion monitoring (sample production decisions → async judge → feedback score) is
   implemented **natively on the API-only ingest path**, reusing the embedded judges from (2).
   No external rules engine runs in the spoke as authoritative.

6. **Build, not buy — the domain-specific, audit-constrained core:** the harness runtime
   ([[0010-harness-runtime-federated-coordinator]]), the decision-log SoR
   ([[0004-storage-architecture]], [[0007-decision-log-scale-and-portable-analytics]]), the
   compliance/obligation metamodel ([[0008-compliance-control-evidence-model]],
   [[0009-obligation-reasoning-ontology]]), and the ground-truth annotation lifecycle +
   validation/evaluation metamodel. These are richer and more constrained than anything the
   tools model.

7. **Prompt-optimization frameworks (DSPy, TextGrad) are parked (v3/v4 candidate).** They
   auto-author prompts, which conflicts with the frozen, digest-pinned, human-authored
   governance model ([[0006-packages-and-governed-deployment]]), pay off least on the complex
   tool-using agents we care about, and clash with the rich prompt-editing experience. If
   reopened, an optimizer is **one authoring source for a `candidate` prompt version**, gated
   through the existing **recommend → human-validate provenance seam** (`derivation_method`,
   [[0009-obligation-reasoning-ontology]]) and frozen/digest-pinned like any prompt — never the
   runtime. **DSPy is preferred over TextGrad** if revisited (more mature; metric-driven search
   is more reproducible/auditable than fuzzy textual-gradient loops), and only for narrow,
   well-labeled, single-shot tasks.

**Opik over Phoenix (for embedding):** Apache-2.0 vs ELv2 — the ELv2 managed-service
restriction is a needless question for software we want to embed/redistribute inside the
harness image; Opik's online-eval/guardrail features map cleanly onto challenger/shadow
evaluation; its k8s/Helm self-host matches the deployment target. **OpenInference** (Phoenix's
contribution) is adopted in (3) **independently** of which platform, if any, a customer runs.

## Consequences

**Positive**
- The hard, well-solved part — a library of LLM-as-judge and heuristic metrics — is bought,
  not reinvented; the cheap Apache-2.0 license makes embedding clean.
- Judges run through the governed model path, so **the evaluators are themselves governed and
  logged** — a differentiator a bolt-on eval platform cannot offer.
- OpenInference gives customers a zero-bespoke ops-observability option without Verity owning,
  hosting, or depending on it; the SoR and the portal stay authoritative and owned.
- The boundary is explicit, so third-party tooling can be swapped behind the seam (mirroring
  the engine-choice latitude of [[0004-storage-architecture]] / [[0007-decision-log-scale-and-portable-analytics]]).

**Negative / costs**
- A dependency on Opik's metric library (and its model-client injection surface) to track and
  pin; judge prompt templates must be versioned for reproducible validation runs.
- Running judges through the governed model adds inference cost to every validation/evaluation
  run and to continuous monitoring sampling.
- OpenInference span emission is additional instrumentation to build and keep aligned with the
  decision-log/event model.
- Maintaining the discipline that Opik never crosses onto the governance path or in front of
  governance users is an ongoing review obligation, not a one-time gate.

## Alternatives considered

- **External platform (Opik/Phoenix) as the store/UI of record.** *Rejected* — breaks
  immutability, metamodel linkage, data residency/air-gap, and regulator-grade retention; the
  SoR must be ours ([[0004-storage-architecture]], [[0007-decision-log-scale-and-portable-analytics]]).
- **Phoenix instead of Opik for embedding.** *Rejected* on ELv2 (managed-service restriction
  is a redistribution question we needn't take on); **OpenInference adopted regardless**.
- **Hand-code all LLM-judge metrics.** *Rejected* — reinvents a well-solved, maintained body of
  work that Apache-2.0 lets us embed cheaply.
- **Opik datasets as the ground-truth system-of-record.** *Rejected* — Verity's model
  (silver/gold tiers, inter-annotator agreement, collecting→labeling→adjudicating→ready
  lifecycle) is richer and audit-grade.
- **DSPy/TextGrad as runtime or autonomous prompt author.** *Rejected* — conflicts with the
  frozen-snapshot/digest-pinned champion ([[0006-packages-and-governed-deployment]]), weak on
  tool-using agents, and competes with human-in-control prompt governance. Permitted only later
  as a human-validated design-time *assist*.

## Notes

Phasing: act now on (2) embed the judge library and (3) OpenInference spans; (4) the
dev-sandbox workbench is a developer convenience; (5) the online-eval pattern lands when
continuous champion monitoring is built; (7) optimizers stay parked. Specific library
versions, judge templates, and the OpenInference attribute mapping are confirmed in the
testing/validation and observability **component specs** — mirroring the "reference choice, not
a hard commitment" stance of [[0004-storage-architecture]]. Re-verify Opik's license and the
relevant feature set at adoption time, as both evolve.
</content>
</invoke>

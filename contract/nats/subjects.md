# NATS subjects — hub ↔ harness dispatch & events (contract)

The dispatch/event bus (PCR §3.3, ADR-0010). The hub never publishes directly; `verity-relay`
drains the transactional outboxes to NATS. The coordinator consumes work + commands and
publishes events; it never reads the hub database. Payload schemas live in `./*.schema.json`
(skeleton — to be filled).

| Subject | Direction | Producer → Consumer | Payload |
|---|---|---|---|
| `verity.runs.pending` | hub → cluster | relay (from `run_dispatch_outbox`) → coordinator (durable consumer group) | `run-pending.schema.json` |
| `verity.cluster.{id}.commands` | hub → cluster | relay (from `harness_command_outbox`) → coordinator | `command.schema.json` |
| `verity.events.{run_id}` | cluster → hub | worker → SSE bridge | `execution-event.schema.json` |
| `verity.worker.heartbeat.{id}` | intra-cluster | worker → coordinator | `worker-heartbeat.schema.json` |
| `verity.integrity.violations` | cluster → hub | worker → hub | `integrity-violation.schema.json` |

Notes:
- Two independent at-least-once layers: NATS redelivery + the `verity-dispatch-sweep` re-publish
  of stuck outbox rows.
- The coordinator *claims* a published run via the gateway (`POST /clusters/{id}/dispatch/next`),
  where the hub-side `SKIP LOCKED` runs — the NATS message is the wake-up, not the claim.
- Execution events (`verity.events.{run_id}`) feed the SSE bridge for live UI; the canonical
  record is still the decision log written via the gateway on release.

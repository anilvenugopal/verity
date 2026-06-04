# tools/ — `dev`, the developer/demo console

A cross-cutting local-dev convenience (not the production path — that's `infra/`). It brings
the local stack, the hub, and canned dev ops under one command, with **aggregated logs** so you
don't tail three terminals. Package `verity.dev`; command `dev`.

It orchestrates **by subprocess** (`docker`, the hub's venv, `pytest`) and imports no other
component — the ADR-0011 boundary holds.

```
uv venv .venv && uv pip install -e .        # in tools/

dev stack up [pg nats minio]   # start local containers (default: all)
dev stack ps                   # status
dev db reset                   # recreate the dev DB from canonical DDL (ADR-0012)
dev run                        # start the hub (uvicorn, mock auth) in the background
dev logs [pg ...]              # aggregate stack + hub logs into one colored stream
dev db query roles|tables|auth|actors|dispatch
dev test all|auth|migrate
dev sh psql|ps
dev stack down

dev menu                       # the slim interactive pane over all of the above
```

Add a canned query/test/shell op once in `catalog.py` and it appears in both the CLI and the
menu. The dev DB defaults to `localhost:5432/verity` (override `VERITY_DEV_DATABASE_URL`).

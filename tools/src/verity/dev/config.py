"""Static config: repo anchors, the local dev containers, the dev DB URL."""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path


def repo_root() -> Path:
    for p in Path(__file__).resolve().parents:
        if (p / "specs" / "schema" / "verity_schema.sql").exists():
            return p
    raise RuntimeError("repo root not found above " + __file__)


REPO = repo_root()
HUB = REPO / "hub"
HUB_PY = HUB / ".venv" / "bin" / "python"  # the hub's own venv (invoked, never imported)

DEV_DB_URL = os.environ.get(
    "VERITY_DEV_DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/verity"
)
RUNTIME = REPO / "tools" / ".dev"  # logs/pids (gitignored)
UVICORN_LOG = RUNTIME / "uvicorn.log"
UVICORN_PID = RUNTIME / "uvicorn.pid"


@dataclass(frozen=True)
class Container:
    name: str
    image: str
    ports: tuple[str, ...]
    env: tuple[str, ...] = ()
    args: tuple[str, ...] = field(default=())


CONTAINERS: dict[str, Container] = {
    "pg": Container(
        "verity-dev-pg", "pgvector/pgvector:pg18", ("5432:5432",),
        ("POSTGRES_PASSWORD=postgres", "POSTGRES_DB=verity"),
    ),
    "nats": Container("verity-dev-nats", "nats:2.10", ("4222:4222", "8222:8222"), args=("-js",)),
    "minio": Container(
        "verity-dev-minio", "minio/minio", ("9000:9000", "9001:9001"),
        ("MINIO_ROOT_USER=minio", "MINIO_ROOT_PASSWORD=minio12345"),
        ("server", "/data", "--console-address", ":9001"),
    ),
}
ALL_SERVICES = tuple(CONTAINERS)

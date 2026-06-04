"""Coordinated dev operations: the local container stack, the hub process, db reset, queries.

Everything is subprocess-based — the console orchestrates `docker`, the hub's venv, and
`pytest`; it never imports another component (ADR-0011 boundary)."""
from __future__ import annotations

import os
import subprocess

import psycopg
from rich.console import Console
from rich.table import Table

from verity.dev.config import CONTAINERS, DEV_DB_URL, HUB, HUB_PY, RUNTIME, UVICORN_LOG, UVICORN_PID

console = Console()


def _running(name: str) -> bool:
    r = subprocess.run(["docker", "ps", "-q", "-f", f"name=^{name}$"], capture_output=True, text=True)
    return bool(r.stdout.strip())


def stack_up(services: list[str]) -> None:
    for key in services:
        c = CONTAINERS[key]
        if _running(c.name):
            console.print(f"[green]{c.name}[/] already running")
            continue
        subprocess.run(["docker", "rm", "-f", c.name], capture_output=True)
        cmd = ["docker", "run", "-d", "--name", c.name]
        for p in c.ports:
            cmd += ["-p", p]
        for e in c.env:
            cmd += ["-e", e]
        cmd += [c.image, *c.args]
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
        console.print(f"[green]started[/] {c.name} ({c.image})")


def stack_down(services: list[str]) -> None:
    for key in services:
        subprocess.run(["docker", "rm", "-f", CONTAINERS[key].name], capture_output=True)
        console.print(f"[yellow]removed[/] {CONTAINERS[key].name}")


def stack_ps() -> None:
    subprocess.run([
        "docker", "ps", "-a", "--filter", "name=verity-dev-",
        "--format", "table {{.Names}}\t{{.Status}}\t{{.Ports}}",
    ])


def _hub_env() -> dict[str, str]:
    return {**os.environ, "VERITY_DATABASE_URL": DEV_DB_URL, "VERITY_ENV": "local",
            "VERITY_AUTH_MODE": "mock"}


def db_reset() -> None:
    """Recreate the dev DB from the canonical DDL (ADR-0012) via the hub's migrate reset."""
    subprocess.run([str(HUB_PY), "-m", "verity.hub.migrate", "reset"],
                   cwd=HUB, env=_hub_env(), check=True)


def run_app(port: int = 8000) -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    logf = open(UVICORN_LOG, "a")
    p = subprocess.Popen(
        [str(HUB_PY), "-m", "uvicorn", "verity.hub.app:app", "--reload", "--port", str(port)],
        cwd=HUB, env=_hub_env(), stdout=logf, stderr=subprocess.STDOUT,
    )
    UVICORN_PID.write_text(str(p.pid))
    console.print(f"[green]hub[/] running pid={p.pid} on :{port} — logs: {UVICORN_LOG}")


def stop_app() -> None:
    if UVICORN_PID.exists():
        subprocess.run(["kill", UVICORN_PID.read_text().strip()], capture_output=True)
        UVICORN_PID.unlink()
        console.print("[yellow]stopped[/] hub")
    else:
        console.print("hub not running")


def run_query(sql: str) -> None:
    with psycopg.connect(DEV_DB_URL) as conn:
        cur = conn.execute(sql)
        cols = [d.name for d in cur.description] if cur.description else []
        rows = cur.fetchall() if cur.description else []
    t = Table(*cols)
    for row in rows:
        t.add_row(*(str(v) for v in row))
    console.print(t)
    console.print(f"[dim]{len(rows)} row(s)[/]")


def run_tests(args: list[str]) -> None:
    subprocess.run([str(HUB_PY), "-m", "pytest", *args], cwd=HUB)

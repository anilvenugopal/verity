#!/usr/bin/env python3
"""Verity dev console — one readable file.

Two ways to run it:
  ./dev            → interactive menu (arrow keys, Enter to choose)
  ./dev up         → run one action by name, no menu

The whole design is the ACTIONS list at the bottom: each entry is
  (name, description, function)
The menu shows "name — description"; `./dev <name>` runs that action's function.
Add a feature = write a function + add one line to ACTIONS.
"""
from __future__ import annotations

import os
import signal
import subprocess
import sys
import urllib.request
from collections import namedtuple
from pathlib import Path

import psycopg
from InquirerPy import inquirer
from rich.console import Console

console = Console()

# ── where things are ────────────────────────────────────────────────────────
REPO = Path(__file__).resolve().parent.parent      # tools/dev.py → repo root
HUB = REPO / "hub"
HUB_PY = HUB / ".venv" / "bin" / "python"           # the hub's own Python
PORTAL = HUB / "portal"
RUN = REPO / "tools" / ".run"                        # pid + log files (gitignored)

# The native dev database (Postgres 18 on the host).
DB_URL = "postgresql://verity:verity@localhost:5432/verity"

# The settings the hub runs with in dev. Read it and you know exactly how the hub is started.
# Roles are chosen per-session on the sign-in screen now; VERITY_MOCK_PLATFORM_ROLES here is only
# the default persona for the env fallback (a request that arrives with no login session).
def _hub_env() -> dict[str, str]:
    return {
        **os.environ,
        "VERITY_DATABASE_URL": DB_URL,
        "VERITY_ENV": "local",
        "VERITY_AUTH_MODE": "mock",
        "VERITY_SESSION_SECRET": "local-dev-insecure-session-secret",
        "VERITY_MOCK_PLATFORM_ROLES": "ai_governance,security,viewer",
        "VERITY_APP_BASE_URL": "http://localhost:5173",  # Entra callback redirects back to the portal
    }


# ── tiny process helpers (start / stop background servers) ───────────────────
def _pid_alive(name: str) -> int | None:
    """Return the pid recorded for `name` if that process is still alive, else None."""
    pidfile = RUN / f"{name}.pid"
    if not pidfile.exists():
        return None
    pid = int(pidfile.read_text().strip())
    try:
        os.kill(pid, 0)          # signal 0 = "does this process exist?"
        return pid
    except OSError:
        pidfile.unlink(missing_ok=True)
        return None


def _start(name: str, cmd: list[str], cwd: Path, env: dict | None = None) -> None:
    """Start `cmd` in the background, recording its pid + logs under tools/.run/."""
    if _pid_alive(name):
        console.print(f"{name} already running")
        return
    RUN.mkdir(parents=True, exist_ok=True)
    log = open(RUN / f"{name}.log", "a")
    # stdin=DEVNULL: the servers must NOT share our terminal's keyboard, or Vite's interactive
    #   mode grabs it and the menu freezes.
    # start_new_session=True: own process group + no controlling terminal, so it's fully detached
    #   (survives closing the terminal) and we can stop it + its children together.
    proc = subprocess.Popen(
        cmd, cwd=cwd, env=env,
        stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    (RUN / f"{name}.pid").write_text(str(proc.pid))
    console.print(f"[green]{name} started[/] (pid {proc.pid}) — logs: tools/.run/{name}.log")


def _stop(name: str) -> None:
    pid = _pid_alive(name)
    if pid is None:
        console.print(f"{name} not running")
        return
    os.killpg(os.getpgid(pid), signal.SIGTERM)   # stop the whole process group
    (RUN / f"{name}.pid").unlink(missing_ok=True)
    console.print(f"[yellow]{name} stopped[/]")


# ── probes (used by status) ──────────────────────────────────────────────────
def _db_up() -> bool:
    try:
        with psycopg.connect(DB_URL, connect_timeout=3) as conn:
            conn.execute("select 1")
        return True
    except Exception:
        return False


def _http_up(url: str) -> bool:
    try:
        urllib.request.urlopen(url, timeout=2)  # noqa: S310 — localhost only
        return True
    except Exception:
        return False


# ── actions (each one is a menu item) ────────────────────────────────────────
def status() -> None:
    """Show whether Postgres, the hub API, and the portal are up."""
    from rich.table import Table

    table = Table("component", "state")
    table.add_row("postgres  :5432", "[green]up[/]" if _db_up() else "[red]down[/]")
    table.add_row("hub       :8000", "[green]up[/]" if _http_up("http://localhost:8000/healthz") else "[dim]down[/]")
    table.add_row("portal    :5173", "[green]up[/]" if _http_up("http://localhost:5173/") else "[dim]down[/]")
    console.print(table)


def _start_hub() -> None:
    _start("hub", [str(HUB_PY), "-m", "uvicorn", "verity.hub.app:app", "--reload", "--port", "8000"], cwd=HUB, env=_hub_env())


def up() -> None:
    """Start the hub + portal, then tell you where to open it."""
    _start_hub()
    _start("portal", ["npm", "run", "dev"], cwd=PORTAL)
    console.print("\n[bold green]ready[/] — open [bold]http://localhost:5173[/]")


def down() -> None:
    """Stop the hub + portal."""
    _stop("portal")
    _stop("hub")


# ── the menu ─────────────────────────────────────────────────────────────────
Action = namedtuple("Action", "name desc fn")

ACTIONS = [
    Action("status", "Show what's running (Postgres / hub / portal)", status),
    Action("up", "Start the hub + portal", up),
    Action("down", "Stop the hub + portal", down),
]
BY_NAME = {a.name: a for a in ACTIONS}


def menu() -> None:
    """Show the list (name — description), run the chosen action, repeat."""
    choices = [{"name": f"{a.name:8} {a.desc}", "value": a.name} for a in ACTIONS]
    choices.append({"name": "quit", "value": "quit"})
    while True:
        pick = inquirer.select(message="verity · dev", choices=choices).execute()
        if pick == "quit":
            return
        BY_NAME[pick].fn()


if __name__ == "__main__":
    if len(sys.argv) > 1:                         # `./dev up` → run that action
        action = BY_NAME.get(sys.argv[1])
        if action is None:
            console.print(f"unknown action '{sys.argv[1]}' — try: {', '.join(BY_NAME)}")
            sys.exit(1)
        action.fn()
    else:                                          # `./dev` → open the menu
        menu()

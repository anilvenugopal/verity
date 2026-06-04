"""The slim interactive pane (InquirerPy) — a thin wrapper over the same ops the CLI exposes."""
from __future__ import annotations

import subprocess

from InquirerPy import inquirer

from verity.dev import logs as logmux
from verity.dev import ops
from verity.dev.catalog import QUERIES, SHELL, TESTS
from verity.dev.config import ALL_SERVICES


def _pick(message: str, items: dict[str, tuple[str, object]]) -> str:
    choice = inquirer.select(
        message=message, choices=[f"{k}  —  {v[0]}" for k, v in items.items()] + ["back"]
    ).execute()
    return choice.split("  —  ")[0]


def run_menu() -> None:
    actions = {
        "stack: up (all)": lambda: ops.stack_up(list(ALL_SERVICES)),
        "stack: up (pg only)": lambda: ops.stack_up(["pg"]),
        "stack: status": ops.stack_ps,
        "stack: down (all)": lambda: ops.stack_down(list(ALL_SERVICES)),
        "db: reset (rebuild from DDL)": ops.db_reset,
        "db: query…": lambda: _run(QUERIES, ops.run_query, idx=1),
        "hub: run": ops.run_app,
        "hub: stop": ops.stop_app,
        "logs: aggregate (stack + hub)": lambda: logmux.tail(list(ALL_SERVICES)),
        "tests: run…": lambda: _run(TESTS, ops.run_tests, idx=1),
        "shell: …": lambda: _run(SHELL, lambda cmd: subprocess.run(cmd), idx=1),
    }
    while True:
        choice = inquirer.select(message="verity · dev", choices=[*actions, "quit"]).execute()
        if choice == "quit":
            return
        actions[choice]()


def _run(items: dict[str, tuple[str, object]], fn, *, idx: int) -> None:
    name = _pick("choose", items)
    if name != "back":
        fn(items[name][idx])

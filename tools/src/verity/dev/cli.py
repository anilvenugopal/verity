"""`dev` — the Verity developer/demo console (headless commands; `dev menu` for the UI)."""
from __future__ import annotations

import subprocess

import typer

from . import logs as logmux
from . import ops
from .catalog import QUERIES, SHELL, TESTS
from .config import ALL_SERVICES

app = typer.Typer(no_args_is_help=True, add_completion=False, help="Verity developer/demo console")
stack_app = typer.Typer(no_args_is_help=True, help="local container stack (pg/nats/minio)")
db_app = typer.Typer(no_args_is_help=True, help="dev database")
app.add_typer(stack_app, name="stack")
app.add_typer(db_app, name="db")


def _services(services: list[str] | None) -> list[str]:
    return services or list(ALL_SERVICES)


@stack_app.command("up")
def stack_up(services: list[str] = typer.Argument(None, help="pg nats minio (default: all)")):
    ops.stack_up(_services(services))


@stack_app.command("down")
def stack_down(services: list[str] = typer.Argument(None)):
    ops.stack_down(_services(services))


@stack_app.command("ps")
def stack_ps():
    ops.stack_ps()


@db_app.command("reset")
def db_reset():
    """Recreate the dev DB from the canonical DDL (ADR-0012)."""
    ops.db_reset()


@db_app.command("query")
def db_query(name: str = typer.Argument(..., help=f"one of: {', '.join(QUERIES)}")):
    if name not in QUERIES:
        raise typer.BadParameter(f"unknown query '{name}'; choices: {', '.join(QUERIES)}")
    ops.run_query(QUERIES[name][1])


@app.command()
def run(port: int = 8000):
    """Start the hub (uvicorn, mock auth) in the background; logs go to the aggregator."""
    ops.run_app(port)


@app.command()
def stop():
    ops.stop_app()


@app.command()
def logs(services: list[str] = typer.Argument(None, help="containers to tail (default: all + hub)")):
    """Aggregate logs from the stack + hub into one colored stream."""
    logmux.tail(_services(services))


@app.command()
def test(name: str = typer.Argument("all", help=f"one of: {', '.join(TESTS)}")):
    if name not in TESTS:
        raise typer.BadParameter(f"choices: {', '.join(TESTS)}")
    ops.run_tests(TESTS[name][1])


@app.command()
def sh(name: str = typer.Argument(..., help=f"one of: {', '.join(SHELL)}")):
    if name not in SHELL:
        raise typer.BadParameter(f"choices: {', '.join(SHELL)}")
    subprocess.run(SHELL[name][1])


@app.command()
def menu():
    """The slim interactive developer pane."""
    from .menu import run_menu

    run_menu()


def main() -> None:
    app()

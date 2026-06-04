"""Numbered SQL migration runner (ADR-0012). No ORM, no autogenerate.

Baseline (0001) = the canonical schema (specs/schema/verity_schema.sql, structure-only) plus
the separated seeds (specs/schema/seed/). Subsequent changes are forward, numbered
hub/db/migrations/NNNN_*.sql, applied in order and tracked in public.schema_migrations.

Run:  python -m hub.migrate
"""
from __future__ import annotations

import re
from pathlib import Path

import psycopg

from .config import get_settings
from .paths import component_root, repo_root

SCHEMA_DIR = repo_root() / "specs" / "schema"                  # canonical schema (hub owns the runner)
MIGRATIONS_DIR = component_root() / "db" / "migrations"


def expand_loader(loader: Path) -> str:
    """Inline a psql `\\i`-style loader into one SQL script (psycopg can't run `\\i`)."""
    base = loader.parent
    out: list[str] = []
    for line in loader.read_text().splitlines():
        s = line.strip()
        m = re.match(r"\\i\s+(.+)$", s)
        if m:
            out.append((base / m.group(1).strip()).read_text())
        elif s.startswith("\\"):
            continue  # drop other psql meta-commands
        else:
            out.append(line)
    return "\n".join(out)


def _applied(conn: psycopg.Connection) -> set[str]:
    conn.execute(
        "CREATE TABLE IF NOT EXISTS public.schema_migrations "
        "(version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())"
    )
    return {r[0] for r in conn.execute("SELECT version FROM public.schema_migrations").fetchall()}


def _record(conn: psycopg.Connection, version: str) -> None:
    conn.execute("INSERT INTO public.schema_migrations (version) VALUES (%s)", (version,))


def run() -> None:
    settings = get_settings()
    with psycopg.connect(settings.database_url) as conn:  # autocommit off; commit per migration
        done = _applied(conn)
        conn.commit()

        if "0001_baseline" not in done:
            conn.execute(expand_loader(SCHEMA_DIR / "verity_schema.sql"))
            conn.execute((SCHEMA_DIR / "seed" / "reference_seed.sql").read_text())
            conn.execute((SCHEMA_DIR / "seed" / "core_seed.sql").read_text())
            _record(conn, "0001_baseline")
            conn.commit()
            print("applied 0001_baseline (canonical schema + seeds)")

        if MIGRATIONS_DIR.exists():
            for f in sorted(MIGRATIONS_DIR.glob("[0-9]*.sql")):
                if f.stem in done:
                    continue
                conn.execute(f.read_text())
                _record(conn, f.stem)
                conn.commit()
                print(f"applied {f.stem}")

    print("migrations up to date")


def reset() -> None:
    """DEV ONLY: drop the app schemas + migration ledger and rebuild from the canonical DDL.

    The preferred pre-stability workflow (ADR-0012): while the schema churns, recreate from
    clean DDL rather than accumulate patches. Fail-closed outside local.
    """
    settings = get_settings()
    if settings.env != "local":
        raise RuntimeError("FATAL: `reset` (destructive recreate) requires VERITY_ENV=local.")
    with psycopg.connect(settings.database_url) as conn:
        for schema in ("reference", "core", "audit"):
            conn.execute(f"DROP SCHEMA IF EXISTS {schema} CASCADE")
        conn.execute("DROP TABLE IF EXISTS public.schema_migrations")
        conn.commit()
    print("reset: dropped reference/core/audit + schema_migrations")
    run()  # rebuild the baseline (canonical schema + seeds)


def main(argv: list[str] | None = None) -> None:
    import sys

    cmd = (argv if argv is not None else sys.argv[1:])[:1] or ["up"]
    match cmd[0]:
        case "reset":
            reset()
        case "up":
            run()
        case other:
            raise SystemExit(f"usage: python -m verity.hub.migrate [up|reset] (got {other!r})")


if __name__ == "__main__":
    main()

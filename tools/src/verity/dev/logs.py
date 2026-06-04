"""Aggregate logs from the dev containers + the hub (uvicorn) into one colored stream —
no more tailing three terminals."""
from __future__ import annotations

import itertools
import subprocess
import sys
import threading

from verity.dev.config import CONTAINERS, UVICORN_LOG

_COLORS = ["36", "32", "33", "35", "34", "31"]  # cyan green yellow magenta blue red


def _pump(label: str, color: str, proc: subprocess.Popen) -> None:
    assert proc.stdout is not None
    for line in proc.stdout:
        sys.stdout.write(f"\033[{color}m{label:>8}\033[0m │ {line}")
        sys.stdout.flush()


def tail(services: list[str], tail_n: int = 20) -> None:
    sources: list[tuple[str, list[str]]] = []
    for key in services:
        if key in CONTAINERS:
            sources.append((key, ["docker", "logs", "-f", "--tail", str(tail_n), CONTAINERS[key].name]))
    if UVICORN_LOG.exists():
        sources.append(("uvicorn", ["tail", "-n", str(tail_n), "-f", str(UVICORN_LOG)]))
    if not sources:
        print("no log sources — start the stack / hub first")
        return

    colors = itertools.cycle(_COLORS)
    procs: list[subprocess.Popen] = []
    threads: list[threading.Thread] = []
    print(f"aggregating: {', '.join(lbl for lbl, _ in sources)}   (Ctrl-C to stop)\n")
    for label, cmd in sources:
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        procs.append(p)
        t = threading.Thread(target=_pump, args=(label, next(colors), p), daemon=True)
        t.start()
        threads.append(t)
    try:
        while any(p.poll() is None for p in procs):
            for t in threads:
                t.join(timeout=0.3)
    except KeyboardInterrupt:
        pass
    finally:
        for p in procs:
            p.terminate()

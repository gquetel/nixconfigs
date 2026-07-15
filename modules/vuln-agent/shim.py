#!/usr/bin/env python3
"""Runner for the autonomous vulnerability-research agent.

Drives Claude Code headless in a loop: each iteration runs one pass of the
Operating Loop, then the shim decides whether to start another. Two stop
conditions: clock cutoff or usage signal.

Config comes from the environment (see below). The agent brain lives in
CLAUDE.md in the working directory; this script only orchestrates.
"""

from __future__ import annotations

import json
import os
import re
import signal
import subprocess
import sys
import time
from datetime import datetime

# --------------------------------------------------------------------------- #
# Config
# --------------------------------------------------------------------------- #

def _env(name: str, default: str) -> str:
    return os.environ.get(name, default)

def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default

# Local time (HH:MM) on or after which no message should be sent.
CUTOFF = _env("VA_CUTOFF", "04:00")

# Backoff (seconds).
WAIT_SERVER_ERR = _env_int("VA_WAIT_SERVER_ERR", 120)
WAIT_CLEAN      = _env_int("VA_WAIT_CLEAN", 5)

CLAUDE_BIN = _env("VA_CLAUDE_BIN", "claude")
MODEL = _env("VA_MODEL", "sonnet")

RESUME_PROMPT = _env(
    "VA_RESUME_PROMPT",
    "Read CLAUDE.md. Pull the active work item and its comments from Plane, "
    "run exactly one iteration of the Operating Loop, then stop.",
)

# --------------------------------------------------------------------------- #
# Reactive detection patterns (checked against every streamed line)
# --------------------------------------------------------------------------- #

USAGE_LIMIT_PATTERNS = [
    re.compile(r"hit your (session|usage) limit", re.I),
    re.compile(r"usage limit reached", re.I),
    re.compile(r"rate_limit_error", re.I),
]
SERVER_ERROR_PATTERNS = [
    re.compile(r"\b5\d\d\b.*(error|bad gateway|gateway timeout)", re.I),
    re.compile(r"error 5\d\d", re.I),
    re.compile(r"retry_after", re.I),
    re.compile(r"overloaded_error", re.I),
]

def matches_any(line: str, patterns) -> bool:
    return any(p.search(line) for p in patterns)

# --------------------------------------------------------------------------- #
# Clock cutoff
# --------------------------------------------------------------------------- #

def local_now() -> datetime:
    return datetime.now().astimezone()

def cutoff_dt() -> datetime:
    """Instant after which no message may be sent, today in local time.
    """
    hh, mm = (int(x) for x in CUTOFF.split(":"))
    return local_now().replace(hour=hh, minute=mm, second=0, microsecond=0)

def preflight() -> tuple[bool, str]:
    """Return (ok_to_run, reason). ok_to_run=False means stop for the night."""
    if local_now() >= cutoff_dt():
        return False, f"clock cutoff {CUTOFF} reached"
    return True, "ok"

# --------------------------------------------------------------------------- #
# Docker cleanup between iterations (belt-and-suspenders; CLAUDE.md also prunes)
# --------------------------------------------------------------------------- #

def docker_cleanup() -> None:
    try:
        ids = subprocess.run(
            ["docker", "ps", "-q"], capture_output=True, text=True, timeout=30
        ).stdout.split()
        for cid in ids:
            subprocess.run(["docker", "stop", cid], capture_output=True, timeout=60)
            subprocess.run(["docker", "rm", cid], capture_output=True, timeout=60)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass  # docker is a fallback path; absence/hang is non-fatal

# --------------------------------------------------------------------------- #
# Stream formatting
# --------------------------------------------------------------------------- #

def _truncate(s: str, n: int = 120) -> str:
    s = " ".join(str(s).split())
    return s if len(s) <= n else s[: n - 1] + "…"

def format_stream_line(evt: dict) -> str | None:
    """Pretty one-liner for a stream-json event, or None to skip."""
    t = evt.get("type")
    if t == "assistant":
        parts = []
        for block in evt.get("message", {}).get("content", []):
            if block.get("type") == "text":
                parts.append(_truncate(block["text"]))
            elif block.get("type") == "tool_use":
                arg = ""
                inp = block.get("input", {})
                if isinstance(inp, dict) and inp:
                    first = next(iter(inp.values()))
                    arg = _truncate(first)
                parts.append(f"→ {block.get('name')}({arg})")
        return "  ".join(p for p in parts if p) or None
    if t == "user":
        for block in evt.get("message", {}).get("content", []):
            if block.get("type") == "tool_result":
                c = block.get("content")
                if isinstance(c, list):
                    c = " ".join(b.get("text", "") for b in c if isinstance(b, dict))
                return f"  ⤶ {_truncate(c)}"
    if t == "result":
        return f"[result] {_truncate(evt.get('result', ''), 200)}"
    return None

# --------------------------------------------------------------------------- #
# One Claude invocation
# --------------------------------------------------------------------------- #

_child: subprocess.Popen | None = None

def run_claude() -> str:
    """Run one iteration. Returns an exit reason:
    'usage_limit' | 'server_error' | 'clean' | 'cutoff'.

    The iteration is killed at the clock cutoff, so no message is sent past it.
    """
    global _child
    cmd = [
        CLAUDE_BIN, "--print",
        "--model", MODEL,
        "--dangerously-skip-permissions",
        "--output-format", "stream-json",
        "--verbose",
        RESUME_PROMPT,
    ]
    print(f"\n=== iteration @ {local_now().isoformat()} ===", flush=True)
    _child = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1
    )

    reason = "clean"
    cutoff_ts = cutoff_dt().timestamp()

    try:
        for line in _child.stdout:  # type: ignore[union-attr]
            line = line.rstrip("\n")
            if not line:
                continue

            if matches_any(line, USAGE_LIMIT_PATTERNS):
                reason = "usage_limit"
                _kill_child()
                break
            if matches_any(line, SERVER_ERROR_PATTERNS):
                reason = "server_error"
                _kill_child()
                break

            try:
                evt = json.loads(line)
            except json.JSONDecodeError:
                print(line, flush=True)
                continue

            pretty = format_stream_line(evt)
            if pretty:
                print(pretty, flush=True)

            if time.time() >= cutoff_ts:
                reason = "cutoff"
                _kill_child()
                break
    finally:
        if _child:
            _child.wait()

    return reason

def _kill_child() -> None:
    global _child
    if _child and _child.poll() is None:
        _child.terminate()
        try:
            _child.wait(timeout=15)
        except subprocess.TimeoutExpired:
            _child.kill()

# --------------------------------------------------------------------------- #
# Main loop
# --------------------------------------------------------------------------- #

_stop = False

def _on_term(signum, frame):
    global _stop
    _stop = True
    _kill_child()

def main() -> int:
    signal.signal(signal.SIGTERM, _on_term)
    signal.signal(signal.SIGINT, _on_term)

    while not _stop:
        ok, why = preflight()
        if not ok:
            print(f"[preflight] stopping for the night: {why}", flush=True)
            break

        docker_cleanup()
        reason = run_claude()

        if _stop:
            break
        if reason == "usage_limit":
            print("[reactive] session/usage limit hit — stopping for the night", flush=True)
            break
        if reason == "cutoff":
            print("[reactive] clock cutoff reached — stopping for the night", flush=True)
            break
        if reason == "server_error":
            print(f"[reactive] server error — backing off {WAIT_SERVER_ERR}s", flush=True)
            time.sleep(WAIT_SERVER_ERR)
        else:
            time.sleep(WAIT_CLEAN)

    docker_cleanup()
    print("[shim] exiting", flush=True)
    return 0

if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Runner for the autonomous vulnerability-research agent.

Driven by systemd as `vuln-agent@<mode>.service`, where <mode> is:

  nightly : started by a 23:00 timer. Runs until the next 04:00 (STOP_AT spans
            midnight from the 23:00 start). Refuses to run outside the
            23:00-04:00 window, so a stray start can't run all day.
  manual  : started by the guest poller when the operator drops a trigger. Runs
            for VA_MANUAL_MIN minutes (default 60), any time of day. A manual run
            preempts a nightly one (the poller stops nightly before starting it).

Each iteration runs one pass of the Operating Loop, then the shim decides whether
to start another. Stop conditions: the STOP_AT instant, or a usage signal from
the stream. The agent brain lives in CLAUDE.md; this script only orchestrates.
"""

from __future__ import annotations

import json
import os
import re
import signal
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

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

MODE = _env("VA_MODE", "nightly")  # "nightly" | "manual"

# Nightly window (local HH:MM). The session runs between START and END, with END
# on the following day — i.e. the window crosses midnight (23:00 -> 04:00).
NIGHT_START = _env("VA_NIGHT_START", "23:00")
NIGHT_END = _env("VA_CUTOFF", "04:00")
# Manual runs are wall-clock boxed to this many minutes instead.
MANUAL_MIN = _env_int("VA_MANUAL_MIN", 60)

# Backoff (seconds).
WAIT_SERVER_ERR = _env_int("VA_WAIT_SERVER_ERR", 120)
WAIT_CLEAN      = _env_int("VA_WAIT_CLEAN", 5)

CLAUDE_BIN = _env("VA_CLAUDE_BIN", "claude")
MODEL = _env("VA_MODEL", "sonnet")

# A manual run may carry a custom resume-prompt: the guest poller copies the
# operator's trigger text here (root-written, agent-readable) before starting us.
PROMPT_FILE = Path(_env("VA_PROMPT_FILE", "/work/state/manual.prompt"))

DEFAULT_PROMPT = (
    "Read CLAUDE.md. Pull the active work item and its comments from Plane, "
    "run exactly one iteration of the Operating Loop, then stop."
)
RESUME_PROMPT = _env("VA_RESUME_PROMPT", DEFAULT_PROMPT)

# Absolute instant (epoch seconds) after which no new message may be sent and any
# in-flight iteration is killed. Set in main() once the mode is known.
STOP_AT = 0.0

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
# Clock window / stop instant
# --------------------------------------------------------------------------- #

def local_now() -> datetime:
    return datetime.now().astimezone()

def _hhmm(s: str) -> tuple[int, int]:
    hh, mm = (int(x) for x in s.split(":"))
    return hh, mm

def in_night_window(now: datetime | None = None) -> bool:
    """True if `now` is inside the [NIGHT_START, NIGHT_END) window that crosses
    midnight (e.g. 23:00 <= now, or now < 04:00)."""
    now = now or local_now()
    s_h, s_m = _hhmm(NIGHT_START)
    e_h, e_m = _hhmm(NIGHT_END)
    start = now.replace(hour=s_h, minute=s_m, second=0, microsecond=0)
    end = now.replace(hour=e_h, minute=e_m, second=0, microsecond=0)
    return now >= start or now < end

def next_night_end() -> datetime:
    """Next occurrence of NIGHT_END (today if still ahead, else tomorrow). From a
    23:00 start this lands on tomorrow 04:00, giving the full 5h window."""
    e_h, e_m = _hhmm(NIGHT_END)
    end = local_now().replace(hour=e_h, minute=e_m, second=0, microsecond=0)
    if local_now() >= end:
        end += timedelta(days=1)
    return end

def compute_stop_at() -> float:
    if MODE == "manual":
        return time.time() + MANUAL_MIN * 60
    return next_night_end().timestamp()

def load_manual_prompt() -> None:
    """Adopt the operator's custom resume-prompt for this manual run, if any.
    Read-only: the poller owns the file's lifecycle (agent can't write here)."""
    global RESUME_PROMPT
    try:
        txt = PROMPT_FILE.read_text().strip()
    except (FileNotFoundError, PermissionError):
        txt = ""
    if txt:
        RESUME_PROMPT = txt
        print("[request] manual run with custom prompt", flush=True)
    else:
        print("[request] manual run with default prompt", flush=True)

def preflight() -> tuple[bool, str]:
    """Return (ok_to_run, reason). ok_to_run=False means stop the session."""
    if MODE == "nightly" and not in_night_window():
        return False, "outside night window"
    if time.time() >= STOP_AT:
        return False, "stop instant reached"
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

    The iteration is killed at STOP_AT, so no message is sent past it.
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

            if time.time() >= STOP_AT:
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
    global STOP_AT
    signal.signal(signal.SIGTERM, _on_term)
    signal.signal(signal.SIGINT, _on_term)

    if MODE == "manual":
        load_manual_prompt()
    STOP_AT = compute_stop_at()
    print(f"[shim] mode={MODE} stop_at="
          f"{datetime.fromtimestamp(STOP_AT).astimezone().isoformat()}", flush=True)

    while not _stop:
        ok, why = preflight()
        if not ok:
            print(f"[preflight] stopping: {why}", flush=True)
            break

        docker_cleanup()
        reason = run_claude()

        if _stop:
            break
        if reason == "usage_limit":
            print("[reactive] session/usage limit hit — stopping", flush=True)
            break
        if reason == "cutoff":
            print("[reactive] stop instant reached — stopping", flush=True)
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

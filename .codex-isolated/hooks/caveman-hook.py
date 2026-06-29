#!/usr/bin/env python3
"""icodex caveman UserPromptSubmit hook.

Injects the active caveman mode into model context only when the session's
current mode deviates from the active launch mode (ICODEX_CAVEMAN_MODE), so the
steady state costs zero tokens. Also handles in-session /caveman switches.
Registered only when caveman is enabled (see lib/caveman/caveman.sh).
"""
import json
import os
import re
import sys

MODES = ("off", "lite", "full", "ultra")
SWITCH_RE = re.compile(r"^\s*/caveman\s+(off|lite|full|ultra)\b", re.IGNORECASE)
STOP_RE = re.compile(r"^\s*(stop caveman|normal mode)\s*$", re.IGNORECASE)

STYLE = {
    "lite": "lite — drop filler words only; keep articles and full sentences.",
    "full": "full — drop articles, filler, pleasantries; fragments OK; short synonyms.",
    "ultra": "ultra — fragments + maximum abbreviation; technical terms exact.",
}
DISABLED = ("CAVEMAN DISABLED for this session — respond normally; "
            "ignore the caveman block.")


def state_path(session_id):
    home = os.environ.get("CODEX_HOME", os.path.expanduser("~/.codex"))
    sid = re.sub(r"[^A-Za-z0-9_.-]", "_", session_id or "default")
    return os.path.join(home, ".caveman", "mode-" + sid)


def read_mode(path, fallback):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            value = fh.read().strip()
        return value if value in MODES else fallback
    except FileNotFoundError:
        return fallback


def write_mode(path, mode):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(mode)


def emit(text):
    if text:
        json.dump({"hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": text,
        }}, sys.stdout)
    sys.exit(0)


def active_line(mode):
    return "CAVEMAN ACTIVE MODE: %s Apply the '%s' row of the caveman mode table." % (
        STYLE[mode], mode)


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        emit("")  # malformed input -> no-op
    prompt = data.get("prompt", "") or ""
    session_id = data.get("session_id", "") or ""

    launch_mode = os.environ.get("ICODEX_CAVEMAN_MODE", "full").strip().lower()
    if launch_mode not in MODES:
        launch_mode = "full"

    path = state_path(session_id)
    current = read_mode(path, launch_mode)

    switch = SWITCH_RE.match(prompt)
    if switch:
        new = switch.group(1).lower()
        write_mode(path, new)
        emit(DISABLED if new == "off" else active_line(new))
    if STOP_RE.match(prompt):
        write_mode(path, "off")
        emit(DISABLED)

    if current == launch_mode:
        emit("")  # AGENTS.md already specifies behaviour -> 0 tokens
    if current == "off":
        emit(DISABLED)
    emit(active_line(current))


if __name__ == "__main__":
    main()

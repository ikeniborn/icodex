#!/usr/bin/env python3
"""Name the current Codex thread after successful task-ledger lifecycle writes."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tomllib


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib" / "profile"))
from app_server import AppServerClient  # noqa: E402


TOOL_RE = re.compile(r"(?:mcp__(?:iwiki_remote|iwiki_local|iwiki)__)?wiki_(write|update)_page\Z")
TOPIC_RE = re.compile(r"reference/tasks/([a-z0-9]+(?:-[a-z0-9]+)*)\Z")
SESSION_RE = re.compile(r"[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\Z")
LIFECYCLE_RE = re.compile(
    r"(?:^|\.\s+)[ \t]*(?:[-*][ \t]+)?(?:\*\*)?Lifecycle(?:\*\*)?:[ \t]*(?:\*\*)?([a-z-]+)",
    re.MULTILINE | re.IGNORECASE,
)


def response_payload(value):
    """Reject MCP errors before using their successful mutation locator."""
    if not isinstance(value, dict) or value.get("isError") or "error" in value:
        return None
    if "content" not in value:
        return value
    content = value["content"]
    if not isinstance(content, list):
        return None
    payloads = []
    for item in content:
        if not isinstance(item, dict) or item.get("type") != "text":
            continue
        try:
            payload = json.loads(item.get("text", ""))
        except (TypeError, ValueError):
            return None
        if not isinstance(payload, dict) or payload.get("isError") or "error" in payload:
            return None
        payloads.append(payload)
    return payloads[0] if len(payloads) == 1 else None


def project_primary(cwd):
    result = subprocess.run(
        ["/usr/bin/git", "-C", str(cwd), "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, timeout=3, check=False,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "GIT_CONFIG_NOSYSTEM": "1"},
    )
    if result.returncode != 0:
        return None
    with (Path(result.stdout.strip()) / ".iwiki.toml").open("rb") as stream:
        primary = tomllib.load(stream).get("primary")
    return primary.strip().lower() if isinstance(primary, str) else None


def rename_thread(binary, home, cwd, session_id, title):
    """Bound the metadata-only App Server exchange, including startup."""
    def deadline(_signum, _frame):
        raise RuntimeError("thread title deadline exceeded")

    previous = signal.signal(signal.SIGALRM, deadline)
    signal.alarm(8)
    client = None
    try:
        client = AppServerClient(
            [str(binary), "app-server"], Path(cwd),
            env={**os.environ, "CODEX_HOME": str(home)},
        )
        client.request("initialize", {"clientInfo": {"name": "icodex-thread-title", "version": "1"}})
        client.notify("initialized", {})
        client.request("thread/name/set", {"threadId": session_id, "name": title})
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, previous)
        if client is not None:
            client.close()
            client.stdout.close()
            client.process.stderr.close()


def handle(event, environ):
    if not isinstance(event, dict) or event.get("hook_event_name") != "PostToolUse":
        return None
    tool = event.get("tool_name")
    match = TOOL_RE.fullmatch(tool) if isinstance(tool, str) else None
    params = event.get("tool_input")
    session_id = event.get("session_id")
    cwd = event.get("cwd")
    if (match is None or not isinstance(params, dict) or not isinstance(session_id, str)
            or SESSION_RE.fullmatch(session_id) is None or not isinstance(cwd, str) or not cwd):
        return None
    slug = params.get("slug")
    topic = TOPIC_RE.fullmatch(slug) if isinstance(slug, str) else None
    response = response_payload(event.get("tool_response"))
    domain = params.get("domain")
    if topic is None or response is None or not isinstance(domain, str):
        return None
    if response.get("page") != f"{domain}/{slug}.md":
        return None
    if match.group(1) == "write":
        markdown = params.get("markdown")
        if not isinstance(markdown, str):
            return None
        section = re.search(r"^## Current State\s*\n(.*?)(?=^## |\Z)", markdown, re.MULTILINE | re.DOTALL)
        body = section.group(1) if section else ""
    else:
        if params.get("heading") != "Current State" or response.get("heading", "Current State") != "Current State":
            return None
        body = params.get("new_body")
    if not isinstance(body, str):
        return None
    body = re.sub(r"^```[^\n]*\n.*?^```[^\n]*$", "", body, flags=re.MULTILINE | re.DOTALL)
    states = LIFECYCLE_RE.findall(body)
    if len(states) != 1 or states[0] not in {"in-progress", "done"}:
        return None
    try:
        if project_primary(cwd) != domain:
            return None
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None
    try:
        home = Path(environ.get("CODEX_HOME", ""))
        if not home.is_absolute() or Path(environ.get("ICODEX_ROOT", "")).resolve() != ROOT:
            raise ValueError("invalid title runtime paths")
        suffix = "done" if states[0] == "done" else "inprogress"
        rename_thread(ROOT / ".codex-isolated" / "bin" / "codex", home, cwd, session_id, f"{topic.group(1)}-{suffix}")
    except Exception as error:
        return {"hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": f"Thread title update failed ({type(error).__name__}). Task execution can continue; the previous title may remain.",
        }}
    return None


def main():
    try:
        event = json.load(sys.stdin)
    except (TypeError, ValueError):
        return 0
    result = handle(event, os.environ)
    if result is not None:
        print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

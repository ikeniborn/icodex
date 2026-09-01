#!/usr/bin/env python3
"""Enforce context-before-mutation ordering for explicit iwiki GWT scenarios.

The hook records successful ``wiki_spec_context`` calls per Codex session. An
unclassified ``wiki_update_page`` receives a context nudge; when context exists, the
hook enforces matching domain and scenario IDs. Successful mutations consume that
evidence. The hook never calls MCP or writes Wiki content.
"""

import json
import os
import re
import sys
import time
import tomllib


CONTEXT_MAX_AGE_SECONDS = 2 * 60 * 60
FENCE_RE = re.compile(r"```iwiki-gwt[ \t]*\n(.*?)```", re.DOTALL)
ID_RE = re.compile(r'^\s*id\s*=\s*"([^"\n]+)"\s*(?:#.*)?$', re.MULTILINE)


def _tool_suffix(name):
    return (name or "").rsplit("__", 1)[-1]


def _state_path():
    home = os.environ.get("CODEX_HOME")
    return os.path.join(home, "state", "gwt-contexts.json") if home else None


def _load_state():
    path = _state_path()
    if not path or not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as stream:
            data = json.load(stream)
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    cutoff = time.time() - CONTEXT_MAX_AGE_SECONDS
    clean = {}
    for session_id, entries in data.items():
        if not isinstance(entries, dict):
            continue
        kept = {
            key: stamp for key, stamp in entries.items()
            if isinstance(key, str) and isinstance(stamp, (int, float)) and stamp >= cutoff
        }
        if kept:
            clean[session_id] = kept
    return clean


def _save_state(state):
    path = _state_path()
    if not path:
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = "%s.%d.tmp" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as stream:
        json.dump(state, stream, sort_keys=True)
    os.replace(tmp, path)


def _key(domain, scenario_id):
    return "%s\0%s" % (domain, scenario_id)


def _scenario_ids(params):
    if not isinstance(params, dict):
        return []
    body = params.get("new_body")
    if not isinstance(body, str):
        return []
    return [match.group(1) for fence in FENCE_RE.findall(body) for match in ID_RE.finditer(fence)]


def _response_failed(data):
    response = data.get("tool_response")
    return isinstance(response, dict) and (
        response.get("isError") is True or response.get("error") is not None
    )


def _specification_disabled(data):
    cwd = data.get("cwd")
    if not isinstance(cwd, str) or not cwd:
        return False
    try:
        with open(os.path.join(cwd, ".iwiki.toml"), "rb") as stream:
            config = tomllib.load(stream)
    except (OSError, tomllib.TOMLDecodeError):
        return False
    specifications = config.get("specifications")
    return isinstance(specifications, dict) and specifications.get("mode") == "disabled"


def _record_context(data):
    if _response_failed(data):
        return
    params = data.get("tool_input") or {}
    session_id = data.get("session_id")
    domain = params.get("domain") if isinstance(params, dict) else None
    scenario_id = params.get("scenario_id") if isinstance(params, dict) else None
    if not all(isinstance(value, str) and value for value in (session_id, domain, scenario_id)):
        return
    state = _load_state()
    state.setdefault(session_id, {})[_key(domain, scenario_id)] = int(time.time())
    _save_state(state)


def _consume_context(data):
    if _response_failed(data):
        return
    params = data.get("tool_input") or {}
    session_id = data.get("session_id")
    domain = params.get("domain") if isinstance(params, dict) else None
    scenario_ids = _scenario_ids(params)
    if not session_id or not domain or not scenario_ids:
        return
    state = _load_state()
    entries = state.get(session_id, {})
    for scenario_id in scenario_ids:
        entries.pop(_key(domain, scenario_id), None)
    if entries:
        state[session_id] = entries
    else:
        state.pop(session_id, None)
    _save_state(state)


def _nudge_context(domain, scenario_ids):
    message = (
        "GWT update contains scenario ID(s) %s in domain %r but the hook cannot infer "
        "whether they already exist. Call wiki_spec_context before mutating an existing "
        "scenario; use an ordinary create path for a new scenario."
        % (", ".join(scenario_ids), domain)
    )
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": message,
        }
    }))


def _check_context(data):
    if _specification_disabled(data):
        return
    params = data.get("tool_input") or {}
    scenario_ids = _scenario_ids(params)
    if not scenario_ids:
        return
    session_id = data.get("session_id")
    domain = params.get("domain") if isinstance(params, dict) else None
    state = _load_state()
    entries = state.get(session_id, {}) if session_id else {}
    domain_prefix = "%s\0" % domain
    domain_entries = {key for key in entries if key.startswith(domain_prefix)}
    if not domain_entries:
        _nudge_context(domain, scenario_ids)
        return
    missing = [scenario_id for scenario_id in scenario_ids if _key(domain, scenario_id) not in entries]
    if not missing:
        return
    sys.stderr.write(
        "GWT gate: call wiki_spec_context for domain %r and scenario ID(s) %s "
        "before updating the existing scenario.\n" % (domain, ", ".join(missing))
    )
    sys.exit(2)


def main():
    try:
        data = json.loads(sys.stdin.read())
    except (ValueError, TypeError):
        return
    if not isinstance(data, dict):
        return
    tool = _tool_suffix(data.get("tool_name"))
    post = "--post" in sys.argv[1:] or data.get("hook_event_name") == "PostToolUse"
    try:
        if post and tool == "wiki_spec_context":
            _record_context(data)
        elif post and tool == "wiki_update_page":
            _consume_context(data)
        elif not post and tool == "wiki_update_page":
            _check_context(data)
    except OSError as exc:
        print("GWT gate: state unavailable, skipping: %s" % exc, file=sys.stderr)


if __name__ == "__main__":
    main()

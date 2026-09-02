#!/usr/bin/env python3
"""Enforce effective mode and context ordering for explicit iwiki GWT scenarios.

The hook records effective modes from trusted ``wiki_status`` responses and successful
``wiki_spec_context`` calls per Codex session. It checks both before GWT-bearing page
updates. Successful mutations consume context evidence. The hook never calls MCP or
writes Wiki content.
"""

import json
import os
import re
import sys
import time


CONTEXT_MAX_AGE_SECONDS = 2 * 60 * 60
STATUS_MAX_AGE_SECONDS = 30 * 60
VALID_MODES = {"disabled", "optional", "strict"}
FENCE_RE = re.compile(r"```iwiki-gwt[ \t]*\n(.*?)```", re.DOTALL)
ID_RE = re.compile(r'^\s*id\s*=\s*"([^"\n]+)"\s*(?:#.*)?$', re.MULTILINE)


def _tool_suffix(name):
    if not isinstance(name, str):
        return ""
    return name.rsplit("__", 1)[-1]


def _state_path():
    home = os.environ.get("CODEX_HOME")
    return os.path.join(home, "state", "gwt-contexts.json") if home else None


def _status_path():
    home = os.environ.get("CODEX_HOME")
    return os.path.join(home, "state", "gwt-status.json") if home else None


def _validated_response_payload(payload):
    if not isinstance(payload, dict):
        return None
    if payload.get("isError") is True or "error" in payload:
        return None
    return payload


def _response_payload(data):
    response = _validated_response_payload(data.get("tool_response"))
    if response is None:
        return None
    content = response.get("content")
    if content is None:
        return response
    if not isinstance(content, list):
        return None
    for item in content:
        if not isinstance(item, dict) or item.get("type") != "text":
            continue
        try:
            payload = json.loads(item.get("text", ""))
        except (TypeError, ValueError):
            continue
        if isinstance(payload, dict):
            return _validated_response_payload(payload)
    return None


def _load_status():
    path = _status_path()
    if not path or not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as stream:
            data = json.load(stream)
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    cutoff = time.time() - STATUS_MAX_AGE_SECONDS
    clean = {}
    for session_id, domains in data.items():
        if not isinstance(session_id, str) or not isinstance(domains, dict):
            continue
        kept = {}
        for domain, entry in domains.items():
            if not isinstance(domain, str) or not isinstance(entry, dict):
                continue
            mode = entry.get("mode")
            stamp = entry.get("timestamp")
            if mode in VALID_MODES and isinstance(stamp, (int, float)) and stamp >= cutoff:
                kept[domain] = {"mode": mode, "timestamp": stamp}
        if kept:
            clean[session_id] = kept
    return clean


def _save_status(state):
    path = _status_path()
    if not path:
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = "%s.%d.tmp" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as stream:
        json.dump(state, stream, sort_keys=True)
    os.replace(tmp, path)


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


def _record_status(data):
    payload = _response_payload(data)
    session_id = data.get("session_id")
    if not isinstance(session_id, str) or not session_id:
        return
    state = _load_status()
    state.pop(session_id, None)
    if not isinstance(payload, dict):
        _save_status(state)
        return
    hosted = payload.get("transport") == "streamable-http"
    if hosted and payload.get("binding_source") != "session":
        _save_status(state)
        return
    if payload.get("primary_substituted") is True:
        _save_status(state)
        return
    specifications = payload.get("specifications")
    rows = specifications.get("domains") if isinstance(specifications, dict) else None
    if not isinstance(rows, list):
        _save_status(state)
        return
    stamp = int(time.time())
    domains = {}
    for row in rows:
        if not isinstance(row, dict):
            continue
        domain = row.get("domain")
        mode = row.get("mode")
        if isinstance(domain, str) and domain and mode in VALID_MODES:
            domains[domain] = {"mode": mode, "timestamp": stamp}
    if domains:
        state[session_id] = domains
    _save_status(state)


def _effective_mode(data, domain):
    session_id = data.get("session_id")
    if not isinstance(session_id, str) or not isinstance(domain, str):
        return None
    entry = _load_status().get(session_id, {}).get(domain)
    return entry.get("mode") if isinstance(entry, dict) else None


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
    params = data.get("tool_input") or {}
    scenario_ids = _scenario_ids(params)
    if not scenario_ids:
        return
    session_id = data.get("session_id")
    domain = params.get("domain") if isinstance(params, dict) else None
    mode = _effective_mode(data, domain)
    if mode is None:
        sys.stderr.write(
            "GWT gate: call wiki_bind and wiki_status for domain %r before mutating an iwiki-gwt scenario.\n"
            % domain
        )
        sys.exit(2)
    if mode == "disabled":
        return
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
        if post and tool == "wiki_status":
            _record_status(data)
        elif post and tool == "wiki_spec_context":
            _record_context(data)
        elif post and tool == "wiki_update_page":
            _consume_context(data)
        elif not post and tool == "wiki_update_page":
            _check_context(data)
    except OSError as exc:
        print("GWT gate: state unavailable, skipping: %s" % exc, file=sys.stderr)


if __name__ == "__main__":
    main()

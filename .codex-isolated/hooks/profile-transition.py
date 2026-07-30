#!/usr/bin/env python3
"""Validate protected tool use against one routed profile decision."""

from __future__ import annotations

import importlib.util
import json
import os
import re
import shlex
import sys
from collections.abc import Mapping
from contextlib import contextmanager
from pathlib import Path
from types import ModuleType


READ_ONLY_TOOLS = {"Read", "Glob", "Grep"}
MUTATING_TOOLS = {"Write", "Edit", "apply_patch"}

CORRELATION_ENV = (
    "ICODEX_PROFILE_RUN_ID",
    "ICODEX_PROFILE_SEQUENCE",
    "ICODEX_PROFILE_REQUEST_ID",
)
SHELL_META_RE = re.compile(r"[|&;<>{}()`$\n\r]")
SHELL_ASSIGNMENT_RE = re.compile(r"(?:^|\s)[A-Za-z_][A-Za-z0-9_]*=")
FIND_ACTIONS = {
    "-delete",
    "-exec",
    "-execdir",
    "-fls",
    "-fprint",
    "-fprint0",
    "-fprintf",
    "-ok",
    "-okdir",
}
GIT_WRITE_OPTIONS = {"--output", "-o"}
RG_EXEC_OPTIONS = {"--pre", "--hostname-bin"}


def _tool_input(event: Mapping[str, object]) -> object:
    return event.get("tool_input", event.get("input", event.get("arguments", {})))


def _command(event: Mapping[str, object]) -> str:
    value = _tool_input(event)
    if isinstance(value, str):
        return value
    if isinstance(value, Mapping):
        command = value.get("command", value.get("cmd", ""))
        return command if isinstance(command, str) else ""
    return ""


def _read_path(event: Mapping[str, object]) -> str:
    value = _tool_input(event)
    if not isinstance(value, Mapping):
        return ""
    for key in ("file_path", "path", "target_file", "target_path"):
        path = value.get(key)
        if isinstance(path, str):
            return path
    return ""


def _safe_shell_discovery(command: str) -> bool:
    if not command or SHELL_META_RE.search(command) or SHELL_ASSIGNMENT_RE.search(command):
        return False
    try:
        argv = shlex.split(command, posix=True)
    except ValueError:
        return False
    if not argv:
        return False
    if argv[0] == "rg":
        return not any(
            argument in RG_EXEC_OPTIONS
            or any(argument.startswith(option + "=") for option in RG_EXEC_OPTIONS)
            for argument in argv[1:]
        )
    if argv[0] == "tree":
        return not any(
            argument in {"-o", "--output"} or argument.startswith("--output=")
            for argument in argv[1:]
        )
    if argv[:2] == ["sed", "-n"]:
        if any(argument == "-i" or argument.startswith("--in-place") for argument in argv[2:]):
            return False
        return not any(
            re.search(r"(?:^|[0-9$/,;])[we](?:\s|$)", argument)
            for argument in argv[2:]
        )
    if argv[0] == "find":
        return not any(argument in FIND_ACTIONS for argument in argv[1:])
    if argv[:2] in (
        ["git", "status"],
        ["git", "diff"],
        ["git", "show"],
        ["git", "log"],
        ["git", "rev-parse"],
    ):
        return not any(
            argument in GIT_WRITE_OPTIONS or argument.startswith("--output=")
            for argument in argv[2:]
        )
    return argv == ["git", "branch", "--show-current"]


def is_protected(event: dict[str, object]) -> bool:
    """Return false only for a closed read-only discovery allowlist."""
    tool = event.get("tool_name", event.get("tool", event.get("name", "")))
    if tool in MUTATING_TOOLS:
        return True
    if tool in READ_ONLY_TOOLS:
        if tool == "Read" and Path(_read_path(event)).name == "SKILL.md":
            return True
        return False
    if tool == "Bash":
        return not _safe_shell_discovery(_command(event))
    return True


def _load_state(environ: Mapping[str, str]) -> ModuleType:
    root_value = environ.get("ICODEX_ROOT", "")
    root = Path(root_value)
    if not root_value or not root.is_absolute():
        raise RuntimeError("ICODEX_ROOT must be absolute")
    state_path = root / "lib" / "profile" / "state.py"
    spec = importlib.util.spec_from_file_location("icodex_profile_state", state_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("profile state module is unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


@contextmanager
def _state_environment(environ: Mapping[str, str]):
    previous = {name: os.environ.get(name) for name in CORRELATION_ENV}
    try:
        for name in CORRELATION_ENV:
            os.environ[name] = environ[name]
        yield
    finally:
        for name, value in previous.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value


def _allow() -> dict[str, object]:
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": "Matching routed profile evidence",
        }
    }


def _remediation(topic: object = None, task_id: object = None) -> str:
    safe_slug = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
    if (
        isinstance(topic, str)
        and isinstance(task_id, str)
        and safe_slug.fullmatch(topic)
        and safe_slug.fullmatch(task_id)
    ):
        return f"icodex --run-task {topic} {task_id}"
    return "icodex --run-task <topic> <task-id>"


def _deny(reason: str, evidence: Mapping[str, object] | None = None) -> dict[str, object]:
    evidence = evidence or {}
    message = (
        f"Routed profile evidence denied: {reason}. "
        f"Restart through {_remediation(evidence.get('topic'), evidence.get('task_id'))}"
    )
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": message,
        }
    }


def _validated_handoff(state: ModuleType, state_root: Path, run_id: str, sequence: int):
    path = state_root / "consumed" / f"{run_id}.{sequence}.json"
    return state._validate_handoff(state._read_json(path))


def _matches_decision(
    state: ModuleType,
    state_root: Path,
    decision: Mapping[str, object],
    session_id: str,
    run_id: str,
    sequence: int,
    request_id: str,
    model: str,
) -> bool:
    if (
        decision.get("session_id") != session_id
        or decision.get("run_id") != run_id
        or decision.get("sequence") != sequence
        or str(decision.get("request_id")) != request_id
        or decision.get("model") != model
        or decision.get("observed_model") != model
        or decision.get("authorized") is not True
    ):
        return False
    handoff = _validated_handoff(state, state_root, run_id, sequence)
    persisted = {key: decision[key] for key in state.HANDOFF_KEYS}
    return handoff == persisted


def validate_event(event: dict[str, object], environ: Mapping[str, str]) -> dict[str, object]:
    """Consume the correlated handoff or validate its persisted session decision."""
    present = [bool(environ.get(name)) for name in CORRELATION_ENV]
    if not any(present):
        return {}
    if not all(present):
        return _deny("routed correlation environment is incomplete")
    if not is_protected(event):
        return {}

    run_id = environ["ICODEX_PROFILE_RUN_ID"]
    sequence_text = environ["ICODEX_PROFILE_SEQUENCE"]
    request_id = environ["ICODEX_PROFILE_REQUEST_ID"]
    session_id = event.get("session_id")
    model = event.get("model")
    if not isinstance(session_id, str) or not session_id:
        return _deny("hook session ID is missing")
    if not isinstance(model, str) or not model:
        return _deny("hook model evidence is missing")
    try:
        sequence = int(sequence_text)
        if sequence < 0 or str(sequence) != sequence_text:
            raise ValueError
    except ValueError:
        return _deny("routed sequence is invalid")

    evidence: Mapping[str, object] | None = None
    try:
        state = _load_state(environ)
        home_value = environ.get("CODEX_HOME", "")
        home = Path(home_value)
        if not home_value or not home.is_absolute():
            raise RuntimeError("CODEX_HOME must be absolute")
        state_root = state.routing_root(home)
        decision = state.load_decision(state_root, session_id)
        if decision is not None:
            evidence = decision
            if not _matches_decision(
                state,
                state_root,
                decision,
                session_id,
                run_id,
                sequence,
                request_id,
                model,
            ):
                raise state.StateError("persisted decision correlation mismatch")
            return _allow()

        try:
            evidence = _validated_handoff(state, state_root, run_id, sequence)
        except Exception:
            evidence = None
        with _state_environment(environ):
            decision = state.consume_handoff(state_root, run_id, sequence, session_id, model)
        if not _matches_decision(
            state,
            state_root,
            decision,
            session_id,
            run_id,
            sequence,
            request_id,
            model,
        ):
            raise state.StateError("new decision correlation mismatch")
        return _allow()
    except Exception as exc:
        return _deny(str(exc) or "routing evidence is unavailable", evidence)


def main() -> int:
    try:
        value = json.load(sys.stdin)
        event = value if isinstance(value, dict) else {}
    except (json.JSONDecodeError, TypeError, ValueError):
        event = {}
    result = validate_event(event, os.environ)
    if result:
        json.dump(result, sys.stdout)
        sys.stdout.write("\n")
    decision = result.get("hookSpecificOutput", {}) if result else {}
    return 2 if isinstance(decision, Mapping) and decision.get("permissionDecision") == "deny" else 0


if __name__ == "__main__":
    raise SystemExit(main())

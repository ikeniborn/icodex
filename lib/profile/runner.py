#!/usr/bin/env python3
"""Run explicit profile-routed tasks through Codex App Server."""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import os
import secrets
import sys
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

from app_server import AppServerClient, AppServerError
from policy import PolicyError, ValidatedPolicy, load_policy, select_validated_profile
from state import (
    SelectionTuple,
    StateError,
    atomic_json_write,
    cache_matches,
    create_handoff,
    load_decision,
    load_selection_cache,
    routing_root,
    save_selection_cache,
)


TRANSITION_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "transition": {"type": "string", "enum": ["complete", "needs_input", "blocked"]},
        "summary": {"type": "string"},
        "evidence": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["transition", "summary", "evidence"],
}


class RunnerError(Exception):
    pass


@dataclass(frozen=True)
class RunnerConfig:
    target_root: Path
    codex_home: Path
    shared_root: Path
    binary: Path

    def __post_init__(self) -> None:
        object.__setattr__(self, "target_root", self.target_root.resolve())
        object.__setattr__(self, "codex_home", self.codex_home.resolve())
        object.__setattr__(self, "shared_root", self.shared_root.resolve())
        object.__setattr__(self, "binary", self.binary.resolve())


@dataclass(frozen=True)
class _TaskResult:
    transition: str
    summary: str
    evidence: tuple[str, ...]
    selection: SelectionTuple
    session_id: str | None


def _canonical_json(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def _manifest_path(config: RunnerConfig, topic: str) -> Path:
    return config.target_root / "docs" / "profiles" / f"{topic}.yaml"


def _registry_path(config: RunnerConfig) -> Path:
    profiles = config.codex_home / "profiles"
    expected = config.shared_root / "profiles"
    if not profiles.is_symlink():
        raise RunnerError(f"shared profiles link is missing: {profiles}")
    try:
        actual = profiles.resolve(strict=True)
        canonical_expected = expected.resolve(strict=True)
    except OSError as exc:
        raise RunnerError(f"cannot resolve shared profiles link: {exc}") from exc
    if actual != canonical_expected:
        raise RunnerError(f"shared profiles link must resolve exactly to {canonical_expected}")
    return profiles / "registry.yaml"


def _load_policy(config: RunnerConfig, topic: str) -> ValidatedPolicy:
    manifest = _manifest_path(config, topic)
    registry = _registry_path(config)
    return load_policy(
        config.target_root,
        config.codex_home,
        config.shared_root,
        manifest,
        registry,
    )


def _tasks(policy: ValidatedPolicy) -> list[Mapping[str, object]]:
    raw_tasks = policy.manifest.get("tasks")
    if not isinstance(raw_tasks, Sequence) or isinstance(raw_tasks, (str, bytes)):
        raise RunnerError("validated policy has no task sequence")
    tasks: list[Mapping[str, object]] = []
    for value in raw_tasks:
        if not isinstance(value, Mapping) or not isinstance(value.get("id"), str):
            raise RunnerError("validated policy contains an invalid task")
        tasks.append(value)
    return tasks


def _task(policy: ValidatedPolicy, task_id: str) -> Mapping[str, object]:
    for task in _tasks(policy):
        if task["id"] == task_id:
            return task
    raise PolicyError(f"unknown task: {task_id}", 4)


def _fingerprint(task: Mapping[str, object]) -> str:
    requirements = task.get("requirements")
    if not isinstance(requirements, Mapping):
        raise RunnerError("validated task has no requirements")
    return hashlib.sha256(_canonical_json(dict(requirements))).hexdigest()


def _selection_tuple(
    policy: ValidatedPolicy,
    task_id: str,
    selected: Mapping[str, object],
) -> SelectionTuple:
    task = _task(policy, task_id)
    return SelectionTuple(
        target_root=policy.target_root,
        topic=policy.topic,
        task_id=task_id,
        requirement_fingerprint=_fingerprint(task),
        registry_commit=policy.registry_commit,
        registry_version=policy.registry_version,
        registry_hash=policy.registry_sha256,
        manifest_commit=policy.target_commit,
        manifest_hash=policy.manifest_sha256,
        profile=str(selected["profile"]),
        model=str(selected["model"]),
        effort=str(selected["effort"]),
    )


def _selection_from_state(value: object) -> SelectionTuple | None:
    if not isinstance(value, Mapping):
        return None
    try:
        return SelectionTuple(**dict(value))
    except TypeError:
        return None


def _read_run(state_root: Path) -> dict[str, object] | None:
    path = state_root / "run.json"
    try:
        with path.open(encoding="utf-8") as stream:
            value = json.load(stream)
    except FileNotFoundError:
        return None
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise RunnerError(f"local orchestration state is malformed: {exc}") from exc
    required = {"run_id", "sequence", "topic", "task_index", "task_id", "selection", "session_id"}
    if not isinstance(value, dict) or set(value) != required:
        raise RunnerError("local orchestration state has an invalid schema")
    if (
        not isinstance(value["run_id"], str)
        or not value["run_id"]
        or type(value["sequence"]) is not int
        or value["sequence"] < 1
        or not isinstance(value["topic"], str)
        or type(value["task_index"]) is not int
        or value["task_index"] < 0
        or value["task_id"] is not None and not isinstance(value["task_id"], str)
        or value["selection"] is not None and not isinstance(value["selection"], dict)
        or value["session_id"] is not None and not isinstance(value["session_id"], str)
    ):
        raise RunnerError("local orchestration state has invalid fields")
    return value


def _write_run(
    state_root: Path,
    *,
    run_id: str,
    sequence: int,
    topic: str,
    task_index: int,
    task_id: str | None,
    selection: SelectionTuple | None,
    session_id: str | None,
) -> None:
    atomic_json_write(
        state_root / "run.json",
        {
            "run_id": run_id,
            "sequence": sequence,
            "topic": topic,
            "task_index": task_index,
            "task_id": task_id,
            "selection": dataclasses.asdict(selection) if selection is not None else None,
            "session_id": session_id,
        },
    )


def _cached_selection(
    state_root: Path,
    run: Mapping[str, object],
    config: RunnerConfig,
    topic: str,
    task_id: str,
) -> SelectionTuple | None:
    selection = _selection_from_state(run.get("selection"))
    session_id = run.get("session_id")
    run_id = run.get("run_id")
    if (
        selection is None
        or not isinstance(session_id, str)
        or not isinstance(run_id, str)
        or selection.target_root != str(config.target_root)
        or selection.topic != topic
        or selection.task_id != task_id
    ):
        return None
    cache = load_selection_cache(state_root, run_id)
    decision = load_decision(state_root, session_id)
    if cache is None or decision is None:
        return None
    try:
        return selection if cache_matches(cache, selection, decision) else None
    except StateError:
        return None


def _app_server_launch(
    config: RunnerConfig,
    run_id: str,
    sequence: int,
    request_id: int,
) -> tuple[list[str], dict[str, str]]:
    environment = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith("ICODEX_PROFILE_") and key != "ICODEX_APP_SERVER_OPENAI_BASE_URL"
    }
    environment.update(
        {
            "ICODEX_PROFILE_RUN_ID": run_id,
            "ICODEX_PROFILE_SEQUENCE": str(sequence),
            "ICODEX_PROFILE_REQUEST_ID": str(request_id),
        }
    )
    command = [str(config.binary)]
    base_url = os.environ.get("ICODEX_APP_SERVER_OPENAI_BASE_URL")
    if base_url:
        command.extend(["-c", f'openai_base_url="{base_url}"'])
    command.append("app-server")
    return command, environment


def _model_list(client: AppServerClient) -> list[dict[str, object]]:
    result = client.request("model/list", {"limit": 100, "includeHidden": False})
    data = result.get("data")
    if not isinstance(data, list) or any(not isinstance(item, dict) for item in data):
        raise AppServerError("model/list returned an invalid data array")
    return data


def _thread_id(result: Mapping[str, object]) -> tuple[str, str]:
    thread = result.get("thread")
    if not isinstance(thread, Mapping):
        raise AppServerError("thread/start returned no thread")
    thread_id = thread.get("id")
    session_id = thread.get("sessionId", thread_id)
    if not isinstance(thread_id, str) or not thread_id or not isinstance(session_id, str) or not session_id:
        raise AppServerError("thread/start returned invalid thread identifiers")
    return thread_id, session_id


def _turn_id(result: Mapping[str, object]) -> str:
    turn = result.get("turn")
    if not isinstance(turn, Mapping) or not isinstance(turn.get("id"), str) or not turn["id"]:
        raise AppServerError("turn/start returned no turn ID")
    return str(turn["id"])


def _structured_transition(turn: Mapping[str, object]) -> tuple[str, str, tuple[str, ...]]:
    if turn.get("status") != "completed":
        raise RunnerError(f"App Server turn stopped with status: {turn.get('status')}")
    items = turn.get("items")
    if not isinstance(items, list):
        raise RunnerError("completed turn has no structured output")
    text: str | None = None
    for item in items:
        if isinstance(item, Mapping) and item.get("type") == "agentMessage" and isinstance(item.get("text"), str):
            text = item["text"]
    if text is None:
        raise RunnerError("completed turn has no final agent message")
    try:
        value = json.loads(text)
    except json.JSONDecodeError as exc:
        raise RunnerError("turn output is not valid structured JSON") from exc
    if not isinstance(value, dict) or set(value) != {"transition", "summary", "evidence"}:
        raise RunnerError("turn output does not match the transition schema")
    transition = value.get("transition")
    summary = value.get("summary")
    evidence = value.get("evidence")
    if (
        transition not in {"complete", "needs_input", "blocked"}
        or not isinstance(summary, str)
        or not isinstance(evidence, list)
        or any(not isinstance(item, str) for item in evidence)
    ):
        raise RunnerError("turn output does not match the transition schema")
    return transition, summary, tuple(evidence)


def _run_one(
    config: RunnerConfig,
    topic: str,
    task_id: str,
    run_id: str,
    sequence: int,
    run: Mapping[str, object] | None = None,
    policy: ValidatedPolicy | None = None,
) -> _TaskResult:
    state_root = routing_root(config.codex_home)
    cached = _cached_selection(state_root, run, config, topic, task_id) if run is not None else None
    model_list_required = cached is None
    expected_turn_request_id = 4 if model_list_required else 3

    command, environment = _app_server_launch(config, run_id, sequence, expected_turn_request_id)
    with AppServerClient(command, config.target_root, env=environment) as client:
        client.request(
            "initialize",
            {"clientInfo": {"name": "icodex", "title": "icodex", "version": "1"}},
        )
        client.notify("initialized", {})
        selection = cached
        if selection is None:
            current_policy = policy if policy is not None else _load_policy(config, topic)
            available = _model_list(client)
            selected = select_validated_profile(current_policy, task_id, available)
            selection = _selection_tuple(current_policy, task_id, selected)
        thread_result = client.request(
            "thread/start",
            {"cwd": str(config.target_root), "model": selection.model},
        )
        thread_id, session_id = _thread_id(thread_result)
        params: dict[str, object] = {
            "threadId": thread_id,
            "input": [{"type": "text", "text": f"Execute routed task {task_id} for topic {topic}."}],
            "cwd": str(config.target_root),
            "model": selection.model,
            "effort": selection.effort,
            "outputSchema": TRANSITION_SCHEMA,
        }

        def before_send(request_id: int, request: dict[str, object]) -> None:
            if request_id != expected_turn_request_id:
                raise RunnerError("App Server request sequence changed before turn/start")
            create_handoff(
                state_root,
                {
                    "run_id": run_id,
                    "sequence": sequence,
                    "target_root": selection.target_root,
                    "topic": selection.topic,
                    "task_id": selection.task_id,
                    "registry_commit": selection.registry_commit,
                    "registry_version": selection.registry_version,
                    "registry_hash": selection.registry_hash,
                    "manifest_commit": selection.manifest_commit,
                    "manifest_hash": selection.manifest_hash,
                    "profile": selection.profile,
                    "model": selection.model,
                    "effort": selection.effort,
                    "request_id": request_id,
                    "request_hash": hashlib.sha256(_canonical_json(request)).hexdigest(),
                },
            )

        turn_result = client.request("turn/start", params, before_send=before_send)
        turn = client.wait_for_turn(_turn_id(turn_result))

    transition, summary, evidence = _structured_transition(turn)
    decision = load_decision(state_root, session_id)
    authorized_session: str | None = None
    if decision is not None:
        save_selection_cache(state_root, run_id, selection, session_id)
        authorized_session = session_id
    return _TaskResult(transition, summary, evidence, selection, authorized_session)


def run_task(config: RunnerConfig, topic: str, task_id: str) -> int:
    """Start exactly one explicit task and return without selecting a successor."""
    run_id = secrets.token_hex(16)
    try:
        result = _run_one(config, topic, task_id, run_id, 1)
    except (AppServerError, PolicyError, RunnerError, StateError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print(result.summary)
    return 0 if result.transition == "complete" else 1


def orchestrate(config: RunnerConfig, topic: str) -> int:
    """Start or continue only local run state and advance on structured complete."""
    state_root = routing_root(config.codex_home)
    try:
        run = _read_run(state_root)
        initial_policy: ValidatedPolicy | None = None
        if run is None or run.get("topic") != topic:
            initial_policy = _load_policy(config, topic)
            declared = _tasks(initial_policy)
            if not declared:
                raise RunnerError("topic has no declared tasks")
            run = {
                "run_id": secrets.token_hex(16),
                "sequence": 1,
                "topic": topic,
                "task_index": 0,
                "task_id": declared[0]["id"],
                "selection": None,
                "session_id": None,
            }
            print(f"Starting new run from first task: {run['task_id']}")

        while run.get("task_id") is not None:
            run_id = str(run["run_id"])
            sequence = int(run["sequence"])
            task_index = int(run["task_index"])
            task_id = str(run["task_id"])
            result = _run_one(
                config,
                topic,
                task_id,
                run_id,
                sequence,
                run=run,
                policy=initial_policy,
            )
            initial_policy = None
            if result.transition != "complete":
                _write_run(
                    state_root,
                    run_id=run_id,
                    sequence=sequence + 1,
                    topic=topic,
                    task_index=task_index,
                    task_id=task_id,
                    selection=result.selection,
                    session_id=result.session_id,
                )
                print(result.summary)
                return 1

            policy = _load_policy(config, topic)
            declared = _tasks(policy)
            if task_index >= len(declared) or declared[task_index]["id"] != task_id:
                raise RunnerError("local task position no longer matches approved policy")
            next_index = task_index + 1
            next_task = str(declared[next_index]["id"]) if next_index < len(declared) else None
            _write_run(
                state_root,
                run_id=run_id,
                sequence=sequence + 1,
                topic=topic,
                task_index=next_index,
                task_id=next_task,
                selection=None,
                session_id=None,
            )
            run = _read_run(state_root)
            if run is None:
                raise RunnerError("local orchestration state disappeared")
            initial_policy = policy
        return 0
    except (AppServerError, PolicyError, RunnerError, StateError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in ("run-task", "orchestrate"):
        command = subparsers.add_parser(name)
        command.add_argument("--target-root", type=Path, required=True)
        command.add_argument("--codex-home", type=Path, required=True)
        command.add_argument("--shared-root", type=Path, required=True)
        command.add_argument("--binary", type=Path, required=True)
        command.add_argument("--topic", required=True)
        if name == "run-task":
            command.add_argument("--task", required=True)
    return parser


def main(arguments: list[str] | None = None) -> int:
    args = _parser().parse_args(arguments)
    config = RunnerConfig(args.target_root, args.codex_home, args.shared_root, args.binary)
    if args.command == "run-task":
        return run_task(config, args.topic, args.task)
    return orchestrate(config, args.topic)


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Run explicit profile-routed tasks through Codex App Server."""

from __future__ import annotations

import argparse
import dataclasses
import fcntl
import hashlib
import json
import os
import re
import secrets
import stat
import sys
from collections.abc import Mapping, Sequence
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

from app_server import AppServerClient, AppServerError
from policy import PolicyError, ValidatedPolicy, load_policy, select_validated_profile
from state import (
    SelectionTuple,
    StateError,
    cache_matches,
    create_handoff,
    load_decision,
    load_selection_cache,
    retire_attempt,
    routing_root,
    save_selection_cache,
    validate_run_id,
    validate_sequence,
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


TOPIC_RE = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")


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


@contextmanager
def _orchestration_directory(state_root: Path, *, create: bool):
    parent_descriptor: int | None = None
    root_descriptor: int | None = None
    orchestration_descriptor: int | None = None
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    missing = False
    try:
        parent_descriptor = os.open(state_root.parent, flags)
        if create:
            try:
                os.mkdir(state_root.name, mode=0o700, dir_fd=parent_descriptor)
            except FileExistsError:
                pass
        root_descriptor = os.open(state_root.name, flags, dir_fd=parent_descriptor)
        root_metadata = os.fstat(root_descriptor)
        if not stat.S_ISDIR(root_metadata.st_mode) or root_metadata.st_uid != os.getuid():
            raise RunnerError("profile routing state must be an owned directory")
        os.fchmod(root_descriptor, 0o700)
        if create:
            try:
                os.mkdir("orchestration", mode=0o700, dir_fd=root_descriptor)
            except FileExistsError:
                pass
        orchestration_descriptor = os.open(
            "orchestration", flags, dir_fd=root_descriptor
        )
        metadata = os.fstat(orchestration_descriptor)
        if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.getuid():
            raise RunnerError("orchestration state must be an owned directory")
        os.fchmod(orchestration_descriptor, 0o700)
    except FileNotFoundError:
        if create:
            for descriptor in (orchestration_descriptor, root_descriptor, parent_descriptor):
                if descriptor is not None:
                    os.close(descriptor)
            raise
        missing = True
    except OSError as exc:
        for descriptor in (orchestration_descriptor, root_descriptor, parent_descriptor):
            if descriptor is not None:
                os.close(descriptor)
        raise RunnerError(f"cannot open orchestration state: {exc}") from exc
    except Exception:
        for descriptor in (orchestration_descriptor, root_descriptor, parent_descriptor):
            if descriptor is not None:
                os.close(descriptor)
        raise
    if missing:
        try:
            yield None
        finally:
            for descriptor in (
                orchestration_descriptor,
                root_descriptor,
                parent_descriptor,
            ):
                if descriptor is not None:
                    os.close(descriptor)
        return
    try:
        yield orchestration_descriptor
    finally:
        for descriptor in (
            orchestration_descriptor,
            root_descriptor,
            parent_descriptor,
        ):
            if descriptor is not None:
                os.close(descriptor)


def _read_run(state_root: Path, topic: str) -> dict[str, object] | None:
    if TOPIC_RE.fullmatch(topic) is None:
        raise RunnerError("topic must be canonical lowercase kebab-case")
    descriptor: int | None = None
    try:
        with _orchestration_directory(state_root, create=False) as directory:
            if directory is None:
                return None
            try:
                descriptor = os.open(
                    f"{topic}.json",
                    os.O_RDONLY
                    | getattr(os, "O_NOFOLLOW", 0)
                    | getattr(os, "O_NONBLOCK", 0),
                    dir_fd=directory,
                )
            except FileNotFoundError:
                return None
            metadata = os.fstat(descriptor)
            if (
                not stat.S_ISREG(metadata.st_mode)
                or metadata.st_uid != os.getuid()
                or metadata.st_nlink != 1
                or stat.S_IMODE(metadata.st_mode) != 0o600
            ):
                raise RunnerError("local orchestration state must be an owner-only regular file")
            with os.fdopen(descriptor, encoding="utf-8") as stream:
                descriptor = None
                value = json.load(stream)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise RunnerError(f"local orchestration state is malformed: {exc}") from exc
    finally:
        if descriptor is not None:
            os.close(descriptor)
    required = {"run_id", "sequence", "topic", "task_index", "task_id", "selection", "session_id"}
    if not isinstance(value, dict) or set(value) != required:
        raise RunnerError("local orchestration state has an invalid schema")
    if (
        value["topic"] != topic
        or type(value["task_index"]) is not int
        or value["task_index"] < 0
        or value["task_id"] is not None and not isinstance(value["task_id"], str)
        or value["selection"] is not None and not isinstance(value["selection"], dict)
        or value["session_id"] is not None and not isinstance(value["session_id"], str)
    ):
        raise RunnerError("local orchestration state has invalid fields")
    try:
        validate_run_id(value["run_id"])
        sequence = validate_sequence(value["sequence"])
    except StateError as exc:
        raise RunnerError("local orchestration state has invalid fields") from exc
    if sequence < 1:
        raise RunnerError("local orchestration state has invalid fields")
    return value


@contextmanager
def _orchestrator_lock(config: RunnerConfig, topic: str):
    if not TOPIC_RE.fullmatch(topic):
        raise RunnerError("topic must be canonical lowercase kebab-case")
    home_descriptor: int | None = None
    state_descriptor: int | None = None
    coordinator_descriptor: int | None = None
    lock_descriptor: int | None = None
    try:
        home_descriptor = os.open(
            config.codex_home,
            os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0),
        )
        try:
            os.mkdir("state", mode=0o700, dir_fd=home_descriptor)
        except FileExistsError:
            pass
        state_descriptor = os.open(
            "state",
            os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0),
            dir_fd=home_descriptor,
        )
        state_metadata = os.fstat(state_descriptor)
        if not stat.S_ISDIR(state_metadata.st_mode) or state_metadata.st_uid != os.getuid():
            raise RunnerError("profile routing state parent must be an owned directory")
        os.fchmod(state_descriptor, 0o700)
        try:
            os.mkdir("profile-routing-coordinator", mode=0o700, dir_fd=state_descriptor)
        except FileExistsError:
            pass
        coordinator_descriptor = os.open(
            "profile-routing-coordinator",
            os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0),
            dir_fd=state_descriptor,
        )
        coordinator_metadata = os.fstat(coordinator_descriptor)
        if (
            not stat.S_ISDIR(coordinator_metadata.st_mode)
            or coordinator_metadata.st_uid != os.getuid()
        ):
            raise RunnerError("profile routing coordinator must be an owned directory")
        os.fchmod(coordinator_descriptor, 0o700)
        lock_descriptor = os.open(
            f"{topic}.orchestrator.lock",
            os.O_RDWR
            | os.O_CREAT
            | getattr(os, "O_NOFOLLOW", 0)
            | getattr(os, "O_NONBLOCK", 0),
            0o600,
            dir_fd=coordinator_descriptor,
        )
        lock_metadata = os.fstat(lock_descriptor)
        if (
            not stat.S_ISREG(lock_metadata.st_mode)
            or lock_metadata.st_uid != os.getuid()
            or lock_metadata.st_nlink != 1
        ):
            raise RunnerError("orchestrator lock must be an owned regular file")
        os.fchmod(lock_descriptor, 0o600)
        try:
            fcntl.flock(lock_descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise RunnerError(f"orchestration is already active for topic {topic}") from exc
        for descriptor in (coordinator_descriptor, state_descriptor, home_descriptor):
            os.close(descriptor)
        coordinator_descriptor = state_descriptor = home_descriptor = None
    except OSError as exc:
        raise RunnerError(f"cannot lock orchestration lifecycle: {exc}") from exc
    except RunnerError:
        raise
    finally:
        for descriptor in (coordinator_descriptor, state_descriptor, home_descriptor):
            if descriptor is not None:
                os.close(descriptor)
        if sys.exc_info()[0] is not None and lock_descriptor is not None:
            os.close(lock_descriptor)
    try:
        yield
    finally:
        assert lock_descriptor is not None
        fcntl.flock(lock_descriptor, fcntl.LOCK_UN)
        os.close(lock_descriptor)


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
    if TOPIC_RE.fullmatch(topic) is None:
        raise RunnerError("topic must be canonical lowercase kebab-case")
    try:
        run_id = validate_run_id(run_id)
        sequence = validate_sequence(sequence)
    except StateError as exc:
        raise RunnerError("local orchestration state has invalid fields") from exc
    if sequence < 1 or task_index < 0:
        raise RunnerError("local orchestration state has invalid fields")
    value = {
        "run_id": run_id,
        "sequence": sequence,
        "topic": topic,
        "task_index": task_index,
        "task_id": task_id,
        "selection": dataclasses.asdict(selection) if selection is not None else None,
        "session_id": session_id,
    }
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8") + b"\n"
    temporary = f".{topic}.json.{os.getpid()}.{secrets.token_hex(8)}.tmp"
    descriptor: int | None = None
    with _orchestration_directory(state_root, create=True) as directory:
        assert directory is not None
        try:
            try:
                existing = os.stat(
                    f"{topic}.json", dir_fd=directory, follow_symlinks=False
                )
            except FileNotFoundError:
                existing = None
            if existing is not None and (
                not stat.S_ISREG(existing.st_mode)
                or existing.st_uid != os.getuid()
                or existing.st_nlink != 1
                or stat.S_IMODE(existing.st_mode) != 0o600
            ):
                raise RunnerError("local orchestration state must be an owner-only regular file")
            descriptor = os.open(
                temporary,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                0o600,
                dir_fd=directory,
            )
            with os.fdopen(descriptor, "wb") as stream:
                descriptor = None
                stream.write(encoded)
                stream.flush()
                os.fsync(stream.fileno())
                os.fchmod(stream.fileno(), 0o600)
            os.replace(
                temporary,
                f"{topic}.json",
                src_dir_fd=directory,
                dst_dir_fd=directory,
            )
            os.fsync(directory)
        except OSError as exc:
            raise RunnerError(f"cannot write local orchestration state: {exc}") from exc
        finally:
            if descriptor is not None:
                os.close(descriptor)
            try:
                os.unlink(temporary, dir_fd=directory)
            except FileNotFoundError:
                pass


def _cached_selection(
    state_root: Path,
    run: Mapping[str, object],
    config: RunnerConfig,
    topic: str,
    task_id: str,
    policy: ValidatedPolicy,
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
    profiles = policy.registry.get("profiles")
    if not isinstance(profiles, Mapping):
        return None
    profile = profiles.get(selection.profile)
    if (
        not isinstance(profile, Mapping)
        or profile.get("model") != selection.model
        or profile.get("effort") != selection.effort
    ):
        return None
    expected = _selection_tuple(
        policy,
        task_id,
        {"profile": selection.profile, "model": selection.model, "effort": selection.effort},
    )
    if selection != expected:
        return None
    cache = load_selection_cache(state_root, run_id)
    decision = load_decision(state_root, session_id)
    if cache is None or decision is None:
        return None
    try:
        return expected if cache_matches(cache, expected, decision) else None
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
    policy: ValidatedPolicy,
    run: Mapping[str, object] | None = None,
) -> _TaskResult:
    state_root = routing_root(config.codex_home)
    cached = (
        _cached_selection(state_root, run, config, topic, task_id, policy)
        if run is not None
        else None
    )
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
            available = _model_list(client)
            selected = select_validated_profile(policy, task_id, available)
            selection = _selection_tuple(policy, task_id, selected)
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
        policy = _load_policy(config, topic)
        _task(policy, task_id)
        result = _run_one(config, topic, task_id, run_id, 1, policy=policy)
    except (AppServerError, PolicyError, RunnerError, StateError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print(result.summary)
    return 0 if result.transition == "complete" else 1


def orchestrate(config: RunnerConfig, topic: str) -> int:
    """Start or continue only local run state and advance on structured complete."""
    state_root = routing_root(config.codex_home)
    try:
        with _orchestrator_lock(config, topic):
            policy = _load_policy(config, topic)
            declared = _tasks(policy)
            run = _read_run(state_root, topic)
            if run is None:
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
                _write_run(
                    state_root,
                    run_id=str(run["run_id"]),
                    sequence=1,
                    topic=topic,
                    task_index=0,
                    task_id=str(run["task_id"]),
                    selection=None,
                    session_id=None,
                )
                print(f"Starting new run from first task: {run['task_id']}")

            while run.get("task_id") is not None:
                policy = _load_policy(config, topic)
                declared = _tasks(policy)
                run_id = str(run["run_id"])
                sequence = int(run["sequence"])
                task_index = int(run["task_index"])
                task_id = str(run["task_id"])
                if (
                    task_index >= len(declared)
                    or declared[task_index]["id"] != task_id
                ):
                    raise RunnerError("local task position no longer matches approved policy")
                try:
                    result = _run_one(
                        config,
                        topic,
                        task_id,
                        run_id,
                        sequence,
                        run=run,
                        policy=policy,
                    )
                except (AppServerError, PolicyError, RunnerError, StateError):
                    retire_attempt(state_root, run_id, sequence)
                    _write_run(
                        state_root,
                        run_id=run_id,
                        sequence=sequence + 1,
                        topic=topic,
                        task_index=task_index,
                        task_id=task_id,
                        selection=_selection_from_state(run.get("selection")),
                        session_id=(
                            str(run["session_id"])
                            if isinstance(run.get("session_id"), str)
                            else None
                        ),
                    )
                    raise
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
                run = _read_run(state_root, topic)
                if run is None:
                    raise RunnerError("local orchestration state disappeared")
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

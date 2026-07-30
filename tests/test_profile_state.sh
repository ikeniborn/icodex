#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT" <<'PY'
from __future__ import annotations

import dataclasses
import importlib.util
import json
import multiprocessing
import os
import shutil
import stat
import sys
import tempfile
import threading
import time
from pathlib import Path


root = Path(sys.argv[1])
module_path = root / "lib" / "profile" / "state.py"
spec = importlib.util.spec_from_file_location("profile_state", module_path)
if spec is None or spec.loader is None:
    raise RuntimeError("cannot load profile state module")
state = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = state
spec.loader.exec_module(state)

PASS = 0
FAIL = 0


def check(name: str, condition: object) -> None:
    global PASS, FAIL
    if condition:
        print(f"PASS [{name}]")
        PASS += 1
    else:
        print(f"FAIL [{name}]")
        FAIL += 1


def expect_state_error(name: str, action) -> None:
    try:
        action()
    except state.StateError:
        check(name, True)
    except Exception as exc:
        print(f"FAIL [{name}]: unexpected {type(exc).__name__}: {exc}")
        global FAIL
        FAIL += 1
    else:
        check(name, False)


def check_loader_invalidation_linearization(
    name: str,
    state_root: Path,
    run_id: str,
    target_path: Path,
    load,
    expected: dict[str, object],
) -> None:
    read_entered = threading.Event()
    release_read = threading.Event()
    exclusive_attempted = threading.Event()
    invalidation_finished = threading.Event()
    load_results: list[dict[str, object] | None] = []
    load_errors: list[Exception] = []
    invalidation_errors: list[Exception] = []
    loader_ident: list[int | None] = [None]
    real_load_json = state._load_json
    real_flock = state.fcntl.flock

    def blocking_load_json(path):
        value = real_load_json(path)
        if path == target_path and threading.get_ident() == loader_ident[0]:
            read_entered.set()
            if not release_read.wait(5):
                raise RuntimeError("timed out waiting to release routing state read")
        return value

    def observed_flock(descriptor, operation):
        if operation == state.fcntl.LOCK_EX:
            exclusive_attempted.set()
        return real_flock(descriptor, operation)

    def blocking_load():
        loader_ident[0] = threading.get_ident()
        try:
            load_results.append(load())
        except Exception as exc:
            load_errors.append(exc)

    def active_invalidate():
        try:
            state.invalidate_run(state_root, run_id)
        except Exception as exc:
            invalidation_errors.append(exc)
        finally:
            invalidation_finished.set()

    state._load_json = blocking_load_json
    state.fcntl.flock = observed_flock
    load_thread = threading.Thread(target=blocking_load)
    invalidate_thread = threading.Thread(target=active_invalidate)
    try:
        load_thread.start()
        check(f"{name} loader reaches read boundary", read_entered.wait(5))
        invalidate_thread.start()
        check(f"{name} invalidation reaches exclusive gate", exclusive_attempted.wait(5))
        check(
            f"{name} invalidation waits for active loader",
            not invalidation_finished.wait(0.2),
        )
        release_read.set()
        load_thread.join(5)
        invalidate_thread.join(5)
    finally:
        release_read.set()
        load_thread.join(5)
        if invalidate_thread.ident is not None:
            invalidate_thread.join(5)
        state._load_json = real_load_json
        state.fcntl.flock = real_flock

    check(
        f"{name} loader may return pre-invalidation state",
        not load_errors and load_results == [expected],
    )
    check(
        f"{name} invalidation finishes cleanly after loader",
        invalidation_finished.is_set() and not invalidation_errors,
    )
    check(f"{name} later loader misses invalidated state", load() is None)
    check(f"{name} invalidation leaves cold root", state.detect_cold_start(state_root))


def request(target: Path, run_id: str = "run-a", sequence: int = 1, **changes):
    value = {
        "run_id": run_id,
        "sequence": sequence,
        "target_root": str(target.resolve()),
        "topic": "demo-topic",
        "task_id": "build-task",
        "registry_commit": "a" * 40,
        "registry_version": 1,
        "registry_hash": "b" * 64,
        "manifest_commit": "c" * 40,
        "manifest_hash": "d" * 64,
        "profile": "deep",
        "model": "gpt-5.6-sol",
        "effort": "high",
        "request_id": 7,
        "request_hash": "e" * 64,
    }
    value.update(changes)
    return value


def selection(target: Path, **changes):
    value = {
        "target_root": str(target.resolve()),
        "topic": "demo-topic",
        "task_id": "build-task",
        "requirement_fingerprint": "f" * 64,
        "registry_commit": "a" * 40,
        "registry_version": 1,
        "registry_hash": "b" * 64,
        "manifest_commit": "c" * 40,
        "manifest_hash": "d" * 64,
        "profile": "deep",
        "model": "gpt-5.6-sol",
        "effort": "high",
    }
    value.update(changes)
    return state.SelectionTuple(**value)


def correlated_env(req: dict[str, object]):
    class Environment:
        def __enter__(self):
            self.previous = {
                key: os.environ.get(key)
                for key in (
                    "ICODEX_PROFILE_RUN_ID",
                    "ICODEX_PROFILE_SEQUENCE",
                    "ICODEX_PROFILE_REQUEST_ID",
                )
            }
            os.environ["ICODEX_PROFILE_RUN_ID"] = str(req["run_id"])
            os.environ["ICODEX_PROFILE_SEQUENCE"] = str(req["sequence"])
            os.environ["ICODEX_PROFILE_REQUEST_ID"] = str(req["request_id"])
            return self

        def __exit__(self, *_):
            for key, value in self.previous.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value

    return Environment()


def consume_worker(state_root: str, req: dict[str, object], session: str, queue) -> None:
    os.environ["ICODEX_PROFILE_RUN_ID"] = str(req["run_id"])
    os.environ["ICODEX_PROFILE_SEQUENCE"] = str(req["sequence"])
    os.environ["ICODEX_PROFILE_REQUEST_ID"] = str(req["request_id"])
    try:
        state.consume_handoff(
            Path(state_root),
            str(req["run_id"]),
            int(req["sequence"]),
            session,
            str(req["model"]),
        )
    except state.StateError:
        queue.put("rejected")
    else:
        queue.put("authorized")


def cold_create_worker(state_root: str, req: dict[str, object], barrier, queue) -> None:
    cold_root = Path(state_root)
    synchronized: set[Path] = set()
    real_mkdir = Path.mkdir

    def synchronized_mkdir(path, *args, **kwargs):
        if path in {cold_root.parent, cold_root} and path not in synchronized:
            synchronized.add(path)
            barrier.wait(timeout=5)
        return real_mkdir(path, *args, **kwargs)

    Path.mkdir = synchronized_mkdir
    try:
        created = state.create_handoff(cold_root, req)
    except Exception as exc:
        queue.put(f"error:{type(exc).__name__}:{exc}")
    else:
        queue.put(f"created:{created.name}")


def slow_decision_worker(state_root: str, req: dict[str, object], session: str, queue) -> None:
    os.environ["ICODEX_PROFILE_RUN_ID"] = str(req["run_id"])
    os.environ["ICODEX_PROFILE_SEQUENCE"] = str(req["sequence"])
    os.environ["ICODEX_PROFILE_REQUEST_ID"] = str(req["request_id"])
    real_atomic_write = state.atomic_json_write

    def slow_decision(path, value):
        if path.parent.name == "decisions":
            time.sleep(0.2)
        return real_atomic_write(path, value)

    state.atomic_json_write = slow_decision
    try:
        state.consume_handoff(
            Path(state_root),
            str(req["run_id"]),
            int(req["sequence"]),
            session,
            str(req["model"]),
        )
    except state.StateError:
        queue.put("rejected")
    else:
        queue.put("authorized")


with tempfile.TemporaryDirectory() as temporary:
    base = Path(temporary)
    home = base / "home"
    state_root = state.routing_root(home)
    check("routing root", state_root == home / "state" / "profile-routing")
    check("new routing root is cold", state.detect_cold_start(state_root))

    req = request(base / "target")
    Path(req["target_root"]).mkdir()
    state.create_handoff(state_root, req)
    check("created routing root is warm", not state.detect_cold_start(state_root))

    directories = [state_root, *[path for path in state_root.rglob("*") if path.is_dir()]]
    check(
        "state directories mode 0700",
        bool(directories) and all(stat.S_IMODE(path.stat().st_mode) == 0o700 for path in directories),
    )
    json_files = list(state_root.rglob("*.json"))
    check(
        "handoff JSON mode 0600",
        len(json_files) == 1 and stat.S_IMODE(json_files[0].stat().st_mode) == 0o600,
    )
    handoff = json.loads(json_files[0].read_text(encoding="utf-8"))
    check("handoff exact schema", set(handoff) == set(req))
    forbidden = {"prompt", "response", "transcript", "auth_path", "session_history", "tool_output"}
    check("handoff contains no portable or sensitive history", not forbidden.intersection(handoff))


    cold_root = base / "cold-shared" / "profile-routing"
    cold_requests = [
        request(Path(req["target_root"]), run_id="cold-run-one", request_id=11),
        request(Path(req["target_root"]), run_id="cold-run-two", request_id=12),
    ]
    cold_barrier = multiprocessing.Barrier(2)
    cold_queue = multiprocessing.Queue()
    cold_processes = [
        multiprocessing.Process(
            target=cold_create_worker,
            args=(str(cold_root), candidate, cold_barrier, cold_queue),
        )
        for candidate in cold_requests
    ]
    check("concurrent cold creators begin before routing directories exist", not cold_root.parent.exists())
    for process in cold_processes:
        process.start()
    for process in cold_processes:
        process.join(10)
    cold_results = sorted(cold_queue.get(timeout=2) for _ in cold_processes)
    check("concurrent cold creators both succeed", all(result.startswith("created:") for result in cold_results))
    cold_handoffs = [json.loads(path.read_text()) for path in (cold_root / "pending").glob("*.json")]
    check(
        "concurrent cold creators remain isolated",
        sorted(value["run_id"] for value in cold_handoffs) == ["cold-run-one", "cold-run-two"],
    )

    atomic_path = state_root / "atomic.json"
    replacements: list[tuple[Path, Path]] = []
    real_replace = state.os.replace

    def recording_replace(source, destination):
        replacements.append((Path(source), Path(destination)))
        return real_replace(source, destination)

    state.os.replace = recording_replace
    try:
        state.atomic_json_write(atomic_path, {"generation": 1})
        state.atomic_json_write(atomic_path, {"generation": 2})
    finally:
        state.os.replace = real_replace
    check("atomic replace keeps temp in destination directory", all(a.parent == b.parent for a, b in replacements))
    check("atomic replace publishes complete JSON", json.loads(atomic_path.read_text()) == {"generation": 2})
    check("atomic replacement file mode 0600", stat.S_IMODE(atomic_path.stat().st_mode) == 0o600)
    atomic_path.unlink()

    expect_state_error(
        "handoff rejects caller extras",
        lambda: state.create_handoff(state_root, request(Path(req["target_root"]), run_id="extra", prompt="secret")),
    )
    missing = request(Path(req["target_root"]), run_id="missing")
    missing.pop("request_hash")
    expect_state_error("handoff rejects missing key", lambda: state.create_handoff(state_root, missing))
    expect_state_error(
        "handoff rejects noncanonical target",
        lambda: state.create_handoff(
            state_root,
            request(Path(req["target_root"]), run_id="noncanonical", target_root=str(base / "target" / ".." / "target")),
        ),
    )
    expect_state_error(
        "handoff rejects malformed hash",
        lambda: state.create_handoff(state_root, request(Path(req["target_root"]), run_id="bad-hash", request_hash="ABC")),
    )
    expect_state_error(
        "same slot rejects cross-task collision",
        lambda: state.create_handoff(state_root, request(Path(req["target_root"]), task_id="other-task")),
    )
    expect_state_error(
        "same slot rejects cross-hash collision",
        lambda: state.create_handoff(state_root, request(Path(req["target_root"]), request_hash="1" * 64)),
    )

    for key in ("ICODEX_PROFILE_RUN_ID", "ICODEX_PROFILE_SEQUENCE", "ICODEX_PROFILE_REQUEST_ID"):
        os.environ.pop(key, None)
    expect_state_error(
        "missing routed correlation rejected",
        lambda: state.consume_handoff(state_root, str(req["run_id"]), 1, "session-x", str(req["model"])),
    )

    with correlated_env(req):
        expect_state_error(
            "cross-run argument rejected",
            lambda: state.consume_handoff(state_root, "run-b", 1, "session-x", str(req["model"])),
        )
        expect_state_error(
            "sequence argument rejected",
            lambda: state.consume_handoff(state_root, str(req["run_id"]), 2, "session-x", str(req["model"])),
        )
        os.environ["ICODEX_PROFILE_RUN_ID"] = "run-b"
        expect_state_error(
            "cross-run environment rejected",
            lambda: state.consume_handoff(state_root, str(req["run_id"]), 1, "session-x", str(req["model"])),
        )
        os.environ["ICODEX_PROFILE_RUN_ID"] = str(req["run_id"])
        os.environ["ICODEX_PROFILE_SEQUENCE"] = "2"
        expect_state_error(
            "sequence environment rejected",
            lambda: state.consume_handoff(state_root, str(req["run_id"]), 1, "session-x", str(req["model"])),
        )
        os.environ["ICODEX_PROFILE_SEQUENCE"] = str(req["sequence"])
        os.environ["ICODEX_PROFILE_REQUEST_ID"] = "8"
        expect_state_error(
            "request ID mismatch rejected",
            lambda: state.consume_handoff(state_root, str(req["run_id"]), 1, "session-x", str(req["model"])),
        )
        os.environ["ICODEX_PROFILE_REQUEST_ID"] = str(req["request_id"])
        expect_state_error(
            "payload model mismatch rejected",
            lambda: state.consume_handoff(state_root, str(req["run_id"]), 1, "session-x", "gpt-other"),
        )
        decision = state.consume_handoff(
            state_root,
            str(req["run_id"]),
            int(req["sequence"]),
            "session-a",
            str(req["model"]),
        )

    check("successful decision authorized", decision["authorized"] is True)
    check("successful decision observes payload model", decision["observed_model"] == req["model"])
    check("decision keeps policy and request correlation", all(decision[key] == req[key] for key in req))
    loaded_decision = state.load_decision(state_root, "session-a")
    check("decision load round trip", loaded_decision == decision)
    decision_files = list((state_root / "decisions").glob("*.json"))
    check(
        "decision JSON mode 0600",
        len(decision_files) == 1 and stat.S_IMODE(decision_files[0].stat().st_mode) == 0o600,
    )
    decision_files[0].write_text(json.dumps({**decision, "session_id": "other-session"}), encoding="utf-8")
    expect_state_error(
        "decision load binds payload session to requested key",
        lambda: state.load_decision(state_root, "session-a"),
    )
    decision_files[0].write_text(json.dumps(decision), encoding="utf-8")
    check("consumed handoff removed from pending", not list((state_root / "pending").glob("*.json")))
    check("consumed evidence retained outside pending", len(list((state_root / "consumed").glob("*.json"))) == 1)
    with correlated_env(req):
        expect_state_error(
            "handoff replay rejected",
            lambda: state.consume_handoff(state_root, str(req["run_id"]), 1, "session-b", str(req["model"])),
        )

    recovery_root = base / "decision-recovery"
    recovery = request(Path(req["target_root"]), run_id="recovery-run", request_id=10)
    state.create_handoff(recovery_root, recovery)
    real_atomic_write = state.atomic_json_write
    failed_once = False

    def fail_first_decision(path, value):
        global failed_once
        if path.parent.name == "decisions" and not failed_once:
            failed_once = True
            raise state.StateError("simulated decision write failure")
        return real_atomic_write(path, value)

    state.atomic_json_write = fail_first_decision
    try:
        with correlated_env(recovery):
            expect_state_error(
                "decision write failure is reported",
                lambda: state.consume_handoff(
                    recovery_root,
                    str(recovery["run_id"]),
                    int(recovery["sequence"]),
                    "recovery-session",
                    str(recovery["model"]),
                ),
            )
    finally:
        state.atomic_json_write = real_atomic_write
    with correlated_env(recovery):
        recovered_decision = state.consume_handoff(
            recovery_root,
            str(recovery["run_id"]),
            int(recovery["sequence"]),
            "recovery-session",
            str(recovery["model"]),
        )
    check("same session recovers consumed evidence", recovered_decision["authorized"] is True)

    malformed_req = request(Path(req["target_root"]), run_id="malformed-run", sequence=2, request_id=9)
    state.create_handoff(state_root, malformed_req)
    malformed_path = next(path for path in (state_root / "pending").glob("*.json") if "malformed-run" in path.name)
    malformed_path.write_text(json.dumps({**malformed_req, "request_hash": "invalid"}), encoding="utf-8")
    with correlated_env(malformed_req):
        expect_state_error(
            "malformed stored hash rejected",
            lambda: state.consume_handoff(state_root, "malformed-run", 2, "session-malformed", str(req["model"])),
        )

    concurrent_root = base / "concurrent"
    first = request(Path(req["target_root"]), run_id="runner-one", sequence=1, request_id=21)
    second = request(Path(req["target_root"]), run_id="runner-two", sequence=1, request_id=22)
    state.create_handoff(concurrent_root, first)
    state.create_handoff(concurrent_root, second)
    queue = multiprocessing.Queue()
    processes = [
        multiprocessing.Process(target=consume_worker, args=(str(concurrent_root), first, "session-one", queue)),
        multiprocessing.Process(target=consume_worker, args=(str(concurrent_root), second, "session-two", queue)),
    ]
    for process in processes:
        process.start()
    for process in processes:
        process.join(10)
    isolated_results = sorted(queue.get(timeout=2) for _ in processes)
    check("concurrent runners consume only own handoffs", isolated_results == ["authorized", "authorized"])

    same_session_root = base / "same-session"
    same_session_first = request(Path(req["target_root"]), run_id="session-run-one", request_id=23)
    same_session_second = request(Path(req["target_root"]), run_id="session-run-two", request_id=24)
    state.create_handoff(same_session_root, same_session_first)
    state.create_handoff(same_session_root, same_session_second)
    queue = multiprocessing.Queue()
    processes = [
        multiprocessing.Process(
            target=slow_decision_worker,
            args=(str(same_session_root), candidate, "shared-session", queue),
        )
        for candidate in (same_session_first, same_session_second)
    ]
    for process in processes:
        process.start()
    for process in processes:
        process.join(10)
    same_session_results = sorted(queue.get(timeout=2) for _ in processes)
    check("same session authorizes exactly one handoff", same_session_results == ["authorized", "rejected"])
    same_session_decision = state.load_decision(same_session_root, "shared-session")
    same_session_consumed = list((same_session_root / "consumed").glob("*.json"))
    same_session_pending = list((same_session_root / "pending").glob("*.json"))
    check(
        "same session consumes only decided handoff",
        same_session_decision is not None
        and len(same_session_consumed) == 1
        and len(same_session_pending) == 1
        and json.loads(same_session_consumed[0].read_text())["run_id"] == same_session_decision["run_id"],
    )
    same_session_loser = (
        same_session_second
        if same_session_decision["run_id"] == same_session_first["run_id"]
        else same_session_first
    )
    state.invalidate_run(same_session_root, str(same_session_decision["run_id"]))
    with correlated_env(same_session_loser):
        replacement_decision = state.consume_handoff(
            same_session_root,
            str(same_session_loser["run_id"]),
            int(same_session_loser["sequence"]),
            "replacement-session",
            str(same_session_loser["model"]),
        )
    check("losing pending handoff remains usable by fresh session", replacement_decision["authorized"] is True)

    single_root = base / "single-consumer"
    single = request(Path(req["target_root"]), run_id="single-run", sequence=1, request_id=31)
    state.create_handoff(single_root, single)
    queue = multiprocessing.Queue()
    processes = [
        multiprocessing.Process(target=consume_worker, args=(str(single_root), single, f"single-{index}", queue))
        for index in range(2)
    ]
    for process in processes:
        process.start()
    for process in processes:
        process.join(10)
    single_results = sorted(queue.get(timeout=2) for _ in processes)
    check("exactly one concurrent consumer", single_results == ["authorized", "rejected"])

    expected = selection(Path(req["target_root"]))
    state.save_selection_cache(state_root, str(req["run_id"]), expected, "session-a")
    cache = state.load_selection_cache(state_root, str(req["run_id"]))
    check("cache stores full tuple", cache["selection"] == dataclasses.asdict(expected))
    cache_path = state_root / "cache" / f"{req['run_id']}.json"
    cache_path.write_text(json.dumps({**cache, "run_id": "other-run"}), encoding="utf-8")
    expect_state_error(
        "cache load binds payload run to requested key",
        lambda: state.load_selection_cache(state_root, str(req["run_id"])),
    )
    cache_path.write_text(json.dumps(cache), encoding="utf-8")
    check("exact tuple cache hit", state.cache_matches(cache, expected, loaded_decision))
    for field in dataclasses.fields(expected):
        old = getattr(expected, field.name)
        if isinstance(old, int):
            changed = old + 1
        elif field.name in {
            "requirement_fingerprint",
            "registry_hash",
            "manifest_hash",
            "registry_commit",
            "manifest_commit",
        }:
            changed = "0" * len(old)
        else:
            changed = old + "-changed"
        candidate = dataclasses.replace(expected, **{field.name: changed})
        check(f"cache miss when {field.name} changes", not state.cache_matches(cache, candidate, loaded_decision))
    check("missing decision cache miss", not state.cache_matches(cache, expected, None))
    check("malformed decision cache miss", not state.cache_matches(cache, expected, {"authorized": True}))
    check(
        "observed model cache miss",
        not state.cache_matches(cache, expected, {**loaded_decision, "observed_model": "gpt-other"}),
    )
    check(
        "unauthorized decision cache miss",
        not state.cache_matches(cache, expected, {**loaded_decision, "authorized": False}),
    )
    expect_state_error(
        "cache run correlation mismatch raises",
        lambda: state.cache_matches({**cache, "run_id": "other-run"}, expected, loaded_decision),
    )
    expect_state_error(
        "cache session correlation mismatch raises",
        lambda: state.cache_matches({**cache, "session_id": "other-session"}, expected, loaded_decision),
    )

    cache_files = list((state_root / "cache").glob("*.json"))
    check(
        "cache JSON mode 0600",
        len(cache_files) == 1 and stat.S_IMODE(cache_files[0].stat().st_mode) == 0o600,
    )
    cache_files[0].write_text("{invalid", encoding="utf-8")
    check("malformed cache load is absent", state.load_selection_cache(state_root, str(req["run_id"])) is None)
    decision_files[0].write_text("[]", encoding="utf-8")
    check("malformed decision load is absent", state.load_decision(state_root, "session-a") is None)
    check("missing decision load is absent", state.load_decision(state_root, "missing-session") is None)

    decision_load_root = base / "decision-load-invalidation"
    decision_load_request = request(
        Path(req["target_root"]),
        run_id="decision-load-run",
        request_id=45,
    )
    state.create_handoff(decision_load_root, decision_load_request)
    with correlated_env(decision_load_request):
        decision_load_expected = state.consume_handoff(
            decision_load_root,
            str(decision_load_request["run_id"]),
            int(decision_load_request["sequence"]),
            "decision-load-session",
            str(decision_load_request["model"]),
        )
    check_loader_invalidation_linearization(
        "decision load",
        decision_load_root,
        str(decision_load_request["run_id"]),
        decision_load_root / "decisions" / "decision-load-session.json",
        lambda: state.load_decision(decision_load_root, "decision-load-session"),
        decision_load_expected,
    )

    cache_load_root = base / "cache-load-invalidation"
    state.save_selection_cache(cache_load_root, "cache-load-run", expected, "cache-load-session")
    cache_load_expected = state.load_selection_cache(cache_load_root, "cache-load-run")
    check_loader_invalidation_linearization(
        "cache load",
        cache_load_root,
        "cache-load-run",
        cache_load_root / "cache" / "cache-load-run.json",
        lambda: state.load_selection_cache(cache_load_root, "cache-load-run"),
        cache_load_expected,
    )

    active_root = base / "active-invalidation"
    active = request(Path(req["target_root"]), run_id="active-run", request_id=40)
    state.create_handoff(active_root, active)
    decision_entered = threading.Event()
    release_decision = threading.Event()
    consume_errors: list[Exception] = []
    invalidate_errors: list[Exception] = []
    real_atomic_write = state.atomic_json_write

    def block_decision(path, value):
        if path.parent.name == "decisions":
            decision_entered.set()
            if not release_decision.wait(5):
                raise RuntimeError("timed out waiting to release decision write")
        return real_atomic_write(path, value)

    def active_consume():
        try:
            state.consume_handoff(
                active_root,
                str(active["run_id"]),
                int(active["sequence"]),
                "active-session",
                str(active["model"]),
            )
        except Exception as exc:
            consume_errors.append(exc)

    def active_invalidate():
        try:
            state.invalidate_run(active_root, str(active["run_id"]))
        except Exception as exc:
            invalidate_errors.append(exc)

    state.atomic_json_write = block_decision
    with correlated_env(active):
        consume_thread = threading.Thread(target=active_consume)
        consume_thread.start()
        check("consumer reached decision boundary", decision_entered.wait(5))
        invalidate_thread = threading.Thread(target=active_invalidate)
        invalidate_thread.start()
        time.sleep(0.1)
        check("invalidation waits for active consumer", invalidate_thread.is_alive())
        release_decision.set()
        consume_thread.join(5)
        invalidate_thread.join(5)
    state.atomic_json_write = real_atomic_write
    check("active consume and invalidation finish cleanly", not consume_errors and not invalidate_errors)
    check("post-consume invalidation returns cold start", state.detect_cold_start(active_root))

    gate_root = base / "gate-invalidation"
    gate_old = request(Path(req["target_root"]), run_id="gate-run", sequence=1, request_id=43)
    gate_new = request(Path(req["target_root"]), run_id="gate-run", sequence=2, request_id=44)
    state.create_handoff(gate_root, gate_old)
    run_lock_unlinked = threading.Event()
    release_cleanup = threading.Event()
    gate_invalidate_errors: list[Exception] = []
    gate_create_errors: list[Exception] = []
    real_path_unlink = Path.unlink
    expected_run_lock = gate_root / "locks" / "gate-run.run.lock"

    def pausing_unlink(path, *args, **kwargs):
        result = real_path_unlink(path, *args, **kwargs)
        if path == expected_run_lock:
            run_lock_unlinked.set()
            if not release_cleanup.wait(5):
                raise RuntimeError("timed out waiting to finish invalidation cleanup")
        return result

    def gate_invalidate():
        try:
            state.invalidate_run(gate_root, "gate-run")
        except Exception as exc:
            gate_invalidate_errors.append(exc)

    def gate_create():
        try:
            state.create_handoff(gate_root, gate_new)
        except Exception as exc:
            gate_create_errors.append(exc)

    Path.unlink = pausing_unlink
    try:
        gate_invalidate_thread = threading.Thread(target=gate_invalidate)
        gate_invalidate_thread.start()
        check("invalidation reached unlinked run-lock boundary", run_lock_unlinked.wait(5))
        gate_create_thread = threading.Thread(target=gate_create)
        gate_create_thread.start()
        time.sleep(0.1)
        check("stable coordinator blocks entrant after run-lock unlink", gate_create_thread.is_alive())
        release_cleanup.set()
        gate_invalidate_thread.join(5)
        gate_create_thread.join(5)
    finally:
        Path.unlink = real_path_unlink
    check("invalidation and later entrant finish cleanly", not gate_invalidate_errors and not gate_create_errors)
    check("post-invalidation entrant creates fresh local state", not state.detect_cold_start(gate_root))
    state.invalidate_run(gate_root, "gate-run")

    invalidation_root = base / "invalidation"
    run_one = request(Path(req["target_root"]), run_id="keep-or-remove-one", sequence=1, request_id=41)
    run_two = request(Path(req["target_root"]), run_id="keep-or-remove-two", sequence=1, request_id=42)
    state.create_handoff(invalidation_root, run_one)
    state.create_handoff(invalidation_root, run_two)
    state.save_selection_cache(invalidation_root, str(run_one["run_id"]), expected, "run-one-session")
    state.save_selection_cache(invalidation_root, str(run_two["run_id"]), expected, "run-two-session")
    state.invalidate_run(invalidation_root, str(run_one["run_id"]))
    check("invalidate removes selected run cache", state.load_selection_cache(invalidation_root, str(run_one["run_id"])) is None)
    check("invalidate preserves other run cache", state.load_selection_cache(invalidation_root, str(run_two["run_id"])) is not None)
    check("partial invalidation remains warm", not state.detect_cold_start(invalidation_root))
    state.invalidate_run(invalidation_root, str(run_two["run_id"]))
    check("last-run invalidation returns cold start", state.detect_cold_start(invalidation_root))

    malformed_cleanup_root = base / "malformed-cleanup"
    malformed_cleanup = request(
        Path(req["target_root"]),
        run_id="malformed-cleanup-run",
        sequence=1,
        request_id=51,
    )
    valid_keep = request(Path(req["target_root"]), run_id="valid-keep-run", sequence=1, request_id=52)
    state.create_handoff(malformed_cleanup_root, malformed_cleanup)
    state.create_handoff(malformed_cleanup_root, valid_keep)
    with correlated_env(malformed_cleanup):
        state.consume_handoff(
            malformed_cleanup_root,
            str(malformed_cleanup["run_id"]),
            int(malformed_cleanup["sequence"]),
            "target-malformed-session",
            str(malformed_cleanup["model"]),
        )
    with correlated_env(valid_keep):
        state.consume_handoff(
            malformed_cleanup_root,
            str(valid_keep["run_id"]),
            int(valid_keep["sequence"]),
            "valid-keep-session",
            str(valid_keep["model"]),
        )
    state.save_selection_cache(
        malformed_cleanup_root,
        str(malformed_cleanup["run_id"]),
        expected,
        "target-malformed-session",
    )
    state.save_selection_cache(
        malformed_cleanup_root,
        str(valid_keep["run_id"]),
        expected,
        "valid-keep-session",
    )
    target_decision = state.load_decision(malformed_cleanup_root, "target-malformed-session")
    malformed_handoff_path = next(
        path
        for path in (malformed_cleanup_root / "consumed").glob("*.json")
        if "malformed-cleanup-run" in path.name
    )
    malformed_cache_path = malformed_cleanup_root / "cache" / "malformed-cleanup-run.json"
    malformed_decision_path = malformed_cleanup_root / "decisions" / "target-malformed-session.json"
    unrelated_decision_path = malformed_cleanup_root / "decisions" / "unrelated-malformed-session.json"
    unrelated_session_lock = malformed_cleanup_root / "locks" / "session.unrelated-malformed-session.lock"
    attributable_session_lock = malformed_cleanup_root / "locks" / "session.target-malformed-session.lock"
    decision_source_path = malformed_cleanup_root / "decisions" / "misplaced-decision-source.json"
    decision_poison_path = malformed_cleanup_root / "decisions" / "decision-poison-session.json"
    session_source_lock = malformed_cleanup_root / "locks" / "session.misplaced-session-source.lock"
    session_poison_lock = malformed_cleanup_root / "locks" / "session.session-poison-session.lock"
    consume_source_lock = malformed_cleanup_root / "locks" / "malformed-cleanup-run.99.consume.lock"
    consume_poison_decision = malformed_cleanup_root / "decisions" / "consume-poison-session.json"
    malformed_handoff_path.write_text("{invalid", encoding="utf-8")
    malformed_cache_path.write_text("[]", encoding="utf-8")
    malformed_decision_path.write_text("{invalid", encoding="utf-8")
    unrelated_decision_path.write_text("{invalid", encoding="utf-8")
    unrelated_session_lock.write_text("{invalid", encoding="utf-8")
    attributable_session_lock.write_text("{invalid", encoding="utf-8")
    decision_source_path.write_text(
        json.dumps({**target_decision, "session_id": "decision-poison-session"}),
        encoding="utf-8",
    )
    decision_poison_path.write_text("{invalid", encoding="utf-8")
    session_source_lock.write_text(
        json.dumps(
            {
                "run_id": "malformed-cleanup-run",
                "sequence": 1,
                "session_id": "session-poison-session",
                "request_id": "51",
                "payload_model": str(malformed_cleanup["model"]),
            }
        ),
        encoding="utf-8",
    )
    session_poison_lock.write_text("{invalid", encoding="utf-8")
    consume_source_lock.write_text(
        json.dumps(
            {
                "run_id": "malformed-cleanup-run",
                "sequence": 100,
                "session_id": "consume-poison-session",
                "request_id": "51",
                "payload_model": str(malformed_cleanup["model"]),
            }
        ),
        encoding="utf-8",
    )
    consume_poison_decision.write_text("{invalid", encoding="utf-8")
    for path in (
        malformed_decision_path,
        unrelated_decision_path,
        unrelated_session_lock,
        attributable_session_lock,
        decision_source_path,
        decision_poison_path,
        session_source_lock,
        session_poison_lock,
        consume_source_lock,
        consume_poison_decision,
    ):
        os.chmod(path, 0o600)

    state.invalidate_run(malformed_cleanup_root, "malformed-cleanup-run")
    check("invalidation removes malformed target handoff by namespace", not malformed_handoff_path.exists())
    check("invalidation removes malformed target cache by exact path", not malformed_cache_path.exists())
    check("invalidation removes attributable malformed target decision", not malformed_decision_path.exists())
    check("invalidation preserves unrelated malformed decision", unrelated_decision_path.exists())
    check("invalidation preserves unrelated malformed session lock", unrelated_session_lock.exists())
    check("invalidation removes attributable malformed session lock", not attributable_session_lock.exists())
    check("misplaced decision cannot attribute malformed victim", decision_poison_path.exists())
    check("misplaced session claim cannot attribute malformed victim", session_poison_lock.exists())
    check("misplaced consume claim cannot attribute malformed victim", consume_poison_decision.exists())
    check(
        "invalidation preserves unrelated valid decision",
        state.load_decision(malformed_cleanup_root, "valid-keep-session") is not None,
    )
    check(
        "invalidation preserves unrelated valid cache",
        state.load_selection_cache(malformed_cleanup_root, "valid-keep-run") is not None,
    )
    state.invalidate_run(malformed_cleanup_root, "valid-keep-run")
    check("unattributable malformed state keeps routing root warm", not state.detect_cold_start(malformed_cleanup_root))
    shutil.rmtree(malformed_cleanup_root, ignore_errors=True)
    check("explicit state deletion restores cold start", state.detect_cold_start(malformed_cleanup_root))

    retire = getattr(state, "retire_attempt", None)
    check("attempt retirement API exists", callable(retire))
    if callable(retire):
        retire_root = base / "attempt-retirement"
        target_attempt = request(
            Path(req["target_root"]),
            run_id="retire-run",
            sequence=1,
            request_id=61,
        )
        later_attempt = request(
            Path(req["target_root"]),
            run_id="retire-run",
            sequence=2,
            request_id=62,
        )
        unrelated_attempt = request(
            Path(req["target_root"]),
            run_id="unrelated-run",
            sequence=1,
            request_id=63,
        )
        state.create_handoff(retire_root, target_attempt)
        with correlated_env(target_attempt):
            state.consume_handoff(
                retire_root,
                "retire-run",
                1,
                "retire-session",
                str(target_attempt["model"]),
            )
        state.create_handoff(retire_root, later_attempt)
        state.create_handoff(retire_root, unrelated_attempt)
        state.save_selection_cache(retire_root, "retire-run", expected, "retire-session")
        retire(retire_root, "retire-run", 1)
        check(
            "attempt retirement removes exact handoff and locks",
            not (retire_root / "pending" / "retire-run.1.json").exists()
            and not (retire_root / "consumed" / "retire-run.1.json").exists()
            and not (retire_root / "locks" / "retire-run.1.slot.lock").exists()
            and not (retire_root / "locks" / "retire-run.1.consume.lock").exists(),
        )
        check(
            "attempt retirement removes attributable decision and session lock",
            not (retire_root / "decisions" / "retire-session.json").exists()
            and not (retire_root / "locks" / "session.retire-session.lock").exists(),
        )
        check(
            "attempt retirement preserves later and unrelated attempts",
            (retire_root / "pending" / "retire-run.2.json").is_file()
            and (retire_root / "pending" / "unrelated-run.1.json").is_file(),
        )
        check(
            "attempt retirement preserves selection cache",
            state.load_selection_cache(retire_root, "retire-run") is not None,
        )

        race_root = base / "attempt-retirement-race"
        race_attempt = request(
            Path(req["target_root"]),
            run_id="retire-race-run",
            sequence=1,
            request_id=64,
        )
        state.create_handoff(race_root, race_attempt)
        race_decision_entered = threading.Event()
        release_race_decision = threading.Event()
        race_consume_errors: list[Exception] = []
        race_retire_errors: list[Exception] = []
        real_atomic_write = state.atomic_json_write

        def block_race_decision(path, value):
            if path.parent.name == "decisions":
                race_decision_entered.set()
                if not release_race_decision.wait(5):
                    raise RuntimeError("timed out waiting to release retirement race")
            return real_atomic_write(path, value)

        def consume_race_attempt():
            try:
                state.consume_handoff(
                    race_root,
                    "retire-race-run",
                    1,
                    "retire-race-session",
                    str(race_attempt["model"]),
                )
            except Exception as exc:
                race_consume_errors.append(exc)

        def retire_race_attempt():
            try:
                retire(race_root, "retire-race-run", 1)
            except Exception as exc:
                race_retire_errors.append(exc)

        state.atomic_json_write = block_race_decision
        with correlated_env(race_attempt):
            consume_thread = threading.Thread(target=consume_race_attempt)
            consume_thread.start()
            check("attempt consumer reaches retirement race boundary", race_decision_entered.wait(5))
            retire_thread = threading.Thread(target=retire_race_attempt)
            retire_thread.start()
            time.sleep(0.1)
            check("attempt retirement waits for active consumer", retire_thread.is_alive())
            release_race_decision.set()
            consume_thread.join(5)
            retire_thread.join(5)
        state.atomic_json_write = real_atomic_write
        check(
            "attempt consume and retirement race finish cleanly",
            not race_consume_errors and not race_retire_errors,
        )
        check(
            "attempt retirement leaves no stale post-race evidence",
            not list((race_root / "pending").glob("retire-race-run.1.json"))
            and not list((race_root / "consumed").glob("retire-race-run.1.json"))
            and not list((race_root / "decisions").glob("retire-race-session.json"))
            and not list((race_root / "locks").glob("retire-race-run.1.*.lock"))
            and not list((race_root / "locks").glob("session.retire-race-session.lock")),
        )

        for linked_directory in ("pending", "decisions"):
            linked_root = base / f"retire-linked-{linked_directory}"
            external = base / f"external-{linked_directory}"
            external.mkdir()
            victim = external / "victim.txt"
            victim.write_text("preserve", encoding="utf-8")
            linked_root.mkdir()
            for name in state.STATE_DIRECTORIES:
                if name == linked_directory:
                    (linked_root / name).symlink_to(external, target_is_directory=True)
                else:
                    (linked_root / name).mkdir()
            expect_state_error(
                f"attempt retirement rejects symlinked {linked_directory} directory",
                lambda root=linked_root: retire(root, "retire-run", 1),
            )
            check(
                f"symlinked {linked_directory} victim survives attempt retirement",
                victim.read_text(encoding="utf-8") == "preserve",
            )

        victim = base / "absolute-run-id-victim"
        victim.write_text("preserve", encoding="utf-8")
        expect_state_error(
            "attempt retirement rejects absolute run id before path construction",
            lambda: retire(retire_root, str(victim), 1),
        )
        expect_state_error(
            "attempt retirement rejects traversal run id before path construction",
            lambda: retire(retire_root, "../../absolute-run-id-victim", 1),
        )
        check(
            "forged run id cannot remove external victim",
            victim.read_text(encoding="utf-8") == "preserve",
        )

        malformed_root = base / "retire-malformed-attempt"
        malformed_attempt = request(
            Path(req["target_root"]),
            run_id="malformed-retire-run",
            sequence=1,
            request_id=65,
        )
        state.create_handoff(malformed_root, malformed_attempt)
        malformed_pending = malformed_root / "pending" / "malformed-retire-run.1.json"
        malformed_pending.write_text("{invalid", encoding="utf-8")
        malformed_pending.chmod(0o600)
        expect_state_error(
            "attempt retirement rejects malformed exact pending state",
            lambda: retire(malformed_root, "malformed-retire-run", 1),
        )
        check(
            "malformed attempt retirement fails without partial cleanup",
            malformed_pending.exists()
            and (malformed_root / "locks" / "malformed-retire-run.1.slot.lock").exists(),
        )

        fifo_root = base / "retire-fifo-attempt"
        fifo_attempt = request(
            Path(req["target_root"]),
            run_id="fifo-retire-run",
            sequence=1,
            request_id=66,
        )
        state.create_handoff(fifo_root, fifo_attempt)
        fifo_pending = fifo_root / "pending" / "fifo-retire-run.1.json"
        fifo_pending.unlink()
        os.mkfifo(fifo_pending, 0o600)
        started = time.monotonic()
        expect_state_error(
            "attempt retirement rejects FIFO exact pending state",
            lambda: retire(fifo_root, "fifo-retire-run", 1),
        )
        check(
            "FIFO attempt retirement rejects without blocking",
            time.monotonic() - started < 1 and fifo_pending.exists(),
        )

        linked_file_root = base / "retire-linked-files"
        linked_attempt = request(
            Path(req["target_root"]),
            run_id="linked-retire-run",
            sequence=1,
            request_id=67,
        )
        state.create_handoff(linked_file_root, linked_attempt)
        linked_pending = linked_file_root / "pending" / "linked-retire-run.1.json"
        linked_pending.unlink()
        pending_victim = base / "linked-pending-victim"
        pending_victim.write_text("preserve", encoding="utf-8")
        linked_pending.symlink_to(pending_victim)
        expect_state_error(
            "attempt retirement rejects symlinked exact pending file",
            lambda: retire(linked_file_root, "linked-retire-run", 1),
        )
        check(
            "symlinked exact pending victim survives retirement",
            pending_victim.read_text(encoding="utf-8") == "preserve",
        )

        linked_decision_root = base / "retire-linked-decision"
        linked_decision_attempt = request(
            Path(req["target_root"]),
            run_id="linked-decision-run",
            sequence=1,
            request_id=68,
        )
        state.create_handoff(linked_decision_root, linked_decision_attempt)
        with correlated_env(linked_decision_attempt):
            state.consume_handoff(
                linked_decision_root,
                "linked-decision-run",
                1,
                "linked-decision-session",
                str(linked_decision_attempt["model"]),
            )
        linked_decision = linked_decision_root / "decisions" / "linked-decision-session.json"
        linked_decision.unlink()
        decision_victim = base / "linked-decision-victim"
        decision_victim.write_text("preserve", encoding="utf-8")
        linked_decision.symlink_to(decision_victim)
        expect_state_error(
            "attempt retirement rejects symlinked attributable decision",
            lambda: retire(linked_decision_root, "linked-decision-run", 1),
        )
        check(
            "symlinked decision victim survives retirement",
            decision_victim.read_text(encoding="utf-8") == "preserve",
        )

        routing_hardlink_root = base / "routing-hardlink" / "profile-routing"
        routing_hardlink_root.parent.mkdir()
        routing_lock_victim = base / "routing-lock-victim"
        routing_lock_victim.write_text("preserve", encoding="utf-8")
        routing_lock_victim.chmod(0o640)
        os.link(
            routing_lock_victim,
            routing_hardlink_root.parent / ".profile-routing.coordinator.lock",
        )
        expect_state_error(
            "routing gate rejects hardlinked coordinator",
            lambda: state.create_handoff(
                routing_hardlink_root,
                request(Path(req["target_root"]), run_id="routing-hardlink-run"),
            ),
        )
        check(
            "routing gate hardlink victim is unchanged",
            routing_lock_victim.read_text(encoding="utf-8") == "preserve"
            and stat.S_IMODE(routing_lock_victim.stat().st_mode) == 0o640,
        )

        run_hardlink_root = base / "run-hardlink"
        state.create_handoff(
            run_hardlink_root,
            request(Path(req["target_root"]), run_id="layout-run", request_id=69),
        )
        run_lock_victim = base / "run-lock-victim"
        run_lock_victim.write_text("preserve", encoding="utf-8")
        run_lock_victim.chmod(0o640)
        os.link(
            run_lock_victim,
            run_hardlink_root / "locks" / "linked-run.run.lock",
        )
        expect_state_error(
            "run gate rejects hardlinked run lock",
            lambda: state.create_handoff(
                run_hardlink_root,
                request(Path(req["target_root"]), run_id="linked-run", request_id=70),
            ),
        )
        check(
            "run gate hardlink victim is unchanged",
            run_lock_victim.read_text(encoding="utf-8") == "preserve"
            and stat.S_IMODE(run_lock_victim.stat().st_mode) == 0o640,
        )

    shutil.rmtree(state_root)
    check("state deletion returns cold start", state.detect_cold_start(state_root))
    check("cold start infers no progress or history", not state_root.exists())

print("---")
print(f"PASS={PASS} FAIL={FAIL}")
raise SystemExit(1 if FAIL else 0)
PY

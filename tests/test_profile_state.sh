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
    cold_parent = Path(state_root).parent
    real_mkdir = Path.mkdir
    synchronized = False

    def synchronized_mkdir(path, *args, **kwargs):
        nonlocal synchronized
        if path == cold_parent and not synchronized:
            synchronized = True
            barrier.wait(timeout=5)
        return real_mkdir(path, *args, **kwargs)

    Path.mkdir = synchronized_mkdir
    try:
        created = state.create_handoff(Path(state_root), req)
    except Exception as exc:
        queue.put(f"error:{type(exc).__name__}:{exc}")
    else:
        queue.put(f"created:{created.name}")


def blocked_decision_worker(
    state_root: str,
    req: dict[str, object],
    session: str,
    decision_entered,
    release_decision,
    queue,
) -> None:
    os.environ["ICODEX_PROFILE_RUN_ID"] = str(req["run_id"])
    os.environ["ICODEX_PROFILE_SEQUENCE"] = str(req["sequence"])
    os.environ["ICODEX_PROFILE_REQUEST_ID"] = str(req["request_id"])
    real_atomic_write = state.atomic_json_write

    def block_decision(path, value):
        if path.parent.name == "decisions":
            decision_entered.set()
            if not release_decision.wait(5):
                raise RuntimeError("timed out waiting to release decision writer")
        return real_atomic_write(path, value)

    state.atomic_json_write = block_decision
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


def crash_claim_worker(
    state_root: str,
    req: dict[str, object],
    session: str,
    crash_write_number: int,
) -> None:
    os.environ["ICODEX_PROFILE_RUN_ID"] = str(req["run_id"])
    os.environ["ICODEX_PROFILE_SEQUENCE"] = str(req["sequence"])
    os.environ["ICODEX_PROFILE_REQUEST_ID"] = str(req["request_id"])
    real_write = state.os.write
    writes = 0

    def crash_during_claim(descriptor, encoded):
        nonlocal writes
        writes += 1
        if writes == crash_write_number:
            os._exit(71 + crash_write_number)
        return real_write(descriptor, encoded)

    state.os.write = crash_during_claim
    state.consume_handoff(
        Path(state_root),
        str(req["run_id"]),
        int(req["sequence"]),
        session,
        str(req["model"]),
    )


def crash_atomic_write_worker(
    state_root: str,
    req: dict[str, object],
    session: str,
    category: str,
) -> None:
    real_replace = state.os.replace

    def crash_before_publish(source, destination):
        if Path(destination).parent.name == category:
            os._exit(80)
        return real_replace(source, destination)

    state.os.replace = crash_before_publish
    if category == "pending":
        state.create_handoff(Path(state_root), req)
    elif category == "cache":
        state.save_selection_cache(
            Path(state_root),
            str(req["run_id"]),
            selection(Path(str(req["target_root"]))),
            session,
        )
    else:
        os.environ["ICODEX_PROFILE_RUN_ID"] = str(req["run_id"])
        os.environ["ICODEX_PROFILE_SEQUENCE"] = str(req["sequence"])
        os.environ["ICODEX_PROFILE_REQUEST_ID"] = str(req["request_id"])
        state.consume_handoff(
            Path(state_root),
            str(req["run_id"]),
            int(req["sequence"]),
            session,
            str(req["model"]),
        )


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

    cold_root = base / "cold-shared" / "profile-routing"
    cold_first = request(Path(req["target_root"]), run_id="cold-run-one", request_id=11)
    cold_second = request(Path(req["target_root"]), run_id="cold-run-two", request_id=12)
    cold_barrier = multiprocessing.Barrier(2)
    cold_queue = multiprocessing.Queue()
    cold_processes = [
        multiprocessing.Process(
            target=cold_create_worker,
            args=(str(cold_root), candidate, cold_barrier, cold_queue),
        )
        for candidate in (cold_first, cold_second)
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
    handoff = json.loads(json_files[0].read_text(encoding="utf-8"))
    check("handoff exact schema", set(handoff) == set(req))
    forbidden = {"prompt", "response", "transcript", "auth_path", "session_history", "tool_output"}
    check("handoff contains no portable or sensitive history", not forbidden.intersection(handoff))

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

    parent_race_base = base / "parent-race"
    parent_race_roots = [parent_race_base / "routing-one", parent_race_base / "routing-two"]
    parent_race_requests = [
        request(Path(req["target_root"]), run_id="parent-race-one", request_id=101),
        request(Path(req["target_root"]), run_id="parent-race-two", request_id=102),
    ]
    parent_mkdir_barrier = threading.Barrier(2)
    parent_race_errors: list[Exception] = []
    real_path_mkdir = Path.mkdir

    def barrier_parent_mkdir(path, *args, **kwargs):
        if path == parent_race_base:
            parent_mkdir_barrier.wait(5)
        return real_path_mkdir(path, *args, **kwargs)

    def parent_race_create(index: int) -> None:
        try:
            state.create_handoff(parent_race_roots[index], parent_race_requests[index])
        except Exception as exc:
            parent_race_errors.append(exc)

    Path.mkdir = barrier_parent_mkdir
    try:
        parent_race_threads = [threading.Thread(target=parent_race_create, args=(index,)) for index in range(2)]
        for thread in parent_race_threads:
            thread.start()
        for thread in parent_race_threads:
            thread.join(10)
    finally:
        Path.mkdir = real_path_mkdir
    check("concurrent cold coordinator parents are race-safe", not parent_race_errors)

    layout_race_parent = base / "layout-race-parent"
    layout_race_parent.mkdir(mode=0o700)
    layout_race_root = layout_race_parent / "profile-routing"
    layout_race_requests = [
        request(Path(req["target_root"]), run_id="layout-race-one", request_id=103),
        request(Path(req["target_root"]), run_id="layout-race-two", request_id=104),
    ]
    layout_mkdir_barrier = threading.Barrier(2)
    layout_race_errors: list[Exception] = []

    def barrier_layout_mkdir(path, *args, **kwargs):
        if path == layout_race_root:
            layout_mkdir_barrier.wait(5)
        return real_path_mkdir(path, *args, **kwargs)

    def layout_race_create(index: int) -> None:
        try:
            state.create_handoff(layout_race_root, layout_race_requests[index])
        except Exception as exc:
            layout_race_errors.append(exc)

    Path.mkdir = barrier_layout_mkdir
    try:
        layout_race_threads = [threading.Thread(target=layout_race_create, args=(index,)) for index in range(2)]
        for thread in layout_race_threads:
            thread.start()
        for thread in layout_race_threads:
            thread.join(10)
    finally:
        Path.mkdir = real_path_mkdir
    check("concurrent cold routing layouts are race-safe", not layout_race_errors)

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
    check(
        "decision load binds payload session to requested key",
        state.load_decision(state_root, "session-a") is None,
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

    handoff_claim_root = base / "handoff-claim-crash"
    handoff_claim = request(Path(req["target_root"]), run_id="handoff-claim-crash", request_id=105)
    state.create_handoff(handoff_claim_root, handoff_claim)
    handoff_claim_crash = multiprocessing.Process(
        target=crash_claim_worker,
        args=(str(handoff_claim_root), handoff_claim, "handoff-claim-session", 1),
    )
    handoff_claim_crash.start()
    handoff_claim_crash.join(10)
    check("handoff claim writer crashes before completing claim", handoff_claim_crash.exitcode == 72)
    try:
        with correlated_env(handoff_claim):
            recovered_handoff_claim = state.consume_handoff(
                handoff_claim_root,
                str(handoff_claim["run_id"]),
                int(handoff_claim["sequence"]),
                "handoff-claim-session",
                str(handoff_claim["model"]),
            )
    except state.StateError:
        recovered_handoff_claim = None
    check(
        "retry recovers incomplete per-handoff claim",
        recovered_handoff_claim is not None and recovered_handoff_claim["authorized"] is True,
    )

    session_claim_root = base / "session-claim-crash"
    session_claim = request(Path(req["target_root"]), run_id="session-claim-crash", request_id=106)
    state.create_handoff(session_claim_root, session_claim)
    session_claim_crash = multiprocessing.Process(
        target=crash_claim_worker,
        args=(str(session_claim_root), session_claim, "session-claim-session", 2),
    )
    session_claim_crash.start()
    session_claim_crash.join(10)
    check("session claim writer crashes before completing claim", session_claim_crash.exitcode == 73)
    try:
        with correlated_env(session_claim):
            recovered_session_claim = state.consume_handoff(
                session_claim_root,
                str(session_claim["run_id"]),
                int(session_claim["sequence"]),
                "session-claim-session",
                str(session_claim["model"]),
            )
    except state.StateError:
        recovered_session_claim = None
    check(
        "retry recovers incomplete per-session claim",
        recovered_session_claim is not None and recovered_session_claim["authorized"] is True,
    )

    partial_claim_root = base / "partial-claim-write"
    partial_claim = request(Path(req["target_root"]), run_id="partial-claim-write", request_id=109)
    state.create_handoff(partial_claim_root, partial_claim)
    real_os_write = state.os.write
    partial_writes = 0

    def partial_os_write(descriptor, encoded):
        global partial_writes
        partial_writes += 1
        return real_os_write(descriptor, encoded[:7])

    state.os.write = partial_os_write
    try:
        with correlated_env(partial_claim):
            partial_claim_decision = state.consume_handoff(
                partial_claim_root,
                str(partial_claim["run_id"]),
                int(partial_claim["sequence"]),
                "partial-claim-session",
                str(partial_claim["model"]),
            )
    finally:
        state.os.write = real_os_write
    check(
        "claim writes complete after partial os.write calls",
        partial_claim_decision["authorized"] is True and partial_writes > 2,
    )

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
    same_session_decision_entered = multiprocessing.Event()
    release_same_session_decision = multiprocessing.Event()
    processes = [
        multiprocessing.Process(
            target=blocked_decision_worker,
            args=(
                str(same_session_root),
                candidate,
                "shared-session",
                same_session_decision_entered,
                release_same_session_decision,
                queue,
            ),
        )
        for candidate in (same_session_first, same_session_second)
    ]
    for process in processes:
        process.start()
    check("one same-session consumer reaches decision boundary", same_session_decision_entered.wait(5))
    first_same_session_result = queue.get(timeout=5)
    check("active session claim rejects competing consumer", first_same_session_result == "rejected")
    release_same_session_decision.set()
    for process in processes:
        process.join(10)
    same_session_results = sorted([first_same_session_result, queue.get(timeout=2)])
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
    check(
        "cache load binds payload run to requested key",
        state.load_selection_cache(state_root, str(req["run_id"])) is None,
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

    substituted_decision_path = state_root / "decisions" / "substituted-session.json"
    substituted_decision_path.write_text(json.dumps(loaded_decision), encoding="utf-8")
    os.chmod(substituted_decision_path, 0o600)
    check(
        "decision namespace mismatch is absent",
        state.load_decision(state_root, "substituted-session") is None,
    )
    substituted_cache_path = state_root / "cache" / "substituted-run.json"
    substituted_cache_path.write_text(json.dumps(cache), encoding="utf-8")
    os.chmod(substituted_cache_path, 0o600)
    substituted_cache = state.load_selection_cache(state_root, "substituted-run")
    check("cache namespace mismatch is absent", substituted_cache is None)
    check(
        "cache namespace substitution cannot hit",
        not state.cache_matches(substituted_cache, expected, loaded_decision),
    )
    substituted_decision_path.unlink()
    substituted_cache_path.unlink()

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

    active_root = base / "active-invalidation"
    active = request(Path(req["target_root"]), run_id="active-run", request_id=40)
    state.create_handoff(active_root, active)
    decision_entered = threading.Event()
    release_decision = threading.Event()
    consume_errors: list[Exception] = []
    invalidate_errors: list[Exception] = []
    invalidate_lock_attempted = threading.Event()
    invalidate_finished = threading.Event()
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
        finally:
            invalidate_finished.set()

    state.atomic_json_write = block_decision
    with correlated_env(active):
        consume_thread = threading.Thread(target=active_consume)
        consume_thread.start()
        check("consumer reached decision boundary", decision_entered.wait(5))
        real_flock = state.fcntl.flock

        def observe_invalidate_flock(descriptor, operation):
            if threading.current_thread().name == "active-invalidate" and operation & state.fcntl.LOCK_EX:
                invalidate_lock_attempted.set()
            return real_flock(descriptor, operation)

        state.fcntl.flock = observe_invalidate_flock
        try:
            invalidate_thread = threading.Thread(target=active_invalidate, name="active-invalidate")
            invalidate_thread.start()
            check("invalidation attempts exclusive coordinator acquisition", invalidate_lock_attempted.wait(5))
            check("invalidation waits for active consumer", not invalidate_finished.is_set())
            release_decision.set()
            consume_thread.join(5)
            invalidate_thread.join(5)
        finally:
            release_decision.set()
            state.fcntl.flock = real_flock
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
    gate_create_lock_attempted = threading.Event()
    gate_create_finished = threading.Event()
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
        finally:
            gate_create_finished.set()

    Path.unlink = pausing_unlink
    real_flock = state.fcntl.flock

    def observe_gate_create_flock(descriptor, operation):
        if threading.current_thread().name == "gate-create" and operation & state.fcntl.LOCK_SH:
            gate_create_lock_attempted.set()
        return real_flock(descriptor, operation)

    state.fcntl.flock = observe_gate_create_flock
    try:
        gate_invalidate_thread = threading.Thread(target=gate_invalidate)
        gate_invalidate_thread.start()
        check("invalidation reached unlinked run-lock boundary", run_lock_unlinked.wait(5))
        gate_create_thread = threading.Thread(target=gate_create, name="gate-create")
        gate_create_thread.start()
        check("later entrant attempts shared coordinator acquisition", gate_create_lock_attempted.wait(5))
        check("stable coordinator blocks entrant after run-lock unlink", not gate_create_finished.is_set())
        release_cleanup.set()
        gate_invalidate_thread.join(5)
        gate_create_thread.join(5)
    finally:
        release_cleanup.set()
        state.fcntl.flock = real_flock
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

    orphan_temp_root = base / "orphan-temps"
    orphan_temp_handoff = request(
        Path(req["target_root"]),
        run_id="orphan-temp-run",
        sequence=1,
        request_id=107,
    )
    orphan_temp_decision = request(
        Path(req["target_root"]),
        run_id="orphan-temp-run",
        sequence=2,
        request_id=108,
    )
    state.create_handoff(orphan_temp_root, orphan_temp_decision)
    orphan_writers = [
        multiprocessing.Process(
            target=crash_atomic_write_worker,
            args=(str(orphan_temp_root), orphan_temp_handoff, "orphan-temp-session", "pending"),
        ),
        multiprocessing.Process(
            target=crash_atomic_write_worker,
            args=(str(orphan_temp_root), orphan_temp_handoff, "orphan-temp-session", "cache"),
        ),
        multiprocessing.Process(
            target=crash_atomic_write_worker,
            args=(str(orphan_temp_root), orphan_temp_decision, "orphan-temp-session", "decisions"),
        ),
    ]
    for process in orphan_writers:
        process.start()
        process.join(10)
    check("writers crash after fsync before atomic publish", all(process.exitcode == 80 for process in orphan_writers))
    target_handoff_temps = list((orphan_temp_root / "pending").glob(".orphan-temp-run.1.json.*.tmp"))
    target_cache_temps = list((orphan_temp_root / "cache").glob(".orphan-temp-run.json.*.tmp"))
    target_decision_temps = list((orphan_temp_root / "decisions").glob(".orphan-temp-session.json.*.tmp"))
    check(
        "crashed writers leave target handoff cache and decision temps",
        len(target_handoff_temps) == len(target_cache_temps) == len(target_decision_temps) == 1,
    )
    unrelated_handoff_temp = orphan_temp_root / "pending" / ".unrelated-run.1.json.999.0123456789abcdef.tmp"
    unrelated_cache_temp = orphan_temp_root / "cache" / ".unrelated-run.json.999.0123456789abcdef.tmp"
    unattributable_decision_temp = (
        orphan_temp_root / "decisions" / ".unattributable-session.json.999.0123456789abcdef.tmp"
    )
    for path in (unrelated_handoff_temp, unrelated_cache_temp, unattributable_decision_temp):
        path.write_text("orphan", encoding="utf-8")
        os.chmod(path, 0o600)

    state.invalidate_run(orphan_temp_root, "orphan-temp-run")
    check("invalidation removes exact target handoff temp namespace", not target_handoff_temps[0].exists())
    check("invalidation removes exact target cache temp namespace", not target_cache_temps[0].exists())
    check("invalidation removes trusted target-session decision temp", not target_decision_temps[0].exists())
    check(
        "invalidation preserves unrelated and unattributable temps",
        unrelated_handoff_temp.exists()
        and unrelated_cache_temp.exists()
        and unattributable_decision_temp.exists(),
    )

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

    shutil.rmtree(state_root)
    check("state deletion returns cold start", state.detect_cold_start(state_root))
    check("cold start infers no progress or history", not state_root.exists())

print("---")
print(f"PASS={PASS} FAIL={FAIL}")
raise SystemExit(1 if FAIL else 0)
PY

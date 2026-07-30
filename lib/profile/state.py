#!/usr/bin/env python3
"""Machine-local profile-routing handoffs, decisions, and selection cache."""

from __future__ import annotations

import dataclasses
import fcntl
import json
import os
import re
import secrets
import stat
from collections.abc import Mapping
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path


SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
OID_RE = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")
SLUG_RE = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
IDENTIFIER_RE = re.compile(r"[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\Z")

HANDOFF_KEYS = {
    "run_id",
    "sequence",
    "target_root",
    "topic",
    "task_id",
    "registry_commit",
    "registry_version",
    "registry_hash",
    "manifest_commit",
    "manifest_hash",
    "profile",
    "model",
    "effort",
    "request_id",
    "request_hash",
}
DECISION_KEYS = HANDOFF_KEYS | {"session_id", "authorized", "observed_model"}
CACHE_KEYS = {"run_id", "session_id", "selection"}
CONSUMER_CLAIM_KEYS = {"run_id", "sequence", "session_id", "request_id", "payload_model"}
SELECTION_KEYS = {
    "target_root",
    "topic",
    "task_id",
    "requirement_fingerprint",
    "registry_commit",
    "registry_version",
    "registry_hash",
    "manifest_commit",
    "manifest_hash",
    "profile",
    "model",
    "effort",
}
STATE_DIRECTORIES = ("pending", "consumed", "decisions", "cache", "locks")


@dataclass(frozen=True)
class SelectionTuple:
    target_root: str
    topic: str
    task_id: str
    requirement_fingerprint: str
    registry_commit: str
    registry_version: int
    registry_hash: str
    manifest_commit: str
    manifest_hash: str
    profile: str
    model: str
    effort: str


class StateError(Exception):
    pass


def routing_root(codex_home: Path) -> Path:
    return codex_home / "state" / "profile-routing"


def detect_cold_start(state_root: Path) -> bool:
    return not state_root.exists()


def _ensure_directory(path: Path) -> None:
    descriptor: int | None = None
    try:
        path.mkdir(parents=True, mode=0o700, exist_ok=True)
        flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(path, flags)
        metadata = os.fstat(descriptor)
        if not stat.S_ISDIR(metadata.st_mode):
            raise StateError(f"state directory is not a regular directory: {path}")
        os.fchmod(descriptor, 0o700)
    except OSError as exc:
        raise StateError(f"cannot prepare state directory {path}: {exc}") from exc
    finally:
        if descriptor is not None:
            os.close(descriptor)


def _ensure_layout(state_root: Path) -> None:
    _ensure_directory(state_root)
    for name in STATE_DIRECTORIES:
        _ensure_directory(state_root / name)


def _fsync_directory(path: Path) -> None:
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    try:
        descriptor = os.open(path, flags)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    except OSError as exc:
        raise StateError(f"cannot sync state directory {path}: {exc}") from exc


def atomic_json_write(path: Path, value: Mapping[str, object]) -> None:
    """Atomically replace one restrictive JSON file using a same-directory temp."""
    _ensure_directory(path.parent)
    temporary = path.parent / f".{path.name}.{os.getpid()}.{secrets.token_hex(8)}.tmp"
    descriptor: int | None = None
    try:
        descriptor = os.open(
            temporary,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
            0o600,
        )
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            descriptor = None
            json.dump(value, stream, sort_keys=True, separators=(",", ":"))
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
        _fsync_directory(path.parent)
    except (OSError, TypeError, ValueError) as exc:
        raise StateError(f"cannot atomically write state file {path}: {exc}") from exc
    finally:
        if descriptor is not None:
            os.close(descriptor)
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def _exclusive_file(path: Path) -> None:
    descriptor: int | None = None
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.fsync(descriptor)
        os.fchmod(descriptor, 0o600)
    except FileExistsError as exc:
        raise StateError(f"routing evidence already claimed: {path.name}") from exc
    except OSError as exc:
        raise StateError(f"cannot claim routing evidence {path}: {exc}") from exc
    finally:
        if descriptor is not None:
            os.close(descriptor)


@contextmanager
def _routing_gate(state_root: Path, *, exclusive: bool = False):
    """Coordinate root deletion through a stable lock outside the deleted tree."""
    parent = state_root.parent
    descriptor: int | None = None
    try:
        _ensure_directory(parent)
        path = parent / f".{state_root.name}.coordinator.lock"
        descriptor = os.open(
            path,
            os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0),
            0o600,
        )
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            raise StateError(f"routing coordinator is not a regular file: {path}")
        os.fchmod(descriptor, 0o600)
        fcntl.flock(descriptor, fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH)
    except OSError as exc:
        if descriptor is not None:
            os.close(descriptor)
        raise StateError(f"cannot lock routing state {state_root}: {exc}") from exc
    except Exception:
        if descriptor is not None:
            os.close(descriptor)
        raise
    try:
        yield
    finally:
        assert descriptor is not None
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


@contextmanager
def _run_gate(state_root: Path, run_id: str, *, exclusive: bool = False):
    """Keep invalidation exclusive with active operations for one run."""
    _ensure_layout(state_root)
    path = state_root / "locks" / f"{run_id}.run.lock"
    flags = os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0)
    descriptor: int | None = None
    try:
        descriptor = os.open(path, flags, 0o600)
        os.fchmod(descriptor, 0o600)
        fcntl.flock(descriptor, fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH)
    except OSError as exc:
        if descriptor is not None:
            os.close(descriptor)
        raise StateError(f"cannot lock routing run {run_id}: {exc}") from exc
    try:
        yield path
    finally:
        assert descriptor is not None
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


@contextmanager
def _consumer_claim(path: Path, claim: Mapping[str, object]):
    """Create or resume one session-bound consume claim while holding its flock."""
    flags = os.O_RDWR | getattr(os, "O_NOFOLLOW", 0)
    created = False
    try:
        descriptor = os.open(path, flags | os.O_CREAT | os.O_EXCL, 0o600)
        created = True
    except FileExistsError:
        try:
            descriptor = os.open(path, flags)
        except OSError as exc:
            raise StateError(f"cannot open consume claim {path}: {exc}") from exc
    except OSError as exc:
        raise StateError(f"cannot create consume claim {path}: {exc}") from exc

    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise StateError(f"handoff is being consumed: {path.name}") from exc
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            raise StateError(f"consume claim is not a regular file: {path}")
        os.fchmod(descriptor, 0o600)
        if created:
            encoded = (json.dumps(dict(claim), sort_keys=True, separators=(",", ":")) + "\n").encode()
            os.write(descriptor, encoded)
            os.fsync(descriptor)
            _fsync_directory(path.parent)
        else:
            os.lseek(descriptor, 0, os.SEEK_SET)
            with os.fdopen(os.dup(descriptor), "r", encoding="utf-8") as stream:
                existing = json.load(stream)
            if existing != dict(claim):
                raise StateError("handoff is already bound to another session or correlation")
        yield
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        if created:
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        raise StateError(f"invalid consume claim {path}: {exc}") from exc
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def _safe_identifier(value: object, label: str) -> str:
    if not isinstance(value, str) or IDENTIFIER_RE.fullmatch(value) is None:
        raise StateError(f"{label} must be a safe non-empty identifier")
    return value


def _slug(value: object, label: str) -> str:
    if not isinstance(value, str) or SLUG_RE.fullmatch(value) is None:
        raise StateError(f"{label} must be lowercase kebab-case")
    return value


def _nonempty_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value or "\x00" in value:
        raise StateError(f"{label} must be a non-empty string")
    return value


def _positive_integer(value: object, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise StateError(f"{label} must be a positive integer")
    return value


def _sequence(value: object) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise StateError("sequence must be a non-negative integer")
    return value


def _hash(value: object, label: str) -> str:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        raise StateError(f"{label} must be a lowercase SHA-256")
    return value


def _oid(value: object, label: str) -> str:
    if not isinstance(value, str) or OID_RE.fullmatch(value) is None:
        raise StateError(f"{label} must be a lowercase Git object ID")
    return value


def _canonical_root(value: object) -> str:
    text = _nonempty_string(value, "target_root")
    path = Path(text)
    if not path.is_absolute() or path.resolve() != path:
        raise StateError("target_root must be canonical and absolute")
    return text


def _request_id(value: object) -> str:
    if isinstance(value, bool):
        raise StateError("request_id must be a non-negative integer or safe identifier")
    if isinstance(value, int):
        if value < 0:
            raise StateError("request_id must be a non-negative integer or safe identifier")
        return str(value)
    return _safe_identifier(value, "request_id")


def _validate_handoff(value: object) -> dict[str, object]:
    if not isinstance(value, Mapping) or set(value) != HANDOFF_KEYS:
        raise StateError("handoff must contain exactly the allowed correlation fields")
    result = dict(value)
    _safe_identifier(result["run_id"], "run_id")
    _sequence(result["sequence"])
    _canonical_root(result["target_root"])
    _slug(result["topic"], "topic")
    _slug(result["task_id"], "task_id")
    _oid(result["registry_commit"], "registry_commit")
    _positive_integer(result["registry_version"], "registry_version")
    _hash(result["registry_hash"], "registry_hash")
    _oid(result["manifest_commit"], "manifest_commit")
    _hash(result["manifest_hash"], "manifest_hash")
    _slug(result["profile"], "profile")
    _nonempty_string(result["model"], "model")
    _slug(result["effort"], "effort")
    _request_id(result["request_id"])
    _hash(result["request_hash"], "request_hash")
    return result


def _validate_selection(value: object) -> dict[str, object]:
    if not isinstance(value, Mapping) or set(value) != SELECTION_KEYS:
        raise StateError("selection cache must contain the complete selection tuple")
    result = dict(value)
    _canonical_root(result["target_root"])
    _slug(result["topic"], "topic")
    _slug(result["task_id"], "task_id")
    _hash(result["requirement_fingerprint"], "requirement_fingerprint")
    _oid(result["registry_commit"], "registry_commit")
    _positive_integer(result["registry_version"], "registry_version")
    _hash(result["registry_hash"], "registry_hash")
    _oid(result["manifest_commit"], "manifest_commit")
    _hash(result["manifest_hash"], "manifest_hash")
    _slug(result["profile"], "profile")
    _nonempty_string(result["model"], "model")
    _slug(result["effort"], "effort")
    return result


def _handoff_name(run_id: str, sequence: int) -> str:
    return f"{run_id}.{sequence}"


def _read_json(path: Path) -> object:
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            raise StateError(f"state path is not a regular file: {path}")
        with os.fdopen(descriptor, "r", encoding="utf-8") as stream:
            descriptor = -1
            return json.load(stream)
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def _load_json(path: Path) -> object | None:
    try:
        return _read_json(path)
    except (OSError, UnicodeError, json.JSONDecodeError, StateError):
        return None


def create_handoff(state_root: Path, request: Mapping[str, object]) -> Path:
    handoff = _validate_handoff(request)
    name = _handoff_name(str(handoff["run_id"]), int(handoff["sequence"]))
    slot_lock = state_root / "locks" / f"{name}.slot.lock"
    pending = state_root / "pending" / f"{name}.json"
    consumed = state_root / "consumed" / f"{name}.json"
    with _routing_gate(state_root):
        with _run_gate(state_root, str(handoff["run_id"])):
            _exclusive_file(slot_lock)
            try:
                if pending.exists() or consumed.exists():
                    raise StateError(f"handoff slot already exists: {name}")
                atomic_json_write(pending, handoff)
            except Exception:
                try:
                    slot_lock.unlink()
                except FileNotFoundError:
                    pass
                raise
    return pending


def _required_environment(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise StateError(f"missing routed correlation environment: {name}")
    return value


def consume_handoff(
    state_root: Path,
    run_id: str,
    sequence: int,
    session_id: str,
    payload_model: str,
) -> dict[str, object]:
    run_id = _safe_identifier(run_id, "run_id")
    sequence = _sequence(sequence)
    session_id = _safe_identifier(session_id, "session_id")
    payload_model = _nonempty_string(payload_model, "payload_model")
    if _required_environment("ICODEX_PROFILE_RUN_ID") != run_id:
        raise StateError("run correlation mismatch")
    if _required_environment("ICODEX_PROFILE_SEQUENCE") != str(sequence):
        raise StateError("sequence correlation mismatch")

    name = _handoff_name(run_id, sequence)
    pending = state_root / "pending" / f"{name}.json"
    consumed = state_root / "consumed" / f"{name}.json"
    consume_lock = state_root / "locks" / f"{name}.consume.lock"
    session_lock = state_root / "locks" / f"session.{session_id}.lock"
    decision_path = state_root / "decisions" / f"{session_id}.json"

    with _routing_gate(state_root):
        if not state_root.exists():
            raise StateError("routing state is missing")
        with _run_gate(state_root, run_id):
            source = pending if pending.exists() else consumed
            try:
                handoff = _validate_handoff(_read_json(source))
            except FileNotFoundError as exc:
                raise StateError("handoff is missing or already consumed") from exc
            except (OSError, UnicodeError, json.JSONDecodeError) as exc:
                raise StateError("handoff JSON is malformed") from exc
            if handoff["run_id"] != run_id:
                raise StateError("handoff run mismatch")
            if handoff["sequence"] != sequence:
                raise StateError("handoff sequence mismatch")
            request_id = _required_environment("ICODEX_PROFILE_REQUEST_ID")
            if request_id != _request_id(handoff["request_id"]):
                raise StateError("request ID correlation mismatch")
            if handoff["model"] != payload_model:
                raise StateError("payload model mismatch")
            claim = {
                "run_id": run_id,
                "sequence": sequence,
                "session_id": session_id,
                "request_id": request_id,
                "payload_model": payload_model,
            }
            with _consumer_claim(consume_lock, claim):
                try:
                    with _consumer_claim(session_lock, claim):
                        source = pending if pending.exists() else consumed
                        try:
                            locked_handoff = _validate_handoff(_read_json(source))
                        except FileNotFoundError as exc:
                            raise StateError("handoff is missing or already consumed") from exc
                        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
                            raise StateError("handoff JSON is malformed") from exc
                        if locked_handoff != handoff:
                            raise StateError("handoff changed during consumption")
                        if decision_path.exists() or decision_path.is_symlink():
                            try:
                                session_lock.unlink()
                            except FileNotFoundError:
                                pass
                            raise StateError("session already has a routing decision")
                        if source == pending:
                            try:
                                os.replace(pending, consumed)
                                _fsync_directory(pending.parent)
                                _fsync_directory(consumed.parent)
                            except OSError as exc:
                                raise StateError(f"cannot consume handoff atomically: {exc}") from exc
                        decision = {
                            **handoff,
                            "session_id": session_id,
                            "authorized": True,
                            "observed_model": payload_model,
                        }
                        atomic_json_write(decision_path, decision)
                        try:
                            session_lock.unlink()
                        except FileNotFoundError:
                            pass
                        return decision
                except StateError:
                    if pending.exists():
                        try:
                            consume_lock.unlink()
                        except FileNotFoundError:
                            pass
                    raise


def _validate_decision(value: object) -> dict[str, object]:
    if not isinstance(value, Mapping) or set(value) != DECISION_KEYS:
        raise StateError("decision has an invalid schema")
    result = dict(value)
    _validate_handoff({key: result[key] for key in HANDOFF_KEYS})
    _safe_identifier(result["session_id"], "session_id")
    if result["authorized"] is not True:
        raise StateError("decision is not authorized")
    _nonempty_string(result["observed_model"], "observed_model")
    return result


def load_decision(state_root: Path, session_id: str) -> dict[str, object] | None:
    try:
        session_id = _safe_identifier(session_id, "session_id")
        value = _load_json(state_root / "decisions" / f"{session_id}.json")
        decision = _validate_decision(value)
    except StateError:
        return None
    if decision["session_id"] != session_id:
        raise StateError("decision session namespace mismatch")
    return decision


def save_selection_cache(
    state_root: Path,
    run_id: str,
    selection_tuple: SelectionTuple,
    session_id: str,
) -> None:
    run_id = _safe_identifier(run_id, "run_id")
    session_id = _safe_identifier(session_id, "session_id")
    if not isinstance(selection_tuple, SelectionTuple):
        raise StateError("selection_tuple must be a SelectionTuple")
    selection = _validate_selection(dataclasses.asdict(selection_tuple))
    with _routing_gate(state_root):
        with _run_gate(state_root, run_id):
            atomic_json_write(
                state_root / "cache" / f"{run_id}.json",
                {"run_id": run_id, "session_id": session_id, "selection": selection},
            )


def _validate_cache(value: object) -> dict[str, object]:
    if not isinstance(value, Mapping) or set(value) != CACHE_KEYS:
        raise StateError("selection cache has an invalid schema")
    result = dict(value)
    _safe_identifier(result["run_id"], "run_id")
    _safe_identifier(result["session_id"], "session_id")
    result["selection"] = _validate_selection(result["selection"])
    return result


def _validate_consumer_claim(value: object) -> dict[str, object]:
    if not isinstance(value, Mapping) or set(value) != CONSUMER_CLAIM_KEYS:
        raise StateError("consumer claim has an invalid schema")
    result = dict(value)
    _safe_identifier(result["run_id"], "run_id")
    _sequence(result["sequence"])
    _safe_identifier(result["session_id"], "session_id")
    _request_id(result["request_id"])
    _nonempty_string(result["payload_model"], "payload_model")
    return result


def load_selection_cache(state_root: Path, run_id: str) -> dict[str, object] | None:
    try:
        run_id = _safe_identifier(run_id, "run_id")
        value = _load_json(state_root / "cache" / f"{run_id}.json")
        cache = _validate_cache(value)
    except StateError:
        return None
    if cache["run_id"] != run_id:
        raise StateError("selection cache run namespace mismatch")
    return cache


def cache_matches(
    cache: object,
    selection_tuple: SelectionTuple,
    authorized_decision: object,
) -> bool:
    try:
        if not isinstance(selection_tuple, SelectionTuple):
            return False
        expected = _validate_selection(dataclasses.asdict(selection_tuple))
        cached = _validate_cache(cache)
        decision = _validate_decision(authorized_decision)
    except StateError:
        return False
    if cached["run_id"] != decision["run_id"]:
        raise StateError("cache and decision run correlation mismatch")
    if cached["session_id"] != decision["session_id"]:
        raise StateError("cache and decision session correlation mismatch")
    return (
        cached["selection"] == expected
        and decision["authorized"] is True
        and decision["observed_model"] == selection_tuple.model
    )


def _remove_namespaced_run_json(directory: Path, run_id: str) -> None:
    if not directory.is_dir():
        return
    for path in directory.glob(f"{run_id}.*.json"):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def _collect_target_sessions(state_root: Path, run_id: str) -> set[str]:
    sessions: set[str] = set()
    cache = _load_json(state_root / "cache" / f"{run_id}.json")
    try:
        validated_cache = _validate_cache(cache)
        if validated_cache["run_id"] == run_id:
            sessions.add(str(validated_cache["session_id"]))
    except StateError:
        pass

    decision_directory = state_root / "decisions"
    if decision_directory.is_dir():
        for path in decision_directory.glob("*.json"):
            try:
                decision = _validate_decision(_read_json(path))
                if path.stem == decision["session_id"] and decision["run_id"] == run_id:
                    sessions.add(str(decision["session_id"]))
            except (OSError, UnicodeError, json.JSONDecodeError, StateError):
                pass

    lock_directory = state_root / "locks"
    if lock_directory.is_dir():
        for path in lock_directory.glob(f"{run_id}.*.consume.lock"):
            try:
                claim = _validate_consumer_claim(_read_json(path))
                expected_name = f"{claim['run_id']}.{claim['sequence']}.consume.lock"
                if path.name == expected_name and claim["run_id"] == run_id:
                    sessions.add(str(claim["session_id"]))
            except (OSError, UnicodeError, json.JSONDecodeError, StateError):
                pass
        for path in lock_directory.glob("session.*.lock"):
            try:
                claim = _validate_consumer_claim(_read_json(path))
                expected_name = f"session.{claim['session_id']}.lock"
                if path.name == expected_name and claim["run_id"] == run_id:
                    sessions.add(str(claim["session_id"]))
            except (OSError, UnicodeError, json.JSONDecodeError, StateError):
                pass
    return sessions


def _remove_decisions(directory: Path, run_id: str, target_sessions: set[str]) -> None:
    if not directory.is_dir():
        return
    for path in directory.glob("*.json"):
        try:
            decision = _validate_decision(_read_json(path))
            if path.stem != decision["session_id"]:
                raise StateError("decision filename and session mismatch")
            remove = decision["run_id"] == run_id
        except (OSError, UnicodeError, json.JSONDecodeError, StateError):
            remove = path.stem in target_sessions
        if remove:
            try:
                path.unlink()
            except FileNotFoundError:
                pass


def _remove_session_locks(directory: Path, run_id: str, target_sessions: set[str]) -> None:
    if not directory.is_dir():
        return
    for path in directory.glob("session.*.lock"):
        session_id = path.name[len("session.") : -len(".lock")]
        try:
            claim = _validate_consumer_claim(_read_json(path))
            if path.name != f"session.{claim['session_id']}.lock":
                raise StateError("session lock filename and claim mismatch")
            remove = claim["run_id"] == run_id
        except (OSError, UnicodeError, json.JSONDecodeError, StateError):
            remove = session_id in target_sessions
        if remove:
            try:
                path.unlink()
            except FileNotFoundError:
                pass


def invalidate_run(state_root: Path, run_id: str) -> None:
    run_id = _safe_identifier(run_id, "run_id")
    with _routing_gate(state_root, exclusive=True):
        if not state_root.exists():
            return
        if state_root.is_symlink() or not state_root.is_dir():
            raise StateError("routing state root is not a regular directory")
        with _run_gate(state_root, run_id, exclusive=True) as run_lock:
            target_sessions = _collect_target_sessions(state_root, run_id)
            _remove_namespaced_run_json(state_root / "pending", run_id)
            _remove_namespaced_run_json(state_root / "consumed", run_id)
            cache_path = state_root / "cache" / f"{run_id}.json"
            try:
                cache_path.unlink()
            except FileNotFoundError:
                pass
            _remove_decisions(state_root / "decisions", run_id, target_sessions)
            lock_directory = state_root / "locks"
            if lock_directory.is_dir():
                _remove_session_locks(lock_directory, run_id, target_sessions)
                for path in lock_directory.glob(f"{run_id}.*.lock"):
                    if path == run_lock:
                        continue
                    try:
                        path.unlink()
                    except FileNotFoundError:
                        pass
            try:
                run_lock.unlink()
            except FileNotFoundError:
                pass
            for name in reversed(STATE_DIRECTORIES):
                directory = state_root / name
                try:
                    directory.rmdir()
                except (FileNotFoundError, OSError):
                    pass
            try:
                state_root.rmdir()
            except OSError:
                pass

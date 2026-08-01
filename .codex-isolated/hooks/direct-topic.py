#!/usr/bin/env python3
"""Bind an interactive Codex session to an explicitly approved direct topic."""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Mapping


SLUG_RE = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
SESSION_RE = re.compile(r"[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\Z")
TOPIC_PROMPT_RE = re.compile(r"@topic\s+([a-z0-9]+(?:-[a-z0-9]+)*)\s*\Z")
MANIFEST_TIMEOUT_SECONDS = 5


def _output(value: Mapping[str, object]) -> None:
    json.dump(value, sys.stdout)
    sys.stdout.write("\n")


def _context(text: str) -> dict[str, object]:
    return {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": text,
        }
    }


def _block(reason: str) -> dict[str, object]:
    return {"decision": "block", "reason": reason}


def _project_root(cwd: object) -> Path:
    if not isinstance(cwd, str) or not cwd:
        raise ValueError("session cwd is missing")
    result = subprocess.run(
        ["/usr/bin/git", "-C", cwd, "rev-parse", "--show-toplevel"],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "GIT_CONFIG_NOSYSTEM": "1"},
    )
    if result.returncode != 0 or not result.stdout.strip():
        raise ValueError("direct topic requires a Git repository")
    return Path(result.stdout.strip()).resolve()


def _registry_profile(home: Path) -> tuple[str, str, str]:
    path = home / "profiles" / "registry.yaml"
    value = path.read_text(encoding="utf-8")
    match = re.search(
        r"^  engineering:\n    model: ([^\n]+)\n    effort: ([^\n]+)\n",
        value,
        re.MULTILINE,
    )
    if match is None:
        raise ValueError("shared engineering profile is unavailable")
    model, effort = match.groups()
    if not model or not effort:
        raise ValueError("shared engineering profile is malformed")
    return hashlib.sha256(value.encode()).hexdigest(), model, effort


def _atomic_write(path: Path, value: str, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            descriptor = -1
            stream.write(value)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def _safe_diagnostic(value: str) -> str:
    normalized = " ".join(value.split())
    normalized = re.sub(r"[^A-Za-z0-9 .,:;_()/-]", "?", normalized)
    return normalized[:240].rstrip()


def _run_manifest(command: list[str], action: str) -> None:
    try:
        result = subprocess.run(
            command,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=MANIFEST_TIMEOUT_SECONDS,
            env={"PATH": "/usr/bin:/bin", "LC_ALL": "C", "LANG": "C"},
        )
    except OSError as error:
        raise ValueError(f"shared manifest helper is unavailable: {_safe_diagnostic(str(error))}") from None
    except subprocess.TimeoutExpired:
        raise ValueError(f"shared manifest helper {action} timed out after {MANIFEST_TIMEOUT_SECONDS} seconds") from None
    if result.returncode != 0:
        raise ValueError(f"shared manifest helper {action} failed with exit code {result.returncode}")


def _update_manifest(home: Path, root: Path, topic: str, exists: bool, environ: Mapping[str, str]) -> None:
    root_text = environ.get("ICODEX_ROOT", "")
    helper_root = Path(root_text)
    if not root_text or not helper_root.is_absolute():
        raise ValueError("ICODEX_ROOT must be absolute")
    installed_root = Path(__file__).resolve().parents[2]
    if helper_root.resolve() != installed_root:
        raise ValueError("ICODEX_ROOT does not match installed hook location")
    helper = helper_root / "lib" / "profile" / "manifest.py"
    if not helper.is_file():
        raise ValueError("shared manifest helper is unavailable")
    registry = home / "profiles" / "registry.yaml"
    if not exists:
        command = [
            sys.executable,
            str(helper),
            "bootstrap",
            "--project-root",
            str(root),
            "--registry",
            str(registry),
            "--topic",
            topic,
            "--intent",
            "docs/profiles/README.md",
            "--status",
            "approved",
            "--route",
            "direct",
        ]
        _run_manifest(command, "bootstrap")
    else:
        command = [
            sys.executable,
            str(helper),
            "expand",
            "--project-root",
            str(root),
            "--registry",
            str(registry),
            "--topic",
            topic,
            "--route",
            "direct",
        ]
        _run_manifest(command, "expansion")


def _mapping_path(home: Path, session_id: str) -> Path:
    if SESSION_RE.fullmatch(session_id) is None:
        raise ValueError("session ID is invalid")
    return home / "state" / "direct-topics" / f"{session_id}.json"


def _save_topic(home: Path, session_id: str, root: Path, topic: str, model: str, effort: str) -> None:
    value = json.dumps(
        {"root": str(root), "topic": topic, "model": model, "effort": effort},
        sort_keys=True,
        separators=(",", ":"),
    ) + "\n"
    _atomic_write(_mapping_path(home, session_id), value, 0o600)


def _load_topic(home: Path, session_id: str, root: Path) -> dict[str, str] | None:
    path = _mapping_path(home, session_id)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, OSError, json.JSONDecodeError):
        return None
    if not isinstance(value, dict) or set(value) != {"root", "topic", "model", "effort"}:
        return None
    if value.get("root") != str(root) or any(not isinstance(value.get(key), str) for key in value):
        return None
    if SLUG_RE.fullmatch(value["topic"]) is None:
        return None
    return value


def active_topic(event: Mapping[str, object], environ: Mapping[str, str]) -> dict[str, str] | None:
    """Return a validated direct-topic mapping for another local hook."""
    session_id = event.get("session_id")
    home_text = environ.get("CODEX_HOME", "")
    if not isinstance(session_id, str) or not home_text:
        return None
    home = Path(home_text)
    if not home.is_absolute():
        return None
    try:
        return _load_topic(home, session_id, _project_root(event.get("cwd")))
    except (OSError, ValueError):
        return None


def handle(event: Mapping[str, object], environ: Mapping[str, str]) -> dict[str, object] | None:
    if event.get("hook_event_name") != "UserPromptSubmit":
        return None
    session_id = event.get("session_id")
    prompt = event.get("prompt")
    model = event.get("model")
    if not isinstance(session_id, str) or not isinstance(prompt, str) or not isinstance(model, str):
        return None
    home_text = environ.get("CODEX_HOME", "")
    home = Path(home_text)
    if not home_text or not home.is_absolute():
        return _block("Direct topic state is unavailable: CODEX_HOME must be absolute.")
    try:
        root = _project_root(event.get("cwd"))
        topic_match = TOPIC_PROMPT_RE.fullmatch(prompt)
        if topic_match is not None:
            topic = topic_match.group(1)
            _, required_model, effort = _registry_profile(home)
            profile = root / "docs" / "profiles" / f"{topic}.yaml"
            _update_manifest(home, root, topic, profile.exists(), environ)
            _save_topic(home, session_id, root, topic, required_model, effort)
            return _context(
                f"Direct topic {topic} is active. Its explicit @topic command approved "
                f"the initial engineering profile ({required_model}/{effort})."
            )
        current = _load_topic(home, session_id, root)
        if current is None:
            return None
        if model != current["model"]:
            return _block(
                f"Direct topic {current['topic']} requires model {current['model']}. "
                "Switch the model, then send any next prompt."
            )
        return _context(
            f"Direct topic {current['topic']} is active with matching model {model}. "
            "The user confirmed the selected reasoning effort by continuing this session."
        )
    except (OSError, ValueError) as error:
        return _block(
            f"Direct topic state is unavailable: {_safe_diagnostic(str(error))}. "
            "Verify ICODEX_ROOT, the shared registry, and docs/profiles/README.md, then send "
            "@topic <lowercase-kebab-case-topic>."
        )


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, TypeError, ValueError):
        return 0
    if not isinstance(event, dict):
        return 0
    result = handle(event, os.environ)
    if result is not None:
        _output(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Create and extend strict topic profile manifests."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
import tempfile
from pathlib import Path
from typing import Any

from policy import DIMENSION_COMPARATORS, PolicyError, SLUG_RE, load_registry, parse_yaml_subset


REQUIREMENTS = {
    "capability": "strong",
    "context": "medium",
    "latency": "medium",
    "cost": "medium",
    "throughput": "medium",
}
TASKS = {
    "intent-profile-selection": "engineering",
    "direct-work": "engineering",
    "spec-design": "synthesis",
    "plan-writing": "synthesis",
    "implementation": "engineering",
    "result-reconciliation": "engineering",
}
ROUTES = {
    "direct": ("direct-work",),
    "full": (
        "intent-profile-selection",
        "spec-design",
        "plan-writing",
        "implementation",
        "result-reconciliation",
    ),
}
PLAIN_SCALAR_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/-]*\Z")


class ManifestError(Exception):
    pass


def _relative_path(value: str, name: str) -> None:
    parts = value.split("/")
    if not value or Path(value).is_absolute() or any(part in {"", ".", ".."} for part in parts):
        raise ManifestError(f"{name} must be a repository-relative path")


def _manifest_path(project_root: str, topic: str) -> Path:
    root = Path(project_root).resolve()
    if not root.is_dir():
        raise ManifestError(f"project root must be an existing directory: {project_root}")
    docs = root / "docs"
    profiles = docs / "profiles"
    for directory, label in ((docs, "docs directory"), (profiles, "profile directory")):
        try:
            mode = directory.lstat().st_mode
        except FileNotFoundError:
            continue
        except OSError as error:
            raise ManifestError(f"cannot inspect {label}: {error}") from None
        if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode):
            raise ManifestError(f"{label} must be a real directory")
    path = profiles / f"{topic}.yaml"
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        mode = None
    except OSError as error:
        raise ManifestError(f"cannot inspect topic manifest: {error}") from None
    if mode is not None and (stat.S_ISLNK(mode) or not stat.S_ISREG(mode)):
        raise ManifestError("topic manifest must be a regular file")
    try:
        path.resolve(strict=False).relative_to(root)
    except ValueError:
        raise ManifestError("topic manifest must remain inside project root") from None
    return path


def _task(task_id: str) -> dict[str, Any]:
    return {
        "id": task_id,
        "requirements": dict(REQUIREMENTS),
        "live_remaining_context": False,
        "preferred_profiles": [TASKS[task_id]],
    }


def _yaml_string(value: str) -> str:
    if PLAIN_SCALAR_RE.fullmatch(value) and value not in {"true", "false", "null", "~"}:
        return value
    return json.dumps(value, ensure_ascii=False)


def _validate_task(
    value: object, index: int, known_profiles: set[str], known_tiers: dict[str, set[str]]
) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ManifestError(f"tasks[{index}] must be a mapping")
    expected = {"id", "requirements", "live_remaining_context", "preferred_profiles"}
    if set(value) != expected:
        raise ManifestError(f"tasks[{index}] has invalid keys")
    task_id = value["id"]
    if not isinstance(task_id, str) or not SLUG_RE.fullmatch(task_id):
        raise ManifestError(f"invalid task id: {task_id}")
    requirements = value["requirements"]
    if not isinstance(requirements, dict) or set(requirements) != set(DIMENSION_COMPARATORS):
        raise ManifestError(f"tasks[{index}].requirements has invalid keys")
    if any(
        not isinstance(tier, str) or tier not in known_tiers[name]
        for name, tier in requirements.items()
    ):
        raise ManifestError(f"tasks[{index}].requirements contains an unknown tier")
    if type(value["live_remaining_context"]) is not bool:
        raise ManifestError(f"tasks[{index}].live_remaining_context must be a boolean")
    preferred = value["preferred_profiles"]
    if not isinstance(preferred, list) or len(preferred) != 1 or not isinstance(preferred[0], str):
        raise ManifestError(f"tasks[{index}].preferred_profiles must contain one profile")
    if preferred[0] not in known_profiles:
        raise ManifestError(f"unknown preferred profile: {preferred[0]}")
    result = dict(value)
    result["requirements"] = dict(requirements)
    result["preferred_profiles"] = list(preferred)
    if task_id in TASKS and result != _task(task_id):
        raise ManifestError(f"canonical task conflicts with required mapping: {task_id}")
    return result


def _validate_manifest(
    data: object,
    topic: str,
    registry_hash: str,
    known_profiles: set[str],
    known_tiers: dict[str, set[str]],
) -> dict[str, Any]:
    if not isinstance(data, dict):
        raise ManifestError("topic manifest must be a mapping")
    expected = {"schema_version", "topic", "status", "registry", "context_inputs", "tasks"}
    if set(data) != expected:
        raise ManifestError("topic manifest has invalid keys")
    if data["schema_version"] != 1 or type(data["schema_version"]) is not int:
        raise ManifestError("unsupported topic schema_version")
    if data["topic"] != topic:
        raise ManifestError("topic must match filename")
    if data["status"] not in {"draft", "approved"}:
        raise ManifestError("topic status must be draft or approved")
    registry = data["registry"]
    if not isinstance(registry, dict) or registry != {
        "authority": "icodex-shared", "path": "profiles/registry.yaml", "sha256": registry_hash
    }:
        raise ManifestError("registry pin is invalid or does not match registry")
    inputs = data["context_inputs"]
    if not isinstance(inputs, list) or not inputs or not all(isinstance(item, str) for item in inputs):
        raise ManifestError("context_inputs must be a non-empty list of paths")
    for item in inputs:
        _relative_path(item, "context input")
    if len(inputs) != len(set(inputs)):
        raise ManifestError("duplicate context input")
    tasks = data["tasks"]
    if not isinstance(tasks, list) or not tasks:
        raise ManifestError("tasks must be a non-empty list")
    validated = [
        _validate_task(item, index, known_profiles, known_tiers) for index, item in enumerate(tasks)
    ]
    ids = [item["id"] for item in validated]
    if len(ids) != len(set(ids)):
        raise ManifestError("duplicate task id")
    result = dict(data)
    result["registry"] = dict(registry)
    result["context_inputs"] = list(inputs)
    result["tasks"] = validated
    return result


def _render(manifest: dict[str, Any]) -> bytes:
    lines = [
        "schema_version: 1",
        f"topic: {_yaml_string(manifest['topic'])}",
        f"status: {_yaml_string(manifest['status'])}",
        "registry:",
        "  authority: icodex-shared",
        "  path: profiles/registry.yaml",
        f"  sha256: {manifest['registry']['sha256']}",
        "context_inputs:",
    ]
    lines.extend(f"  - {_yaml_string(item)}" for item in manifest["context_inputs"])
    lines.append("tasks:")
    for task in manifest["tasks"]:
        lines.extend((f"  - id: {_yaml_string(task['id'])}", "    requirements:"))
        lines.extend(
            f"      {name}: {_yaml_string(task['requirements'][name])}"
            for name in DIMENSION_COMPARATORS
        )
        lines.append("    live_remaining_context: false")
        lines.append("    preferred_profiles:")
        lines.extend(f"      - {_yaml_string(profile)}" for profile in task["preferred_profiles"])
    return ("\n".join(lines) + "\n").encode()


def _replace_if_changed(path: Path, data: bytes) -> None:
    if path.exists() and path.read_bytes() == data:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(descriptor, 0o644)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def _registry(path: Path) -> tuple[str, set[str], dict[str, set[str]]]:
    registry_bytes = path.read_bytes()
    registry = load_registry(path)
    profiles = registry["profiles"]
    dimensions = registry["dimensions"]
    assert isinstance(profiles, dict)
    assert isinstance(dimensions, dict)
    tiers = {
        name: set(dimension["tiers"])
        for name, dimension in dimensions.items()
        if isinstance(dimension, dict) and isinstance(dimension.get("tiers"), list)
    }
    return hashlib.sha256(registry_bytes).hexdigest(), set(profiles), tiers


def bootstrap(args: argparse.Namespace) -> None:
    if not SLUG_RE.fullmatch(args.topic):
        raise ManifestError("topic must be lowercase kebab-case")
    _relative_path(args.intent, "intent")
    registry_hash, profiles, _ = _registry(Path(args.registry))
    for profile in TASKS.values():
        if profile not in profiles:
            raise ManifestError(f"registry missing required profile: {profile}")
    project_root = Path(args.project_root).resolve()
    if not project_root.is_dir():
        raise ManifestError(f"project root must be an existing directory: {args.project_root}")
    intent_path = project_root / args.intent
    if not intent_path.is_file():
        raise ManifestError(f"intent must name an existing regular file: {args.intent}")
    path = _manifest_path(args.project_root, args.topic)
    if path.exists():
        raise ManifestError(f"topic manifest already exists: {path}")
    if args.route == "direct":
        if args.status != "approved":
            raise ManifestError("direct bootstrap status must be approved")
        if args.intent != "docs/profiles/README.md":
            raise ManifestError("direct bootstrap intent must be docs/profiles/README.md")
        task_ids = ("direct-work",)
    else:
        task_ids = ("intent-profile-selection",)
    manifest = {
        "schema_version": 1,
        "topic": args.topic,
        "status": args.status,
        "registry": {"authority": "icodex-shared", "path": "profiles/registry.yaml", "sha256": registry_hash},
        "context_inputs": [args.intent],
        "tasks": [_task(task_id) for task_id in task_ids],
    }
    _replace_if_changed(path, _render(manifest))


def expand(args: argparse.Namespace) -> None:
    if not SLUG_RE.fullmatch(args.topic):
        raise ManifestError("topic must be lowercase kebab-case")
    registry_hash, profiles, tiers = _registry(Path(args.registry))
    path = _manifest_path(args.project_root, args.topic)
    try:
        manifest = _validate_manifest(
            parse_yaml_subset(path.read_text(encoding="utf-8")),
            args.topic,
            registry_hash,
            profiles,
            tiers,
        )
    except OSError as error:
        raise ManifestError(f"cannot read topic manifest {path}: {error}") from None
    existing = {task["id"] for task in manifest["tasks"]}
    if args.route == "full":
        if args.authorization != "full":
            raise ManifestError("full expansion requires --authorization full")
        if manifest["status"] != "approved":
            raise ManifestError("full expansion requires an approved manifest")
        if "intent-profile-selection" not in existing or "direct-work" in existing:
            raise ManifestError("full expansion requires a chain bootstrap manifest")
    for task_id in ROUTES[args.route]:
        if task_id not in existing:
            manifest["tasks"].append(_task(task_id))
    _replace_if_changed(path, _render(manifest))


def main() -> int:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    bootstrap_parser = commands.add_parser("bootstrap")
    bootstrap_parser.add_argument("--project-root", required=True)
    bootstrap_parser.add_argument("--registry", required=True)
    bootstrap_parser.add_argument("--topic", required=True)
    bootstrap_parser.add_argument("--intent", required=True)
    bootstrap_parser.add_argument("--status", choices=("draft", "approved"), required=True)
    bootstrap_parser.add_argument("--route", choices=("bootstrap", "direct"), default="bootstrap")
    expand_parser = commands.add_parser("expand")
    expand_parser.add_argument("--project-root", required=True)
    expand_parser.add_argument("--registry", required=True)
    expand_parser.add_argument("--topic", required=True)
    expand_parser.add_argument("--route", choices=tuple(ROUTES), required=True)
    expand_parser.add_argument("--authorization", choices=("full",))
    args = parser.parse_args()
    try:
        if args.command == "bootstrap":
            bootstrap(args)
        else:
            expand(args)
    except (ManifestError, PolicyError, OSError, UnicodeError) as error:
        print(f"manifest: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

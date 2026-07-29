#!/usr/bin/env python3
"""Strict, dependency-free policy loading and profile selection."""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import NoReturn


SCHEMA_VERSION = 1
SUPPORTED_EFFORTS = {"low", "medium", "high", "xhigh", "max", "ultra"}
DIMENSION_COMPARATORS = {
    "capability": "gte",
    "context": "gte",
    "latency": "lte",
    "cost": "lte",
    "throughput": "gte",
}
SLUG_RE = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
INTEGER_RE = re.compile(r"[-+]?(?:0|[1-9][0-9]*)\Z")


class PolicyError(Exception):
    def __init__(self, message: str, exit_code: int = 2):
        super().__init__(message)
        self.exit_code = exit_code


@dataclass(frozen=True)
class _Token:
    indent: int
    text: str
    line: int


def _unsupported(line: int, detail: str) -> NoReturn:
    raise PolicyError(f"unsupported YAML at line {line}: {detail}")


def _outside_quoted(text: str) -> list[tuple[int, str]]:
    result: list[tuple[int, str]] = []
    quote: str | None = None
    escaped = False
    index = 0
    while index < len(text):
        char = text[index]
        if quote == '"':
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
        elif quote == "'":
            if char == quote:
                if index + 1 < len(text) and text[index + 1] == quote:
                    index += 1
                else:
                    quote = None
        elif char in {"'", '"'}:
            quote = char
        else:
            result.append((index, char))
        index += 1
    if quote is not None:
        raise PolicyError("unsupported YAML: unterminated quoted scalar")
    return result


def _strip_comment(text: str) -> str:
    outside = dict(_outside_quoted(text))
    for index, char in outside.items():
        if char == "#" and (index == 0 or text[index - 1].isspace()):
            return text[:index].rstrip()
    return text.rstrip()


def _mapping_separator(text: str) -> int | None:
    outside = dict(_outside_quoted(text))
    for index, char in outside.items():
        if char == ":" and (index + 1 == len(text) or text[index + 1].isspace()):
            return index
    return None


def _tokenize(text: str) -> list[_Token]:
    tokens: list[_Token] = []
    for line_number, raw in enumerate(text.splitlines(), 1):
        if "\t" in raw:
            _unsupported(line_number, "tabs are not allowed")
        stripped = _strip_comment(raw)
        if not stripped.strip():
            continue
        indent = len(stripped) - len(stripped.lstrip(" "))
        if indent % 2:
            _unsupported(line_number, "indentation must use two spaces")
        content = stripped[indent:]
        outside = _outside_quoted(content)
        if any(char in "[]{}" for _, char in outside):
            _unsupported(line_number, "flow collections are not allowed")
        if content in {"---", "..."}:
            _unsupported(line_number, "document markers are not allowed")
        if content.startswith("- "):
            item = content[2:].strip()
            if _mapping_separator(item) is not None:
                tokens.append(_Token(indent, "-", line_number))
                tokens.append(_Token(indent + 2, item, line_number))
                continue
        tokens.append(_Token(indent, content, line_number))
    return tokens


def _parse_scalar(text: str, line: int) -> object:
    if not text:
        return None
    if text[0] in "&*!|>":
        _unsupported(line, "anchors, aliases, tags, and block scalars are not allowed")
    for index, char in _outside_quoted(text):
        if char in "&*!" and (index == 0 or text[index - 1].isspace()):
            _unsupported(line, "anchors, aliases, and tags are not allowed")
    if text.startswith('"'):
        try:
            value = json.loads(text)
        except json.JSONDecodeError as error:
            raise PolicyError(f"invalid quoted scalar at line {line}: {error.msg}") from None
        if not isinstance(value, str):
            _unsupported(line, "quoted scalar must be a string")
        return value
    if text.startswith("'"):
        if len(text) < 2 or not text.endswith("'"):
            raise PolicyError(f"invalid quoted scalar at line {line}")
        return text[1:-1].replace("''", "'")
    if "'" in text or '"' in text:
        _unsupported(line, "quotes inside plain scalars are not allowed")
    if text == "true":
        return True
    if text == "false":
        return False
    if text in {"null", "~"}:
        return None
    if INTEGER_RE.fullmatch(text):
        return int(text)
    return text


def _parse_tokens(tokens: list[_Token]) -> object:
    def parse_node(index: int, indent: int, path: list[str]) -> tuple[object, int]:
        token = tokens[index]
        if token.indent != indent:
            _unsupported(token.line, "invalid indentation")
        if token.text == "-" or token.text.startswith("- "):
            values: list[object] = []
            while index < len(tokens) and tokens[index].indent == indent:
                current = tokens[index]
                if current.text == "-":
                    index += 1
                    if index >= len(tokens) or tokens[index].indent != indent + 2:
                        _unsupported(current.line, "list item must contain a value")
                    value, index = parse_node(index, indent + 2, path + [f"[{len(values)}]"])
                elif current.text.startswith("- "):
                    value = _parse_scalar(current.text[2:].strip(), current.line)
                    index += 1
                    if index < len(tokens) and tokens[index].indent > indent:
                        _unsupported(tokens[index].line, "scalar list item cannot have children")
                else:
                    break
                values.append(value)
            return values, index

        mapping: dict[str, object] = {}
        while index < len(tokens) and tokens[index].indent == indent:
            current = tokens[index]
            if current.text == "-" or current.text.startswith("- "):
                break
            separator = _mapping_separator(current.text)
            if separator is None:
                _unsupported(current.line, "mapping entry requires ':'")
            raw_key = current.text[:separator].strip()
            raw_value = current.text[separator + 1 :].strip()
            key_value = _parse_scalar(raw_key, current.line)
            if not isinstance(key_value, str) or not key_value:
                raise PolicyError(f"mapping key must be a non-empty string at line {current.line}")
            if key_value == "<<":
                _unsupported(current.line, "merge keys are not allowed")
            key_path = ".".join(path + [key_value]).replace(".[", "[")
            if key_value in mapping:
                raise PolicyError(f"duplicate key: {key_path}")
            index += 1
            if raw_value:
                value = _parse_scalar(raw_value, current.line)
                if index < len(tokens) and tokens[index].indent > indent:
                    _unsupported(tokens[index].line, "scalar mapping value cannot have children")
            elif index < len(tokens) and tokens[index].indent > indent:
                if tokens[index].indent != indent + 2:
                    _unsupported(tokens[index].line, "invalid indentation jump")
                value, index = parse_node(index, indent + 2, path + [key_value])
            else:
                value = None
            mapping[key_value] = value
        return mapping, index

    if not tokens:
        return {}
    if tokens[0].indent != 0:
        _unsupported(tokens[0].line, "top-level content must not be indented")
    value, consumed = parse_node(0, 0, [])
    if consumed != len(tokens):
        _unsupported(tokens[consumed].line, "inconsistent indentation")
    return value


def parse_yaml_subset(text: str) -> dict[str, object]:
    """Parse the project-owned strict YAML subset into JSON-compatible values."""
    value = _parse_tokens(_tokenize(text))
    if not isinstance(value, dict):
        raise PolicyError("YAML document must be a mapping")
    return value


def _read_bytes(path: Path) -> bytes:
    try:
        return path.read_bytes()
    except OSError as error:
        raise PolicyError(f"cannot read policy file {path}: {error}") from None


def _parse_yaml_bytes(data: bytes, path: Path) -> dict[str, object]:
    try:
        text = data.decode("utf-8")
    except UnicodeError as error:
        raise PolicyError(f"cannot read policy file {path}: {error}") from None
    return parse_yaml_subset(text)


def _mapping(value: object, name: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise PolicyError(f"{name} must be a mapping")
    return value


def _list(value: object, name: str) -> list[object]:
    if not isinstance(value, list):
        raise PolicyError(f"{name} must be a list")
    return value


def _string(value: object, name: str) -> str:
    if not isinstance(value, str) or not value:
        raise PolicyError(f"{name} must be a non-empty string")
    return value


def _exact_keys(mapping: dict[str, object], expected: set[str], name: str) -> None:
    missing = sorted(expected - mapping.keys())
    unknown = sorted(mapping.keys() - expected)
    if missing:
        raise PolicyError(f"{name} missing keys: {', '.join(missing)}")
    if unknown:
        raise PolicyError(f"{name} unknown keys: {', '.join(unknown)}")


def _version(value: object, name: str) -> int:
    if type(value) is not int or value < 1:
        raise PolicyError(f"{name} must be a positive integer")
    return value


def _validate_registry(registry: dict[str, object]) -> dict[str, object]:
    _exact_keys(registry, {"schema_version", "registry_version", "dimensions", "profiles"}, "registry")
    if type(registry["schema_version"]) is not int or registry["schema_version"] != SCHEMA_VERSION:
        raise PolicyError(f"unsupported registry schema_version: {registry['schema_version']}")
    _version(registry["registry_version"], "registry_version")

    dimensions = _mapping(registry["dimensions"], "dimensions")
    _exact_keys(dimensions, set(DIMENSION_COMPARATORS), "dimensions")
    tier_sets: dict[str, list[str]] = {}
    for name, required_comparator in DIMENSION_COMPARATORS.items():
        dimension = _mapping(dimensions[name], f"dimensions.{name}")
        _exact_keys(dimension, {"comparator", "tiers"}, f"dimensions.{name}")
        if dimension["comparator"] != required_comparator:
            raise PolicyError(f"dimensions.{name}.comparator must be {required_comparator}")
        raw_tiers = _list(dimension["tiers"], f"dimensions.{name}.tiers")
        tiers = [_string(tier, f"dimensions.{name}.tiers") for tier in raw_tiers]
        if not tiers or len(tiers) != len(set(tiers)):
            raise PolicyError(f"dimensions.{name}.tiers must be non-empty and unique")
        tier_sets[name] = tiers

    profiles = _mapping(registry["profiles"], "profiles")
    if not profiles:
        raise PolicyError("profiles must not be empty")
    pairs: set[tuple[str, str]] = set()
    for profile_id, raw_profile in profiles.items():
        if not SLUG_RE.fullmatch(profile_id):
            raise PolicyError(f"invalid profile id: {profile_id}")
        profile = _mapping(raw_profile, f"profiles.{profile_id}")
        _exact_keys(profile, {"model", "effort", "capacities"}, f"profiles.{profile_id}")
        model = _string(profile["model"], f"profiles.{profile_id}.model")
        effort = _string(profile["effort"], f"profiles.{profile_id}.effort")
        if effort not in SUPPORTED_EFFORTS:
            raise PolicyError(f"unsupported effort: profiles.{profile_id}.effort={effort}")
        pair = (model, effort)
        if pair in pairs:
            raise PolicyError(f"duplicate model/effort profile: {model}/{effort}")
        pairs.add(pair)
        capacities = _mapping(profile["capacities"], f"profiles.{profile_id}.capacities")
        _exact_keys(capacities, set(DIMENSION_COMPARATORS), f"profiles.{profile_id}.capacities")
        for dimension, tiers in tier_sets.items():
            tier = _string(capacities[dimension], f"profiles.{profile_id}.capacities.{dimension}")
            if tier not in tiers:
                raise PolicyError(f"unknown tier: profiles.{profile_id}.capacities.{dimension}={tier}")
    return registry


def _registry_from_bytes(data: bytes, path: Path) -> dict[str, object]:
    return _validate_registry(_parse_yaml_bytes(data, path))


def load_registry(path: Path) -> dict[str, object]:
    """Validate schema_version, registry_version, dimensions, and exact profiles."""
    return _registry_from_bytes(_read_bytes(path), path)


def _repo_relative(path: Path, repo: Path, label: str) -> Path:
    try:
        return path.resolve().relative_to(repo.resolve())
    except ValueError:
        raise PolicyError(f"{label} must be inside repository {repo}") from None


def _validate_relative_path(value: str, name: str) -> None:
    path = Path(value)
    if path.is_absolute() or ".." in path.parts or value in {"", "."}:
        raise PolicyError(f"{name} must be a repository-relative path")


def _require_context_blob(repo: Path, commit: str, value: str) -> None:
    relative = Path(value)
    candidate = repo.resolve() / relative
    resolved = candidate.resolve()
    try:
        resolved.relative_to(repo.resolve())
    except ValueError:
        raise PolicyError(f"context input must resolve inside repository: {value}", 3) from None
    if not resolved.is_file():
        raise PolicyError(f"context input does not exist: {value}", 3)
    result = subprocess.run(
        ["git", "-C", str(repo), "ls-tree", "--full-tree", commit, "--", relative.as_posix()],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    entry = result.stdout.strip().split(None, 3)
    if result.returncode != 0 or not entry:
        raise PolicyError(f"context input is not tracked at pinned HEAD: {value}", 3)
    if len(entry) < 2 or entry[0] not in {"100644", "100755"} or entry[1] != "blob":
        raise PolicyError(f"context input must be a tracked regular file at pinned HEAD: {value}", 3)


@dataclass(frozen=True)
class _PolicyPair:
    topic: dict[str, object]
    registry: dict[str, object]


def _policy_pair_from_bytes(
    path: Path,
    registry_path: Path,
    repo: Path,
    topic_bytes: bytes,
    registry_bytes: bytes,
    commit: str,
) -> _PolicyPair:
    topic = _parse_yaml_bytes(topic_bytes, path)
    _exact_keys(
        topic,
        {"schema_version", "topic", "status", "registry", "context_inputs", "portable_history", "tasks"},
        "topic manifest",
    )
    if type(topic["schema_version"]) is not int or topic["schema_version"] != SCHEMA_VERSION:
        raise PolicyError(f"unsupported topic schema_version: {topic['schema_version']}")
    topic_name = _string(topic["topic"], "topic")
    if not SLUG_RE.fullmatch(topic_name) or path.stem != topic_name:
        raise PolicyError("topic must be canonical lowercase kebab-case and match the filename")
    expected_topic = repo.resolve() / "docs" / "profiles" / f"{topic_name}.yaml"
    if path.resolve() != expected_topic:
        raise PolicyError(f"topic manifest path must be docs/profiles/{topic_name}.yaml", 3)
    if topic["status"] != "approved":
        raise PolicyError("topic status must be approved", 3)

    registry_pin = _mapping(topic["registry"], "registry")
    _exact_keys(registry_pin, {"path", "sha256"}, "registry")
    pinned_path = _string(registry_pin["path"], "registry.path")
    _validate_relative_path(pinned_path, "registry.path")
    expected_registry = repo.resolve() / "docs" / "profiles" / "registry.yaml"
    if registry_path.resolve() != expected_registry:
        raise PolicyError("registry path must be docs/profiles/registry.yaml", 3)
    actual_registry_relative = _repo_relative(registry_path, repo, "registry")
    if Path(pinned_path) != actual_registry_relative:
        raise PolicyError(f"registry path mismatch: expected {actual_registry_relative.as_posix()}", 3)
    pinned_hash = _string(registry_pin["sha256"], "registry.sha256")
    if not SHA256_RE.fullmatch(pinned_hash):
        raise PolicyError("registry.sha256 must be a lowercase SHA-256")
    registry = _registry_from_bytes(registry_bytes, registry_path)
    if hashlib.sha256(registry_bytes).hexdigest() != pinned_hash:
        raise PolicyError("registry hash mismatch; review and repin the topic manifest", 3)

    context_inputs = _list(topic["context_inputs"], "context_inputs")
    if not context_inputs:
        raise PolicyError("context_inputs must not be empty")
    seen_inputs: set[str] = set()
    for index, raw_input in enumerate(context_inputs):
        context_input = _string(raw_input, f"context_inputs[{index}]")
        _validate_relative_path(context_input, f"context_inputs[{index}]")
        if context_input in seen_inputs:
            raise PolicyError(f"duplicate context input: {context_input}")
        seen_inputs.add(context_input)
        # Validation consumes only the path, not context bytes. Bind that path to a
        # tracked blob in the same immutable commit without reading mutable content.
        _require_context_blob(repo, commit, context_input)

    portable_history = _mapping(topic["portable_history"], "portable_history")
    _exact_keys(portable_history, {"enabled"}, "portable_history")
    if type(portable_history["enabled"]) is not bool:
        raise PolicyError("portable_history.enabled must be a boolean")

    dimensions = _mapping(registry["dimensions"], "dimensions")
    profiles = _mapping(registry["profiles"], "profiles")
    tasks = _list(topic["tasks"], "tasks")
    if not tasks:
        raise PolicyError("tasks must not be empty")
    seen_tasks: set[str] = set()
    for index, raw_task in enumerate(tasks):
        task = _mapping(raw_task, f"tasks[{index}]")
        _exact_keys(
            task,
            {"id", "requirements", "live_remaining_context", "preferred_profiles"},
            f"tasks[{index}]",
        )
        task_id = _string(task["id"], f"tasks[{index}].id")
        if not SLUG_RE.fullmatch(task_id):
            raise PolicyError(f"invalid task id: {task_id}")
        if task_id in seen_tasks:
            raise PolicyError(f"duplicate task id: {task_id}")
        seen_tasks.add(task_id)
        requirements = _mapping(task["requirements"], f"tasks[{index}].requirements")
        _exact_keys(requirements, set(DIMENSION_COMPARATORS), f"tasks[{index}].requirements")
        for dimension, raw_tier in requirements.items():
            tier = _string(raw_tier, f"tasks[{index}].requirements.{dimension}")
            dimension_data = _mapping(dimensions[dimension], f"dimensions.{dimension}")
            tiers = _list(dimension_data["tiers"], f"dimensions.{dimension}.tiers")
            if tier not in tiers:
                raise PolicyError(f"unknown tier: tasks[{index}].requirements.{dimension}={tier}")
        if type(task["live_remaining_context"]) is not bool:
            raise PolicyError(f"tasks[{index}].live_remaining_context must be a boolean")
        preferred = _list(task["preferred_profiles"], f"tasks[{index}].preferred_profiles")
        if not preferred:
            raise PolicyError(f"tasks[{index}].preferred_profiles must not be empty")
        preferred_ids = [_string(item, f"tasks[{index}].preferred_profiles") for item in preferred]
        if len(preferred_ids) != len(set(preferred_ids)):
            raise PolicyError(f"tasks[{index}].preferred_profiles must be unique")
        unknown_profiles = [profile_id for profile_id in preferred_ids if profile_id not in profiles]
        if unknown_profiles:
            raise PolicyError(f"unknown preferred profile: {unknown_profiles[0]}")
    return _PolicyPair(topic, registry)


def _load_topic_schema(path: Path, registry_path: Path, repo: Path) -> _PolicyPair:
    commit = _resolve_head(repo)
    topic_bytes = _read_bytes(path)
    registry_bytes = _read_bytes(registry_path)
    return _policy_pair_from_bytes(path, registry_path, repo, topic_bytes, registry_bytes, commit)


def _resolve_head(repo: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", "--verify", "HEAD^{commit}"],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    commit = result.stdout.strip()
    if result.returncode != 0 or not re.fullmatch(r"[0-9a-f]{40,64}", commit):
        raise PolicyError("cannot resolve immutable HEAD commit", 3)
    return commit


def _head_bytes(repo: Path, commit: str, path: Path, label: str) -> bytes:
    relative = _repo_relative(path, repo, label)
    result = subprocess.run(
        ["git", "-C", str(repo), "show", f"{commit}:{relative.as_posix()}"],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        raise PolicyError(f"{label} is not tracked at pinned HEAD; approve and commit it", 3)
    return result.stdout


def _load_committed_pair(path: Path, registry_path: Path, repo: Path) -> _PolicyPair:
    commit = _resolve_head(repo)
    topic_bytes = _read_bytes(path)
    registry_bytes = _read_bytes(registry_path)
    committed_topic = _head_bytes(repo, commit, path, "topic manifest")
    committed_registry = _head_bytes(repo, commit, registry_path, "registry")
    if topic_bytes != committed_topic:
        raise PolicyError("topic manifest differs from HEAD; approve and commit exact bytes", 3)
    if registry_bytes != committed_registry:
        raise PolicyError(
            "registry differs from pinned HEAD; registry hash mismatch requires review and repinning",
            3,
        )
    return _policy_pair_from_bytes(path, registry_path, repo, topic_bytes, registry_bytes, commit)


def load_topic(path: Path, registry_path: Path, repo: Path) -> dict[str, object]:
    """Validate schema, committed HEAD equality, approval, registry pin, and tasks."""
    return _load_committed_pair(path, registry_path, repo).topic


def _task(topic: dict[str, object], task_id: str) -> dict[str, object]:
    tasks = _list(topic.get("tasks"), "tasks")
    for raw_task in tasks:
        task = _mapping(raw_task, "task")
        if task.get("id") == task_id:
            return task
    raise PolicyError(f"unknown task: {task_id}", 4)


def _availability(available_models: list[dict[str, object]]) -> dict[str, set[str] | None]:
    availability: dict[str, set[str] | None] = {}
    for index, entry in enumerate(available_models):
        if not isinstance(entry, dict):
            raise PolicyError(f"available_models[{index}] must be a mapping")
        model_id = entry.get("id")
        model_alias = entry.get("model")
        if model_id is not None and model_alias is not None and model_id != model_alias:
            raise PolicyError(f"model/list id and model disagree at index {index}", 4)
        model = _string(model_id if model_id is not None else model_alias, f"available_models[{index}].id")
        if model in availability:
            raise PolicyError(f"duplicate available model id: {model}", 4)
        raw_efforts = entry.get("supportedReasoningEfforts")
        if raw_efforts is None:
            availability[model] = None
            continue
        efforts = _list(raw_efforts, f"available_models[{index}].supportedReasoningEfforts")
        parsed: set[str] = set()
        for effort_index, raw_effort in enumerate(efforts):
            if not isinstance(raw_effort, dict) or not isinstance(raw_effort.get("reasoningEffort"), str):
                raise PolicyError(
                    f"model/list supportedReasoningEfforts[{effort_index}].reasoningEffort is required",
                    4,
                )
            effort = _string(
                raw_effort["reasoningEffort"],
                f"available_models[{index}].supportedReasoningEfforts[{effort_index}].reasoningEffort",
            )
            if effort not in SUPPORTED_EFFORTS:
                raise PolicyError(f"unsupported effort metadata for model {model}: {effort}", 4)
            parsed.add(effort)
        availability[model] = parsed
    return availability


def select_profile(
    registry: dict[str, object],
    topic: dict[str, object],
    task_id: str,
    available_models: list[dict[str, object]],
) -> dict[str, object]:
    """Return the first ordered profile that is available and sufficient."""
    task = _task(topic, task_id)
    if task.get("live_remaining_context") is True:
        raise PolicyError(
            f"task {task_id} requires live remaining-context confirmation from an unsupported source",
            4,
        )
    dimensions = _mapping(registry.get("dimensions"), "dimensions")
    profiles = _mapping(registry.get("profiles"), "profiles")
    requirements = _mapping(task.get("requirements"), f"task {task_id} requirements")
    preferred = _list(task.get("preferred_profiles"), f"task {task_id} preferred_profiles")
    available = _availability(available_models)
    evidence: list[str] = []

    for raw_profile_id in preferred:
        profile_id = _string(raw_profile_id, f"task {task_id} preferred profile")
        if profile_id not in profiles:
            raise PolicyError(f"unknown preferred profile: {profile_id}", 4)
        profile = _mapping(profiles[profile_id], f"profiles.{profile_id}")
        model = _string(profile.get("model"), f"profiles.{profile_id}.model")
        effort = _string(profile.get("effort"), f"profiles.{profile_id}.effort")
        if effort not in SUPPORTED_EFFORTS:
            raise PolicyError(f"unsupported effort: profiles.{profile_id}.effort={effort}", 4)
        if model not in available:
            evidence.append(f"{profile_id}: model {model} unavailable")
            continue
        supported_efforts = available[model]
        if supported_efforts is None:
            raise PolicyError(f"model {model} is missing supported effort metadata", 4)
        if effort not in supported_efforts:
            evidence.append(f"{profile_id}: effort {effort} unavailable for model {model}")
            continue

        capacities = _mapping(profile.get("capacities"), f"profiles.{profile_id}.capacities")
        failures: list[str] = []
        for dimension_name in DIMENSION_COMPARATORS:
            if dimension_name not in requirements:
                raise PolicyError(f"missing requirement dimension: {dimension_name}", 4)
            if dimension_name not in capacities:
                raise PolicyError(f"missing profile dimension: {profile_id}.{dimension_name}", 4)
            if dimension_name not in dimensions:
                raise PolicyError(f"missing registry dimension: {dimension_name}", 4)
            dimension = _mapping(dimensions[dimension_name], f"dimensions.{dimension_name}")
            comparator = dimension.get("comparator")
            if comparator not in {"gte", "lte"}:
                raise PolicyError(f"unknown comparator for dimension {dimension_name}", 4)
            tiers = _list(dimension.get("tiers"), f"dimensions.{dimension_name}.tiers")
            candidate = capacities[dimension_name]
            requirement = requirements[dimension_name]
            if candidate not in tiers:
                raise PolicyError(f"unknown candidate tier: {profile_id}.{dimension_name}={candidate}", 4)
            if requirement not in tiers:
                raise PolicyError(f"unknown requirement tier: {task_id}.{dimension_name}={requirement}", 4)
            candidate_index = tiers.index(candidate)
            requirement_index = tiers.index(requirement)
            sufficient = candidate_index >= requirement_index if comparator == "gte" else candidate_index <= requirement_index
            if not sufficient:
                failures.append(
                    f"dimension {dimension_name}: candidate {candidate} does not satisfy {requirement} ({comparator})"
                )
        if failures:
            evidence.append(f"{profile_id}: " + "; ".join(failures))
            continue
        return {"effort": effort, "model": model, "profile": profile_id, "task": task_id}

    detail = "; ".join(evidence) if evidence else "no preferred profiles"
    raise PolicyError(f"no available sufficient profile for task {task_id}: {detail}", 4)


def _find_repo(path: Path) -> Path:
    result = subprocess.run(
        ["git", "-C", str(path.parent), "rev-parse", "--show-toplevel"],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        raise PolicyError(f"cannot locate Git repository for {path}", 3)
    return Path(result.stdout.strip())


def _available_json(text: str) -> list[dict[str, object]]:
    try:
        value = json.loads(text)
    except json.JSONDecodeError as error:
        raise PolicyError(f"invalid available model JSON: {error.msg}") from None
    if not isinstance(value, list) or any(not isinstance(item, dict) for item in value):
        raise PolicyError("available model JSON must be a list of objects")
    return value


def _usage() -> NoReturn:
    raise PolicyError(
        "usage: policy.py validate-registry <registry> | validate-topic <topic> <registry> | "
        "validate-topic-schema <topic> <registry> | select <topic> <task> <available-json>"
    )


def _run_cli(arguments: list[str]) -> None:
    if not arguments:
        _usage()
    command = arguments[0]
    if command == "validate-registry" and len(arguments) == 2:
        load_registry(Path(arguments[1]))
        return
    if command in {"validate-topic", "validate-topic-schema"} and len(arguments) == 3:
        topic_path = Path(arguments[1])
        registry_path = Path(arguments[2])
        repo = _find_repo(topic_path)
        if command == "validate-topic":
            load_topic(topic_path, registry_path, repo)
        else:
            _load_topic_schema(topic_path, registry_path, repo)
        return
    if command == "select" and len(arguments) == 4:
        topic_path = Path(arguments[1])
        repo = _find_repo(topic_path)
        registry_path = repo / "docs/profiles/registry.yaml"
        pair = _load_committed_pair(topic_path, registry_path, repo)
        selected = select_profile(pair.registry, pair.topic, arguments[2], _available_json(arguments[3]))
        print(json.dumps(selected, sort_keys=True, separators=(",", ":")))
        return
    _usage()


def main() -> int:
    try:
        _run_cli(sys.argv[1:])
        return 0
    except PolicyError as error:
        print(str(error), file=sys.stderr)
        return error.exit_code
    except Exception as error:  # pragma: no cover - defensive CLI boundary
        if os.environ.get("ICODEX_PROFILE_DEBUG") == "1":
            raise
        print(f"unexpected policy error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

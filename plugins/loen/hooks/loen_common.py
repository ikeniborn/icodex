#!/usr/bin/env python3
"""Shared deterministic helpers for LoEn hook assets."""
from __future__ import annotations

import fnmatch
import html
import json
import os
import posixpath
from pathlib import Path
import re
import sys
from typing import Any


BLOCK = 2
TOPIC_RE = re.compile(r"[a-z0-9](?:[a-z0-9]|-(?=[a-z0-9])){0,78}[a-z0-9]?")
CHECKPOINT_DEFAULTS: dict[str, dict[str, Any]] = {
  "goal_context": {"confirmed": False, "goal_hash": "", "context_hash": ""},
  "mode": {"confirmed": False, "mode": "", "subtype": ""},
  "plan": {"confirmed": False, "plan_hash": "", "policy_hash": ""},
  "launch": {"confirmed": False, "goal_hash": "", "context_hash": "", "plan_hash": "", "policy_hash": ""},
}


def mode() -> str:
  value = os.environ.get("LOEN_MODE", "advisory").strip().lower()
  return value if value in {"off", "advisory", "enforce", "strict"} else "advisory"


def is_enforcing() -> bool:
  return mode() in {"enforce", "strict"}


def is_advisory() -> bool:
  return mode() == "advisory"


def is_off() -> bool:
  return mode() == "off"


def is_strict() -> bool:
  return mode() == "strict"


def read_event() -> dict[str, Any]:
  try:
    raw = sys.stdin.read()
  except OSError:
    return {}
  if not raw.strip():
    return {}
  try:
    data = json.loads(raw)
  except json.JSONDecodeError:
    return {}
  return data if isinstance(data, dict) else {}


def topic() -> str:
  return os.environ.get("LOEN_TOPIC", "").strip()


def artifact_root() -> Path:
  return Path(os.environ.get("LOEN_ARTIFACT_ROOT", "docs/loen"))


def topic_dir(topic_value: str | None = None) -> Path:
  return artifact_root() / (topic_value if topic_value is not None else topic())


def read_loop_artifact(topic_value: str | None = None) -> str:
  topic_name = (topic_value if topic_value is not None else topic()).strip()
  if not topic_name:
    return ""
  loop_file = artifact_root() / topic_name / "loop.yaml"
  if not loop_file.is_file():
    return ""
  try:
    return loop_file.read_text(encoding="utf-8")
  except (OSError, UnicodeDecodeError):
    return ""


def _parse_scalar(value: str) -> Any:
  value = value.strip()
  if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
    return value[1:-1]
  lowered = value.lower()
  if lowered in {"null", "~"} or value == "":
    return None
  if lowered == "true":
    return True
  if lowered == "false":
    return False
  return value


def _strip_yaml_comment(line: str) -> str:
  quote = ""
  escaped = False
  for index, char in enumerate(line):
    if escaped:
      escaped = False
      continue
    if char == "\\" and quote == '"':
      escaped = True
      continue
    if char in {'"', "'"}:
      if not quote:
        quote = char
      elif quote == char:
        quote = ""
      continue
    if char == "#" and not quote:
      return line[:index].rstrip()
  return line.rstrip()


def _mapping_key(text: str) -> tuple[str, str] | None:
  quote = ""
  escaped = False
  for index, char in enumerate(text):
    if escaped:
      escaped = False
      continue
    if char == "\\" and quote == '"':
      escaped = True
      continue
    if char in {'"', "'"}:
      if not quote:
        quote = char
      elif quote == char:
        quote = ""
      continue
    if char == ":" and not quote:
      key = text[:index].strip()
      if len(key) >= 2 and key[0] == key[-1] and key[0] in {'"', "'"}:
        key = key[1:-1]
      return key, text[index + 1:].strip()
  return None


CANONICAL_TOP_LEVEL = {
  "mutable_scope", "protected_scope", "quality_gates", "verifier", "budget",
  "stop_conditions", "handoff_conditions", "rollback_policy", "governance",
  "release_policy", "checkpoints",
}
CANONICAL_MAPPINGS = {"verifier", "budget", "governance", "release_policy"}
CANONICAL_LIST_SECTIONS = {
  "mutable_scope", "protected_scope", "stop_conditions", "handoff_conditions",
}
CANONICAL_MEMBERS = {
  "verifier": {"type", "command"},
  "budget": {"max_iterations"},
  "governance": {
    "automation_type", "schedule", "owner", "first_runs_require_human_review",
    "reviewed_runs", "auto_fix", "auto_merge", "report_only_on_no_findings",
    "alert_on",
  },
  "release_policy": {
    "target_branch", "merge_strategy", "verifier_required", "evidence_required",
    "scope_limit", "recovery_policy",
  },
}
QUALITY_GATE_MEMBERS = {"command", "evidence"}


def _canonical_authority_diagnostics(text: str) -> list[str]:
  seen: set[str] = set()
  duplicates: list[str] = []
  section = ""
  checkpoint = ""
  quality_item = -1
  nested_parent_indent: int | None = None

  def register(path: str) -> None:
    if path in seen and path not in duplicates:
      duplicates.append(path)
    seen.add(path)

  for raw_line in text.splitlines():
    line = _strip_yaml_comment(raw_line)
    if not line.strip():
      continue
    leading = line[:len(line) - len(line.lstrip())]
    if "\t" in leading:
      if section in CANONICAL_MAPPINGS or section in CANONICAL_LIST_SECTIONS or section == "quality_gates":
        duplicates.append(f"{section}.<malformed-indentation>")
      continue
    indent = len(line) - len(line.lstrip(" "))
    stripped = line.strip()
    item = stripped.startswith("- ")
    mapping = _mapping_key(stripped[2:].strip() if item else stripped)
    if section in CANONICAL_LIST_SECTIONS and indent > 0:
      if item and indent != 2:
        duplicates.append(f"{section}.<malformed-list-item>")
      continue
    if mapping is None:
      continue
    key, _ = mapping
    if indent == 0:
      section = key
      checkpoint = ""
      quality_item = -1
      nested_parent_indent = None
      if key in CANONICAL_TOP_LEVEL:
        register(key)
      continue
    if section == "quality_gates":
      if item and indent != 2:
        duplicates.append("quality_gates.<malformed-list-item>")
        continue
      if indent == 2 and item:
        quality_item += 1
        nested_parent_indent = None
      if quality_item < 0 or indent <= 0:
        continue
      if item:
        if key in QUALITY_GATE_MEMBERS:
          register(f"quality_gates[{quality_item}].{key}")
        elif key not in QUALITY_GATE_MEMBERS:
          nested_parent_indent = 4
        continue
      if indent == 4:
        nested_parent_indent = indent if key not in QUALITY_GATE_MEMBERS else None
        if key in QUALITY_GATE_MEMBERS:
          register(f"quality_gates[{quality_item}].{key}")
      elif nested_parent_indent is None and key in QUALITY_GATE_MEMBERS:
        duplicates.append(f"quality_gates[{quality_item}].<malformed-indentation>")
      continue
    if section in CANONICAL_MAPPINGS and indent > 0:
      members = CANONICAL_MEMBERS[section]
      if indent == 2:
        nested_parent_indent = indent if key not in members else None
        if key in members:
          register(f"{section}.{key}")
      elif nested_parent_indent is None and key in members:
        duplicates.append(f"{section}.<malformed-indentation>")
      continue
    if section == "checkpoints":
      if indent == 2 and not item:
        checkpoint = key if key in CHECKPOINT_DEFAULTS else ""
        if checkpoint:
          register(f"checkpoints.{checkpoint}")
        continue
      if indent == 4 and checkpoint and key in CHECKPOINT_DEFAULTS[checkpoint]:
        register(f"checkpoints.{checkpoint}.{key}")
  return duplicates


def parse_loop_yaml_checked(text: str) -> tuple[dict[str, Any], list[str]]:
  return parse_loop_yaml(text), _canonical_authority_diagnostics(text)


def _parse_governance_scalar(key: str, value: str) -> Any:
  parsed = _parse_scalar(value)
  if key in {"first_runs_require_human_review", "reviewed_runs"} and isinstance(parsed, str) and re.fullmatch(r"-?[0-9]+", parsed):
    return int(parsed)
  return parsed


def _parse_run_scalar(key: str, value: str) -> Any:
  parsed = _parse_scalar(value)
  if key in {"max_passes", "current_pass"} and isinstance(parsed, str) and re.fullmatch(r"-?[0-9]+", parsed):
    return int(parsed)
  return parsed


def _parse_inline_list(value: str) -> list[str]:
  value = value.strip()
  if not (value.startswith("[") and value.endswith("]")):
    return []
  inner = value[1:-1].strip()
  if not inner:
    return []
  return [item.strip().strip('"').strip("'") for item in inner.split(",")]


def parse_loop_yaml(text: str) -> dict[str, Any]:
  data: dict[str, Any] = {
    "agents": {},
    "stages": {},
    "tools": {"allowed": [], "denied": []},
    "permissions": {
      "filesystem": {"mutable_scope": [], "protected_scope": []},
      "network": {"mode": "off", "allowlist": []},
      "shell": {"allow": [], "deny_patterns": []},
    },
    "mutable_scope": [],
    "protected_scope": [],
    "quality_gates": [],
    "verifier": {},
    "budget": {},
    "stop_conditions": [],
    "handoff_conditions": [],
    "checkpoints": {name: dict(fields) for name, fields in CHECKPOINT_DEFAULTS.items()},
    "governance": {
      "automation_type": "",
      "schedule": "",
      "owner": "",
      "first_runs_require_human_review": 0,
      "reviewed_runs": 0,
      "auto_fix": False,
      "auto_merge": False,
      "report_only_on_no_findings": True,
      "alert_on": [],
    },
    "run": {
      "mode": "",
      "subtype": "",
      "plan_approved": False,
      "plan_hash": "",
      "state": "",
      "max_passes": 0,
      "current_pass": 0,
      "approval_source": "",
      "approved_at": "",
    },
    "release_policy": {
      "target_branch": "",
      "merge_strategy": "",
      "verifier_required": False,
      "evidence_required": False,
      "scope_limit": "",
      "recovery_policy": "",
    },
  }
  section = ""
  subsection = ""
  current_checkpoint = ""
  current_checkpoint_fields: set[str] = set()
  seen_checkpoints: set[str] = set()
  current_agent = ""
  current_list_item: dict[str, Any] | None = None
  list_target: list[Any] | None = None
  canonical_nested_parent_indent: int | None = None
  quality_nested_parent_indent: int | None = None

  for raw_line in text.splitlines():
    line = _strip_yaml_comment(raw_line)
    if not line.strip():
      continue
    indent = len(line) - len(line.lstrip(" "))
    stripped = line.strip()

    leading_whitespace = line[:len(line) - len(line.lstrip())]
    if section == "checkpoints" and "\t" in leading_whitespace:
      if current_checkpoint:
        data["checkpoints"][current_checkpoint] = dict(CHECKPOINT_DEFAULTS[current_checkpoint])
      current_checkpoint = ""
      current_checkpoint_fields = set()
      continue

    if indent == 0:
      section = ""
      subsection = ""
      current_checkpoint = ""
      current_checkpoint_fields = set()
      current_agent = ""
      current_list_item = None
      list_target = None
      canonical_nested_parent_indent = None
      quality_nested_parent_indent = None
      if stripped.endswith(":") and stripped[:-1] != "rollback_policy":
        section = stripped[:-1]
        if section in {"mutable_scope", "protected_scope", "stop_conditions", "handoff_conditions"}:
          list_target = data[section]
        continue
      mapping = _mapping_key(stripped)
      if mapping is not None:
        key, value = mapping
        if key in {"mutable_scope", "protected_scope", "stop_conditions", "handoff_conditions"}:
          parsed_list = _parse_inline_list(value)
          if parsed_list or value.strip() == "[]":
            data[key] = parsed_list
          elif value.strip():
            data[key] = [_parse_scalar(value)]
          continue
        parsed = _parse_scalar(value)
        data[key] = parsed
        if key == "current_stage":
          data["stage"] = parsed
      continue

    if section in {"mutable_scope", "protected_scope", "stop_conditions", "handoff_conditions"}:
      if indent == 2 and stripped.startswith("- "):
        data[section].append(stripped[2:].strip())
      continue

    if section == "quality_gates":
      if stripped.startswith("- "):
        if indent != 2:
          continue
        current_list_item = {}
        data["quality_gates"].append(current_list_item)
        quality_nested_parent_indent = None
        item = stripped[2:].strip()
        mapping = _mapping_key(item)
        if mapping is not None:
          key, value = mapping
          if key in QUALITY_GATE_MEMBERS:
            current_list_item[key] = _parse_scalar(value)
          elif value == "":
            quality_nested_parent_indent = 4
      elif current_list_item is not None:
        mapping = _mapping_key(stripped)
        if mapping is None:
          continue
        key, value = mapping
        if quality_nested_parent_indent is not None and indent > quality_nested_parent_indent:
          continue
        if indent == 4 and key in QUALITY_GATE_MEMBERS:
          quality_nested_parent_indent = None
          current_list_item[key] = _parse_scalar(value)
        elif indent == 4 and value == "":
          quality_nested_parent_indent = indent
      continue

    if section in {"verifier", "budget"}:
      mapping = _mapping_key(stripped)
      if mapping is not None:
        key, value = mapping
        if canonical_nested_parent_indent is not None and indent > canonical_nested_parent_indent:
          continue
        if indent == 2 and key in CANONICAL_MEMBERS[section]:
          canonical_nested_parent_indent = None
          data[section][key] = _parse_scalar(value)
        elif indent == 2 and value == "":
          canonical_nested_parent_indent = indent
      continue

    if section == "checkpoints":
      if indent == 2:
        if not stripped.endswith(":"):
          if current_checkpoint:
            data["checkpoints"][current_checkpoint] = dict(CHECKPOINT_DEFAULTS[current_checkpoint])
          current_checkpoint = ""
          current_checkpoint_fields = set()
          continue
        checkpoint = stripped[:-1]
        if checkpoint not in CHECKPOINT_DEFAULTS:
          current_checkpoint = ""
          current_checkpoint_fields = set()
        elif checkpoint in seen_checkpoints:
          data["checkpoints"][checkpoint] = dict(CHECKPOINT_DEFAULTS[checkpoint])
          current_checkpoint = ""
          current_checkpoint_fields = set()
        else:
          seen_checkpoints.add(checkpoint)
          current_checkpoint = checkpoint
          current_checkpoint_fields = set()
        continue
      if indent not in {2, 4}:
        if current_checkpoint:
          data["checkpoints"][current_checkpoint] = dict(CHECKPOINT_DEFAULTS[current_checkpoint])
        current_checkpoint = ""
        current_checkpoint_fields = set()
        continue
      if indent == 4 and current_checkpoint and ":" in stripped:
        key, value = stripped.split(":", 1)
        key = key.strip()
        if key in CHECKPOINT_DEFAULTS[current_checkpoint]:
          if key in current_checkpoint_fields:
            data["checkpoints"][current_checkpoint] = dict(CHECKPOINT_DEFAULTS[current_checkpoint])
            current_checkpoint = ""
            current_checkpoint_fields = set()
          else:
            current_checkpoint_fields.add(key)
            data["checkpoints"][current_checkpoint][key] = _parse_scalar(value)
      elif indent == 4 and current_checkpoint:
        data["checkpoints"][current_checkpoint] = dict(CHECKPOINT_DEFAULTS[current_checkpoint])
        current_checkpoint = ""
        current_checkpoint_fields = set()
      continue

    if section == "agents":
      if indent == 2 and stripped.endswith(":"):
        current_agent = stripped[:-1]
        data["agents"].setdefault(current_agent, {})
        list_target = None
        continue
      if current_agent and ":" in stripped:
        key, value = stripped.split(":", 1)
        key = key.strip()
        value = value.strip()
        data["agents"][current_agent][key] = _parse_inline_list(value) or _parse_scalar(value)
      continue

    if section == "stages":
      if indent == 2 and stripped.endswith(":"):
        current_agent = stripped[:-1]
        data["stages"].setdefault(current_agent, {})
        list_target = None
        continue
      if current_agent and ":" in stripped:
        key, value = stripped.split(":", 1)
        key = key.strip()
        value = value.strip()
        data["stages"][current_agent][key] = _parse_inline_list(value) or _parse_scalar(value)
      continue

    if section == "tools":
      if ":" in stripped:
        key, value = stripped.split(":", 1)
        key = key.strip()
        parsed = _parse_inline_list(value)
        data["tools"].setdefault(key, [])
        if parsed or value.strip() == "[]":
          data["tools"][key] = parsed
          list_target = None
        else:
          list_target = data["tools"][key]
      elif stripped.startswith("- ") and list_target is not None:
        list_target.append(stripped[2:].strip())
      continue

    if section in {"governance", "run", "release_policy"}:
      target = data[section]
      mapping = _mapping_key(stripped)
      if mapping is not None:
        key, value = mapping
        if section in CANONICAL_MAPPINGS:
          if canonical_nested_parent_indent is not None and indent > canonical_nested_parent_indent:
            continue
          if indent != 2 or key not in CANONICAL_MEMBERS[section]:
            canonical_nested_parent_indent = indent if indent == 2 and value == "" else canonical_nested_parent_indent
            list_target = None
            continue
          canonical_nested_parent_indent = None
        parsed = _parse_inline_list(value)
        if parsed or value.strip() == "[]":
          target[key] = parsed
          list_target = None
        elif value.strip():
          if section == "governance":
            target[key] = _parse_governance_scalar(key, value)
          elif section == "run":
            target[key] = _parse_run_scalar(key, value)
          else:
            target[key] = _parse_scalar(value)
          list_target = None
        else:
          target.setdefault(key, [])
          list_target = target[key]
      elif stripped.startswith("- ") and list_target is not None:
        list_target.append(stripped[2:].strip())
      continue

    if section == "permissions":
      if indent == 2 and stripped.endswith(":"):
        subsection = stripped[:-1]
        list_target = None
        continue
      target = data["permissions"].setdefault(subsection, {})
      if ":" in stripped:
        key, value = stripped.split(":", 1)
        key = key.strip()
        parsed = _parse_inline_list(value)
        if parsed or value.strip() == "[]":
          target[key] = parsed
          list_target = None
        elif value.strip():
          target[key] = _parse_scalar(value)
          list_target = None
        else:
          target.setdefault(key, [])
          list_target = target[key]
      elif stripped.startswith("- ") and list_target is not None:
        list_target.append(stripped[2:].strip())

  if isinstance(data["mutable_scope"], list) and data["mutable_scope"] and not data["permissions"]["filesystem"]["mutable_scope"]:
    data["permissions"]["filesystem"]["mutable_scope"] = list(data["mutable_scope"])
  if isinstance(data["protected_scope"], list) and data["protected_scope"] and not data["permissions"]["filesystem"]["protected_scope"]:
    data["permissions"]["filesystem"]["protected_scope"] = list(data["protected_scope"])
  if "current_stage" in data:
    data["stage"] = data["current_stage"]
  elif "stage" in data:
    data["current_stage"] = data["stage"]
  return data


def loop_policy(topic_value: str | None = None) -> dict[str, Any]:
  return parse_loop_yaml(read_loop_artifact(topic_value))


def _valid_topic_name(candidate: str) -> bool:
  return bool(TOPIC_RE.fullmatch(candidate))


def current_topic() -> str:
  current = artifact_root() / "current"
  loop_file = current / "loop.yaml"
  if not loop_file.is_file():
    return ""
  try:
    loop_text = loop_file.read_text(encoding="utf-8")
  except (OSError, UnicodeDecodeError):
    return ""
  policy = parse_loop_yaml(loop_text)
  if str(policy.get("status", "")).strip() != "active":
    return ""

  topic_name = str(policy.get("topic") or "").strip()
  if _valid_topic_name(topic_name) and (artifact_root() / topic_name / "loop.yaml").is_file():
    return topic_name

  try:
    root = artifact_root().resolve()
    resolved = current.resolve()
  except OSError:
    return ""
  if resolved.parent == root and _valid_topic_name(resolved.name) and (resolved / "loop.yaml").is_file():
    return resolved.name
  return ""


def stderr(message: str) -> None:
  print(message, file=sys.stderr)


def block_or_nudge(message: str) -> int:
  if is_enforcing():
    stderr(message)
    return BLOCK
  if is_advisory():
    stderr(message)
  return 0


def tool_name(event: dict[str, Any]) -> str:
  return str(event.get("tool_name") or event.get("tool") or event.get("name") or "")


def tool_input(event: dict[str, Any]) -> dict[str, Any]:
  value = event.get("tool_input") or event.get("input") or event.get("parameters") or {}
  if isinstance(value, dict):
    return value
  if isinstance(value, str):
    return {"_raw": value}
  return {}


def tool_class(event: dict[str, Any]) -> str:
  name = tool_name(event)
  if name in {"Bash", "shell", "exec_command"}:
    return "shell"
  if name in {"apply_patch", "ApplyPatch"}:
    return "apply_patch"
  if name in {"Edit", "Write", "MultiEdit"}:
    return "edit"
  if name in {"Read", "open", "view_image"}:
    return "read"
  if name in {"Grep", "Glob", "find", "search"}:
    return "search"
  return name.lower()


def is_edit_event(event: dict[str, Any]) -> bool:
  return tool_class(event) in {"apply_patch", "edit"}


def extract_paths(event: dict[str, Any]) -> list[str]:
  inp = tool_input(event)
  paths: list[str] = []
  for key in ("file_path", "path"):
    value = inp.get(key)
    if isinstance(value, str) and value.strip():
      paths.append(value.strip())
  patch = inp.get("patch") or inp.get("_raw") or event.get("patch") or ""
  if isinstance(patch, str):
    for line in patch.splitlines():
      match = re.match(r"\*\*\* (?:Add|Update|Delete) File: (.+)$", line)
      if match:
        paths.append(match.group(1).strip())
      match = re.match(r"\*\*\* Move to: (.+)$", line)
      if match:
        paths.append(match.group(1).strip())
  return list(dict.fromkeys(paths))


def normalize_path(path: str) -> str:
  clean = path.replace("\\", "/")
  normalized = posixpath.normpath(clean)
  if normalized == ".":
    normalized = ""
  if clean.startswith("/"):
    cwd = posixpath.normpath(Path.cwd().as_posix())
    if normalized == cwd:
      return ""
    if normalized.startswith(f"{cwd}/"):
      return normalized[len(cwd) + 1:]
  return normalized


def matches_any(path: str, patterns: list[str]) -> bool:
  clean = normalize_path(path)
  return any(fnmatch.fnmatch(clean, pattern) for pattern in patterns)


def is_loen_topic_path(path: str, topic_name: str) -> bool:
  clean = normalize_path(path)
  root = normalize_path(str(artifact_root() / topic_name))
  return clean.startswith(f"docs/loen/{topic_name}/") or clean.startswith(f"{root}/")


def topic_from_path(path: str) -> str:
  clean = normalize_path(path)
  roots = ["docs/loen", normalize_path(str(artifact_root()))]
  for root in dict.fromkeys(roots):
    if not root or not clean.startswith(f"{root}/"):
      continue
    rest = clean[len(root) + 1:]
    candidate = rest.split("/", 1)[0]
    if _valid_topic_name(candidate):
      return candidate
  return ""


def event_topic(event: dict[str, Any]) -> str:
  explicit = topic()
  if explicit:
    return explicit
  for path in extract_paths(event):
    found = topic_from_path(path)
    if found:
      return found
  current = current_topic()
  if current:
    return current
  return ""


def should_run_hook(event: dict[str, Any]) -> bool:
  return not is_off() and bool(event_topic(event))


def shell_command(event: dict[str, Any]) -> str:
  value = tool_input(event).get("command") or tool_input(event).get("_raw") or event.get("command") or ""
  return value if isinstance(value, str) else ""


def command_matches(command: str, pattern: str) -> bool:
  return command == pattern or fnmatch.fnmatch(command, pattern)


def html_page(topic_name: str, policy: dict[str, Any]) -> str:
  stage = html.escape(str(policy.get("stage", "")))
  status = html.escape(str(policy.get("status", "")))
  safe_topic = html.escape(topic_name)
  return "\n".join([
    "<!doctype html>",
    "<html>",
    "<head><meta charset=\"utf-8\"><title>LoEn Audit</title></head>",
    "<body>",
    f"<h1>LoEn Audit: {safe_topic}</h1>",
    f"<p>Status: {status}</p>",
    f"<p>Stage: {stage}</p>",
    "</body>",
    "</html>",
    "",
  ])

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
  "release_policy", "checkpoints", "agents", "stages", "tools", "permissions",
  "execution",
}
CANONICAL_TOP_SCALARS = {"topic", "mode", "status", "objective", "current_stage", "stage"}
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
AGENT_MEMBERS = {"tools", "sandbox", "must_not_edit", "experiment_scope_required"}
STAGE_MEMBERS = {"roles"}
TOOL_MEMBERS = {"allowed", "denied"}
PERMISSION_MEMBERS = {
  "filesystem": {"mutable_scope", "protected_scope"},
  "network": {"mode", "allowlist"},
  "shell": {"allow", "deny_patterns"},
}
EXECUTION_MEMBERS = {"isolation", "executor", "network", "mounts"}
EXECUTION_MOUNT_MEMBERS = {"path", "mode"}
RUN_MEMBERS = {"mode", "subtype", "plan_approved", "plan_hash", "state", "max_passes", "current_pass", "approval_source", "approved_at"}
RUNTIME_AUTHORITY_SECTIONS = CANONICAL_TOP_LEVEL | CANONICAL_TOP_SCALARS | {"run"}


def _authority_depth_allowed(section: str, indent: int, item: bool) -> bool:
  if section in CANONICAL_LIST_SECTIONS:
    return indent == 2
  if section in {"agents", "stages", "permissions"}:
    return indent == 6 if item else indent in {2, 4}
  if section == "tools":
    return indent == 4 if item else indent == 2
  if section == "execution":
    return indent == 4 if item else indent in {2, 6}
  if section == "quality_gates":
    return indent == 2 if item else indent == 4
  if section == "governance":
    return indent == 4 if item else indent == 2
  if section in CANONICAL_MAPPINGS or section == "run":
    return not item and indent == 2
  if section == "checkpoints":
    return not item and indent in {2, 4}
  return False


def _canonical_authority_diagnostics(text: str) -> list[str]:
  seen: set[str] = set()
  duplicates: list[str] = []
  section = ""
  checkpoint = ""
  quality_item = -1
  nested_parent_indent: int | None = None
  permission_subsection = ""
  permission_list = ""
  runtime_name = ""
  runtime_list = ""
  tool_list = ""
  governance_list = ""
  ignored_parent_indent: int | None = None
  canonical_list_active = False
  execution_mount = -1

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
      diagnostic = f"{section}.<malformed-indentation>" if section else "<malformed-indentation>"
      if diagnostic not in duplicates:
        duplicates.append(diagnostic)
      runtime_list = ""
      tool_list = ""
      governance_list = ""
      permission_list = ""
      ignored_parent_indent = None
      canonical_list_active = False
      execution_mount = -1
      quality_item = -1
      continue
    indent = len(line) - len(line.lstrip(" "))
    stripped = line.strip()
    item = stripped.startswith("- ")
    mapping = _mapping_key(stripped[2:].strip() if item else stripped)
    ignored_indent = ignored_parent_indent if ignored_parent_indent is not None else nested_parent_indent
    if ignored_indent is not None and indent > ignored_indent and not item:
      continue
    if ignored_indent is not None and indent <= ignored_indent:
      ignored_parent_indent = None
      nested_parent_indent = None
    if indent > 0 and section in RUNTIME_AUTHORITY_SECTIONS and not _authority_depth_allowed(section, indent, item):
      duplicates.append(f"{section}.<malformed-indentation>")
      runtime_list = ""
      tool_list = ""
      governance_list = ""
      permission_list = ""
      ignored_parent_indent = None
      canonical_list_active = False
      execution_mount = -1
      quality_item = -1
      nested_parent_indent = None
      continue
    if section in CANONICAL_LIST_SECTIONS and indent > 0:
      if item and (indent != 2 or not canonical_list_active):
        duplicates.append(f"{section}.<malformed-list-item>")
      elif not item:
        if mapping is None:
          duplicates.append(f"{section}.<malformed-structure>")
        canonical_list_active = False
      continue
    if section == "tools" and item:
      if ignored_parent_indent is not None and indent == ignored_parent_indent + 2:
        continue
      if indent != 4 or not tool_list:
        duplicates.append("tools.<malformed-list-item>")
      continue
    if section == "permissions" and indent > 0:
      if item:
        if ignored_parent_indent is not None and indent == ignored_parent_indent + 2:
          continue
        if not permission_list or indent != 6:
          duplicates.append(f"permissions.{permission_subsection}.{permission_list}.<malformed-list-item>")
        continue
      if mapping is None:
        duplicates.append("permissions.<malformed-structure>")
        permission_list = ""
        ignored_parent_indent = None
        continue
      key, value = mapping
      if indent == 2:
        permission_subsection = key if key in PERMISSION_MEMBERS and value == "" else ""
        permission_list = ""
        ignored_parent_indent = None
        if permission_subsection:
          register(f"permissions.{permission_subsection}")
      elif indent == 4 and permission_subsection:
        if key in PERMISSION_MEMBERS[permission_subsection]:
          register(f"permissions.{permission_subsection}.{key}")
        permission_list = key if key in PERMISSION_MEMBERS[permission_subsection] and key != "mode" and value == "" else ""
        ignored_parent_indent = indent if key not in PERMISSION_MEMBERS[permission_subsection] and value == "" else None
      elif key in PERMISSION_MEMBERS.get(permission_subsection, set()):
        duplicates.append(f"permissions.{permission_subsection}.<malformed-indentation>")
      continue
    if section in {"agents", "stages"} and item:
      if ignored_parent_indent is not None and indent == ignored_parent_indent + 2:
        continue
      if indent != 6 or not runtime_list:
        duplicates.append(f"{section}.<malformed-list-item>")
      continue
    if section == "governance" and item:
      if ignored_parent_indent is not None and indent == ignored_parent_indent + 2:
        continue
      if indent != 4 or governance_list != "alert_on":
        duplicates.append("governance.<malformed-list-item>")
      continue
    if mapping is None:
      if indent > 0 and section in RUNTIME_AUTHORITY_SECTIONS:
        duplicates.append(f"{section}.<malformed-structure>")
        runtime_list = ""
        tool_list = ""
        governance_list = ""
        execution_mount = -1
        quality_item = -1
        ignored_parent_indent = None
        canonical_list_active = False
      continue
    key, value = mapping
    if indent == 0:
      section = key
      checkpoint = ""
      quality_item = -1
      nested_parent_indent = None
      runtime_name = ""
      runtime_list = ""
      tool_list = ""
      governance_list = ""
      ignored_parent_indent = None
      execution_mount = -1
      if key in CANONICAL_TOP_LEVEL:
        register(key)
        canonical_list_active = key in CANONICAL_LIST_SECTIONS
      if key in CANONICAL_TOP_SCALARS:
        register(key)
      continue
    if section in {"agents", "stages"}:
      members = AGENT_MEMBERS if section == "agents" else STAGE_MEMBERS
      if indent == 2 and not item and mapping is not None:
        runtime_name = key if mapping[1] == "" else ""
        runtime_list = ""
        ignored_parent_indent = None
        if runtime_name:
          register(f"{section}.{runtime_name}")
      elif indent == 4 and runtime_name and key in members:
        register(f"{section}.{runtime_name}.{key}")
        runtime_list = key if value == "" and key in ({"tools"} if section == "agents" else {"roles"}) else ""
        ignored_parent_indent = None
      elif runtime_name and key in members:
        duplicates.append(f"{section}.{runtime_name}.<malformed-indentation>")
        runtime_list = ""
      elif indent == 4:
        runtime_list = ""
        ignored_parent_indent = indent if value == "" else None
      continue
    if section == "tools":
      if indent == 2 and key in TOOL_MEMBERS:
        register(f"tools.{key}")
        tool_list = key if value == "" else ""
        ignored_parent_indent = None
      elif key in TOOL_MEMBERS:
        duplicates.append("tools.<malformed-indentation>")
        tool_list = ""
      elif indent == 2:
        tool_list = ""
        ignored_parent_indent = indent if value == "" else None
      continue
    if section == "execution":
      if item:
        if indent != 4:
          duplicates.append("execution.mounts.<malformed-list-item>")
          continue
        execution_mount += 1
        if key in EXECUTION_MOUNT_MEMBERS:
          register(f"execution.mounts[{execution_mount}].{key}")
        continue
      if indent == 2 and key in EXECUTION_MEMBERS:
        register(f"execution.{key}")
        ignored_parent_indent = None
      elif indent == 6 and execution_mount >= 0 and key in EXECUTION_MOUNT_MEMBERS:
        register(f"execution.mounts[{execution_mount}].{key}")
        ignored_parent_indent = None
      elif execution_mount >= 0 and key in EXECUTION_MOUNT_MEMBERS:
        duplicates.append(f"execution.mounts[{execution_mount}].<malformed-indentation>")
      elif key in EXECUTION_MEMBERS:
        duplicates.append("execution.<malformed-indentation>")
      elif indent in {2, 6}:
        ignored_parent_indent = indent if value == "" else None
      continue
    if section == "run":
      if indent == 2 and key in RUN_MEMBERS:
        register(f"run.{key}")
        ignored_parent_indent = None
      elif indent == 2:
        ignored_parent_indent = indent if value == "" else None
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
          if section == "governance":
            governance_list = key if key == "alert_on" and value == "" else ""
            ignored_parent_indent = None
        elif section == "governance":
          governance_list = ""
          ignored_parent_indent = indent if value == "" else None
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
    "execution": {"isolation": "", "executor": "", "network": "off", "mounts": []},
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
      "alert_on": [
        "protected_scope_attempt",
        "verifier_failure",
        "budget_exhausted",
        "metric_regression",
      ],
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
  current_mount: dict[str, Any] | None = None
  ignored_runtime_parent_indent: int | None = None

  for raw_line in text.splitlines():
    line = _strip_yaml_comment(raw_line)
    if not line.strip():
      continue
    indent = len(line) - len(line.lstrip(" "))
    stripped = line.strip()

    leading_whitespace = line[:len(line) - len(line.lstrip())]
    if "\t" in leading_whitespace:
      if section == "checkpoints":
        if current_checkpoint:
          data["checkpoints"][current_checkpoint] = dict(CHECKPOINT_DEFAULTS[current_checkpoint])
        current_checkpoint = ""
        current_checkpoint_fields = set()
      list_target = None
      current_list_item = None
      current_mount = None
      canonical_nested_parent_indent = None
      quality_nested_parent_indent = None
      ignored_runtime_parent_indent = None
      continue

    ignored_indent = ignored_runtime_parent_indent
    if section == "quality_gates" and quality_nested_parent_indent is not None:
      ignored_indent = quality_nested_parent_indent
    elif section in CANONICAL_MAPPINGS | {"run"} and canonical_nested_parent_indent is not None:
      ignored_indent = canonical_nested_parent_indent
    if ignored_indent is not None and indent > ignored_indent and not stripped.startswith("- "):
      continue
    if ignored_indent is not None and indent <= ignored_indent:
      ignored_runtime_parent_indent = None
      if section == "quality_gates":
        quality_nested_parent_indent = None
      elif section in CANONICAL_MAPPINGS | {"run"}:
        canonical_nested_parent_indent = None

    item = stripped.startswith("- ")
    if indent > 0 and section in RUNTIME_AUTHORITY_SECTIONS and not _authority_depth_allowed(section, indent, item):
      if section == "checkpoints" and current_checkpoint:
        data["checkpoints"][current_checkpoint] = dict(CHECKPOINT_DEFAULTS[current_checkpoint])
        current_checkpoint = ""
        current_checkpoint_fields = set()
      list_target = None
      current_list_item = None
      current_mount = None
      current_agent = ""
      subsection = ""
      canonical_nested_parent_indent = None
      quality_nested_parent_indent = None
      ignored_runtime_parent_indent = None
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
      current_mount = None
      ignored_runtime_parent_indent = None
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
      if indent == 2 and stripped.startswith("- ") and list_target is not None:
        list_target.append(stripped[2:].strip())
      elif not stripped.startswith("- "):
        list_target = None
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
          current_list_item = None
          quality_nested_parent_indent = None
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
      else:
        canonical_nested_parent_indent = None
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
      mapping = _mapping_key(stripped)
      if indent == 2 and mapping is not None and mapping[1] == "":
        current_agent = mapping[0]
        data["agents"].setdefault(current_agent, {})
        list_target = None
        continue
      if indent == 4 and current_agent and mapping is not None and mapping[0] in AGENT_MEMBERS:
        key, value = mapping
        parsed = _parse_inline_list(value)
        if parsed or value.strip() == "[]":
          data["agents"][current_agent][key] = parsed
          list_target = None
        elif value.strip():
          data["agents"][current_agent][key] = _parse_scalar(value)
          list_target = None
        else:
          data["agents"][current_agent][key] = []
          list_target = data["agents"][current_agent][key]
      elif indent == 4 and mapping is not None:
        list_target = None
        ignored_runtime_parent_indent = indent if mapping[1] == "" else None
      elif indent == 6 and stripped.startswith("- ") and list_target is not None:
        list_target.append(stripped[2:].strip())
      elif mapping is None and not stripped.startswith("- "):
        list_target = None
      continue

    if section == "stages":
      mapping = _mapping_key(stripped)
      if indent == 2 and mapping is not None and mapping[1] == "":
        current_agent = mapping[0]
        data["stages"].setdefault(current_agent, {})
        list_target = None
        continue
      if indent == 4 and current_agent and mapping is not None and mapping[0] in STAGE_MEMBERS:
        key, value = mapping
        parsed = _parse_inline_list(value)
        if parsed or value.strip() == "[]":
          data["stages"][current_agent][key] = parsed
          list_target = None
        elif value.strip():
          data["stages"][current_agent][key] = _parse_scalar(value)
          list_target = None
        else:
          data["stages"][current_agent][key] = []
          list_target = data["stages"][current_agent][key]
      elif indent == 4 and mapping is not None:
        list_target = None
        ignored_runtime_parent_indent = indent if mapping[1] == "" else None
      elif indent == 6 and stripped.startswith("- ") and list_target is not None:
        list_target.append(stripped[2:].strip())
      elif mapping is None and not stripped.startswith("- "):
        list_target = None
      continue

    if section == "tools":
      mapping = _mapping_key(stripped)
      if indent == 2 and mapping is not None and mapping[0] in TOOL_MEMBERS:
        key, value = mapping
        parsed = _parse_inline_list(value)
        if parsed or value.strip() == "[]":
          data["tools"][key] = parsed
          list_target = None
        else:
          data["tools"][key] = []
          list_target = data["tools"][key]
      elif indent == 2 and mapping is not None:
        list_target = None
        ignored_runtime_parent_indent = indent if mapping[1] == "" else None
      elif indent == 4 and stripped.startswith("- ") and list_target is not None:
        list_target.append(stripped[2:].strip())
      elif mapping is None and not stripped.startswith("- "):
        list_target = None
      continue

    if section == "execution":
      mapping = _mapping_key(stripped[2:].strip() if stripped.startswith("- ") else stripped)
      if indent == 2 and mapping is not None and mapping[0] in {"isolation", "executor", "network"}:
        data["execution"][mapping[0]] = _parse_scalar(mapping[1])
        current_mount = None
      elif indent == 2 and mapping == ("mounts", ""):
        current_mount = None
      elif indent == 4 and stripped.startswith("- "):
        current_mount = {}
        data["execution"]["mounts"].append(current_mount)
        if mapping is not None and mapping[0] in EXECUTION_MOUNT_MEMBERS:
          current_mount[mapping[0]] = _parse_scalar(mapping[1])
      elif indent == 6 and current_mount is not None and mapping is not None and mapping[0] in EXECUTION_MOUNT_MEMBERS:
        current_mount[mapping[0]] = _parse_scalar(mapping[1])
      elif mapping is not None and indent in {2, 6}:
        ignored_runtime_parent_indent = indent if mapping[1] == "" else None
      elif mapping is None:
        current_mount = None
      continue

    if section in {"governance", "run", "release_policy"}:
      target = data[section]
      mapping = _mapping_key(stripped)
      if mapping is not None:
        key, value = mapping
        if section == "run" and (indent != 2 or key not in RUN_MEMBERS):
          canonical_nested_parent_indent = indent if indent == 2 and value == "" else canonical_nested_parent_indent
          list_target = None
          continue
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
          target[key] = []
          list_target = target[key]
      elif indent == 4 and stripped.startswith("- ") and list_target is not None:
        list_target.append(stripped[2:].strip())
      elif mapping is None and not stripped.startswith("- "):
        list_target = None
      continue

    if section == "permissions":
      mapping = _mapping_key(stripped)
      if indent == 2 and mapping is not None and mapping[0] in PERMISSION_MEMBERS and mapping[1] == "":
        subsection = mapping[0]
        list_target = None
        continue
      target = data["permissions"].get(subsection)
      if isinstance(target, dict) and mapping is not None and indent == 4 and mapping[0] in PERMISSION_MEMBERS[subsection]:
        key, value = mapping
        parsed = _parse_inline_list(value)
        if parsed or value.strip() == "[]":
          target[key] = parsed
          list_target = None
        elif value.strip():
          target[key] = _parse_scalar(value)
          list_target = None
        else:
          target[key] = []
          list_target = target[key]
      elif indent == 4 and mapping is not None:
        list_target = None
        ignored_runtime_parent_indent = indent if mapping[1] == "" else None
      elif indent == 6 and stripped.startswith("- ") and list_target is not None:
        list_target.append(stripped[2:].strip())
      elif mapping is None and not stripped.startswith("- "):
        list_target = None

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


def checked_loop_policy(topic_value: str | None = None) -> tuple[dict[str, Any], list[str]]:
  return parse_loop_yaml_checked(read_loop_artifact(topic_value))


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
  policy, diagnostics = parse_loop_yaml_checked(loop_text)
  if diagnostics:
    return ""
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

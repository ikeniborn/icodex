#!/usr/bin/env python3
"""Shared deterministic helpers for LoEn hook assets."""
from __future__ import annotations

import fnmatch
import html
import json
import os
from pathlib import Path
import re
import sys
from typing import Any


BLOCK = 2


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
  value = value.strip().strip('"').strip("'")
  if value.lower() == "true":
    return True
  if value.lower() == "false":
    return False
  return value


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
    "tools": {"allowed": [], "denied": []},
    "permissions": {
      "filesystem": {"mutable_scope": [], "protected_scope": []},
      "network": {"mode": "off", "allowlist": []},
      "shell": {"allow": [], "deny_patterns": []},
    },
  }
  section = ""
  subsection = ""
  current_agent = ""
  list_target: list[str] | None = None

  for raw_line in text.splitlines():
    line = raw_line.split("#", 1)[0].rstrip()
    if not line.strip():
      continue
    indent = len(line) - len(line.lstrip(" "))
    stripped = line.strip()

    if indent == 0:
      section = ""
      subsection = ""
      current_agent = ""
      list_target = None
      if stripped in {"agents:", "tools:", "permissions:"}:
        section = stripped[:-1]
        continue
      if ":" in stripped:
        key, value = stripped.split(":", 1)
        data[key.strip()] = _parse_scalar(value)
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

  return data


def loop_policy() -> dict[str, Any]:
  return parse_loop_yaml(read_loop_artifact())


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
  return value if isinstance(value, dict) else {}


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
  patch = inp.get("patch") or event.get("patch") or ""
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
  return path.replace("\\", "/").lstrip("./")


def matches_any(path: str, patterns: list[str]) -> bool:
  clean = normalize_path(path)
  return any(fnmatch.fnmatch(clean, pattern) for pattern in patterns)


def is_loen_topic_path(path: str, topic_name: str) -> bool:
  clean = normalize_path(path)
  root = normalize_path(str(artifact_root() / topic_name))
  return clean.startswith(f"docs/loen/{topic_name}/") or clean.startswith(f"{root}/")


def shell_command(event: dict[str, Any]) -> str:
  value = tool_input(event).get("command") or event.get("command") or ""
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

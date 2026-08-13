#!/usr/bin/env python3
"""LoEn shell and network permission guard; reads LOEN_ARTIFACT_ROOT through loen_common."""
from __future__ import annotations

import shlex
from urllib.parse import urlparse

from loen_common import block_or_nudge, checked_loop_policy, command_matches, event_topic, is_advisory, is_off, is_strict, read_event, read_loop_artifact, should_run_hook, shell_command, tool_class

SCRIPT_NAME = "permission-guard"
NETWORK_TOOLS = {"curl", "wget", "ssh", "scp", "nc"}


def _command_parts(command: str) -> list[str]:
  try:
    return shlex.split(command)
  except ValueError:
    return command.split()


def _token_basename(token: str) -> str:
  return token.rsplit("/", 1)[-1]


def _network_command_index(parts: list[str]) -> int | None:
  for index, part in enumerate(parts):
    for word in part.split():
      if _token_basename(word) in NETWORK_TOOLS:
        return index
  return None


def _network_target(command: str) -> str:
  parts = _command_parts(command)
  command_index = _network_command_index(parts)
  start = command_index + 1 if command_index is not None else 1
  for part in parts[start:]:
    if part.startswith("-"):
      continue
    parsed = urlparse(part)
    if parsed.hostname:
      return parsed.hostname
    if "." in part and "/" not in part:
      return part.split(":", 1)[0]
  return ""


def main() -> int:
  if is_off():
    return 0
  event = read_event()
  if not should_run_hook(event):
    return 0
  topic_name = event_topic(event)
  read_loop_artifact(topic_name)
  if not (is_advisory() or is_strict()):
    return 0
  if tool_class(event) != "shell":
    return 0

  command = shell_command(event)
  parsed, diagnostics = checked_loop_policy(topic_name)
  if diagnostics:
    return block_or_nudge("LoEn: invalid canonical authority")
  policy = parsed.get("permissions", {})
  shell_policy = policy.get("shell", {})
  for pattern in shell_policy.get("deny_patterns", []):
    if command_matches(command, pattern) or command.startswith(pattern + " "):
      return block_or_nudge(f"LoEn: shell command denied by policy: {pattern}")
  if "git reset --hard" in command:
    return block_or_nudge("LoEn: destructive git command denied")
  network_mode = policy.get("network", {}).get("mode", "off")
  parts = _command_parts(command)
  is_network = _network_command_index(parts) is not None
  if is_network and network_mode == "off":
    return block_or_nudge("LoEn: network command denied by policy")
  allowlist = policy.get("network", {}).get("allowlist", [])
  if is_network and network_mode == "allowlist":
    target = _network_target(command)
    if not target or target not in allowlist:
      return block_or_nudge("LoEn: network target denied by allowlist")
  allow = shell_policy.get("allow", [])
  if allow and not any(command_matches(command, pattern) for pattern in allow):
    return block_or_nudge("LoEn: shell command not in allowlist")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())

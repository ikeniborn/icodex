#!/usr/bin/env python3
"""LoEn shell and network permission guard; reads LOEN_ARTIFACT_ROOT through loen_common."""
from urllib.parse import urlparse

from loen_common import block_or_nudge, command_matches, is_advisory, is_off, is_strict, loop_policy, read_event, read_loop_artifact, shell_command, tool_class

SCRIPT_NAME = "permission-guard"
NETWORK_TOOLS = ("curl ", "wget ", "ssh ", "scp ", "nc ")


def _network_target(command: str) -> str:
  parts = command.split()
  for part in parts[1:]:
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
  read_loop_artifact()
  if not (is_advisory() or is_strict()):
    return 0
  if tool_class(event) != "shell":
    return 0

  command = shell_command(event)
  policy = loop_policy().get("permissions", {})
  shell_policy = policy.get("shell", {})
  for pattern in shell_policy.get("deny_patterns", []):
    if command_matches(command, pattern) or command.startswith(pattern + " "):
      return block_or_nudge(f"LoEn: shell command denied by policy: {pattern}")
  if "git reset --hard" in command:
    return block_or_nudge("LoEn: destructive git command denied")
  network_mode = policy.get("network", {}).get("mode", "off")
  is_network = any(token in command for token in NETWORK_TOOLS)
  if is_network and network_mode == "off":
    return block_or_nudge("LoEn: network command denied by policy")
  allowlist = policy.get("network", {}).get("allowlist", [])
  if is_network and allowlist:
    target = _network_target(command)
    if target not in allowlist:
      return block_or_nudge("LoEn: network target denied by allowlist")
  allow = shell_policy.get("allow", [])
  if allow and not any(command_matches(command, pattern) for pattern in allow):
    return block_or_nudge("LoEn: shell command not in allowlist")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())

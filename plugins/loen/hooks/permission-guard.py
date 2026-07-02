#!/usr/bin/env python3
"""LoEn shell and network permission guard; reads LOEN_ARTIFACT_ROOT through loen_common."""
from loen_common import BLOCK, command_matches, is_strict, loop_policy, read_event, read_loop_artifact, shell_command, stderr, tool_class

SCRIPT_NAME = "permission-guard"


def main() -> int:
  event = read_event()
  read_loop_artifact()
  if not is_strict() or tool_class(event) != "shell":
    return 0

  command = shell_command(event)
  policy = loop_policy().get("permissions", {})
  shell_policy = policy.get("shell", {})
  for pattern in shell_policy.get("deny_patterns", []):
    if command_matches(command, pattern):
      stderr(f"LoEn: shell command denied by policy: {pattern}")
      return BLOCK
  if "git reset --hard" in command:
    stderr("LoEn: destructive git command denied")
    return BLOCK
  network_mode = policy.get("network", {}).get("mode", "off")
  if network_mode == "off" and any(token in command for token in ("curl ", "wget ", "ssh ", "scp ", "nc ")):
    stderr("LoEn: network command denied by policy")
    return BLOCK
  allow = shell_policy.get("allow", [])
  if allow and not any(command_matches(command, pattern) for pattern in allow):
    stderr("LoEn: shell command not in allowlist")
    return BLOCK
  return 0


if __name__ == "__main__":
  raise SystemExit(main())

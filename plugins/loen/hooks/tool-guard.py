#!/usr/bin/env python3
"""LoEn tool/role guard; reads LOEN_ARTIFACT_ROOT through loen_common."""
from loen_common import block_or_nudge, is_advisory, is_off, is_strict, loop_policy, read_event, read_loop_artifact, tool_class

SCRIPT_NAME = "tool-guard"


def _policy_tool(tool: str) -> str:
  return "edit" if tool in {"edit", "apply_patch"} else tool


def main() -> int:
  if is_off():
    return 0
  event = read_event()
  read_loop_artifact()
  if not (is_advisory() or is_strict()):
    return 0

  policy = loop_policy()
  tool = tool_class(event)
  policy_tool = _policy_tool(tool)
  role = str(event.get("agent_role") or event.get("role") or "").strip()
  root_allowed = policy.get("tools", {}).get("allowed", [])
  if policy_tool == "edit":
    allowed_by_root = "apply_patch" in root_allowed or "edit" in root_allowed
  else:
    allowed_by_root = policy_tool in root_allowed
  if root_allowed and not allowed_by_root:
    return block_or_nudge(f"LoEn: tool class not allowed by loop policy: {tool}")

  agent = policy.get("agents", {}).get(role, {}) if role else {}
  agent_tools = agent.get("tools", [])
  if agent.get("must_not_edit") is True and policy_tool == "edit":
    return block_or_nudge(f"LoEn: {role} must not edit in strict mode")
  if agent_tools and policy_tool not in agent_tools:
    return block_or_nudge(f"LoEn: role {role} cannot use tool class {tool}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())

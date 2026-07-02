#!/usr/bin/env python3
"""LoEn tool/role guard; reads LOEN_ARTIFACT_ROOT through loen_common."""
from loen_common import BLOCK, is_strict, loop_policy, read_event, read_loop_artifact, stderr, tool_class

SCRIPT_NAME = "tool-guard"


def main() -> int:
  event = read_event()
  read_loop_artifact()
  if not is_strict():
    return 0

  policy = loop_policy()
  tool = tool_class(event)
  role = str(event.get("agent_role") or event.get("role") or "").strip()
  root_allowed = policy.get("tools", {}).get("allowed", [])
  if tool == "edit":
    allowed_by_root = "apply_patch" in root_allowed or "edit" in root_allowed
  else:
    allowed_by_root = tool in root_allowed
  if root_allowed and not allowed_by_root:
    stderr(f"LoEn: tool class not allowed by loop policy: {tool}")
    return BLOCK

  agent = policy.get("agents", {}).get(role, {}) if role else {}
  agent_tools = agent.get("tools", [])
  if agent.get("must_not_edit") is True and tool in {"edit", "apply_patch"}:
    stderr(f"LoEn: {role} must not edit in strict mode")
    return BLOCK
  if agent_tools and tool not in agent_tools:
    stderr(f"LoEn: role {role} cannot use tool class {tool}")
    return BLOCK
  return 0


if __name__ == "__main__":
  raise SystemExit(main())

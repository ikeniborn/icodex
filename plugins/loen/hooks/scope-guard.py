#!/usr/bin/env python3
"""LoEn mutable/protected path scope guard; reads LOEN_ARTIFACT_ROOT through loen_common."""
from loen_common import BLOCK, extract_paths, is_enforcing, is_loen_topic_path, loop_policy, matches_any, read_event, read_loop_artifact, stderr, topic

SCRIPT_NAME = "scope-guard"


def main() -> int:
  event_paths = extract_paths(read_event())
  read_loop_artifact()
  if not is_enforcing() or not event_paths:
    return 0
  policy = loop_policy()
  fs_policy = policy.get("permissions", {}).get("filesystem", {})
  mutable = fs_policy.get("mutable_scope", [])
  protected = fs_policy.get("protected_scope", [])
  topic_name = topic()

  for path in event_paths:
    if topic_name and is_loen_topic_path(path, topic_name):
      continue
    if matches_any(path, protected):
      stderr(f"LoEn: protected path blocked: {path}")
      return BLOCK
    if mutable and not matches_any(path, mutable):
      stderr(f"LoEn: path outside mutable scope: {path}")
      return BLOCK
  return 0


if __name__ == "__main__":
  raise SystemExit(main())

#!/usr/bin/env python3
"""LoEn mutable/protected path scope guard; reads LOEN_ARTIFACT_ROOT through loen_common."""
from loen_common import block_or_nudge, extract_paths, is_off, is_loen_topic_path, loop_policy, matches_any, read_event, read_loop_artifact, topic

SCRIPT_NAME = "scope-guard"


def main() -> int:
  if is_off():
    return 0
  event_paths = extract_paths(read_event())
  read_loop_artifact()
  if not event_paths:
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
      return block_or_nudge(f"LoEn: protected path blocked: {path}")
    if mutable and not matches_any(path, mutable):
      return block_or_nudge(f"LoEn: path outside mutable scope: {path}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())

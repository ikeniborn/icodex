#!/usr/bin/env python3
"""LoEn loop-state gate; reads LOEN_ARTIFACT_ROOT through loen_common."""
from loen_common import BLOCK, extract_paths, is_edit_event, is_enforcing, read_event, read_loop_artifact, stderr, topic, topic_dir

SCRIPT_NAME = "loop-gate"


def _artifact_number(path: str) -> int | None:
  name = path.rsplit("/", 1)[-1]
  if len(name) < 3 or name[1] != "_":
    return None
  return int(name[0]) if name[0].isdigit() else None


def _missing_prior_artifact(number: int) -> str:
  names = {
    1: "1_goal.md",
    2: "2_context.md",
    3: "3_plan.md",
    4: "4_act.md",
    5: "5_check.md",
    6: "6_reflect.md",
    7: "7_result.md",
  }
  base = topic_dir()
  for index in range(1, number):
    filename = names[index]
    if not (base / filename).is_file():
      return filename
  return ""


def main() -> int:
  event = read_event()
  loop_text = read_loop_artifact()
  if is_enforcing() and is_edit_event(event) and not loop_text:
    stderr("LoEn: code edits require an active loop in enforce/strict mode")
    return BLOCK

  if is_enforcing() and topic():
    for path in extract_paths(event):
      number = _artifact_number(path)
      if number is None:
        continue
      missing = _missing_prior_artifact(number)
      if missing:
        stderr(f"LoEn: cannot write {path}; missing prior artifact {missing}")
        return BLOCK
      if number == 7 and not (topic_dir() / "5_check.md").is_file():
        stderr("LoEn: final result requires 5_check.md")
        return BLOCK
  return 0


if __name__ == "__main__":
  raise SystemExit(main())

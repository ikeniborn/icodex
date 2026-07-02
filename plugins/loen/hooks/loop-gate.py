#!/usr/bin/env python3
"""LoEn loop-state gate; reads LOEN_ARTIFACT_ROOT through loen_common."""
from loen_common import block_or_nudge, extract_paths, is_edit_event, is_off, parse_loop_yaml, read_event, read_loop_artifact, tool_input, topic, topic_dir

SCRIPT_NAME = "loop-gate"
STAGE_NUMBERS = {
  "goal": 1,
  "context": 2,
  "plan": 3,
  "act": 4,
  "check": 5,
  "reflect": 6,
  "result": 7,
}


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


def _proposed_stage(event: dict) -> int | None:
  if not any(path.endswith("loop.yaml") for path in extract_paths(event)):
    return None
  inp = tool_input(event)
  content = inp.get("content") or inp.get("new_string") or ""
  patch = inp.get("patch") or inp.get("_raw") or event.get("patch") or ""
  text = "\n".join(part for part in (content, patch) if isinstance(part, str))
  for raw_line in text.splitlines():
    line = raw_line[1:] if raw_line.startswith("+") else raw_line
    stripped = line.strip()
    for key in ("stage:", "current_stage:"):
      if stripped.startswith(key):
        value = stripped.split(":", 1)[1].strip().strip('"').strip("'")
        return STAGE_NUMBERS.get(value)
  return None


def main() -> int:
  if is_off():
    return 0
  event = read_event()
  loop_text = read_loop_artifact()
  if is_edit_event(event) and not loop_text:
    return block_or_nudge("LoEn: code edits require an active loop in enforce/strict mode")
  if is_edit_event(event) and loop_text:
    status = str(parse_loop_yaml(loop_text).get("status", "")).strip()
    if status != "active":
      current = status or "missing"
      return block_or_nudge(f"LoEn: code edits require an active loop; current status is {current}")

  if topic() and is_edit_event(event):
    stage_number = _proposed_stage(event)
    if stage_number is not None:
      missing = _missing_prior_artifact(stage_number)
      if missing:
        return block_or_nudge(f"LoEn: cannot jump loop.yaml stage; missing prior artifact {missing}")
    for path in extract_paths(event):
      number = _artifact_number(path)
      if number is None:
        continue
      missing = _missing_prior_artifact(number)
      if missing:
        return block_or_nudge(f"LoEn: cannot write {path}; missing prior artifact {missing}")
      if number == 7 and not (topic_dir() / "5_check.md").is_file():
        return block_or_nudge("LoEn: final result requires 5_check.md")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())

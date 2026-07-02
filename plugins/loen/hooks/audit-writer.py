#!/usr/bin/env python3
"""LoEn audit artifact writer; reads LOEN_ARTIFACT_ROOT through loen_common."""
import os
from pathlib import Path

from loen_common import html_page, loop_policy, read_loop_artifact, topic, topic_dir

SCRIPT_NAME = "audit-writer"


def _ensure_todo_row(topic_name: str) -> None:
  todo = Path(os.environ.get("LOEN_TODO_PATH", "docs/TODO.md"))
  header = "| Topic | Status | Intent | Spec | Plan | Result | Opened | Closed | Notes |\n"
  separator = "|---|---|---|---|---|---|---|---|---|\n"
  row = f"| {topic_name} | in-progress | n/a | n/a | n/a | - |  |  | LoEn loop |\n"
  try:
    if todo.is_file():
      lines = todo.read_text(encoding="utf-8").splitlines(keepends=True)
    else:
      todo.parent.mkdir(parents=True, exist_ok=True)
      lines = [header, separator]
    needle = f"| {topic_name} |"
    for index, line in enumerate(lines):
      if line.startswith(needle):
        lines[index] = row
        break
    else:
      lines.append(row)
    todo.write_text("".join(lines), encoding="utf-8")
  except OSError:
    return


def main() -> int:
  loop_text = read_loop_artifact()
  topic_name = topic()
  if not topic_name or not loop_text:
    return 0
  base = topic_dir(topic_name)
  try:
    base.mkdir(parents=True, exist_ok=True)
    (base / "audit.html").write_text(html_page(topic_name, loop_policy()), encoding="utf-8")
  except OSError:
    return 0
  _ensure_todo_row(topic_name)
  return 0


if __name__ == "__main__":
  raise SystemExit(main())

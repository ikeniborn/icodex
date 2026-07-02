#!/usr/bin/env python3
"""LoEn audit artifact writer; reads LOEN_ARTIFACT_ROOT through loen_common."""
import os
from pathlib import Path

from loen_artifacts import render_audit, upsert_todo_row, validate_topic_slug
from loen_common import is_off, read_loop_artifact, topic, topic_dir

SCRIPT_NAME = "audit-writer"


def main() -> int:
  if is_off():
    return 0
  topic_name = topic()
  if not topic_name or not read_loop_artifact(topic_name):
    return 0
  try:
    validate_topic_slug(topic_name)
  except ValueError:
    return 0
  base = topic_dir(topic_name)
  try:
    base.mkdir(parents=True, exist_ok=True)
    (base / "audit.html").write_text(render_audit(base, topic_name), encoding="utf-8")
    upsert_todo_row(Path(os.environ.get("LOEN_TODO_PATH", "docs/TODO.md")), topic_name)
  except OSError:
    return 0
  return 0


if __name__ == "__main__":
  raise SystemExit(main())

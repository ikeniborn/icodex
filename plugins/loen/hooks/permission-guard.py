#!/usr/bin/env python3
"""Inert LoEn permission guard hook asset."""
from pathlib import Path
import os

SCRIPT_NAME = "permission-guard"


def read_loop_artifact() -> str:
  topic = os.environ.get("LOEN_TOPIC", "").strip()
  root = Path(os.environ.get("LOEN_ARTIFACT_ROOT", "docs/loen"))
  if not topic:
    return ""
  loop_file = root / topic / "loop.yaml"
  if not loop_file.is_file():
    return ""
  try:
    return loop_file.read_text(encoding="utf-8")
  except (OSError, UnicodeDecodeError):
    return ""


def main() -> int:
  read_loop_artifact()
  return 0


if __name__ == "__main__":
  raise SystemExit(main())

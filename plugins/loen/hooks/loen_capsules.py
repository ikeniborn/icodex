#!/usr/bin/env python3
"""Render bounded LoEn context capsules from topic artifacts."""
from __future__ import annotations

from pathlib import Path
import sys
from typing import Any

from loen_common import parse_loop_yaml_checked

BLOCK = 2


def read_text(path: Path) -> str:
  try:
    return path.read_text(encoding="utf-8")
  except (OSError, UnicodeDecodeError):
    return ""


def normalize_heading(line: str) -> str:
  return line.lstrip("#").strip().lower().replace("_", "-").replace(" ", "-")


def extract_section(text: str, *headings: str) -> str:
  wanted = {heading.lower().replace("_", "-").replace(" ", "-") for heading in headings}
  lines = text.splitlines()
  collecting = False
  collected: list[str] = []
  for line in lines:
    stripped = line.strip()
    if stripped.startswith("#"):
      if collecting:
        break
      collecting = normalize_heading(stripped) in wanted
      continue
    if collecting:
      collected.append(line.rstrip())
  return "\n".join(line for line in collected if line.strip()).strip()


def bullet_list(values: Any) -> str:
  if isinstance(values, list) and values:
    return "\n".join(f"- {value}" for value in values)
  if isinstance(values, str) and values:
    return f"- {values}"
  return "- none"


def quality_gates(policy: dict[str, Any]) -> str:
  gates = policy.get("quality_gates", [])
  if not isinstance(gates, list) or not gates:
    return "- none"
  rendered = []
  for gate in gates:
    if not isinstance(gate, dict):
      continue
    command = gate.get("command", "")
    evidence = gate.get("evidence", "")
    rendered.append(f"- {command} -> {evidence}" if evidence else f"- {command}")
  return "\n".join(rendered) if rendered else "- none"


def validate_verifier_execution(role: str, execution: dict[str, Any]) -> str:
  if role != "verifier":
    return ""
  if execution.get("isolation") != "wasm":
    return ""
  if execution.get("network", "off") != "off":
    return "LoEn verifier WASM execution network must be off"
  for mount in execution.get("mounts", []):
    if not isinstance(mount, dict):
      continue
    path = mount.get("path", "")
    mode = mount.get("mode", "")
    if path == "." and mode != "read-only":
      return "LoEn verifier project mount must be read-only"
    if mode == "write" and path != "/tmp/loen":
      return "LoEn verifier write mount must be /tmp/loen"
  return ""


def render_capsule(topic_dir: Path, role: str, question: str) -> str:
  loop_text = read_text(topic_dir / "loop.yaml")
  policy, diagnostics = parse_loop_yaml_checked(loop_text)
  if diagnostics:
    raise ValueError("LoEn: invalid canonical authority")
  execution = policy.get("execution", {})
  if not isinstance(execution, dict):
    raise ValueError("LoEn: invalid canonical authority")
  rejection = validate_verifier_execution(role, execution)
  if rejection:
    raise ValueError(rejection)

  context_text = read_text(topic_dir / "2_context.md")
  check_text = read_text(topic_dir / "5_check.md")
  relevant_files = extract_section(context_text, "Relevant Files", "Relevant files")
  last_evidence = extract_section(check_text, "Last Evidence Summary", "Last evidence summary")

  topic = str(policy.get("topic") or topic_dir.name)
  objective = str(policy.get("objective") or "")
  mode = str(policy.get("mode") or "")
  current_stage = str(policy.get("current_stage") or policy.get("stage") or "")

  return "\n".join([
    "Topic",
    topic,
    "",
    "Objective",
    objective,
    "",
    "Loop mode",
    mode,
    "",
    "Current stage",
    current_stage,
    "",
    "Mutable scope",
    bullet_list(policy.get("mutable_scope", [])),
    "",
    "Protected scope",
    bullet_list(policy.get("protected_scope", [])),
    "",
    "Quality gates",
    quality_gates(policy),
    "",
    "Relevant files",
    relevant_files or "- none",
    "",
    "Last evidence summary",
    last_evidence or "none",
    "",
    "Specific question or task for the agent",
    question,
    "",
  ])


def main(argv: list[str]) -> int:
  if len(argv) < 4:
    print("usage: loen_capsules.py <topic-dir> <role> <question>", file=sys.stderr)
    return BLOCK
  topic_dir = Path(argv[1])
  role = argv[2]
  question = argv[3]
  try:
    print(render_capsule(topic_dir, role, question), end="")
  except ValueError as exc:
    print(str(exc), file=sys.stderr)
    return BLOCK
  return 0


if __name__ == "__main__":
  raise SystemExit(main(sys.argv))

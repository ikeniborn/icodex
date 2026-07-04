#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
cd "$ROOT"

assert_exit "agent configs parse and match contract" 0 python3 - <<'PY'
from pathlib import Path
import re
import sys

root = Path(".codex-isolated/agents")
expected = {
    "chain-auditor.toml": {
        "name": "chain-auditor",
        "model": "gpt-5.5",
        "model_reasoning_effort": "high",
        "sandbox_mode": "read-only",
        "phrases": ["check-chain", "CRITICAL", "frontmatter", "decision", "evidence", "risks", "next_action"],
    },
    "artifact-renderer.toml": {
        "name": "artifact-renderer",
        "model": "gpt-5.4-mini",
        "model_reasoning_effort": "medium",
        "sandbox_mode": "read-only",
        "phrases": ["html-report", "zero-dependency", "chain-tab", "decision", "evidence", "risks", "next_action"],
    },
    "diagram-checker.toml": {
        "name": "diagram-checker",
        "model": "gpt-5.4-mini",
        "model_reasoning_effort": "medium",
        "sandbox_mode": "read-only",
        "phrases": ["mermaid-obsidian", "Obsidian", "syntax", "decision", "evidence", "risks", "next_action"],
    },
    "repo-safety-reviewer.toml": {
        "name": "repo-safety-reviewer",
        "model": "gpt-5.5",
        "model_reasoning_effort": "high",
        "sandbox_mode": "read-only",
        "phrases": ["git-workflow", "branch", "commit", "decision", "evidence", "risks", "next_action"],
    },
    "project-explorer.toml": {
        "name": "project-explorer",
        "model": "gpt-5.4-mini",
        "model_reasoning_effort": "low",
        "sandbox_mode": "read-only",
        "phrases": ["context-awareness", "project_context", "iwiki", "decision", "evidence", "risks", "next_action"],
    },
}

errors = []
if not root.is_dir():
    errors.append(f"missing directory: {root}")

for filename, want in expected.items():
    path = root / filename
    if not path.is_file():
        errors.append(f"missing file: {path}")
        continue
    text = path.read_text()
    data = {}
    for key in ("name", "description", "model", "model_reasoning_effort", "sandbox_mode"):
        match = re.search(rf'^{key}\s*=\s*"([^"]*)"\s*$', text, re.MULTILINE)
        if match:
            data[key] = match.group(1)
        else:
            errors.append(f"{path}: missing {key}")
    instr = re.search(r'^developer_instructions\s*=\s*"""\n?(.*?)\n?"""\s*$', text, re.MULTILINE | re.DOTALL)
    if instr:
        data["developer_instructions"] = instr.group(1)
    else:
        errors.append(f"{path}: missing developer_instructions")
    for key in ("name", "model", "model_reasoning_effort", "sandbox_mode"):
        if data.get(key) != want[key]:
            errors.append(f"{path}: {key}={data.get(key)!r}, want {want[key]!r}")
    instructions = data.get("developer_instructions", "")
    if "Do not modify files." not in instructions:
        errors.append(f"{path}: instructions must forbid file modification")
    for phrase in want["phrases"]:
        if phrase not in instructions:
            errors.append(f"{path}: missing phrase {phrase!r}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
PY

finish

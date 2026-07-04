---
review:
  plan_hash: 81a1765ac272b9a4
  last_run: 2026-07-04
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: null
  spec: docs/superpowers/specs/2026-07-02-03-loen-enforcement-hooks-design.md
result_check:
  verdict: OK
  plan_hash: 81a1765ac272b9a4
  last_run: 2026-07-04
---

# 03 LoEn Enforcement Hooks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make LoEn hooks deterministically enforce active loop state, scoped edits, tool and shell policy, evidence gates, and audit updates without depending on IDD->SDD or Superpowers frontmatter.

**Architecture:** Keep enforcement inside the editable LoEn plugin source tree under `plugins/loen/hooks/`. Shared parsing and event helpers live in `loen_common.py`; each guard remains a small single-purpose Python hook that reads JSON from stdin and returns exit code `2` only for blocking modes. Bash fixture tests exercise hook scripts directly with temporary `docs/loen/<topic>/` artifacts, so this layer is testable before icodex launch-time wiring exists.

**Tech Stack:** Bash tests, Python 3 standard library, JSON hook payloads, lightweight YAML parsing already used by LoEn runtime artifacts.

Spec: `docs/superpowers/specs/2026-07-02-03-loen-enforcement-hooks-design.md`

---

## Scope Check

This spec covers one subsystem: LoEn hook enforcement behavior under `plugins/loen/hooks/`. It does not install LoEn into `.codex-isolated/`, vendor plugin cache files, add icodex launch-time `ICODEX_LOEN_MODE` wiring, or implement later agent isolation/runtime profile split work. Those belong to later LoEn specs.

The current workspace may already contain enforcement-hook source files and tests from draft PR work. Execute this plan as a reconciliation plan: keep matching code, patch only missing behavior, and verify the final diff against this plan with `/check-chain result`.

## File Structure

- **Modify** `tests/test_loen_enforcement_hooks.sh` - focused fixture suite for hook modes, active-loop state, stage ordering, path extraction, shell/network policy, verifier edit blocking, evidence gates, audit idempotence, task-log preservation, template policy, and IDD independence.
- **Modify** `plugins/loen/hooks/hooks.json` - registers LoEn pre-tool, post-tool, and stop hooks against the plugin source paths.
- **Modify** `plugins/loen/hooks/loen_common.py` - shared deterministic helpers for mode parsing, JSON event parsing, loop contract parsing, path normalization, tool classification, shell command extraction, and block/nudge behavior.
- **Modify** `plugins/loen/hooks/loop-gate.py` - blocks code edits without active loop state, skipped numbered artifacts, `loop.yaml` stage jumps, and final result writes without check artifacts.
- **Modify** `plugins/loen/hooks/scope-guard.py` - blocks protected paths and paths outside configured mutable scope while allowing topic artifacts and read-only events.
- **Modify** `plugins/loen/hooks/tool-guard.py` - enforces root tool policy, role tool policy, stage role policy, and verifier/reviewer no-edit rules in `strict`; emits nudges in `advisory`.
- **Modify** `plugins/loen/hooks/permission-guard.py` - enforces shell deny patterns, destructive Git blocking, network-off policy, and network allowlists in `strict`; emits nudges in `advisory`.
- **Modify** `plugins/loen/hooks/evidence-gate.py` - blocks final done/success/Stop outcomes without check, result, verifier verdict, and evidence files; enforces worker/verifier separation in `strict`.
- **Modify** `plugins/loen/hooks/audit-writer.py` - regenerates per-topic `audit.html` and upserts the matching task-log row without subjective review.
- **Modify** `plugins/loen/assets/templates/loop.yaml` - extends the runtime loop contract with agent, stage, tool, filesystem, network, and shell policy defaults.
- **Modify** `plugins/loen/docs/README.md` and `plugins/loen/docs/architecture.md` - document enforcement hook behavior and boundaries.
- **Update via iwiki MCP** page `loen-enforcement-hooks` and, if needed, page `loen-overview` after behavior is implemented.
- **Do not modify** `lib/`, `icodex.sh`, `.codex-isolated/plugins/cache/`, or global plugin installation wiring in this plan.

## Execution Prerequisites

Use the project branch workflow before Task 1. If no suitable `dev-*` branch already exists, use `git-workflow` and `superpowers:using-git-worktrees`: ask whether to create a worktree, then create a branch such as `dev-03-loen-enforcement-hooks` from the intended base branch. Run every command from the repository root.

Before implementation, validate the spec gate if it is not already cached:

```text
/check-chain spec docs/superpowers/specs/2026-07-02-03-loen-enforcement-hooks-design.md
```

Expected: `OK` or `OK (cached, hash match)`. If the spec gate reports open CRITICAL findings, fix the spec first and rerun the gate before editing code.

---

### Task 1: Add Enforcement Hook Fixture Coverage

**Files:**
- Modify: `tests/test_loen_enforcement_hooks.sh`
- Read: `tests/helpers.sh`
- Read: `docs/superpowers/specs/2026-07-02-03-loen-enforcement-hooks-design.md`

- [ ] **Step 1: Write the failing fixture suite**

Replace `tests/test_loen_enforcement_hooks.sh` with this executable Bash test. If the file already exists, reconcile it so the assertions below are covered without deleting broader existing assertions.

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

hook_root="$ROOT/plugins/loen/hooks"
template="$ROOT/plugins/loen/assets/templates/loop.yaml"
hooks_json="$ROOT/plugins/loen/hooks/hooks.json"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

artifact_root="$tmp/loen"
topic="demo-topic"
topic_dir="$artifact_root/$topic"
mkdir -p "$topic_dir"

cat > "$topic_dir/loop.yaml" <<'YAML'
topic: demo-topic
status: active
stage: check
artifact_root: docs/loen/demo-topic
agents:
  planner:
    tools: [read, search]
    sandbox: read-only
  worker:
    tools: [read, search, edit, shell]
    sandbox: workspace-write
  verifier:
    tools: [read, search, shell]
    sandbox: read-only
    must_not_edit: true
  reviewer:
    tools: [read, search, shell]
    sandbox: read-only
    must_not_edit: true
stages:
  goal:
    roles: [planner, worker]
  context:
    roles: [planner, worker, researcher]
  plan:
    roles: [planner]
  act:
    roles: [worker]
  check:
    roles: [verifier]
  reflect:
    roles: [planner, verifier, reviewer]
  result:
    roles: [planner, verifier, reviewer]
tools:
  allowed:
    - read
    - search
    - apply_patch
    - shell
  denied:
    - network
    - secrets
    - destructive_git
    - external_write
permissions:
  filesystem:
    mutable_scope:
      - src/**
      - tests/**
    protected_scope:
      - migrations/**
      - secrets/**
  network:
    mode: off
    allowlist: []
  shell:
    allow:
      - pytest tests/auth
      - ruff check .
    deny_patterns:
      - rm -rf
      - git reset --hard
      - curl *|sh
YAML

touch "$topic_dir/1_goal.md" "$topic_dir/2_context.md" "$topic_dir/3_plan.md" "$topic_dir/4_act.md"

run_hook() {
  local hook="$1" mode="$2" topic_value="$3" payload="$4"
  env LOEN_MODE="$mode" LOEN_TOPIC="$topic_value" LOEN_ARTIFACT_ROOT="$artifact_root" LOEN_TODO_PATH="$tmp/TODO.md" \
    python3 "$hook_root/$hook" <<<"$payload" >/dev/null 2>&1
}

run_hook_capture() {
  local hook="$1" mode="$2" topic_value="$3" payload="$4" stderr_file="$5"
  env LOEN_MODE="$mode" LOEN_TOPIC="$topic_value" LOEN_ARTIFACT_ROOT="$artifact_root" LOEN_TODO_PATH="$tmp/TODO.md" \
    python3 "$hook_root/$hook" <<<"$payload" >/dev/null 2>"$stderr_file"
}

assert_hook_exit() {
  local desc="$1" expected="$2" hook="$3" mode="$4" topic_value="$5" payload="$6" code=0
  run_hook "$hook" "$mode" "$topic_value" "$payload" || code=$?
  assert_eq "$desc" "$expected" "$code"
}

assert_hook_stderr_contains() {
  local desc="$1" expected="$2" hook="$3" mode="$4" topic_value="$5" payload="$6" needle="$7" code=0
  local stderr_file="$tmp/stderr-${desc//[^A-Za-z0-9]/_}.txt"
  run_hook_capture "$hook" "$mode" "$topic_value" "$payload" "$stderr_file" || code=$?
  assert_eq "$desc exit" "$expected" "$code"
  assert_contains "$desc stderr" "$(cat "$stderr_file" 2>/dev/null)" "$needle"
}

edit_payload='{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Update File: src/app.py\n@@\n-old\n+new\n*** End Patch\n"}}'
protected_patch='{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Update File: migrations/001.sql\n@@\n-old\n+new\n*** End Patch\n"}}'
raw_protected_patch='{"tool_name":"apply_patch","tool_input":"*** Begin Patch\n*** Update File: migrations/002.sql\n@@\n-old\n+new\n*** End Patch\n"}'
traversal_protected_patch='{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Update File: src/../migrations/001.sql\n@@\n-old\n+new\n*** End Patch\n"}}'
topic_doc_write='{"tool_name":"Write","tool_input":{"file_path":"docs/loen/demo-topic/5_check.md","content":"ok"}}'
skipped_reflect_write='{"tool_name":"Write","tool_input":{"file_path":"docs/loen/demo-topic/6_reflect.md","content":"too early"}}'
read_readme='{"tool_name":"Read","tool_input":{"file_path":"README.md"}}'
test_edit='{"tool_name":"Edit","tool_input":{"file_path":"tests/test_demo.sh","old_string":"old","new_string":"new"}}'
traversal_test_edit='{"tool_name":"Edit","tool_input":{"file_path":"tests/../tests/test_demo.sh","old_string":"old","new_string":"new"}}'
worker_edit='{"tool_name":"Edit","agent_role":"worker","tool_input":{"file_path":"tests/test_demo.sh","old_string":"old","new_string":"new"}}'
worker_shell='{"tool_name":"Bash","agent_role":"worker","tool_input":{"command":"pytest tests/auth"}}'
verifier_shell='{"tool_name":"Bash","agent_role":"verifier","tool_input":{"command":"pytest tests/auth"}}'
verifier_read='{"tool_name":"Read","agent_role":"verifier","tool_input":{"file_path":"tests/test_demo.sh"}}'
shell_allow='{"tool_name":"Bash","tool_input":{"command":"pytest tests/auth"}}'
shell_deny='{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD"}}'
shell_deny_pattern='{"tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'
raw_shell_deny_pattern='{"tool_name":"Bash","tool_input":"rm -rf build"}'
network_deny='{"tool_name":"Bash","tool_input":{"command":"curl https://example.com/file"}}'
network_deny_tab='{"tool_name":"Bash","tool_input":{"command":"curl\thttps://example.com/file"}}'
network_deny_absolute='{"tool_name":"Bash","tool_input":{"command":"/usr/bin/curl https://example.com/file"}}'
network_deny_env='{"tool_name":"Bash","tool_input":{"command":"env curl https://example.com/file"}}'
network_deny_bash_c="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"bash -c 'curl https://example.com/file'\"}}"
verifier_edit='{"tool_name":"Edit","agent_role":"verifier","tool_input":{"file_path":"tests/test_demo.sh","old_string":"old","new_string":"new"}}'
reviewer_edit='{"tool_name":"Edit","agent_role":"reviewer","tool_input":{"file_path":"tests/test_demo.sh","old_string":"old","new_string":"new"}}'
done_payload='{"verdict":"done","agent_role":"verifier"}'
metadata_stop_payload='{"hook_event_name":"Stop","session_id":"s"}'
self_approval_payload='{"verdict":"done","agent_role":"verifier","worker_role":"same-agent","verifier_role":"same-agent"}'
separated_done_payload='{"verdict":"done","agent_role":"verifier","worker_role":"worker-agent","verifier_role":"verifier-agent"}'
success_message_payload='{"message":"final success: implementation complete","agent_role":"verifier"}'
stage_jump_loop_yaml='{"tool_name":"Write","tool_input":{"file_path":"docs/loen/demo-topic/loop.yaml","content":"topic: demo-topic\nstage: reflect\n"}}'

assert_contains "hooks registry PreToolUse present" "$(cat "$hooks_json" 2>/dev/null)" "PreToolUse"
assert_contains "hooks registry Stop present" "$(cat "$hooks_json" 2>/dev/null)" "evidence-gate.py"

assert_hook_exit "loop-gate off allows edit without topic" 0 "loop-gate.py" "off" "" "$edit_payload"
assert_hook_exit "loop-gate advisory allows edit without topic" 0 "loop-gate.py" "advisory" "" "$edit_payload"
assert_hook_stderr_contains "loop-gate advisory nudges missing loop" 0 "loop-gate.py" "advisory" "" "$edit_payload" "LoEn:"
assert_hook_exit "loop-gate enforce blocks edit without topic" 2 "loop-gate.py" "enforce" "" "$edit_payload"
assert_hook_exit "loop-gate strict blocks edit without topic" 2 "loop-gate.py" "strict" "" "$edit_payload"
assert_hook_exit "loop-gate blocks skipped stage artifact" 2 "loop-gate.py" "enforce" "$topic" "$skipped_reflect_write"
assert_hook_exit "loop-gate blocks loop yaml stage jump" 2 "loop-gate.py" "enforce" "$topic" "$stage_jump_loop_yaml"

inactive_topic="inactive-topic"
inactive_dir="$artifact_root/$inactive_topic"
mkdir -p "$inactive_dir"
printf 'topic: inactive-topic\nstatus: done\nstage: result\n' > "$inactive_dir/loop.yaml"
assert_hook_stderr_contains "loop-gate advisory nudges inactive loop" 0 "loop-gate.py" "advisory" "$inactive_topic" "$edit_payload" "LoEn:"
assert_hook_exit "loop-gate enforce blocks inactive loop" 2 "loop-gate.py" "enforce" "$inactive_topic" "$edit_payload"

touch "$topic_dir/5_check.md"
assert_hook_exit "scope-guard allows read outside mutable scope" 0 "scope-guard.py" "strict" "$topic" "$read_readme"
assert_hook_exit "scope-guard allows LoEn topic artifact" 0 "scope-guard.py" "enforce" "$topic" "$topic_doc_write"
assert_hook_exit "scope-guard allows configured mutable scope" 0 "scope-guard.py" "enforce" "$topic" "$test_edit"
assert_hook_exit "scope-guard allows normalized mutable traversal path" 0 "scope-guard.py" "enforce" "$topic" "$traversal_test_edit"
assert_hook_exit "scope-guard blocks protected path from patch" 2 "scope-guard.py" "enforce" "$topic" "$protected_patch"
assert_hook_exit "scope-guard blocks protected traversal path" 2 "scope-guard.py" "enforce" "$topic" "$traversal_protected_patch"
assert_hook_exit "scope-guard blocks raw string protected patch" 2 "scope-guard.py" "enforce" "$topic" "$raw_protected_patch"
assert_hook_stderr_contains "scope-guard advisory nudges protected path" 0 "scope-guard.py" "advisory" "$topic" "$protected_patch" "LoEn:"

assert_hook_exit "permission-guard allows configured shell command" 0 "permission-guard.py" "strict" "$topic" "$shell_allow"
assert_hook_exit "permission-guard blocks destructive git" 2 "permission-guard.py" "strict" "$topic" "$shell_deny"
assert_hook_exit "permission-guard blocks configured deny pattern" 2 "permission-guard.py" "strict" "$topic" "$shell_deny_pattern"
assert_hook_stderr_contains "permission-guard blocks raw string deny pattern" 2 "permission-guard.py" "strict" "$topic" "$raw_shell_deny_pattern" "denied by policy"
assert_hook_exit "permission-guard blocks network command" 2 "permission-guard.py" "strict" "$topic" "$network_deny"
assert_hook_stderr_contains "permission-guard blocks network command with tab" 2 "permission-guard.py" "strict" "$topic" "$network_deny_tab" "network command denied"
assert_hook_stderr_contains "permission-guard blocks absolute network command" 2 "permission-guard.py" "strict" "$topic" "$network_deny_absolute" "network command denied"
assert_hook_stderr_contains "permission-guard blocks env wrapped network command" 2 "permission-guard.py" "strict" "$topic" "$network_deny_env" "network command denied"
assert_hook_stderr_contains "permission-guard blocks bash -c network command" 2 "permission-guard.py" "strict" "$topic" "$network_deny_bash_c" "network command denied"
assert_hook_exit "permission-guard enforce does not block strict-only shell policy" 0 "permission-guard.py" "enforce" "$topic" "$shell_deny_pattern"
assert_hook_stderr_contains "permission-guard advisory nudges denied shell" 0 "permission-guard.py" "advisory" "$topic" "$shell_deny_pattern" "LoEn:"

assert_hook_exit "tool-guard blocks verifier edits in strict" 2 "tool-guard.py" "strict" "$topic" "$verifier_edit"
assert_hook_exit "tool-guard blocks reviewer edits in strict" 2 "tool-guard.py" "strict" "$topic" "$reviewer_edit"
assert_hook_exit "tool-guard enforce does not block strict-only role policy" 0 "tool-guard.py" "enforce" "$topic" "$verifier_edit"
assert_hook_exit "tool-guard blocks worker edit at check stage in strict" 2 "tool-guard.py" "strict" "$topic" "$worker_edit"
assert_hook_exit "tool-guard blocks worker shell at check stage in strict" 2 "tool-guard.py" "strict" "$topic" "$worker_shell"
assert_hook_exit "tool-guard allows verifier shell at check stage in strict" 0 "tool-guard.py" "strict" "$topic" "$verifier_shell"
assert_hook_exit "tool-guard allows verifier read at check stage in strict" 0 "tool-guard.py" "strict" "$topic" "$verifier_read"
assert_hook_stderr_contains "tool-guard advisory nudges verifier edits" 0 "tool-guard.py" "advisory" "$topic" "$verifier_edit" "LoEn:"

assert_hook_exit "evidence-gate blocks empty stop without evidence" 2 "evidence-gate.py" "enforce" "$topic" "{}"
assert_hook_stderr_contains "evidence-gate advisory nudges metadata stop without evidence" 0 "evidence-gate.py" "advisory" "$topic" "$metadata_stop_payload" "LoEn:"
assert_hook_exit "evidence-gate blocks done without result evidence" 2 "evidence-gate.py" "enforce" "$topic" "$done_payload"
assert_hook_exit "evidence-gate blocks success message without result evidence" 2 "evidence-gate.py" "enforce" "$topic" "$success_message_payload"
touch "$topic_dir/7_result.md" "$topic_dir/verifier-verdict.md"
mkdir -p "$topic_dir/evidence"
printf 'log\n' > "$topic_dir/evidence/run.log"
assert_hook_exit "evidence-gate allows done with evidence" 0 "evidence-gate.py" "enforce" "$topic" "$done_payload"
assert_hook_exit "evidence-gate strict blocks missing separation fields" 2 "evidence-gate.py" "strict" "$topic" "$done_payload"
assert_hook_exit "evidence-gate blocks verifier self-approval in strict" 2 "evidence-gate.py" "strict" "$topic" "$self_approval_payload"
assert_hook_exit "evidence-gate strict allows separated verifier" 0 "evidence-gate.py" "strict" "$topic" "$separated_done_payload"

assert_hook_exit "audit-writer off no-ops" 0 "audit-writer.py" "off" "$topic" "$test_edit"
assert_hook_exit "audit-writer regenerates audit html" 0 "audit-writer.py" "advisory" "$topic" "$test_edit"
first_audit="$(cat "$topic_dir/audit.html" 2>/dev/null)"
assert_hook_exit "audit-writer regenerates audit html idempotently" 0 "audit-writer.py" "advisory" "$topic" "$test_edit"
second_audit="$(cat "$topic_dir/audit.html" 2>/dev/null)"
assert_eq "audit html is idempotent" "$first_audit" "$second_audit"
assert_contains "audit html names topic" "$second_audit" "demo-topic"
assert_contains "audit writer updates TODO row" "$(cat "$tmp/TODO.md" 2>/dev/null)" "| demo-topic | in-progress |"

hook_refs="$(find "$hook_root" -maxdepth 1 -type f -name '*.py' -print0 | xargs -0 grep -En 'chain-gate|IDD|SDD|docs/superpowers|frontmatter' 2>/dev/null || true)"
assert_eq "LoEn hooks do not depend on chain-gate or IDD frontmatter" "" "$hook_refs"

assert_contains "loop template includes agent policy" "$(cat "$template" 2>/dev/null)" "agents:"
assert_contains "loop template includes stage policy" "$(cat "$template" 2>/dev/null)" "stages:"
assert_contains "loop template includes tool policy" "$(cat "$template" 2>/dev/null)" "tools:"
assert_contains "loop template includes permission policy" "$(cat "$template" 2>/dev/null)" "permissions:"

finish
```

- [ ] **Step 2: Run the focused test and verify it fails for missing enforcement**

```bash
bash tests/test_loen_enforcement_hooks.sh
```

Expected before implementation: non-zero exit, with failures naming missing hook scripts, missing `hooks.json` matchers, or guards returning `0` where the test expects `2`.

- [ ] **Step 3: Commit the failing test**

```bash
git add tests/test_loen_enforcement_hooks.sh
git commit -m "test(loen): cover enforcement hook behavior"
```

Expected: commit succeeds on a `dev-*` branch.

---

### Task 2: Add Shared Hook Helpers and Policy Template

**Files:**
- Modify: `plugins/loen/hooks/loen_common.py`
- Modify: `plugins/loen/assets/templates/loop.yaml`
- Test: `tests/test_loen_enforcement_hooks.sh`

- [ ] **Step 1: Replace or extend shared helpers**

Update `plugins/loen/hooks/loen_common.py` with these helper groups. Keep any existing compatible helpers from earlier LoEn layers, but ensure these exact public functions exist: `mode`, `is_enforcing`, `is_advisory`, `is_off`, `is_strict`, `read_event`, `topic`, `artifact_root`, `topic_dir`, `read_loop_artifact`, `parse_loop_yaml`, `loop_policy`, `block_or_nudge`, `tool_name`, `tool_input`, `tool_class`, `is_edit_event`, `extract_paths`, `normalize_path`, `matches_any`, `is_loen_topic_path`, `shell_command`, and `command_matches`.

```python
#!/usr/bin/env python3
"""Shared deterministic helpers for LoEn hook assets."""
from __future__ import annotations

import fnmatch
import html
import json
import os
import posixpath
from pathlib import Path
import re
import sys
from typing import Any

BLOCK = 2

def mode() -> str:
  value = os.environ.get("LOEN_MODE", "advisory").strip().lower()
  return value if value in {"off", "advisory", "enforce", "strict"} else "advisory"

def is_enforcing() -> bool:
  return mode() in {"enforce", "strict"}

def is_advisory() -> bool:
  return mode() == "advisory"

def is_off() -> bool:
  return mode() == "off"

def is_strict() -> bool:
  return mode() == "strict"

def read_event() -> dict[str, Any]:
  try:
    raw = sys.stdin.read()
  except OSError:
    return {}
  if not raw.strip():
    return {}
  try:
    data = json.loads(raw)
  except json.JSONDecodeError:
    return {}
  return data if isinstance(data, dict) else {}

def topic() -> str:
  return os.environ.get("LOEN_TOPIC", "").strip()

def artifact_root() -> Path:
  return Path(os.environ.get("LOEN_ARTIFACT_ROOT", "docs/loen"))

def topic_dir(topic_value: str | None = None) -> Path:
  return artifact_root() / (topic_value if topic_value is not None else topic())

def read_loop_artifact(topic_value: str | None = None) -> str:
  topic_name = (topic_value if topic_value is not None else topic()).strip()
  if not topic_name:
    return ""
  loop_file = artifact_root() / topic_name / "loop.yaml"
  if not loop_file.is_file():
    return ""
  try:
    return loop_file.read_text(encoding="utf-8")
  except (OSError, UnicodeDecodeError):
    return ""

def _parse_scalar(value: str) -> Any:
  value = value.strip().strip('"').strip("'")
  if value.lower() == "true":
    return True
  if value.lower() == "false":
    return False
  return value

def _parse_inline_list(value: str) -> list[str]:
  value = value.strip()
  if not (value.startswith("[") and value.endswith("]")):
    return []
  inner = value[1:-1].strip()
  if not inner:
    return []
  return [item.strip().strip('"').strip("'") for item in inner.split(",")]

def parse_loop_yaml(text: str) -> dict[str, Any]:
  data: dict[str, Any] = {
    "agents": {},
    "stages": {},
    "tools": {"allowed": [], "denied": []},
    "permissions": {
      "filesystem": {"mutable_scope": [], "protected_scope": []},
      "network": {"mode": "off", "allowlist": []},
      "shell": {"allow": [], "deny_patterns": []},
    },
    "mutable_scope": [],
    "protected_scope": [],
    "quality_gates": [],
    "verifier": {},
    "budget": {},
    "stop_conditions": [],
    "handoff_conditions": [],
  }
  section = ""
  subsection = ""
  current_key = ""
  current_list_item: dict[str, Any] | None = None
  list_target: list[Any] | None = None

  for raw_line in text.splitlines():
    line = raw_line.split("#", 1)[0].rstrip()
    if not line.strip():
      continue
    indent = len(line) - len(line.lstrip(" "))
    stripped = line.strip()

    if indent == 0:
      section = ""
      subsection = ""
      current_key = ""
      current_list_item = None
      list_target = None
      if stripped.endswith(":"):
        section = stripped[:-1]
        if section in {"mutable_scope", "protected_scope", "stop_conditions", "handoff_conditions"}:
          list_target = data[section]
        continue
      if ":" in stripped:
        key, value = stripped.split(":", 1)
        key = key.strip()
        if key in {"mutable_scope", "protected_scope", "stop_conditions", "handoff_conditions"}:
          parsed_list = _parse_inline_list(value)
          if parsed_list or value.strip() == "[]":
            data[key] = parsed_list
          elif value.strip():
            data[key] = [_parse_scalar(value)]
          continue
        parsed = _parse_scalar(value)
        data[key] = parsed
        if key == "current_stage":
          data["stage"] = parsed
      continue

    if section in {"mutable_scope", "protected_scope", "stop_conditions", "handoff_conditions"}:
      if stripped.startswith("- "):
        data[section].append(stripped[2:].strip())
      continue

    if section == "quality_gates":
      if stripped.startswith("- "):
        current_list_item = {}
        data["quality_gates"].append(current_list_item)
        item = stripped[2:].strip()
        if ":" in item:
          key, value = item.split(":", 1)
          current_list_item[key.strip()] = _parse_scalar(value)
      elif current_list_item is not None and ":" in stripped:
        key, value = stripped.split(":", 1)
        current_list_item[key.strip()] = _parse_scalar(value)
      continue

    if section in {"verifier", "budget"}:
      if ":" in stripped:
        key, value = stripped.split(":", 1)
        data[section][key.strip()] = _parse_scalar(value)
      continue

    if section in {"agents", "stages"}:
      if indent == 2 and stripped.endswith(":"):
        current_key = stripped[:-1]
        data[section].setdefault(current_key, {})
        continue
      if current_key and ":" in stripped:
        key, value = stripped.split(":", 1)
        parsed = _parse_inline_list(value) or _parse_scalar(value)
        data[section][current_key][key.strip()] = parsed
      continue

    if section == "tools":
      if ":" in stripped:
        key, value = stripped.split(":", 1)
        key = key.strip()
        parsed = _parse_inline_list(value)
        data["tools"].setdefault(key, [])
        if parsed or value.strip() == "[]":
          data["tools"][key] = parsed
          list_target = None
        else:
          list_target = data["tools"][key]
      elif stripped.startswith("- ") and list_target is not None:
        list_target.append(stripped[2:].strip())
      continue

    if section == "permissions":
      if indent == 2 and stripped.endswith(":"):
        subsection = stripped[:-1]
        list_target = None
        continue
      target = data["permissions"].setdefault(subsection, {})
      if ":" in stripped:
        key, value = stripped.split(":", 1)
        key = key.strip()
        parsed = _parse_inline_list(value)
        if parsed or value.strip() == "[]":
          target[key] = parsed
          list_target = None
        elif value.strip():
          target[key] = _parse_scalar(value)
          list_target = None
        else:
          target.setdefault(key, [])
          list_target = target[key]
      elif stripped.startswith("- ") and list_target is not None:
        list_target.append(stripped[2:].strip())

  if isinstance(data["mutable_scope"], list) and data["mutable_scope"] and not data["permissions"]["filesystem"]["mutable_scope"]:
    data["permissions"]["filesystem"]["mutable_scope"] = list(data["mutable_scope"])
  if isinstance(data["protected_scope"], list) and data["protected_scope"] and not data["permissions"]["filesystem"]["protected_scope"]:
    data["permissions"]["filesystem"]["protected_scope"] = list(data["protected_scope"])
  if "current_stage" in data:
    data["stage"] = data["current_stage"]
  elif "stage" in data:
    data["current_stage"] = data["stage"]
  return data

def loop_policy() -> dict[str, Any]:
  return parse_loop_yaml(read_loop_artifact())

def stderr(message: str) -> None:
  print(message, file=sys.stderr)

def block_or_nudge(message: str) -> int:
  if is_enforcing():
    stderr(message)
    return BLOCK
  if is_advisory():
    stderr(message)
  return 0

def tool_name(event: dict[str, Any]) -> str:
  return str(event.get("tool_name") or event.get("tool") or event.get("name") or "")

def tool_input(event: dict[str, Any]) -> dict[str, Any]:
  value = event.get("tool_input") or event.get("input") or event.get("parameters") or {}
  if isinstance(value, dict):
    return value
  if isinstance(value, str):
    return {"_raw": value}
  return {}

def tool_class(event: dict[str, Any]) -> str:
  name = tool_name(event)
  if name in {"Bash", "shell", "exec_command"}:
    return "shell"
  if name in {"apply_patch", "ApplyPatch"}:
    return "apply_patch"
  if name in {"Edit", "Write", "MultiEdit"}:
    return "edit"
  if name in {"Read", "open", "view_image"}:
    return "read"
  if name in {"Grep", "Glob", "find", "search"}:
    return "search"
  return name.lower()

def is_edit_event(event: dict[str, Any]) -> bool:
  return tool_class(event) in {"apply_patch", "edit"}

def extract_paths(event: dict[str, Any]) -> list[str]:
  inp = tool_input(event)
  paths: list[str] = []
  for key in ("file_path", "path"):
    value = inp.get(key)
    if isinstance(value, str) and value.strip():
      paths.append(value.strip())
  patch = inp.get("patch") or inp.get("_raw") or event.get("patch") or ""
  if isinstance(patch, str):
    for line in patch.splitlines():
      match = re.match(r"\*\*\* (?:Add|Update|Delete) File: (.+)$", line)
      if match:
        paths.append(match.group(1).strip())
      match = re.match(r"\*\*\* Move to: (.+)$", line)
      if match:
        paths.append(match.group(1).strip())
  return list(dict.fromkeys(paths))

def normalize_path(path: str) -> str:
  clean = path.replace("\\", "/")
  normalized = posixpath.normpath(clean)
  if normalized == ".":
    normalized = ""
  if clean.startswith("/"):
    cwd = posixpath.normpath(Path.cwd().as_posix())
    if normalized == cwd:
      return ""
    if normalized.startswith(f"{cwd}/"):
      return normalized[len(cwd) + 1:]
  return normalized

def matches_any(path: str, patterns: list[str]) -> bool:
  clean = normalize_path(path)
  return any(fnmatch.fnmatch(clean, pattern) for pattern in patterns)

def is_loen_topic_path(path: str, topic_name: str) -> bool:
  clean = normalize_path(path)
  root = normalize_path(str(artifact_root() / topic_name))
  return clean.startswith(f"docs/loen/{topic_name}/") or clean.startswith(f"{root}/")

def shell_command(event: dict[str, Any]) -> str:
  value = tool_input(event).get("command") or tool_input(event).get("_raw") or event.get("command") or ""
  return value if isinstance(value, str) else ""

def command_matches(command: str, pattern: str) -> bool:
  return command == pattern or fnmatch.fnmatch(command, pattern)

def html_page(topic_name: str, policy: dict[str, Any]) -> str:
  stage = html.escape(str(policy.get("stage", "")))
  status = html.escape(str(policy.get("status", "")))
  safe_topic = html.escape(topic_name)
  return "\n".join([
    "<!doctype html>",
    "<html>",
    "<head><meta charset=\"utf-8\"><title>LoEn Audit</title></head>",
    "<body>",
    f"<h1>LoEn Audit: {safe_topic}</h1>",
    f"<p>Status: {status}</p>",
    f"<p>Stage: {stage}</p>",
    "</body>",
    "</html>",
    "",
  ])
```

- [ ] **Step 2: Extend the loop template with enforcement policy**

Ensure `plugins/loen/assets/templates/loop.yaml` contains both runtime fields and policy fields:

```yaml
topic: {{topic}}
mode: delivery
status: active
objective: "{{objective}}"
current_stage: goal
stage: goal
created: "{{created_date}}"
updated: "{{updated_date}}"
mutable_scope:
  - {{mutable_scope}}
protected_scope:
  - {{protected_scope}}
quality_gates:
  - command: {{quality_gate_command}}
    evidence: evidence/latest-test.json
verifier:
  type: test
  command: {{verifier_command}}
budget:
  max_iterations: 3
stop_conditions:
  - quality gates pass
handoff_conditions:
  - schema change required
rollback_policy: "Revert unsafe changes"
agents:
  planner:
    tools: [read, search]
    sandbox: read-only
  worker:
    tools: [read, search, edit, shell]
    sandbox: workspace-write
  verifier:
    tools: [read, search, shell]
    sandbox: read-only
    must_not_edit: true
  reviewer:
    tools: [read, search, shell]
    sandbox: read-only
    must_not_edit: true
stages:
  goal:
    roles: [planner, worker]
  context:
    roles: [planner, worker, researcher]
  plan:
    roles: [planner]
  act:
    roles: [worker]
  check:
    roles: [verifier]
  reflect:
    roles: [planner, verifier, reviewer]
  result:
    roles: [planner, verifier, reviewer]
tools:
  allowed:
    - read
    - search
    - apply_patch
    - shell
  denied:
    - network
    - secrets
    - destructive_git
    - external_write
permissions:
  filesystem:
    mutable_scope:
      - src/**
      - tests/**
    protected_scope:
      - migrations/**
      - secrets/**
  network:
    mode: off
    allowlist: []
  shell:
    allow:
      - pytest tests/auth
      - ruff check .
    deny_patterns:
      - rm -rf
      - git reset --hard
      - curl *|sh
```

- [ ] **Step 3: Run the focused test**

```bash
bash tests/test_loen_enforcement_hooks.sh
```

Expected now: failures remain for guard scripts not yet enforcing behavior, but parser/template assertions pass.

- [ ] **Step 4: Commit shared helpers**

```bash
git add plugins/loen/hooks/loen_common.py plugins/loen/assets/templates/loop.yaml
git commit -m "feat(loen): add enforcement hook helpers"
```

Expected: commit succeeds.

---

### Task 3: Implement Loop, Scope, Tool, Permission, and Evidence Guards

**Files:**
- Modify: `plugins/loen/hooks/hooks.json`
- Modify: `plugins/loen/hooks/loop-gate.py`
- Modify: `plugins/loen/hooks/scope-guard.py`
- Modify: `plugins/loen/hooks/tool-guard.py`
- Modify: `plugins/loen/hooks/permission-guard.py`
- Modify: `plugins/loen/hooks/evidence-gate.py`
- Test: `tests/test_loen_enforcement_hooks.sh`

- [ ] **Step 1: Register the enforcement hooks**

Set `plugins/loen/hooks/hooks.json` to:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Read|Grep|Glob|apply_patch|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"${PLUGIN_ROOT}/hooks/loop-gate.py\"",
            "timeout": 30,
            "statusMessage": "LoEn loop gate"
          },
          {
            "type": "command",
            "command": "python3 \"${PLUGIN_ROOT}/hooks/scope-guard.py\"",
            "timeout": 30,
            "statusMessage": "LoEn scope guard"
          },
          {
            "type": "command",
            "command": "python3 \"${PLUGIN_ROOT}/hooks/tool-guard.py\"",
            "timeout": 30,
            "statusMessage": "LoEn tool guard"
          },
          {
            "type": "command",
            "command": "python3 \"${PLUGIN_ROOT}/hooks/permission-guard.py\"",
            "timeout": 30,
            "statusMessage": "LoEn permission guard"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash|apply_patch|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"${PLUGIN_ROOT}/hooks/audit-writer.py\"",
            "timeout": 30,
            "statusMessage": "LoEn audit writer"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"${PLUGIN_ROOT}/hooks/evidence-gate.py\"",
            "timeout": 30,
            "statusMessage": "LoEn evidence gate"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Implement loop-gate**

Set `plugins/loen/hooks/loop-gate.py` to:

```python
#!/usr/bin/env python3
"""LoEn loop-state gate; reads LOEN_ARTIFACT_ROOT through loen_common."""
from loen_common import block_or_nudge, extract_paths, is_edit_event, is_off, parse_loop_yaml, read_event, read_loop_artifact, tool_input, topic, topic_dir

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
```

- [ ] **Step 3: Implement scope-guard**

Set `plugins/loen/hooks/scope-guard.py` to:

```python
#!/usr/bin/env python3
"""LoEn mutable/protected path scope guard; reads LOEN_ARTIFACT_ROOT through loen_common."""
from loen_common import block_or_nudge, extract_paths, is_edit_event, is_off, is_loen_topic_path, loop_policy, matches_any, read_event, read_loop_artifact, topic

def main() -> int:
  if is_off():
    return 0
  event = read_event()
  if not is_edit_event(event):
    return 0
  event_paths = extract_paths(event)
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
```

- [ ] **Step 4: Implement tool-guard**

Set `plugins/loen/hooks/tool-guard.py` to:

```python
#!/usr/bin/env python3
"""LoEn tool/role guard; reads LOEN_ARTIFACT_ROOT through loen_common."""
from loen_common import block_or_nudge, is_advisory, is_off, is_strict, loop_policy, read_event, read_loop_artifact, tool_class

def _policy_tool(tool: str) -> str:
  return "edit" if tool in {"edit", "apply_patch"} else tool

def main() -> int:
  if is_off():
    return 0
  event = read_event()
  read_loop_artifact()
  if not (is_advisory() or is_strict()):
    return 0

  policy = loop_policy()
  tool = tool_class(event)
  policy_tool = _policy_tool(tool)
  role = str(event.get("agent_role") or event.get("role") or "").strip()
  root_allowed = policy.get("tools", {}).get("allowed", [])
  if policy_tool == "edit":
    allowed_by_root = "apply_patch" in root_allowed or "edit" in root_allowed
  else:
    allowed_by_root = policy_tool in root_allowed
  if root_allowed and not allowed_by_root:
    return block_or_nudge(f"LoEn: tool class not allowed by loop policy: {tool}")

  agent = policy.get("agents", {}).get(role, {}) if role else {}
  stage = str(policy.get("current_stage") or policy.get("stage") or "").strip()
  stage_roles = policy.get("stages", {}).get(stage, {}).get("roles", [])
  if role and stage_roles and role not in stage_roles:
    return block_or_nudge(f"LoEn: role {role} is not allowed during stage {stage}")

  agent_tools = agent.get("tools", [])
  if agent.get("must_not_edit") is True and policy_tool == "edit":
    return block_or_nudge(f"LoEn: {role} must not edit in strict mode")
  if agent_tools and policy_tool not in agent_tools:
    return block_or_nudge(f"LoEn: role {role} cannot use tool class {tool}")
  return 0

if __name__ == "__main__":
  raise SystemExit(main())
```

- [ ] **Step 5: Implement permission-guard**

Set `plugins/loen/hooks/permission-guard.py` to:

```python
#!/usr/bin/env python3
"""LoEn shell and network permission guard; reads LOEN_ARTIFACT_ROOT through loen_common."""
import shlex
from urllib.parse import urlparse

from loen_common import block_or_nudge, command_matches, is_advisory, is_off, is_strict, loop_policy, read_event, read_loop_artifact, shell_command, tool_class

NETWORK_TOOLS = {"curl", "wget", "ssh", "scp", "nc"}

def _command_parts(command: str) -> list[str]:
  try:
    return shlex.split(command)
  except ValueError:
    return command.split()

def _token_basename(token: str) -> str:
  return token.rsplit("/", 1)[-1]

def _network_command_index(parts: list[str]) -> int | None:
  for index, part in enumerate(parts):
    for word in part.split():
      if _token_basename(word) in NETWORK_TOOLS:
        return index
  return None

def _network_target(command: str) -> str:
  parts = _command_parts(command)
  command_index = _network_command_index(parts)
  start = command_index + 1 if command_index is not None else 1
  for part in parts[start:]:
    if part.startswith("-"):
      continue
    parsed = urlparse(part)
    if parsed.hostname:
      return parsed.hostname
    if "." in part and "/" not in part:
      return part.split(":", 1)[0]
  return ""

def main() -> int:
  if is_off():
    return 0
  event = read_event()
  read_loop_artifact()
  if not (is_advisory() or is_strict()):
    return 0
  if tool_class(event) != "shell":
    return 0

  command = shell_command(event)
  policy = loop_policy().get("permissions", {})
  shell_policy = policy.get("shell", {})
  for pattern in shell_policy.get("deny_patterns", []):
    if command_matches(command, pattern) or command.startswith(pattern + " "):
      return block_or_nudge(f"LoEn: shell command denied by policy: {pattern}")
  if "git reset --hard" in command:
    return block_or_nudge("LoEn: destructive git command denied")
  network_mode = policy.get("network", {}).get("mode", "off")
  parts = _command_parts(command)
  is_network = _network_command_index(parts) is not None
  if is_network and network_mode == "off":
    return block_or_nudge("LoEn: network command denied by policy")
  allowlist = policy.get("network", {}).get("allowlist", [])
  if is_network and network_mode == "allowlist":
    target = _network_target(command)
    if not target or target not in allowlist:
      return block_or_nudge("LoEn: network target denied by allowlist")
  allow = shell_policy.get("allow", [])
  if allow and not any(command_matches(command, pattern) for pattern in allow):
    return block_or_nudge("LoEn: shell command not in allowlist")
  return 0

if __name__ == "__main__":
  raise SystemExit(main())
```

- [ ] **Step 6: Implement evidence-gate**

Set `plugins/loen/hooks/evidence-gate.py` to:

```python
#!/usr/bin/env python3
"""LoEn result/evidence gate; reads LOEN_ARTIFACT_ROOT through loen_common."""
from loen_common import BLOCK, block_or_nudge, is_off, is_strict, read_event, read_loop_artifact, stderr, topic_dir

def main() -> int:
  if is_off():
    return 0
  event = read_event()
  read_loop_artifact()
  verdict = str(event.get("verdict") or event.get("decision") or "").strip().lower()
  message = str(event.get("message") or "").lower()
  event_name = str(event.get("hook_event_name") or event.get("event") or "").strip().lower()
  final_marker = str(event.get("final") or event.get("is_final") or "").strip().lower()
  non_final = verdict in {"continue", "pending", "not_done", "skip"} or final_marker in {"false", "0", "no"}
  wants_done = (
    not event
    or (event_name == "stop" and not non_final)
    or verdict in {"done", "ok", "success", "final"}
    or any(word in message for word in ("done", "ok", "success", "final"))
  )
  if not wants_done:
    return 0

  base = topic_dir()
  missing = []
  for filename in ("5_check.md", "7_result.md", "verifier-verdict.md"):
    if not (base / filename).is_file():
      missing.append(filename)
  evidence_dir = base / "evidence"
  has_evidence = evidence_dir.is_dir() and any(path.is_file() for path in evidence_dir.iterdir())
  if not has_evidence:
    missing.append("evidence/*")
  if is_strict():
    worker_role = event.get("worker_role")
    verifier_role = event.get("verifier_role")
    if not worker_role or not verifier_role:
      stderr("LoEn: strict mode requires worker/verifier identity")
      return BLOCK
    if (worker_role and verifier_role and worker_role == verifier_role) or event.get("agent_role") == worker_role:
      stderr("LoEn: strict mode requires worker/verifier separation")
      return BLOCK
  if missing:
    return block_or_nudge("LoEn: done verdict missing evidence: " + ", ".join(missing))
  return 0

if __name__ == "__main__":
  raise SystemExit(main())
```

- [ ] **Step 7: Run the focused hook test**

```bash
bash tests/test_loen_enforcement_hooks.sh
```

Expected: `PASS` summary from `tests/helpers.sh`, exit code `0`.

- [ ] **Step 8: Commit guard implementation**

```bash
git add plugins/loen/hooks/hooks.json plugins/loen/hooks/loop-gate.py plugins/loen/hooks/scope-guard.py plugins/loen/hooks/tool-guard.py plugins/loen/hooks/permission-guard.py plugins/loen/hooks/evidence-gate.py
git commit -m "feat(loen): enforce loop hook policies"
```

Expected: commit succeeds.

---

### Task 4: Regenerate Audit Artifacts and Preserve the Task Log

**Files:**
- Modify: `plugins/loen/hooks/audit-writer.py`
- Read: `plugins/loen/hooks/loen_artifacts.py`
- Test: `tests/test_loen_enforcement_hooks.sh`

- [ ] **Step 1: Implement audit-writer using runtime artifact helpers**

Set `plugins/loen/hooks/audit-writer.py` to:

```python
#!/usr/bin/env python3
"""LoEn audit artifact writer; reads LOEN_ARTIFACT_ROOT through loen_common."""
import os
from pathlib import Path

from loen_artifacts import render_audit, upsert_todo_row, validate_topic_slug
from loen_common import is_off, read_loop_artifact, topic, topic_dir

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
```

- [ ] **Step 2: Ensure task-log upsert preserves existing row fields**

If `plugins/loen/hooks/loen_artifacts.py` does not already preserve existing task-log rows, update `upsert_todo_row()` to use this behavior:

```python
def upsert_todo_row(todo_path: Path, topic: str, opened: str | None = None) -> None:
  topic_name = validate_topic_slug(topic)
  opened_date = opened or date.today().isoformat()
  header = "| Topic | Status | Intent | Spec | Plan | Result | Opened | Closed | Notes |\n"
  separator = "|-------|--------|--------|------|------|--------|--------|--------|-------|\n"
  row = f"| {topic_name} | in-progress | n/a | n/a | n/a | - | {opened_date} |  | LoEn loop |\n"
  todo_path.parent.mkdir(parents=True, exist_ok=True)
  lines = todo_path.read_text(encoding="utf-8").splitlines(keepends=True) if todo_path.is_file() else [header, separator]
  needle = f"| {topic_name} |"
  for index, line in enumerate(lines):
    if line.startswith(needle):
      cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
      if len(cells) == 9:
        if cells[1] != "done":
          cells[1] = "in-progress"
        if not cells[6]:
          cells[6] = opened_date
        lines[index] = "| " + " | ".join(cells) + " |\n"
      else:
        lines[index] = row
      break
  else:
    lines.append(row)
  todo_path.write_text("".join(lines), encoding="utf-8")
```

- [ ] **Step 3: Run audit-focused fixture assertions**

```bash
bash tests/test_loen_enforcement_hooks.sh
```

Expected: audit-writer assertions pass, including idempotent `audit.html` regeneration and duplicate-free task-log update.

- [ ] **Step 4: Commit audit writer**

```bash
git add plugins/loen/hooks/audit-writer.py plugins/loen/hooks/loen_artifacts.py tests/test_loen_enforcement_hooks.sh
git commit -m "feat(loen): update audit from enforcement hooks"
```

Expected: commit succeeds. If `plugins/loen/hooks/loen_artifacts.py` did not change, omit it from `git add`.

---

### Task 5: Document Enforcement Boundaries

**Files:**
- Modify: `plugins/loen/docs/README.md`
- Modify: `plugins/loen/docs/architecture.md`
- Update via iwiki MCP: `loen-enforcement-hooks`
- Update via iwiki MCP: `loen-overview` if its layer table still says this layer is not implemented
- Test: `tests/test_loen_enforcement_hooks.sh`

- [ ] **Step 1: Update plugin README**

Append this section to `plugins/loen/docs/README.md` if equivalent text is not already present:

```markdown
## Enforcement Hooks

The enforcement layer turns the hook assets into deterministic local checks.
`LOEN_MODE=off` no-ops, `advisory` emits nudges without blocking, `enforce`
blocks missing loop state, stage-order violations, protected path edits, and
missing evidence, and `strict` adds tool, role, shell, network, and
worker/verifier separation checks.

Hook scripts read JSON events from stdin and repository-local loop state from
`LOEN_ARTIFACT_ROOT` plus `LOEN_TOPIC`. They do not call IDD, Superpowers,
chain-gate, or subjective review tools.
```

- [ ] **Step 2: Update plugin architecture docs**

Replace the `## Hook Assets` section in `plugins/loen/docs/architecture.md` with:

```markdown
## Hook Assets

Hook scripts are deterministic and read only JSON tool events plus LoEn topic
artifacts such as `docs/loen/<topic>/loop.yaml`. They are source-layer plugin
assets until a later icodex integration layer installs and enables the plugin,
but their behavior is implemented and fixture-tested in this repository.

The enforcement layer owns loop-state gating, mutable/protected path checks,
tool and role policy, shell and network policy, final evidence checks, and
audit regeneration. The hooks do not depend on IDD->SDD, Superpowers, or
frontmatter review state.
```

- [ ] **Step 3: Update iwiki documentation**

Use MCP tools, not shell commands:

```text
wiki_status
wiki_bind(read=["icodex"], write="icodex")
wiki_update_page(domain="icodex", slug="loen-enforcement-hooks", heading="Overview", new_body="<current implemented overview>", source="plugins/loen/hooks/hooks.json")
wiki_update_page(domain="icodex", slug="loen-enforcement-hooks", heading="Modes", new_body="<mode table matching this plan>", source="plugins/loen/hooks/hooks.json")
wiki_update_page(domain="icodex", slug="loen-enforcement-hooks", heading="Hook Responsibilities", new_body="<hook responsibility summary matching this plan>", source="plugins/loen/hooks/hooks.json")
wiki_update_page(domain="icodex", slug="loen-enforcement-hooks", heading="Validation", new_body="<focused fixture test summary>", source="tests/test_loen_enforcement_hooks.sh")
wiki_lint(domain="icodex")
```

Use this exact Overview body:

```markdown
LoEn enforcement hooks provide deterministic loop enforcement under `plugins/loen/hooks/`. This layer turns the source-layer hook assets into runtime checks while staying independent from IDD->SDD, Superpowers, and icodex launch-time wiring.

The hook set is `loop-gate.py`, `scope-guard.py`, `tool-guard.py`, `permission-guard.py`, `evidence-gate.py`, and `audit-writer.py`, with shared helpers in `loen_common.py` and plugin hook registration in `hooks.json`.
```

Use this exact Validation body:

```markdown
`tests/test_loen_enforcement_hooks.sh` is the focused JSON fixture suite for this layer. It covers runtime modes, active-loop enforcement, stage order, read-vs-write behavior, mutable/protected scope extraction, raw string tool input, shell and network policies, verifier/reviewer edit blocking, strict separation, evidence gates, idempotent audit generation, task-log preservation, and absence of chain-gate/IDD frontmatter dependencies.
```

- [ ] **Step 4: Run wiki lint**

Expected from `wiki_lint(domain="icodex")`: no broken refs, no stale pages for `loen-enforcement-hooks`; advisory long-lead or missing-overview lint elsewhere may remain if pre-existing.

- [ ] **Step 5: Commit docs**

```bash
git add plugins/loen/docs/README.md plugins/loen/docs/architecture.md
git commit -m "docs(loen): document enforcement hook layer"
```

Expected: commit succeeds. iwiki writes auto-commit the wiki base separately through MCP; do not run `wiki_index` after successful writes.

---

### Task 6: Verify Full Behavior and Close the Chain Result

**Files:**
- Read: `tests/test_loen_enforcement_hooks.sh`
- Read: `docs/superpowers/specs/2026-07-02-03-loen-enforcement-hooks-design.md`
- Read: `docs/superpowers/plans/2026-07-02-03-loen-enforcement-hooks.md`
- Update via check-chain: plan frontmatter and `docs/TODO.md`

- [ ] **Step 1: Run focused enforcement tests**

```bash
bash tests/test_loen_enforcement_hooks.sh
```

Expected: exit code `0`; final test summary reports no failures.

- [ ] **Step 2: Run all Bash tests**

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: exit code `0`. If unrelated pre-existing failures occur, capture the failing test names and run the focused LoEn suite again to preserve evidence for this layer.

- [ ] **Step 3: Check Python syntax for hook scripts**

```bash
python3 -m py_compile plugins/loen/hooks/*.py
```

Expected: exit code `0`, no syntax errors.

- [ ] **Step 4: Confirm no IDD dependency in LoEn hooks**

```bash
find plugins/loen/hooks -maxdepth 1 -type f -name '*.py' -print0 | xargs -0 grep -En 'chain-gate|IDD|SDD|docs/superpowers|frontmatter' || true
```

Expected: no output. Any output is a defect unless it appears only in this plan or unrelated docs, not in hook source files.

- [ ] **Step 5: Validate plan gate before result reconciliation**

```text
/check-chain plan docs/superpowers/plans/2026-07-02-03-loen-enforcement-hooks.md
```

Expected: `OK` or `OK (cached, hash match)`.

- [ ] **Step 6: Reconcile implementation against this plan**

```text
/check-chain result docs/superpowers/plans/2026-07-02-03-loen-enforcement-hooks.md
```

Expected: `OK`, `docs/TODO.md` row `03-loen-enforcement-hooks` changes to `done`, and the result tab in `docs/superpowers/reports/03-loen-enforcement-hooks-results.html` shows all planned tasks as done or already present.

- [ ] **Step 7: Final commit if check-chain changed local artifacts**

```bash
git add docs/TODO.md docs/superpowers/plans/2026-07-02-03-loen-enforcement-hooks.md docs/superpowers/reports/03-loen-enforcement-hooks-results.html
git commit -m "chore(loen): close enforcement hook chain"
```

Expected: commit succeeds if those files changed. If no files changed, `git status --short` should show no stage artifacts needing commit.

## Self-Review

- Spec coverage: Hook files, modes, contract extensions, hook responsibilities, tests, and acceptance criteria from the design are mapped to Tasks 1-6.
- Placeholder scan: No unresolved implementation placeholders are intentional. The string `docs/TODO.md` is the required project task-log filename.
- Type consistency: Public helper names in Task 2 match imports used by Tasks 3 and 4. Hook exit behavior uses `0` for allow/no-op and `2` for block.

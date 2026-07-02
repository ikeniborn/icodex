#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

hook_root="$ROOT/plugins/loen/hooks"
template="$ROOT/plugins/loen/assets/templates/loop.yaml"

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

assert_hook_exit() {
  local desc="$1" expected="$2" hook="$3" mode="$4" topic_value="$5" payload="$6" code=0
  run_hook "$hook" "$mode" "$topic_value" "$payload" || code=$?
  assert_eq "$desc" "$expected" "$code"
}

edit_payload='{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Update File: src/app.py\n@@\n-old\n+new\n*** End Patch\n"}}'
protected_patch='{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Update File: migrations/001.sql\n@@\n-old\n+new\n*** End Patch\n"}}'
topic_doc_write='{"tool_name":"Write","tool_input":{"file_path":"docs/loen/demo-topic/5_check.md","content":"ok"}}'
skipped_reflect_write='{"tool_name":"Write","tool_input":{"file_path":"docs/loen/demo-topic/6_reflect.md","content":"too early"}}'
test_edit='{"tool_name":"Edit","tool_input":{"file_path":"tests/test_demo.sh","old_string":"old","new_string":"new"}}'
shell_allow='{"tool_name":"Bash","tool_input":{"command":"pytest tests/auth"}}'
shell_deny='{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD"}}'
network_deny='{"tool_name":"Bash","tool_input":{"command":"curl https://example.com/file"}}'
verifier_edit='{"tool_name":"Edit","agent_role":"verifier","tool_input":{"file_path":"tests/test_demo.sh","old_string":"old","new_string":"new"}}'
done_payload='{"verdict":"done","agent_role":"verifier"}'
self_approval_payload='{"verdict":"done","agent_role":"verifier","worker_role":"same-agent","verifier_role":"same-agent"}'

assert_hook_exit "loop-gate off allows edit without topic" 0 "loop-gate.py" "off" "" "$edit_payload"
assert_hook_exit "loop-gate advisory allows edit without topic" 0 "loop-gate.py" "advisory" "" "$edit_payload"
assert_hook_exit "loop-gate enforce blocks edit without topic" 2 "loop-gate.py" "enforce" "" "$edit_payload"
assert_hook_exit "loop-gate strict blocks edit without topic" 2 "loop-gate.py" "strict" "" "$edit_payload"

assert_hook_exit "loop-gate blocks skipped stage artifact" 2 "loop-gate.py" "enforce" "$topic" "$skipped_reflect_write"

touch "$topic_dir/5_check.md"
assert_hook_exit "scope-guard allows LoEn topic artifact" 0 "scope-guard.py" "enforce" "$topic" "$topic_doc_write"
assert_hook_exit "scope-guard allows configured mutable scope from Edit" 0 "scope-guard.py" "enforce" "$topic" "$test_edit"
assert_hook_exit "scope-guard blocks protected path from patch" 2 "scope-guard.py" "enforce" "$topic" "$protected_patch"

assert_hook_exit "permission-guard allows configured shell command" 0 "permission-guard.py" "strict" "$topic" "$shell_allow"
assert_hook_exit "permission-guard blocks destructive git" 2 "permission-guard.py" "strict" "$topic" "$shell_deny"
assert_hook_exit "permission-guard blocks network command" 2 "permission-guard.py" "strict" "$topic" "$network_deny"

assert_hook_exit "tool-guard blocks verifier edits in strict" 2 "tool-guard.py" "strict" "$topic" "$verifier_edit"
assert_hook_exit "tool-guard allows worker edits in strict" 0 "tool-guard.py" "strict" "$topic" "$test_edit"

assert_hook_exit "evidence-gate blocks done without result evidence" 2 "evidence-gate.py" "enforce" "$topic" "$done_payload"
touch "$topic_dir/7_result.md" "$topic_dir/verifier-verdict.md"
mkdir -p "$topic_dir/evidence"
printf 'log\n' > "$topic_dir/evidence/run.log"
assert_hook_exit "evidence-gate allows done with evidence" 0 "evidence-gate.py" "enforce" "$topic" "$done_payload"
assert_hook_exit "evidence-gate blocks verifier self-approval in strict" 2 "evidence-gate.py" "strict" "$topic" "$self_approval_payload"

assert_hook_exit "audit-writer regenerates audit html" 0 "audit-writer.py" "advisory" "$topic" "$test_edit"
first_audit="$(cat "$topic_dir/audit.html" 2>/dev/null)"
assert_hook_exit "audit-writer regenerates audit html idempotently" 0 "audit-writer.py" "advisory" "$topic" "$test_edit"
second_audit="$(cat "$topic_dir/audit.html" 2>/dev/null)"
assert_eq "audit html is idempotent" "$first_audit" "$second_audit"
assert_contains "audit html names topic" "$second_audit" "demo-topic"
assert_contains "audit writer updates TODO row" "$(cat "$tmp/TODO.md" 2>/dev/null)" "| demo-topic | in-progress |"

hook_refs="$(find "$hook_root" -maxdepth 1 -type f -name '*.py' -print0 | xargs -0 grep -En 'chain-gate|IDD|SDD|docs/superpowers|frontmatter' 2>/dev/null || true)"
assert_eq "LoEn hooks do not depend on chain-gate or IDD frontmatter" "" "$hook_refs"

assert_contains "loop template includes agent policy" "$(cat "$template")" "agents:"
assert_contains "loop template includes tool policy" "$(cat "$template")" "tools:"
assert_contains "loop template includes permission policy" "$(cat "$template")" "permissions:"

finish

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

assert_hook_stderr_eq() {
  local desc="$1" expected="$2" hook="$3" mode="$4" topic_value="$5" payload="$6" expected_stderr="$7" code=0
  local stderr_file="$tmp/stderr-${desc//[^A-Za-z0-9]/_}.txt"
  run_hook_capture "$hook" "$mode" "$topic_value" "$payload" "$stderr_file" || code=$?
  assert_eq "$desc exit" "$expected" "$code"
  assert_eq "$desc stderr" "$expected_stderr" "$(cat "$stderr_file" 2>/dev/null)"
}

edit_payload='{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Update File: src/app.py\n@@\n-old\n+new\n*** End Patch\n"}}'
protected_patch='{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Update File: migrations/001.sql\n@@\n-old\n+new\n*** End Patch\n"}}'
raw_protected_patch='{"tool_name":"apply_patch","tool_input":"*** Begin Patch\n*** Update File: migrations/002.sql\n@@\n-old\n+new\n*** End Patch\n"}'
traversal_protected_patch='{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Update File: src/../migrations/001.sql\n@@\n-old\n+new\n*** End Patch\n"}}'
topic_doc_write='{"tool_name":"Write","tool_input":{"file_path":"docs/loen/demo-topic/5_check.md","content":"ok"}}'
skipped_reflect_write='{"tool_name":"Write","tool_input":{"file_path":"docs/loen/demo-topic/6_reflect.md","content":"too early"}}'
read_readme='{"tool_name":"Read","tool_input":{"file_path":"README.md"}}'
read_result_artifact='{"tool_name":"Read","tool_input":{"file_path":"docs/loen/demo-topic/7_result.md"}}'
test_edit='{"tool_name":"Edit","tool_input":{"file_path":"tests/test_demo.sh","old_string":"old","new_string":"new"}}'
outside_edit='{"tool_name":"Edit","tool_input":{"file_path":"outside/expanded.py","old_string":"old","new_string":"new"}}'
traversal_test_edit='{"tool_name":"Edit","tool_input":{"file_path":"tests/../tests/test_demo.sh","old_string":"old","new_string":"new"}}'
worker_edit='{"tool_name":"Edit","agent_role":"worker","tool_input":{"file_path":"tests/test_demo.sh","old_string":"old","new_string":"new"}}'
worker_patch='{"tool_name":"apply_patch","agent_role":"worker","tool_input":{"patch":"*** Begin Patch\n*** Update File: tests/test_demo.sh\n@@\n-old\n+new\n*** End Patch\n"}}'
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
raw_stage_jump_loop_yaml='{"tool_name":"apply_patch","tool_input":"*** Begin Patch\n*** Update File: docs/loen/demo-topic/loop.yaml\n@@\n-stage: check\n+stage: reflect\n*** End Patch\n"}'
absolute_test_edit="$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/tests/test_demo.sh","old_string":"old","new_string":"new"}}' "$ROOT")"
absolute_protected_patch="$(printf '{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\\n*** Update File: %s/migrations/001.sql\\n@@\\n-old\\n+new\\n*** End Patch\\n"}}' "$ROOT")"

assert_contains "hooks registry still present in enforcement layer" "$(cat "$hooks_json")" "LoEn loop gate"
pretool_matchers="$(python3 - "$hooks_json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for entry in data.get("hooks", {}).get("PreToolUse", []):
  print(entry.get("matcher", ""))
PY
)"
assert_contains "hooks registry PreToolUse matches Read" "$pretool_matchers" "Read"
assert_contains "hooks registry PreToolUse matches Grep" "$pretool_matchers" "Grep"
assert_contains "hooks registry PreToolUse matches Glob" "$pretool_matchers" "Glob"

assert_hook_exit "loop-gate off allows edit without topic" 0 "loop-gate.py" "off" "" "$edit_payload"
assert_hook_exit "loop-gate advisory allows edit without topic" 0 "loop-gate.py" "advisory" "" "$edit_payload"
assert_hook_stderr_eq "loop-gate advisory is quiet without topic" 0 "loop-gate.py" "advisory" "" "$edit_payload" ""
assert_hook_exit "loop-gate enforce allows edit without topic" 0 "loop-gate.py" "enforce" "" "$edit_payload"
assert_hook_exit "loop-gate strict allows edit without topic" 0 "loop-gate.py" "strict" "" "$edit_payload"

ln -s "$topic" "$artifact_root/current"
assert_hook_exit "scope-guard blocks current active topic protected path" 2 "scope-guard.py" "enforce" "" "$protected_patch"
assert_hook_exit "tool-guard blocks current active topic verifier edit" 2 "tool-guard.py" "strict" "" "$verifier_edit"
rm "$artifact_root/current"

assert_hook_exit "loop-gate blocks skipped stage artifact" 2 "loop-gate.py" "enforce" "$topic" "$skipped_reflect_write"
assert_hook_stderr_contains "loop-gate advisory nudges skipped stage artifact" 0 "loop-gate.py" "advisory" "$topic" "$skipped_reflect_write" "LoEn:"
assert_hook_exit "loop-gate blocks loop yaml stage jump" 2 "loop-gate.py" "enforce" "$topic" "$stage_jump_loop_yaml"
assert_hook_exit "loop-gate blocks raw patch loop yaml stage jump" 2 "loop-gate.py" "enforce" "$topic" "$raw_stage_jump_loop_yaml"
assert_hook_exit "loop-gate does not block reading future artifact in enforce" 0 "loop-gate.py" "enforce" "$topic" "$read_result_artifact"
assert_hook_exit "loop-gate does not block reading future artifact in strict" 0 "loop-gate.py" "strict" "$topic" "$read_result_artifact"

inactive_topic="inactive-topic"
inactive_dir="$artifact_root/$inactive_topic"
mkdir -p "$inactive_dir"
cat > "$inactive_dir/loop.yaml" <<'YAML'
topic: inactive-topic
status: done
stage: result
YAML
assert_hook_stderr_contains "loop-gate advisory nudges inactive loop" 0 "loop-gate.py" "advisory" "$inactive_topic" "$edit_payload" "LoEn:"
assert_hook_exit "loop-gate enforce blocks inactive loop" 2 "loop-gate.py" "enforce" "$inactive_topic" "$edit_payload"
assert_hook_exit "loop-gate strict blocks inactive loop" 2 "loop-gate.py" "strict" "$inactive_topic" "$edit_payload"

nostatus_topic="nostatus-topic"
nostatus_dir="$artifact_root/$nostatus_topic"
mkdir -p "$nostatus_dir"
cat > "$nostatus_dir/loop.yaml" <<'YAML'
topic: nostatus-topic
stage: act
YAML
assert_hook_stderr_contains "loop-gate advisory nudges missing status" 0 "loop-gate.py" "advisory" "$nostatus_topic" "$edit_payload" "LoEn:"
assert_hook_exit "loop-gate enforce blocks missing status" 2 "loop-gate.py" "enforce" "$nostatus_topic" "$edit_payload"

touch "$topic_dir/5_check.md"
assert_hook_exit "scope-guard allows read outside mutable scope in enforce" 0 "scope-guard.py" "enforce" "$topic" "$read_readme"
assert_hook_exit "scope-guard allows read outside mutable scope in strict" 0 "scope-guard.py" "strict" "$topic" "$read_readme"
assert_hook_exit "scope-guard allows LoEn topic artifact" 0 "scope-guard.py" "enforce" "$topic" "$topic_doc_write"
assert_hook_exit "scope-guard allows configured mutable scope from Edit" 0 "scope-guard.py" "enforce" "$topic" "$test_edit"
assert_hook_exit "scope-guard allows absolute mutable path" 0 "scope-guard.py" "enforce" "$topic" "$absolute_test_edit"
assert_hook_exit "scope-guard allows normalized mutable traversal path" 0 "scope-guard.py" "enforce" "$topic" "$traversal_test_edit"
assert_hook_exit "scope-guard blocks protected path from patch" 2 "scope-guard.py" "enforce" "$topic" "$protected_patch"
assert_hook_stderr_contains "scope-guard blocks absolute protected path" 2 "scope-guard.py" "enforce" "$topic" "$absolute_protected_patch" "protected path"
assert_hook_stderr_contains "scope-guard blocks protected traversal path" 2 "scope-guard.py" "enforce" "$topic" "$traversal_protected_patch" "protected path"
assert_hook_exit "scope-guard blocks raw string protected patch" 2 "scope-guard.py" "enforce" "$topic" "$raw_protected_patch"
assert_hook_stderr_contains "scope-guard advisory nudges protected path" 0 "scope-guard.py" "advisory" "$topic" "$protected_patch" "LoEn:"

cp "$topic_dir/loop.yaml" "$topic_dir/loop.yaml.valid"
python3 - "$topic_dir/loop.yaml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(text.replace("      - tests/**", "      - tests/**\n      \t- outside/**"), encoding="utf-8")
PY
assert_hook_stderr_contains "scope-guard rejects mixed-tab scope expansion when invoked directly" 2 "scope-guard.py" "enforce" "$topic" "$outside_edit" "invalid canonical authority"
assert_hook_stderr_contains "permission-guard rejects malformed canonical authority" 2 "permission-guard.py" "strict" "$topic" "$shell_allow" "invalid canonical authority"
assert_hook_stderr_contains "tool-guard rejects malformed canonical authority" 2 "tool-guard.py" "strict" "$topic" "$verifier_read" "invalid canonical authority"
mv "$topic_dir/loop.yaml.valid" "$topic_dir/loop.yaml"

assert_malformed_runtime_authority() {
  local name="$1"
  local hook="$2"
  local mode="$3"
  local payload="$4"
  local old="$5"
  local new="$6"
  cp "$topic_dir/loop.yaml" "$topic_dir/loop.yaml.valid"
  python3 - "$topic_dir/loop.yaml" "$old" "$new" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(text.replace(sys.argv[2], sys.argv[3], 1), encoding="utf-8")
PY
  assert_hook_stderr_contains "$name" 2 "$hook" "$mode" "$topic" "$payload" "invalid canonical authority"
  mv "$topic_dir/loop.yaml.valid" "$topic_dir/loop.yaml"
}

assert_malformed_runtime_authority "loop-gate rejects duplicate status" "loop-gate.py" "enforce" "$edit_payload" "status: active" $'status: done\nstatus: active'
assert_malformed_runtime_authority "loop-gate rejects tab-prefixed status override" "loop-gate.py" "enforce" "$edit_payload" "status: active" $'status: active\n\tstatus: done'
assert_malformed_runtime_authority "tool-guard rejects duplicate tools allowed" "tool-guard.py" "strict" "$verifier_read" "  allowed:" $'  allowed: [read]\n  allowed:'
assert_malformed_runtime_authority "tool-guard rejects mixed-indent tools authority" "tool-guard.py" "strict" "$verifier_read" "  allowed:" $' \tallowed: [read]\n  allowed:'
assert_malformed_runtime_authority "scope-guard rejects duplicate permission scope expansion" "scope-guard.py" "enforce" "$outside_edit" $'    mutable_scope:\n      - src/**\n      - tests/**' $'    mutable_scope:\n      - outside/**\n    mutable_scope:\n      - src/**\n      - tests/**'

cp "$topic_dir/loop.yaml" "$topic_dir/loop.yaml.valid"
python3 - "$topic_dir/loop.yaml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("    - search\n    - apply_patch", "    - search\n  metadata:\n    - edit", 1)
path.write_text(text, encoding="utf-8")
PY
assert_hook_stderr_contains "tool-guard ignores list item below unknown sibling" 2 "tool-guard.py" "strict" "$topic" "$test_edit" "tool class not allowed"
mv "$topic_dir/loop.yaml.valid" "$topic_dir/loop.yaml"

cp "$topic_dir/loop.yaml" "$topic_dir/loop.yaml.valid"
python3 - "$topic_dir/loop.yaml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("      - tests/**", "      - tests/**\n    metadata:\n      - outside/**", 1)
path.write_text(text, encoding="utf-8")
PY
assert_hook_stderr_contains "scope-guard ignores list item below unknown sibling" 2 "scope-guard.py" "enforce" "$topic" "$outside_edit" "outside mutable scope"
mv "$topic_dir/loop.yaml.valid" "$topic_dir/loop.yaml"

cp "$topic_dir/loop.yaml" "$topic_dir/loop.yaml.valid"
python3 - "$topic_dir/loop.yaml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("    - search\n    - apply_patch", "    - search\n  metadata\n    - edit", 1)
path.write_text(text, encoding="utf-8")
PY
assert_hook_stderr_contains "tool-guard rejects malformed sibling list attachment" 2 "tool-guard.py" "strict" "$topic" "$test_edit" "invalid canonical authority"
mv "$topic_dir/loop.yaml.valid" "$topic_dir/loop.yaml"

cp "$topic_dir/loop.yaml" "$topic_dir/loop.yaml.valid"
python3 - "$topic_dir/loop.yaml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("      - tests/**", "      - tests/**\n    metadata\n      - outside/**", 1)
path.write_text(text, encoding="utf-8")
PY
assert_hook_stderr_contains "scope-guard rejects malformed sibling list attachment" 2 "scope-guard.py" "enforce" "$topic" "$outside_edit" "invalid canonical authority"
mv "$topic_dir/loop.yaml.valid" "$topic_dir/loop.yaml"

assert_malformed_runtime_authority "tool-guard rejects odd-indent unknown mapping" "tool-guard.py" "strict" "$test_edit" $'    - search\n    - apply_patch' $'    - search\n   metadata:\n    - edit'
assert_malformed_runtime_authority "scope-guard rejects odd-indent unknown mapping" "scope-guard.py" "enforce" "$outside_edit" $'      - src/**\n      - tests/**' $'      - src/**\n     metadata:\n      - outside/**'

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
assert_hook_stderr_contains "permission-guard advisory nudges bash -c network command" 0 "permission-guard.py" "advisory" "$topic" "$network_deny_bash_c" "network command denied"
assert_hook_stderr_contains "permission-guard advisory nudges raw string deny pattern" 0 "permission-guard.py" "advisory" "$topic" "$raw_shell_deny_pattern" "denied by policy"

assert_hook_exit "tool-guard blocks verifier edits in strict" 2 "tool-guard.py" "strict" "$topic" "$verifier_edit"
assert_hook_exit "tool-guard blocks reviewer edits in strict" 2 "tool-guard.py" "strict" "$topic" "$reviewer_edit"
assert_hook_exit "tool-guard enforce does not block strict-only role policy" 0 "tool-guard.py" "enforce" "$topic" "$verifier_edit"
assert_hook_exit "tool-guard blocks worker edit at check stage in strict" 2 "tool-guard.py" "strict" "$topic" "$worker_edit"
assert_hook_exit "tool-guard blocks worker shell at check stage in strict" 2 "tool-guard.py" "strict" "$topic" "$worker_shell"
assert_hook_exit "tool-guard allows verifier shell at check stage in strict" 0 "tool-guard.py" "strict" "$topic" "$verifier_shell"
assert_hook_exit "tool-guard allows verifier read at check stage in strict" 0 "tool-guard.py" "strict" "$topic" "$verifier_read"
assert_hook_stderr_contains "tool-guard advisory nudges disallowed stage role" 0 "tool-guard.py" "advisory" "$topic" "$worker_shell" "LoEn:"
assert_hook_stderr_contains "tool-guard advisory nudges verifier edits" 0 "tool-guard.py" "advisory" "$topic" "$verifier_edit" "LoEn:"

assert_hook_exit "evidence-gate blocks empty stop without evidence" 2 "evidence-gate.py" "enforce" "$topic" "{}"
assert_hook_stderr_contains "evidence-gate advisory nudges empty stop without evidence" 0 "evidence-gate.py" "advisory" "$topic" "{}" "LoEn:"
assert_hook_exit "evidence-gate blocks metadata stop without evidence" 2 "evidence-gate.py" "enforce" "$topic" "$metadata_stop_payload"
assert_hook_stderr_contains "evidence-gate advisory nudges metadata stop without evidence" 0 "evidence-gate.py" "advisory" "$topic" "$metadata_stop_payload" "LoEn:"
assert_hook_exit "evidence-gate blocks done without result evidence" 2 "evidence-gate.py" "enforce" "$topic" "$done_payload"
assert_hook_exit "evidence-gate blocks success message without result evidence" 2 "evidence-gate.py" "enforce" "$topic" "$success_message_payload"
assert_hook_stderr_contains "evidence-gate advisory nudges missing evidence" 0 "evidence-gate.py" "advisory" "$topic" "$success_message_payload" "LoEn:"
touch "$topic_dir/7_result.md" "$topic_dir/verifier-verdict.md"
mkdir -p "$topic_dir/evidence"
printf 'log\n' > "$topic_dir/evidence/run.log"
assert_hook_exit "evidence-gate allows done with evidence" 0 "evidence-gate.py" "enforce" "$topic" "$done_payload"
assert_hook_exit "evidence-gate strict blocks missing separation fields" 2 "evidence-gate.py" "strict" "$topic" "$done_payload"
assert_hook_exit "evidence-gate blocks verifier self-approval in strict" 2 "evidence-gate.py" "strict" "$topic" "$self_approval_payload"
assert_hook_exit "evidence-gate strict allows separated verifier" 0 "evidence-gate.py" "strict" "$topic" "$separated_done_payload"

assert_hook_exit "audit-writer off no-ops" 0 "audit-writer.py" "off" "$topic" "$test_edit"
assert_eq "audit-writer off skips audit html" "" "$(cat "$topic_dir/audit.html" 2>/dev/null || true)"
assert_eq "audit-writer off skips TODO row" "" "$(cat "$tmp/TODO.md" 2>/dev/null || true)"
assert_hook_exit "audit-writer regenerates audit html" 0 "audit-writer.py" "advisory" "$topic" "$test_edit"
first_audit="$(cat "$topic_dir/audit.html" 2>/dev/null)"
assert_hook_exit "audit-writer regenerates audit html idempotently" 0 "audit-writer.py" "advisory" "$topic" "$test_edit"
second_audit="$(cat "$topic_dir/audit.html" 2>/dev/null)"
assert_eq "audit html is idempotent" "$first_audit" "$second_audit"
assert_contains "audit html names topic" "$second_audit" "demo-topic"
assert_contains "audit writer updates TODO row" "$(cat "$tmp/TODO.md" 2>/dev/null)" "| demo-topic | in-progress |"

preserve_topic="preserve-topic"
preserve_dir="$artifact_root/$preserve_topic"
mkdir -p "$preserve_dir"
cat > "$preserve_dir/loop.yaml" <<'YAML'
topic: preserve-topic
status: active
stage: act
YAML
cat > "$tmp/TODO.md" <<'MD'
| Topic | Status | Intent | Spec | Plan | Result | Opened | Closed | Notes |
|---|---|---|---|---|---|---|---|---|
| preserve-topic | review | ✓ | ✓ | ✓ | OK | 2026-07-02 |  | Keep this note |
MD
assert_hook_exit "audit-writer preserves existing TODO row fields" 0 "audit-writer.py" "advisory" "$preserve_topic" "$test_edit"
preserved_row="$(grep -F '| preserve-topic |' "$tmp/TODO.md" 2>/dev/null || true)"
assert_contains "audit writer preserves TODO intent" "$preserved_row" "| preserve-topic | in-progress | ✓ | ✓ | ✓ | OK | 2026-07-02 |  | Keep this note |"

hook_refs="$(find "$hook_root" -maxdepth 1 -type f -name '*.py' -print0 | xargs -0 grep -En 'chain-gate|IDD|SDD|docs/superpowers|frontmatter' 2>/dev/null || true)"
assert_eq "LoEn hooks do not depend on chain-gate or IDD frontmatter" "" "$hook_refs"

assert_contains "loop template includes agent policy" "$(cat "$template")" "agents:"
assert_contains "loop template includes reviewer policy" "$(cat "$template")" "reviewer:"
assert_contains "loop template includes stage policy" "$(cat "$template")" "stages:"
assert_contains "loop template includes tool policy" "$(cat "$template")" "tools:"
assert_contains "loop template includes permission policy" "$(cat "$template")" "permissions:"

act_topic="act-topic"
act_dir="$artifact_root/$act_topic"
mkdir -p "$act_dir"
cat > "$act_dir/loop.yaml" <<'YAML'
topic: act-topic
status: active
stage: act
agents:
  worker:
    tools: [read, search, edit, shell]
    sandbox: workspace-write
stages:
  act:
    roles: [worker]
tools:
  allowed:
    - read
    - search
    - apply_patch
    - shell
YAML
assert_hook_exit "tool-guard allows worker edit at act stage in strict" 0 "tool-guard.py" "strict" "$act_topic" "$worker_edit"
assert_hook_exit "tool-guard allows worker apply_patch at act stage in strict" 0 "tool-guard.py" "strict" "$act_topic" "$worker_patch"

allow_topic="allow-topic"
allow_dir="$artifact_root/$allow_topic"
mkdir -p "$allow_dir"
cat > "$allow_dir/loop.yaml" <<'YAML'
topic: allow-topic
status: active
stage: check
permissions:
  network:
    mode: allowlist
    allowlist:
      - allowed.example.com
  shell:
    allow: []
    deny_patterns: []
YAML
network_allowed='{"tool_name":"Bash","tool_input":{"command":"curl https://allowed.example.com/file"}}'
network_not_allowed='{"tool_name":"Bash","tool_input":{"command":"curl https://blocked.example.com/file"}}'
assert_hook_exit "permission-guard allows allowlisted network target" 0 "permission-guard.py" "strict" "$allow_topic" "$network_allowed"
assert_hook_exit "permission-guard blocks network target outside allowlist" 2 "permission-guard.py" "strict" "$allow_topic" "$network_not_allowed"

empty_allow_topic="empty-allow-topic"
empty_allow_dir="$artifact_root/$empty_allow_topic"
mkdir -p "$empty_allow_dir"
cat > "$empty_allow_dir/loop.yaml" <<'YAML'
topic: empty-allow-topic
status: active
stage: check
permissions:
  network:
    mode: allowlist
    allowlist: []
  shell:
    allow: []
    deny_patterns: []
YAML
assert_hook_exit "permission-guard blocks network when allowlist is empty" 2 "permission-guard.py" "strict" "$empty_allow_topic" "$network_not_allowed"

finish

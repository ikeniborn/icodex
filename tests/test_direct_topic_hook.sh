#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

HOOK="$ROOT/.codex-isolated/hooks/direct-topic.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

project="$tmp/project"
home="$tmp/home"
mkdir -p "$project/docs/profiles" "$home/profiles"
git -C "$project" init -q -b main
git -C "$project" config user.email test@example.com
git -C "$project" config user.name Test
cp "$ROOT/.codex-isolated/profiles/registry.yaml" "$home/profiles/registry.yaml"

run_hook() { # <payload>
  env -i PATH=/usr/bin:/bin LC_ALL=C CODEX_HOME="$home" ICODEX_ROOT="$ROOT" \
    python3 "$HOOK" <<<"$1"
}

topic_payload="$(python3 - "$project" <<'PY'
import json
import sys
print(json.dumps({
    "hook_event_name": "UserPromptSubmit",
    "session_id": "session-1",
    "cwd": sys.argv[1],
    "model": "gpt-5.6-terra",
    "prompt": "@topic direct-hook-test",
}))
PY
)"

assert_exit "direct topic hook exists" 0 test -f "$HOOK"
topic_result="$(run_hook "$topic_payload")"
assert_exit "topic prompt creates topic profile" 0 test -f "$project/docs/profiles/direct-hook-test.yaml"
assert_contains "topic profile is approved by explicit topic command" "$(cat "$project/docs/profiles/direct-hook-test.yaml")" 'status: approved'
assert_contains "topic profile selects engineering" "$(cat "$project/docs/profiles/direct-hook-test.yaml")" '      - engineering'
assert_exit "topic prompt persists local session mapping" 0 test -f "$home/state/direct-topics/session-1.json"
assert_contains "topic prompt returns model-visible context" "$topic_result" 'direct-hook-test'

continue_payload="$(python3 - "$project" <<'PY'
import json
import sys
print(json.dumps({
    "hook_event_name": "UserPromptSubmit",
    "session_id": "session-1",
    "cwd": sys.argv[1],
    "model": "gpt-5.6-terra",
    "prompt": "гоу",
}))
PY
)"
continue_result="$(run_hook "$continue_payload")"
assert_contains "any next prompt continues matching topic model" "$continue_result" 'Direct topic direct-hook-test is active'

mismatch_payload="${continue_payload/gpt-5.6-terra/gpt-5.6-sol}"
mismatch_result="$(run_hook "$mismatch_payload")"
assert_contains "mismatched model blocks any next prompt" "$mismatch_result" '"decision": "block"'
assert_contains "mismatched model names required model" "$mismatch_result" 'gpt-5.6-terra'

pretool_payload="$(python3 - "$project" <<'PY'
import json
import sys
print(json.dumps({
    "hook_event_name": "PreToolUse",
    "session_id": "session-1",
    "cwd": sys.argv[1],
    "model": "gpt-5.6-sol",
    "tool_name": "Write",
    "tool_input": {"file_path": "work.txt"},
}))
PY
)"
pretool_result="$(env -i PATH=/usr/bin:/bin LC_ALL=C CODEX_HOME="$home" ICODEX_ROOT="$ROOT" python3 "$ROOT/.codex-isolated/hooks/profile-transition.py" <<<"$pretool_payload")"
assert_contains "mismatched direct model blocks protected tool" "$pretool_result" '"permissionDecision": "deny"'
assert_contains "protected tool denial names direct topic model" "$pretool_result" 'gpt-5.6-terra'

finish

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
cp "$ROOT/docs/profiles/README.md" "$project/docs/profiles/README.md"
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
assert_contains "topic profile contains direct task only" "$(cat "$project/docs/profiles/direct-hook-test.yaml")" '  - id: direct-work'
assert_eq "topic profile has exact direct task IDs" "direct-work" "$(awk '/^  - id: / { print $3 }' "$project/docs/profiles/direct-hook-test.yaml" | paste -sd, -)"
assert_exit "topic profile omits intent selection task" 0 sh -c '! grep -q "  - id: intent-profile-selection" "$1"' _ "$project/docs/profiles/direct-hook-test.yaml"
assert_exit "topic profile omits full implementation task" 0 sh -c '! grep -q "  - id: implementation" "$1"' _ "$project/docs/profiles/direct-hook-test.yaml"
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

failed_helper_project="$tmp/failed-helper-project"
mkdir -p "$failed_helper_project/docs/profiles"
cp "$ROOT/docs/profiles/README.md" "$failed_helper_project/docs/profiles/README.md"
git -C "$failed_helper_project" init -q -b main
failed_helper_payload="$(python3 - "$failed_helper_project" <<'PY'
import json
import sys
print(json.dumps({
    "hook_event_name": "UserPromptSubmit",
    "session_id": "session-helper-failure",
    "cwd": sys.argv[1],
    "model": "gpt-5.6-terra",
    "prompt": "@topic helper-failure",
}))
PY
)"
failed_helper_result="$(env -i PATH=/usr/bin:/bin LC_ALL=C CODEX_HOME="$home" ICODEX_ROOT="$tmp/missing-root" python3 "$HOOK" <<<"$failed_helper_payload")"
assert_contains "manifest helper failure blocks topic activation" "$failed_helper_result" '"decision": "block"'
assert_contains "manifest helper failure names cause" "$failed_helper_result" 'ICODEX_ROOT does not match installed hook location'
assert_contains "manifest helper failure names remediation" "$failed_helper_result" 'Verify ICODEX_ROOT'
assert_exit "manifest helper failure writes no topic profile" 0 test ! -e "$failed_helper_project/docs/profiles/helper-failure.yaml"

untrusted_root="$tmp/untrusted-root"
untrusted_marker="$tmp/untrusted-helper-ran"
mkdir -p "$untrusted_root/lib/profile"
printf '%s\n' 'from pathlib import Path' "Path('$untrusted_marker').write_text('ran')" > "$untrusted_root/lib/profile/manifest.py"
untrusted_result="$(env -i PATH=/usr/bin:/bin LC_ALL=C CODEX_HOME="$home" ICODEX_ROOT="$untrusted_root" python3 "$HOOK" <<<"$failed_helper_payload")"
assert_contains "untrusted helper root blocks topic activation" "$untrusted_result" 'ICODEX_ROOT does not match installed hook location'
assert_exit "untrusted helper cannot execute" 0 test ! -e "$untrusted_marker"

hostile_python="$tmp/hostile-python"
hostile_marker="$tmp/hostile-python-ran"
hostile_project="$tmp/hostile-python-project"
mkdir -p "$hostile_python" "$hostile_project/docs/profiles"
cp "$ROOT/docs/profiles/README.md" "$hostile_project/docs/profiles/README.md"
git -C "$hostile_project" init -q -b main
printf '%s\n' 'from pathlib import Path' "Path('$hostile_marker').write_text('ran')" > "$hostile_python/sitecustomize.py"
hostile_payload="$(python3 - "$hostile_project" <<'PY'
import json
import sys
print(json.dumps({
    "hook_event_name": "UserPromptSubmit",
    "session_id": "session-hostile-python",
    "cwd": sys.argv[1],
    "model": "gpt-5.6-terra",
    "prompt": "@topic hostile-python-env",
}))
PY
)"
env -i PATH=/usr/bin:/bin LC_ALL=C CODEX_HOME="$home" ICODEX_ROOT="$ROOT" PYTHONPATH="$hostile_python" \
  python3 -S "$HOOK" <<<"$hostile_payload" >/dev/null
assert_exit "hostile Python environment is not inherited by helper" 0 test ! -e "$hostile_marker"

assert_exit "manifest helper timeout is bounded and actionable" 0 python3 - "$HOOK" <<'PY'
import importlib.util
import subprocess
import sys

spec = importlib.util.spec_from_file_location("direct_topic", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def timeout(*args, **kwargs):
    assert kwargs["timeout"] == 5
    assert kwargs["stderr"] is subprocess.DEVNULL
    assert "PYTHONPATH" not in kwargs["env"]
    raise subprocess.TimeoutExpired(args[0], kwargs["timeout"])

module.subprocess.run = timeout
try:
    module._run_manifest(["helper"], "bootstrap")
except ValueError as error:
    assert str(error) == "shared manifest helper bootstrap timed out after 5 seconds"
else:
    raise AssertionError("expected timeout failure")
PY

finish

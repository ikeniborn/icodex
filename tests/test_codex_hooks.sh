#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

REDACT_HOOK="$ROOT/.codex-isolated/hooks/redact-secrets.py"
GWT_HOOK="$ROOT/.codex-isolated/hooks/gwt-gate.py"
HOOKS_JSON="$ROOT/.codex-isolated/hooks.json"

capture_hook() { # <hook> <json>
  local hook="$1" payload="$2"
  local out err code
  out="$(mktemp)"
  err="$(mktemp)"
  printf '%s' "$payload" | python3 "$hook" >"$out" 2>"$err"
  code=$?
  printf '%s\n%s\n%s' "$code" "$(cat "$out")" "$(cat "$err")"
  rm -f "$out" "$err"
}

assert_exit "redact hook exists" 0 test -f "$REDACT_HOOK"
assert_exit "GWT hook exists" 0 test -f "$GWT_HOOK"
assert_exit "hooks json exists" 0 test -f "$HOOKS_JSON"

secret_payload='{"tool_name":"Bash","tool_input":{"command":"export OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz123456"}}'
secret_result="$(capture_hook "$REDACT_HOOK" "$secret_payload")"
secret_code="$(sed -n '1p' <<<"$secret_result")"
assert_eq "redact hook blocks secrets in bash commands" "2" "$secret_code"
assert_contains "redact hook explains secret block" "$secret_result" "secret"

patch_secret_payload='{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Add File: safe.txt\n+token=ghp_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKL123456\n*** End Patch\n"}}'
patch_secret_result="$(capture_hook "$REDACT_HOOK" "$patch_secret_payload")"
patch_secret_code="$(sed -n '1p' <<<"$patch_secret_result")"
assert_eq "redact hook blocks secrets in patches" "2" "$patch_secret_code"

hooks_config="$(cat "$HOOKS_JSON" 2>/dev/null || true)"
assert_contains "hooks json wires PreToolUse" "$hooks_config" '"PreToolUse"'
assert_contains "hooks json wires redact hook" "$hooks_config" 'redact-secrets.py'
assert_contains "hooks json wires GWT gate" "$hooks_config" 'gwt-gate.py'
assert_contains "hooks json matches GWT context" "$hooks_config" 'wiki_spec_context'
assert_contains "hooks json matches GWT mutation" "$hooks_config" 'wiki_update_page'
assert_contains "hooks json matches Bash" "$hooks_config" 'Bash'
assert_contains "hooks json matches apply_patch" "$hooks_config" 'apply_patch'

check_content_heredocs() {
  python3 - "$REDACT_HOOK" <<'END'
import json
import subprocess
import sys

token = 'sk-proj-' + 'A' * 36
for language, body in [('python3', 'print(' + repr(token) + ')'), ('bash', 'echo ' + repr(token))]:
    command = language + " <<'EOF'\n" + body + '\nEOF'
    payload = {'tool_name': 'Bash', 'tool_input': {'command': command}}
    result = subprocess.run([sys.executable, sys.argv[1]], input=json.dumps(payload), text=True, capture_output=True, timeout=10)
    assert result.returncode == 2
    assert 'secret_content' in result.stderr
    assert token not in result.stdout + result.stderr
END
}
assert_exit "content hook blocks secrets in interpreter heredocs" 0 check_content_heredocs

finish

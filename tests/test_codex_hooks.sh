#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

BLOCK_HOOK="$ROOT/.codex-isolated/hooks/block-secrets.py"
REDACT_HOOK="$ROOT/.codex-isolated/hooks/redact-secrets.py"
HOOKS_JSON="$ROOT/.codex-isolated/hooks.json"

run_hook() { # <hook> <json>
  local hook="$1" payload="$2"
  printf '%s' "$payload" | python3 "$hook"
}

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

assert_exit "block hook exists" 0 test -f "$BLOCK_HOOK"
assert_exit "redact hook exists" 0 test -f "$REDACT_HOOK"
assert_exit "hooks json exists" 0 test -f "$HOOKS_JSON"

safe_payload='{"tool_name":"Bash","tool_input":{"command":"cat .env.example"}}'
assert_exit "block hook allows safe env templates" 0 run_hook "$BLOCK_HOOK" "$safe_payload"

blocked_path_payload='{"tool_name":"Bash","tool_input":{"command":"cat .env"}}'
blocked_path_result="$(capture_hook "$BLOCK_HOOK" "$blocked_path_payload")"
blocked_path_code="$(sed -n '1p' <<<"$blocked_path_result")"
assert_eq "block hook blocks sensitive bash paths" "2" "$blocked_path_code"
assert_contains "block hook explains blocked path" "$blocked_path_result" "sensitive"

patch_path_payload='{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Add File: .env\n+TOKEN=placeholder\n*** End Patch\n"}}'
patch_path_result="$(capture_hook "$BLOCK_HOOK" "$patch_path_payload")"
patch_path_code="$(sed -n '1p' <<<"$patch_path_result")"
assert_eq "block hook blocks sensitive patch targets" "2" "$patch_path_code"

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
assert_contains "hooks json wires block hook" "$hooks_config" 'block-secrets.py'
assert_contains "hooks json wires redact hook" "$hooks_config" 'redact-secrets.py'
assert_contains "hooks json matches Bash" "$hooks_config" 'Bash'
assert_contains "hooks json matches apply_patch" "$hooks_config" 'apply_patch'

finish

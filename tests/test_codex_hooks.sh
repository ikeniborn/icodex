#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

GWT_HOOK="$ROOT/.codex-isolated/hooks/gwt-gate.py"
HOOKS_JSON="$ROOT/.codex-isolated/hooks.json"

assert_exit "GWT hook exists" 0 test -f "$GWT_HOOK"
assert_exit "hooks json exists" 0 test -f "$HOOKS_JSON"

hooks_config="$(cat "$HOOKS_JSON" 2>/dev/null || true)"
assert_contains "hooks json wires PreToolUse" "$hooks_config" '"PreToolUse"'
assert_contains "hooks json wires GWT gate" "$hooks_config" 'gwt-gate.py'
assert_contains "hooks json matches GWT context" "$hooks_config" 'wiki_spec_context'
assert_contains "hooks json matches GWT mutation" "$hooks_config" 'wiki_update_page'

finish

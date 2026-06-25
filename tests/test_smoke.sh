#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

# --help exits 0 and prints usage
out="$("$ROOT/icodex.sh" --help)"; code=$?
assert_eq       "help exit 0" "0" "$code"
assert_contains "help usage"  "$out" "Usage:"

# --version exits 0 and names icodex even when codex isn't installed
out="$("$ROOT/icodex.sh" --version 2>/dev/null)"; code=$?
assert_eq       "version exit 0" "0" "$code"
assert_contains "version names icodex" "$out" "icodex"

# launch guard: launch_codex returns 1 when the binary is absent
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/launcher/launch.sh"
ICODEX_BIN="/nonexistent/codex"
assert_exit "launch guard -> 1" 1 launch_codex --help

finish

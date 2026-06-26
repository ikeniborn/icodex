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

# invoking via a symlink must resolve modules from the real script dir
td="$(mktemp -d)"
ln -s "$ROOT/icodex.sh" "$td/icodex"
out="$("$td/icodex" --help 2>&1)"; code=$?
assert_eq       "symlink invocation exit 0" "0" "$code"
assert_contains "symlink resolves modules"  "$out" "Usage:"
rm -rf "$td"

# launch guard: launch_codex returns 1 when the binary is absent
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/launcher/launch.sh"
ICODEX_BIN="/nonexistent/codex"
assert_exit "launch guard -> 1" 1 launch_codex --help

# icodex.sh must source the plugin module and call ensure_superpowers_wiring
assert_eq "sources plugin module" "1" \
  "$(grep -c 'plugin/superpowers' "$ROOT/icodex.sh")"
assert_eq "calls wiring on launch" "1" \
  "$(grep -c 'ensure_superpowers_wiring' "$ROOT/icodex.sh")"

# install/update branch must NOT call the wiring (binary-only): the single-line
# install)/update) case branches must contain zero ensure_superpowers_wiring calls
assert_eq "install branch binary-only" "0" \
  "$(grep -E 'install\)|update\)' "$ROOT/icodex.sh" | grep -c ensure_superpowers_wiring)"

finish

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

# icodex.sh must source launch-time modules and call launch-time wiring
assert_eq "sources permissions module" "1" \
  "$(grep -c 'config/permissions' "$ROOT/icodex.sh")"
assert_eq "sources plugin module" "1" \
  "$(grep -c 'plugin/superpowers' "$ROOT/icodex.sh")"
assert_eq "calls wiring on launch" "1" \
  "$(grep -Ec '^[[:space:]]*ensure_superpowers_wiring[[:space:]]*$' "$ROOT/icodex.sh")"
assert_eq "calls binary permission wiring on launch" "1" \
  "$(grep -Ec '^[[:space:]]*ensure_launcher_binary_permission[[:space:]]*$' "$ROOT/icodex.sh")"
launch_order_ok="$(awk '
  /# default: run/ { inblock = 1; step = 0; next }
  inblock && /^[[:space:]]*setup_codex_home[[:space:]]*$/ && step == 0 { step = 1; next }
  inblock && /^[[:space:]]*ensure_launcher_binary_permission[[:space:]]*$/ && step == 1 { step = 2; next }
  inblock && /^[[:space:]]*ensure_superpowers_wiring[[:space:]]*$/ && step == 2 { step = 3; next }
  inblock && /^[[:space:]]*ensure_iwiki_wiring[[:space:]]*$/ && step == 3 { step = 4; next }
  inblock && /^[[:space:]]*install_ensure \|\| exit 1[[:space:]]*$/ && step == 4 { step = 5; next }
  inblock && /^[[:space:]]*ensure_uv_dependency \|\| exit 1[[:space:]]*$/ && step == 5 { step = 6; next }
  inblock && /^[[:space:]]*\(\([[:space:]]*ICODEX_DISABLE_PROXY[[:space:]]*\)\)[[:space:]]*\|\|[[:space:]]*proxy_apply[[:space:]]*$/ && step == 6 { step = 7; next }
  inblock && /^[[:space:]]*launch_codex[[:space:]]/ && step == 7 { print 1; found = 1; exit }
  END { if (!found) print 0 }
' "$ROOT/icodex.sh")"
assert_eq "default launch wiring order" "1" "$launch_order_ok"

# install/update branch must NOT call launch-time wiring: the single-line
# install)/update) case branches must contain zero wiring calls.
assert_eq "install branch skips binary permission wiring" "0" \
  "$(grep -E 'install\)|update\)' "$ROOT/icodex.sh" | grep -c ensure_launcher_binary_permission)"
assert_eq "install branch skips superpowers wiring" "0" \
  "$(grep -E 'install\)|update\)' "$ROOT/icodex.sh" | grep -c ensure_superpowers_wiring)"

finish

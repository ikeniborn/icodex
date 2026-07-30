#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/profile/profile.sh"

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
assert_eq "sources sandbox module" "1" \
  "$(grep -c 'config/sandbox' "$ROOT/icodex.sh")"
assert_eq "sources profile wiring module" "1" \
  "$(grep -c 'profile/wiring' "$ROOT/icodex.sh")"
assert_eq "sources profile runner module" "1" \
  "$(grep -c 'profile/profile' "$ROOT/icodex.sh")"
assert_eq "does not source iwiki plugin module" "0" \
  "$(grep -c 'plugin/iwiki' "$ROOT/icodex.sh")"
assert_eq "calls wiring on launch" "1" \
  "$(grep -Ec '^[[:space:]]*ensure_superpowers_wiring[[:space:]]*$' "$ROOT/icodex.sh")"
assert_eq "calls iwiki wiring on launch" "1" \
  "$(grep -Ec '^[[:space:]]*ensure_iwiki_wiring[[:space:]]*$' "$ROOT/icodex.sh")"
assert_eq "calls iwiki binding on launch" "1" \
  "$(grep -Ec '^[[:space:]]*ensure_iwiki_binding[[:space:]]*$' "$ROOT/icodex.sh")"
assert_eq "calls profile wiring on launch" "1" \
  "$(grep -Ec '^[[:space:]]*ensure_profile_wiring[[:space:]]*$' "$ROOT/icodex.sh")"
assert_eq "calls profile environment sanitizer on launch" "1" \
  "$(grep -Ec '^[[:space:]]*sanitize_profile_hook_environment[[:space:]]*$' "$ROOT/icodex.sh")"
assert_eq "calls binary permission wiring on launch" "1" \
  "$(grep -Ec '^[[:space:]]*ensure_launcher_binary_permission[[:space:]]*$' "$ROOT/icodex.sh")"
assert_eq "calls apply_mode on launch" "1" \
  "$(grep -Ec '^[[:space:]]*apply_mode \|\| exit 1[[:space:]]*$' "$ROOT/icodex.sh")"
assert_eq "calls ensure_project_trust on launch" "1" \
  "$(grep -Ec '^[[:space:]]*ensure_project_trust ' "$ROOT/icodex.sh")"
assert_eq "calls optional pii launch wrapper" "1" \
  "$(grep -Ec '^[[:space:]]*launch_codex_with_optional_pii[[:space:]]' "$ROOT/icodex.sh")"
assert_eq "dispatches explicit profile task" "1" \
  "$(grep -Ec '^[[:space:]]*profile-run-task\)[[:space:]]*run_profile_task' "$ROOT/lib/profile/profile.sh")"
assert_eq "dispatches profile orchestrator" "1" \
  "$(grep -Ec '^[[:space:]]*profile-orchestrate\)[[:space:]]*run_profile_orchestrator' "$ROOT/lib/profile/profile.sh")"
assert_eq "profile dispatch precedes interactive launch" "1" \
  "$(awk '
    /^[[:space:]]*run_profile_dispatch[[:space:]]*$/ { dispatch = NR }
    /^[[:space:]]*launch_codex_with_optional_pii[[:space:]]/ { launch = NR }
    END { print (dispatch > 0 && launch > dispatch) ? 1 : 0 }
  ' "$ROOT/icodex.sh")"
assert_eq "profile commands reuse PII startup" "1" \
  "$(grep -Ec '^[[:space:]]*if ! start_pii_proxy_server; then[[:space:]]*$' "$ROOT/lib/profile/profile.sh")"
assert_eq "profile commands reuse PII cleanup" "1" \
  "$(grep -Ec '^[[:space:]]*stop_pii_proxy_server[[:space:]]*$' "$ROOT/lib/profile/profile.sh")"
assert_eq "profile commands pass exact PII base URL override" "1" \
  "$(grep -Ec '^[[:space:]]*export ICODEX_APP_SERVER_OPENAI_BASE_URL="http://127\.0\.0\.1:\$\{PII_PROXY_ACTIVE_PORT\}/v1"[[:space:]]*$' "$ROOT/lib/profile/profile.sh")"
assert_eq "tracked config does not enable iwiki" "0" \
  "$(grep -c 'iwiki@ai-wiki' "$ROOT/.codex-isolated/config.toml")"
launch_order_ok="$(awk '
  /# default: run/ { inblock = 1; step = 0; next }
  inblock && /^[[:space:]]*setup_codex_home[[:space:]]*$/ && step == 0 { step = 1; next }
  inblock && /^[[:space:]]*apply_mode \|\| exit 1[[:space:]]*$/ && step == 1 { step = 2; next }
  inblock && /^[[:space:]]*ensure_project_trust / && step == 2 { step = 3; next }
  inblock && /^[[:space:]]*ensure_launcher_binary_permission[[:space:]]*$/ && step == 3 { step = 4; next }
  inblock && /^[[:space:]]*ensure_superpowers_wiring[[:space:]]*$/ && step == 4 { step = 5; next }
  inblock && /^[[:space:]]*install_ensure \|\| exit 1[[:space:]]*$/ && step == 5 { step = 6; next }
  inblock && /^[[:space:]]*ensure_uv_dependency \|\| exit 1[[:space:]]*$/ && step == 6 { step = 7; next }
  inblock && /^[[:space:]]*\(\([[:space:]]*ICODEX_DISABLE_PROXY[[:space:]]*\)\)[[:space:]]*\|\|[[:space:]]*proxy_ensure[[:space:]]*$/ && step == 7 { step = 8; next }
  inblock && /^[[:space:]]*launch_codex_with_optional_pii[[:space:]]/ && step == 8 { print 1; found = 1; exit }
  END { if (!found) print 0 }
' "$ROOT/icodex.sh")"
assert_eq "default launch wiring order" "1" "$launch_order_ok"

profile_wiring_order_ok="$(awk '
  /^[[:space:]]*ensure_iwiki_binding[[:space:]]*$/ { iwiki = NR }
  /^[[:space:]]*ensure_profile_wiring[[:space:]]*$/ { profile = NR }
  END { print (iwiki > 0 && profile == iwiki + 1) ? 1 : 0 }
' "$ROOT/icodex.sh")"
assert_eq "profile wiring follows existing hook wiring" "1" "$profile_wiring_order_ok"

profile_sanitizer_order_ok="$(awk '
  /^[[:space:]]*ensure_profile_wiring[[:space:]]*$/ { profile = NR }
  /^[[:space:]]*sanitize_profile_hook_environment[[:space:]]*$/ { sanitize = NR }
  /^[[:space:]]*telemetry_setup / { telemetry = NR }
  END { print (profile > 0 && sanitize > profile && telemetry == sanitize + 1) ? 1 : 0 }
' "$ROOT/icodex.sh")"
assert_eq "profile environment sanitized immediately before telemetry" "1" "$profile_sanitizer_order_ok"

# install/update branch must NOT call launch-time wiring: the single-line
# install)/update) case branches must contain zero wiring calls.
assert_eq "install branch skips binary permission wiring" "0" \
  "$(grep -E 'install\)|update\)' "$ROOT/icodex.sh" | grep -c ensure_launcher_binary_permission)"
assert_eq "install branch skips superpowers wiring" "0" \
  "$(grep -E 'install\)|update\)' "$ROOT/icodex.sh" | grep -c ensure_superpowers_wiring)"
assert_eq "install branch skips profile wiring" "0" \
  "$(grep -E 'install\)|update\)' "$ROOT/icodex.sh" | grep -c ensure_profile_wiring)"
assert_eq "install branch skips profile environment sanitizer" "0" \
  "$(grep -E 'install\)|update\)' "$ROOT/icodex.sh" | grep -c sanitize_profile_hook_environment)"

profile_tmp="$(mktemp -d)"
if ! declare -F run_profile_dispatch >/dev/null 2>&1; then
  for name in \
    "profile dispatch function exists" \
    "profile dispatch preserves normal exit" \
    "profile dispatch preserves error exit" \
    "profile TERM forwards and reaps child" \
    "profile cleanup runs on PII startup failure"; do
    echo "FAIL [$name]"
    FAIL=$((FAIL+1))
  done
else
  echo "PASS [profile dispatch function exists]"
  PASS=$((PASS+1))
  profile_cleanup="$profile_tmp/cleanup"
  telemetry_cleanup() { printf 'telemetry\n' >> "$profile_cleanup"; }
  stop_pii_proxy_server() { printf 'pii\n' >> "$profile_cleanup"; }
  start_pii_proxy_server() { PII_PROXY_ACTIVE_PORT=15432; return 0; }
  run_profile_task() { return "${PROFILE_TEST_EXIT_CODE:-0}"; }
  run_profile_orchestrator() { return "${PROFILE_TEST_EXIT_CODE:-0}"; }
  ICODEX_CMD=profile-run-task
  ICODEX_USE_PII_PROXY_RESOLVED=false
  PROFILE_TEST_EXIT_CODE=0
  run_profile_dispatch
  assert_eq "profile dispatch preserves normal exit" "0" "$?"
  PROFILE_TEST_EXIT_CODE=27
  run_profile_dispatch
  assert_eq "profile dispatch preserves error exit" "27" "$?"

  profile_runner="$profile_tmp/runner"
  profile_ready="$profile_tmp/ready"
  profile_child_pid="$profile_tmp/child.pid"
  cat > "$profile_runner" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$$" > "$PROFILE_TEST_CHILD_PID_FILE"
printf ready > "$PROFILE_TEST_READY_FILE"
trap 'exit 0' INT TERM
while :; do sleep 0.05; done
SH
  chmod +x "$profile_runner"
  run_profile_task() { exec "$profile_runner"; }
  PROFILE_TEST_READY_FILE="$profile_ready"
  PROFILE_TEST_CHILD_PID_FILE="$profile_child_pid"
  export PROFILE_TEST_READY_FILE PROFILE_TEST_CHILD_PID_FILE
  ICODEX_CMD=profile-run-task
  ICODEX_USE_PII_PROXY_RESOLVED=true
  run_profile_dispatch &
  profile_wrapper_pid="$!"
  for _ in {1..100}; do
    [[ -f "$profile_ready" ]] && break
    sleep 0.01
  done
  kill -TERM "$profile_wrapper_pid" 2>/dev/null || true
  wait "$profile_wrapper_pid"
  profile_term_rc="$?"
  child_alive=0
  if [[ -f "$profile_child_pid" ]]; then
    kill -0 "$(cat "$profile_child_pid")" 2>/dev/null
    child_alive="$?"
  fi
  assert_eq "profile TERM preserves conventional status" "143" "$profile_term_rc"
  assert_eq "profile TERM forwards and reaps child" "1" "$child_alive"
  assert_eq "profile TERM runs PII cleanup once" "1" "$(grep -c '^pii$' "$profile_cleanup")"

  : > "$profile_cleanup"
  start_pii_proxy_server() { return 1; }
  ICODEX_USE_PII_PROXY_RESOLVED=true
  PROFILE_TEST_EXIT_CODE=0
  run_profile_dispatch
  assert_eq "profile PII startup failure is nonzero" "1" "$?"
  assert_eq "profile cleanup runs on PII startup failure" "1" "$(grep -c '^telemetry$' "$profile_cleanup")"
fi
rm -rf "$profile_tmp"

finish

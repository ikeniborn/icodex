#!/usr/bin/env bash
# Dispatch explicit profile-routed work through the Python App Server runner.

run_profile_task() {
  python3 "$ICODEX_ROOT/lib/profile/runner.py" run-task --target-root "$ICODEX_PROJECT_ROOT" --codex-home "$CODEX_HOME" --shared-root "$ICODEX_SHARED_DIR" --binary "$ICODEX_BIN" --topic "$ICODEX_PROFILE_TOPIC" --task "$ICODEX_PROFILE_TASK"
}

run_profile_orchestrator() {
  python3 "$ICODEX_ROOT/lib/profile/runner.py" orchestrate --target-root "$ICODEX_PROJECT_ROOT" --codex-home "$CODEX_HOME" --shared-root "$ICODEX_SHARED_DIR" --binary "$ICODEX_BIN" --topic "$ICODEX_PROFILE_TOPIC"
}

_profile_dispatch_cleanup() {
  [[ "${profile_cleanup_done:-false}" == "false" ]] || return 0
  profile_cleanup_done=true
  if [[ "${pii_started:-false}" == "true" ]]; then
    stop_pii_proxy_server
  fi
  if declare -F telemetry_cleanup >/dev/null 2>&1; then
    telemetry_cleanup || true
  fi
}

_profile_dispatch_signal() {
  signal_status="$1"
  local signal_name="$2"
  if [[ -n "${child_pid:-}" ]]; then
    kill "-$signal_name" "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
  fi
}

run_profile_dispatch() {
  local child_pid="" rc=0 signal_status=0
  local pii_started=false profile_cleanup_done=false
  trap '_profile_dispatch_cleanup' EXIT
  trap '_profile_dispatch_signal 130 INT' INT
  trap '_profile_dispatch_signal 143 TERM' TERM

  if [[ "${ICODEX_USE_PII_PROXY_RESOLVED:-false}" == "true" ]]; then
    if ! start_pii_proxy_server; then
      rc=1
      _profile_dispatch_cleanup
      trap - EXIT INT TERM
      return "$rc"
    fi
    pii_started=true
    export ICODEX_APP_SERVER_OPENAI_BASE_URL="http://127.0.0.1:${PII_PROXY_ACTIVE_PORT}/v1"
  fi

  case "$ICODEX_CMD" in
    profile-run-task) run_profile_task & ;;
    profile-orchestrate) run_profile_orchestrator & ;;
    *) rc=1 ;;
  esac
  if (( rc == 0 )); then
    child_pid="$!"
    wait "$child_pid" || rc=$?
  fi
  if (( signal_status != 0 )); then
    rc="$signal_status"
  fi
  _profile_dispatch_cleanup
  trap - EXIT INT TERM
  return "$rc"
}

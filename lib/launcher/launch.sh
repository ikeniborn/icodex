#!/usr/bin/env bash
# Final transparent exec of the isolated codex binary.
launch_codex() { # <args...>
  if [[ ! -x "$ICODEX_BIN" ]]; then
    log_error "codex binary missing — run: ./icodex.sh --install"
    return 1
  fi
  if [[ "${ICODEX_LAUNCH_NO_EXEC:-0}" == "1" ]]; then
    "$ICODEX_BIN" "$@"
  else
    exec "$ICODEX_BIN" "$@"
  fi
}

launch_codex_with_optional_pii() {
  if [[ "${ICODEX_USE_PII_PROXY_RESOLVED:-false}" != "true" ]]; then
    launch_codex "$@"
    return $?
  fi
  start_pii_proxy_server || return 1
  trap 'stop_pii_proxy_server' EXIT INT TERM
  ICODEX_LAUNCH_NO_EXEC=1 launch_codex \
    -c "openai_base_url=\"http://127.0.0.1:${PII_PROXY_ACTIVE_PORT}/v1\"" \
    "$@"
}

start_pii_proxy_server() {
  local py
  py="$(get_pii_proxy_python)" || { log_error "PII proxy not installed — run: ./icodex.sh --install-pii-proxy"; return 1; }
  mkdir -p "$ICODEX_PII_PROXY_LOG_DIR" "$ICODEX_PII_PROXY_PID_DIR"
  rm -f "$ICODEX_PII_PROXY_LOG_DIR/server.port"
  map_pii_env
  PII_PROXY_LOG_DIR="$ICODEX_PII_PROXY_LOG_DIR" \
  "$py" "$ICODEX_PII_PROXY_SERVER_SCRIPT" --port "$ICODEX_PII_PROXY_PORT" --log-dir "$ICODEX_PII_PROXY_LOG_DIR" \
    >/dev/null 2>&1 &
  PII_PROXY_PID=$!
  echo "$PII_PROXY_PID" > "$ICODEX_PII_PROXY_PID_FILE"
  local ticks=0 port=""
  while (( ticks < 30 )); do
    if ! kill -0 "$PII_PROXY_PID" 2>/dev/null; then
      log_error "PII proxy exited during startup"
      return 1
    fi
    if [[ -f "$ICODEX_PII_PROXY_LOG_DIR/server.port" ]]; then
      port="$(cat "$ICODEX_PII_PROXY_LOG_DIR/server.port" 2>/dev/null || true)"
      if [[ "$port" =~ ^[0-9]+$ ]] && (: >/dev/tcp/127.0.0.1/"$port") 2>/dev/null; then
        PII_PROXY_ACTIVE_PORT="$port"
        export PII_PROXY_ACTIVE_PORT
        return 0
      fi
    fi
    sleep 0.5
    ticks=$((ticks + 1))
  done
  log_error "PII proxy did not become ready"
  kill "$PII_PROXY_PID" 2>/dev/null || true
  return 1
}

stop_pii_proxy_server() {
  if [[ -f "${ICODEX_PII_PROXY_PID_FILE:-}" ]]; then
    local pid
    pid="$(cat "$ICODEX_PII_PROXY_PID_FILE" 2>/dev/null || true)"
    rm -f "$ICODEX_PII_PROXY_PID_FILE" "$ICODEX_PII_PROXY_LOG_DIR/server.port"
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  fi
}

launch_codex_wrapped() { # <args...>
  if [[ ! -x "$ICODEX_BIN" ]]; then
    log_error "codex binary missing — run: ./icodex.sh --install"
    return 1
  fi

  local rc=0
  ICODEX_LAUNCH_NO_EXEC=1 launch_codex_with_optional_pii "$@" || rc=$?
  if declare -F telemetry_cleanup >/dev/null 2>&1; then
    telemetry_cleanup || true
  fi
  return "$rc"
}

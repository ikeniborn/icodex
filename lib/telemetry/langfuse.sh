#!/usr/bin/env bash
# Local trusted Langfuse full-capture validation and lifecycle helpers.

_telemetry_langfuse_log_error() { # <message>
  if command -v log_error >/dev/null 2>&1; then
    log_error "$1"
  else
    printf 'ERROR: %s\n' "$1" >&2
  fi
}

telemetry_langfuse_enabled() {
  telemetry_mode_default
  [[ "$ICODEX_TELEMETRY" == "langfuse" || "$ICODEX_TELEMETRY" == "both" ]]
}

telemetry_langfuse_validate_config() {
  telemetry_langfuse_enabled || return 0
  if [[ -z "${ICODEX_LANGFUSE_BASE_URL:-}" ]]; then
    _telemetry_langfuse_log_error "ICODEX_LANGFUSE_BASE_URL is required for langfuse telemetry"
    return 1
  fi
  if [[ -z "${ICODEX_LANGFUSE_PUBLIC_KEY:-}" ]]; then
    _telemetry_langfuse_log_error "ICODEX_LANGFUSE_PUBLIC_KEY is required for langfuse telemetry"
    return 1
  fi
  if [[ -z "${ICODEX_LANGFUSE_SECRET_KEY:-}" ]]; then
    _telemetry_langfuse_log_error "ICODEX_LANGFUSE_SECRET_KEY is required for langfuse telemetry"
    return 1
  fi
  if ! telemetry_url_is_local_trusted "$ICODEX_LANGFUSE_BASE_URL"; then
    _telemetry_langfuse_log_error "ICODEX_LANGFUSE_BASE_URL must be local/trusted"
    return 1
  fi
}

telemetry_langfuse_capture_bin() {
  printf '%s\n' "${_TELEMETRY_LANGFUSE_CAPTURE_BIN:-${ICODEX_SHARED_DIR:-}/bin/icodex-langfuse-capture}"
}

telemetry_langfuse_capture_pid_file() {
  printf '%s\n' "${_TELEMETRY_LANGFUSE_CAPTURE_PID_FILE:-${ICODEX_HOME_DIR:-$PWD}/langfuse-capture.pid}"
}

telemetry_langfuse_capture_state_file() {
  printf '%s\n' "${_TELEMETRY_LANGFUSE_CAPTURE_STATE_FILE:-${ICODEX_HOME_DIR:-$PWD}/langfuse-capture.state}"
}

telemetry_langfuse_capture_tags() {
  printf 'icodex.project=%s,icodex.session_id=%s\n' \
    "${ICODEX_TELEMETRY_PROJECT:-unknown}" \
    "${ICODEX_TELEMETRY_SESSION_ID:-unknown}"
}

telemetry_langfuse_capture_context() {
  printf 'ICODEX_TELEMETRY_PROJECT=%s\n' "${ICODEX_TELEMETRY_PROJECT:-unknown}"
  printf 'ICODEX_TELEMETRY_SESSION_ID=%s\n' "${ICODEX_TELEMETRY_SESSION_ID:-unknown}"
  printf 'LANGFUSE_TAGS=%s\n' "$(telemetry_langfuse_capture_tags)"
}

telemetry_langfuse_string_safe() { # <value>
  local value="$1"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* ]] || return 1
  [[ "$value" != *\\* && "$value" != *\"* ]] || return 1
  [[ "$value" != *[[:cntrl:]]* ]]
}

telemetry_langfuse_provider_config() { # <provider-base-url>
  local base_url="$1"
  telemetry_url_is_local_trusted "$base_url" || return 1
  telemetry_langfuse_string_safe "$base_url" || return 1
  cat <<EOF
model = "gpt-5.5"
model_provider = "icodex_capture"

[model_providers.icodex_capture]
name = "icodex Langfuse Capture"
base_url = "$base_url"
wire_api = "responses"
EOF
}

telemetry_langfuse_write_provider_config() { # <config.toml> <provider-base-url>
  local file="$1" base_url="$2"
  telemetry_langfuse_provider_config "$base_url" > "$file"
}

telemetry_langfuse_probe_command() { # <workdir> <prompt>
  local workdir="$1" prompt="$2"
  "${ICODEX_BIN:-${ICODEX_ROOT:-.}/.codex-isolated/bin/codex}" exec \
    --strict-config \
    --ignore-rules \
    --skip-git-repo-check \
    --ephemeral \
    -C "$workdir" \
    --color never \
    "$prompt"
}

telemetry_langfuse_capture_pid_running() { # <pid>
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

telemetry_langfuse_running_pid() {
  local pid_file pid
  pid="${_TELEMETRY_LANGFUSE_CAPTURE_PID:-}"
  if [[ -n "$pid" ]] && telemetry_langfuse_capture_pid_running "$pid"; then
    printf '%s\n' "$pid"
    return 0
  fi

  pid_file="$(telemetry_langfuse_capture_pid_file)"
  if [[ -f "$pid_file" ]]; then
    IFS= read -r pid < "$pid_file" || pid=""
    if telemetry_langfuse_capture_pid_running "$pid"; then
      _TELEMETRY_LANGFUSE_CAPTURE_PID="$pid"
      printf '%s\n' "$pid"
      return 0
    fi
    rm -f "$pid_file"
  fi
  return 1
}

telemetry_langfuse_export_capture_env() {
  _TELEMETRY_LANGFUSE_CAPTURE_PID_FILE="$(telemetry_langfuse_capture_pid_file)"
  LANGFUSE_CAPTURE_STATE_FILE="$(telemetry_langfuse_capture_state_file)"
  LANGFUSE_TAGS="$(telemetry_langfuse_capture_tags)"
  export ICODEX_LANGFUSE_BASE_URL ICODEX_LANGFUSE_PUBLIC_KEY ICODEX_LANGFUSE_SECRET_KEY
  export ICODEX_TELEMETRY_PROJECT ICODEX_TELEMETRY_SESSION_ID
  export LANGFUSE_TAGS LANGFUSE_CAPTURE_STATE_FILE
}

telemetry_langfuse_start_capture() {
  telemetry_langfuse_enabled || return 0
  telemetry_langfuse_validate_config || return 1
  telemetry_langfuse_running_pid >/dev/null 2>&1 && return 0

  local bin pid pid_file
  bin="$(telemetry_langfuse_capture_bin)"
  if [[ ! -x "$bin" ]]; then
    _telemetry_langfuse_log_error "Langfuse capture binary missing: $bin"
    return 1
  fi

  telemetry_langfuse_export_capture_env
  pid_file="$_TELEMETRY_LANGFUSE_CAPTURE_PID_FILE"
  mkdir -p "$(dirname "$pid_file")" "$(dirname "$LANGFUSE_CAPTURE_STATE_FILE")"

  "$bin" &
  pid="$!"
  _TELEMETRY_LANGFUSE_CAPTURE_PID="$pid"
  printf '%s\n' "$pid" > "$pid_file"

  sleep 0.1
  if ! telemetry_langfuse_capture_pid_running "$pid"; then
    rm -f "$pid_file"
    _telemetry_langfuse_log_error "Langfuse capture failed to start"
    return 1
  fi
}

telemetry_langfuse_stop_capture() {
  local pid pid_file
  pid_file="$(telemetry_langfuse_capture_pid_file)"
  pid="$(telemetry_langfuse_running_pid 2>/dev/null)" || return 0

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  rm -f "$pid_file"
  unset _TELEMETRY_LANGFUSE_CAPTURE_PID
}

telemetry_langfuse_cleanup() {
  telemetry_langfuse_stop_capture
}

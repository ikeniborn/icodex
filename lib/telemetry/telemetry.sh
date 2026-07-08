#!/usr/bin/env bash
# Telemetry orchestration helpers. Telemetry is opt-in via ICODEX_TELEMETRY.

telemetry_mode_default() {
  ICODEX_TELEMETRY="${ICODEX_TELEMETRY:-off}"
}

telemetry_validate_mode() {
  telemetry_mode_default
  case "$ICODEX_TELEMETRY" in
    off|otel|langfuse|both) return 0 ;;
    *)
      log_error "invalid ICODEX_TELEMETRY='$ICODEX_TELEMETRY' (allowed: off|otel|langfuse|both)"
      return 1
      ;;
  esac
}

telemetry_derive_project() { # <dir>
  local dir="${1:-$PWD}" top name
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || top=""
  if [[ -n "$top" ]]; then
    name="$(basename "$top")"
  else
    name="$(basename "$dir")"
  fi
  name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//')"
  [[ -n "$name" ]] || name="unknown"
  printf '%s' "$name"
}

telemetry_new_session_id() {
  printf 'icodex-%s-%s\n' "$(date +%Y%m%d%H%M%S)" "$$"
}

telemetry_url_host() { # <url>
  local url="$1" rest authority host
  [[ "$url" == http://* || "$url" == https://* ]] || return 1
  rest="${url#*://}"
  authority="${rest%%[/?#]*}"
  [[ "$authority" != *@* ]] || return 1
  if [[ "$authority" == \[* ]]; then
    [[ "$authority" =~ ^\[[^]]+\](:[0-9]+)?$ ]] || return 1
    host="${authority%%]*}"
    host="${host#[}"
  else
    host="${authority%%:*}"
  fi
  [[ -n "$host" ]] || return 1
  printf '%s\n' "$host"
}

telemetry_ipv4_valid() { # <host>
  local host="$1" a b c d octet
  [[ "$host" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
  IFS=. read -r a b c d <<<"$host"
  for octet in "$a" "$b" "$c" "$d"; do
    [[ "$octet" =~ ^[0-9]+$ ]] || return 1
    (( 10#$octet >= 0 && 10#$octet <= 255 )) || return 1
  done
}

telemetry_url_is_local_trusted() { # <url>
  local host
  host="$(telemetry_url_host "$1")" || return 1
  [[ "$host" == "localhost" || "$host" == "::1" ]] && return 0
  telemetry_ipv4_valid "$host" || return 1
  case "$host" in
    127.*|10.*|192.168.*) return 0 ;;
    172.*)
      local second="${host#172.}"
      second="${second%%.*}"
      [[ "$second" =~ ^[0-9]+$ ]] && (( second >= 16 && second <= 31 ))
      return
      ;;
    *) return 1 ;;
  esac
}

telemetry_setup_context() {
  telemetry_validate_mode || return 1
  ICODEX_TELEMETRY_PROJECT="${ICODEX_TELEMETRY_PROJECT:-$(telemetry_derive_project "${ICODEX_PROJECT_ROOT:-$PWD}")}"
  ICODEX_TELEMETRY_SESSION_ID="${ICODEX_TELEMETRY_SESSION_ID:-$(telemetry_new_session_id)}"
  export ICODEX_TELEMETRY ICODEX_TELEMETRY_PROJECT ICODEX_TELEMETRY_SESSION_ID
}

_ICODEX_TELEMETRY_CLEANUPS=()

telemetry_register_cleanup() { # <shell-snippet>
  _ICODEX_TELEMETRY_CLEANUPS+=("$1")
}

telemetry_run_registered_cleanups() {
  local item
  for item in "${_ICODEX_TELEMETRY_CLEANUPS[@]}"; do
    eval "$item"
  done
}

telemetry_cleanup() {
  if declare -F telemetry_langfuse_cleanup >/dev/null 2>&1; then
    telemetry_langfuse_cleanup
  fi
  telemetry_run_registered_cleanups
}

telemetry_setup() { # <config.toml>
  local config_file="${1:-${ICODEX_HOME_DIR:-}/config.toml}" provider_url
  telemetry_setup_context || return 1

  case "$ICODEX_TELEMETRY" in
    off)
      telemetry_otel_remove "$config_file" || return 1
      telemetry_langfuse_strip_provider_region "$config_file" || return 1
      return 0
      ;;
    otel)
      telemetry_langfuse_strip_provider_region "$config_file" || return 1
      telemetry_otel_configure "$config_file" || return 1
      ;;
    langfuse)
      telemetry_otel_remove "$config_file" || return 1
      telemetry_langfuse_start_capture || return 1
      provider_url="$(telemetry_langfuse_capture_provider_url)" || { telemetry_langfuse_cleanup; return 1; }
      telemetry_langfuse_configure_provider "$config_file" "$provider_url" || { telemetry_langfuse_cleanup; return 1; }
      ;;
    both)
      telemetry_otel_configure "$config_file" || return 1
      telemetry_langfuse_start_capture || return 1
      provider_url="$(telemetry_langfuse_capture_provider_url)" || { telemetry_langfuse_cleanup; return 1; }
      telemetry_langfuse_configure_provider "$config_file" "$provider_url" || { telemetry_langfuse_cleanup; return 1; }
      ;;
  esac
}

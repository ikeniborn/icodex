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

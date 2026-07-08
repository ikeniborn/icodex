#!/usr/bin/env bash
# Codex OpenTelemetry metadata-only configuration.

_TELEMETRY_OTEL_START="# icodex:telemetry-otel:start"
_TELEMETRY_OTEL_END="# icodex:telemetry-otel:end"

telemetry_otel_endpoint() {
  printf '%s\n' "${ICODEX_OTEL_ENDPOINT:-http://127.0.0.1:4318}"
}

telemetry_otel_header() {
  [[ -n "${ICODEX_OTEL_CREDENTIALS:-}" ]] || return 0
  local b64
  b64="$(printf '%s' "$ICODEX_OTEL_CREDENTIALS" | base64 -w 0)"
  printf 'Authorization=Basic %s\n' "$b64"
}

telemetry_no_proxy_add_host() { # <url>
  local host
  host="$(telemetry_url_host "$1")" || return 0
  [[ "$host" == localhost || "$host" == 127.* || "$host" == "::1" ]] && return 0
  if [[ ",${NO_PROXY:-}," != *",${host},"* ]]; then
    NO_PROXY="${NO_PROXY:+${NO_PROXY},}${host}"
    no_proxy="$NO_PROXY"
    export NO_PROXY no_proxy
  fi
}

telemetry_otel_region() {
  local endpoint header attrs root version
  endpoint="$(telemetry_otel_endpoint)"
  header="$(telemetry_otel_header)"
  root="${ICODEX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
  version="$(cat "$root/VERSION" 2>/dev/null || echo dev)"
  attrs="service.name=codex,service.namespace=icodex,icodex.project=${ICODEX_TELEMETRY_PROJECT:-unknown},icodex.session_id=${ICODEX_TELEMETRY_SESSION_ID:-unknown},wrapper.version=${version}"
  printf '%s\n' "$_TELEMETRY_OTEL_START"
  printf 'otel.environment = "local"\n'
  printf 'otel.log_user_prompt = false\n'
  printf 'otel.resource_attributes = "%s"\n' "$attrs"
  printf '[otel.exporter.otlp]\n'
  printf 'endpoint = "%s"\n' "$endpoint"
  if [[ -n "$header" ]]; then
    printf 'headers = "%s"\n' "$header"
  fi
  printf '%s\n' "$_TELEMETRY_OTEL_END"
}

telemetry_otel_configure() { # <config.toml>
  local file="$1" tmp
  local endpoint
  endpoint="$(telemetry_otel_endpoint)"
  telemetry_url_host "$endpoint" >/dev/null || { log_error "invalid ICODEX_OTEL_ENDPOINT='$endpoint'"; return 1; }
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    awk -v s="$_TELEMETRY_OTEL_START" -v e="$_TELEMETRY_OTEL_END" '
      $0 == s { skip=1; next }
      $0 == e { skip=0; next }
      !skip { print }
    ' "$file" > "$tmp"
  fi
  telemetry_otel_region >> "$tmp"
  if [[ ! -f "$file" ]] || ! cmp -s "$tmp" "$file"; then
    cat "$tmp" > "$file"
  fi
  rm -f "$tmp"
  telemetry_no_proxy_add_host "$endpoint"
}

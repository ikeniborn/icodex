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
  printf 'Basic %s\n' "$b64"
}

telemetry_otel_exporter_value() { # <endpoint> <authorization-header>
  local endpoint="$1" header="${2:-}"
  if [[ -n "$header" ]]; then
    printf '{ otlp-http = { endpoint = "%s", protocol = "binary", headers = { "Authorization" = "%s" } } }\n' "$endpoint" "$header"
  else
    printf '{ otlp-http = { endpoint = "%s", protocol = "binary" } }\n' "$endpoint"
  fi
}

telemetry_no_proxy_add_host() { # <url>
  local host current item
  local -a parts
  host="$(telemetry_url_host "$1")" || return 0
  [[ "$host" == localhost || "$host" == 127.* || "$host" == "::1" ]] && return 0
  current="${NO_PROXY:-}"
  IFS=, read -ra parts <<<"${no_proxy:-}"
  for item in "${parts[@]}"; do
    if [[ -n "$item" && ",$current," != *",${item},"* ]]; then
      current="${current:+${current},}${item}"
    fi
  done
  if [[ ",$current," != *",${host},"* ]]; then
    current="${current:+${current},}${host}"
  fi
  NO_PROXY="$current"
  no_proxy="$current"
  export NO_PROXY no_proxy
}

telemetry_otel_region() {
  local endpoint header exporter
  endpoint="$(telemetry_otel_endpoint)"
  header="$(telemetry_otel_header)"
  exporter="$(telemetry_otel_exporter_value "$endpoint" "$header")"
  printf '%s\n' "$_TELEMETRY_OTEL_START"
  printf '[otel]\n'
  printf 'environment = "local"\n'
  printf 'log_user_prompt = false\n'
  printf 'exporter = %s\n' "$exporter"
  printf 'metrics_exporter = %s\n' "$exporter"
  printf 'trace_exporter = %s\n' "$exporter"
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

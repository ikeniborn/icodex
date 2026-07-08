#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/telemetry/telemetry.sh"
source "$ROOT/lib/telemetry/otel.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cfg="$tmp/config.toml"
printf '[sandbox]\nmode = "workspace-write"\n' > "$cfg"

ICODEX_HOME_DIR="$tmp"
ICODEX_TELEMETRY_PROJECT="repo"
ICODEX_TELEMETRY_SESSION_ID="icodex-test-session"
ICODEX_OTEL_ENDPOINT=""
unset ICODEX_OTEL_CREDENTIALS NO_PROXY no_proxy

telemetry_otel_configure "$cfg"
out="$(cat "$cfg")"
assert_contains "otel start marker" "$out" "# icodex:telemetry-otel:start"
assert_contains "otel table" "$out" "[otel]"
assert_contains "otel exporter inline map" "$out" "exporter = { otlp-http = {"
assert_contains "otel metrics exporter inline map" "$out" "metrics_exporter = { otlp-http = {"
assert_contains "otel trace exporter inline map" "$out" "trace_exporter = { otlp-http = {"
assert_contains "otel exporter endpoint" "$out" 'endpoint = "http://127.0.0.1:4318"'
assert_contains "prompt logging disabled" "$out" "log_user_prompt = false"
assert_eq "no proxy localhost" "" "${NO_PROXY:-}"

ICODEX_OTEL_ENDPOINT="http://otel.local:4318"
ICODEX_OTEL_CREDENTIALS="otel:secret"
unset NO_PROXY
no_proxy="existing.local"
telemetry_otel_configure "$cfg"
out="$(cat "$cfg")"
expected="$(printf '%s' 'otel:secret' | base64 -w 0)"
assert_contains "basic auth header" "$out" "headers = { \"Authorization\" = \"Basic ${expected}\" }"
assert_eq "no duplicate region" "1" "$(grep -c '# icodex:telemetry-otel:start' "$cfg")"
assert_contains "NO_PROXY preserves lowercase existing" "${NO_PROXY:-}" "existing.local"
assert_contains "NO_PROXY contains endpoint host" "${NO_PROXY:-}" "otel.local"
assert_contains "no_proxy preserves lowercase existing" "${no_proxy:-}" "existing.local"
assert_contains "no_proxy contains endpoint host" "${no_proxy:-}" "otel.local"

if [[ -x "$ROOT/.codex-isolated/bin/codex" ]]; then
  CODEX_HOME="$tmp" "$ROOT/.codex-isolated/bin/codex" --strict-config --help >/dev/null 2>&1
  code="$?"
  assert_eq "codex strict-config accepts otel config" "0" "$code"
fi

finish

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
assert_contains "otel exporter table" "$out" "[otel.exporter.otlp]"
assert_contains "otel exporter endpoint" "$out" 'endpoint = "http://127.0.0.1:4318"'
assert_contains "prompt logging disabled" "$out" "otel.log_user_prompt = false"
assert_contains "project resource" "$out" "icodex.project=repo"
assert_contains "session resource" "$out" "icodex.session_id=icodex-test-session"
assert_eq "no proxy localhost" "" "${NO_PROXY:-}"

ICODEX_OTEL_ENDPOINT="http://otel.local:4318"
ICODEX_OTEL_CREDENTIALS="otel:secret"
telemetry_otel_configure "$cfg"
out="$(cat "$cfg")"
expected="$(printf '%s' 'otel:secret' | base64 -w 0)"
assert_contains "basic auth header" "$out" "Authorization=Basic ${expected}"
assert_eq "no duplicate region" "1" "$(grep -c '# icodex:telemetry-otel:start' "$cfg")"
assert_contains "NO_PROXY contains endpoint host" "${NO_PROXY:-}" "otel.local"

finish

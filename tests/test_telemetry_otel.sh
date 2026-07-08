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
assert_contains "span attributes map" "$out" "span_attributes = {"
assert_contains "project span attribute" "$out" "\"icodex.project\" = \"repo\""
assert_contains "session span attribute" "$out" "\"icodex.session_id\" = \"icodex-test-session\""
assert_contains "wrapper version span attribute" "$out" "\"icodex.wrapper.version\" = \"0.1.0\""
assert_contains "codex version span attribute" "$out" "\"icodex.codex.version\" = \"codex-cli 0.142.5\""
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
  strict_home="$tmp/strict-home"
  mkdir -p "$strict_home"
  strict_cfg="$strict_home/config.toml"
  : > "$strict_cfg"
  ICODEX_OTEL_ENDPOINT="http://127.0.0.1:4318"
  unset ICODEX_OTEL_CREDENTIALS
  telemetry_otel_configure "$strict_cfg"
  strict_err="$tmp/codex-strict.err"
  timeout 10s env CODEX_HOME="$strict_home" "$ROOT/.codex-isolated/bin/codex" exec --strict-config --skip-git-repo-check --ephemeral 'true' >/dev/null 2>"$strict_err"
  code="$?"
  case "$code" in
    0|1|124) PASS=$((PASS+1)); echo "PASS [codex strict-config completed or reached auth/network]" ;;
    *) FAIL=$((FAIL+1)); echo "FAIL [codex strict-config completed or reached auth/network]: exit $code" ;;
  esac
  strict_out="$(cat "$strict_err")"
  if grep -Eq 'Error loading config\.toml|unknown configuration field|invalid type' <<<"$strict_out"; then
    echo "FAIL [codex strict-config has no config parse error]: $strict_out"
    FAIL=$((FAIL+1))
  else
    echo "PASS [codex strict-config has no config parse error]"
    PASS=$((PASS+1))
  fi
fi

bad_cfg="$tmp/bad-config.toml"
printf '[sandbox]\nmode = "workspace-write"\n' > "$bad_cfg"
bad_before="$(cat "$bad_cfg")"
ICODEX_OTEL_ENDPOINT='http://otel.local:4318/"bad'
telemetry_otel_configure "$bad_cfg" >/dev/null 2>&1
bad_code="$?"
assert_eq "malformed endpoint rejected" "1" "$bad_code"
assert_eq "malformed endpoint does not rewrite config" "$bad_before" "$(cat "$bad_cfg")"

finish

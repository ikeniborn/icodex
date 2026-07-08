#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/telemetry/telemetry.sh"
source "$ROOT/lib/telemetry/langfuse.sh"

unset ICODEX_LANGFUSE_BASE_URL ICODEX_LANGFUSE_PUBLIC_KEY ICODEX_LANGFUSE_SECRET_KEY
for mode in off otel; do
  ICODEX_TELEMETRY="$mode"
  assert_exit "missing langfuse config ignored for $mode" 0 telemetry_langfuse_validate_config
done

for mode in langfuse both; do
  ICODEX_TELEMETRY="$mode"
  unset ICODEX_LANGFUSE_BASE_URL ICODEX_LANGFUSE_PUBLIC_KEY ICODEX_LANGFUSE_SECRET_KEY
  assert_exit "missing langfuse config fails for $mode" 1 telemetry_langfuse_validate_config

  ICODEX_LANGFUSE_BASE_URL="http://127.0.0.1:3000"
  unset ICODEX_LANGFUSE_PUBLIC_KEY ICODEX_LANGFUSE_SECRET_KEY
  assert_exit "missing langfuse public key fails for $mode" 1 telemetry_langfuse_validate_config

  ICODEX_LANGFUSE_PUBLIC_KEY="pk-test"
  unset ICODEX_LANGFUSE_SECRET_KEY
  assert_exit "missing langfuse secret key fails for $mode" 1 telemetry_langfuse_validate_config

  ICODEX_LANGFUSE_SECRET_KEY="sk-test"
  assert_exit "local langfuse url accepted for $mode" 0 telemetry_langfuse_validate_config
done

ICODEX_TELEMETRY="langfuse"
ICODEX_LANGFUSE_PUBLIC_KEY="pk-test"
ICODEX_LANGFUSE_SECRET_KEY="sk-test"
for url in "https://example.com" "localhost:3000" "http://user:pass@localhost:3000"; do
  ICODEX_LANGFUSE_BASE_URL="$url"
  assert_exit "untrusted langfuse url rejected: $url" 1 telemetry_langfuse_validate_config
done

ICODEX_LANGFUSE_BASE_URL="http://127.0.0.1:3000"
ICODEX_TELEMETRY_PROJECT="repo"
ICODEX_TELEMETRY_SESSION_ID="icodex-test-session"
context="$(telemetry_langfuse_capture_context)"
assert_contains "context contains project" "$context" "ICODEX_TELEMETRY_PROJECT=repo"
assert_contains "context contains session" "$context" "ICODEX_TELEMETRY_SESSION_ID=icodex-test-session"
assert_contains "context tags contain project" "$context" "icodex.project=repo"
assert_contains "context tags contain session" "$context" "icodex.session_id=icodex-test-session"
if grep -qE 'ICODEX_LANGFUSE_CAPTURE_|ICODEX_LANGFUSE_TAGS' "$ROOT/lib/telemetry/langfuse.sh"; then
  echo "FAIL [no extra ICODEX langfuse capture config surface]"
  FAIL=$((FAIL+1))
else
  echo "PASS [no extra ICODEX langfuse capture config surface]"
  PASS=$((PASS+1))
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fake="$tmp/fake-capture"
cat > "$fake" <<'EOF'
#!/usr/bin/env bash
printf 'started\n' > "$LANGFUSE_CAPTURE_STATE_FILE"
printf 'project=%s\n' "$ICODEX_TELEMETRY_PROJECT" >> "$LANGFUSE_CAPTURE_STATE_FILE"
printf 'session=%s\n' "$ICODEX_TELEMETRY_SESSION_ID" >> "$LANGFUSE_CAPTURE_STATE_FILE"
printf 'tags=%s\n' "$LANGFUSE_TAGS" >> "$LANGFUSE_CAPTURE_STATE_FILE"
printf 'http://127.0.0.1:18766/v1\n' > "$LANGFUSE_CAPTURE_PROVIDER_URL_FILE"
trap 'printf stopped >> "$LANGFUSE_CAPTURE_STATE_FILE"; exit 0' TERM
while :; do sleep 1; done
EOF
chmod +x "$fake"

_TELEMETRY_LANGFUSE_CAPTURE_BIN="$fake"
_TELEMETRY_LANGFUSE_CAPTURE_PID_FILE="$tmp/capture.pid"
_TELEMETRY_LANGFUSE_CAPTURE_STATE_FILE="$tmp/capture.state"
_TELEMETRY_LANGFUSE_CAPTURE_PROVIDER_URL_FILE="$tmp/capture-provider.url"

telemetry_langfuse_start_capture
first_pid="$(cat "$_TELEMETRY_LANGFUSE_CAPTURE_PID_FILE")"
kill -0 "$first_pid" 2>/dev/null
assert_eq "capture process running" "0" "$?"
assert_contains "state has project" "$(cat "$_TELEMETRY_LANGFUSE_CAPTURE_STATE_FILE")" "project=repo"
assert_contains "state has session" "$(cat "$_TELEMETRY_LANGFUSE_CAPTURE_STATE_FILE")" "session=icodex-test-session"
assert_contains "state has tags" "$(cat "$_TELEMETRY_LANGFUSE_CAPTURE_STATE_FILE")" "tags=icodex.project=repo,icodex.session_id=icodex-test-session"
assert_eq "provider url published" "http://127.0.0.1:18766/v1" "$(cat "$_TELEMETRY_LANGFUSE_CAPTURE_PROVIDER_URL_FILE")"

provider_cfg="$tmp/provider-config.toml"
printf 'model_provider = "openai"\n[shell]\nprogram = "bash"\n' > "$provider_cfg"
telemetry_langfuse_configure_provider "$provider_cfg" "$(cat "$_TELEMETRY_LANGFUSE_CAPTURE_PROVIDER_URL_FILE")"
provider_out="$(cat "$provider_cfg")"
assert_contains "provider region marker" "$provider_out" "# icodex:telemetry-langfuse-provider:start"
assert_contains "provider route selected" "$provider_out" 'model_provider = "icodex_capture"'
assert_contains "provider inline config" "$provider_out" 'model_providers.icodex_capture = {'
assert_eq "provider route not duplicated" "1" "$(grep -c 'model_provider = ' "$provider_cfg")"
assert_contains "existing table preserved after provider route" "$provider_out" "[shell]"

telemetry_langfuse_strip_provider_region "$provider_cfg"
assert_eq "provider region removed" "0" "$(grep -c 'icodex:telemetry-langfuse-provider:start' "$provider_cfg")"

telemetry_langfuse_start_capture
second_pid="$(cat "$_TELEMETRY_LANGFUSE_CAPTURE_PID_FILE")"
assert_eq "start is idempotent" "$first_pid" "$second_pid"

telemetry_langfuse_stop_capture
sleep 0.2
kill -0 "$first_pid" 2>/dev/null
assert_eq "capture process stopped" "1" "$?"
assert_exit "stop is idempotent" 0 telemetry_langfuse_stop_capture
assert_exit "cleanup safe when not started" 0 telemetry_langfuse_cleanup

bad="$tmp/bad-capture"
cat > "$bad" <<'EOF'
#!/usr/bin/env bash
exit 42
EOF
chmod +x "$bad"
_TELEMETRY_LANGFUSE_CAPTURE_BIN="$bad"
rm -f "$_TELEMETRY_LANGFUSE_CAPTURE_PID_FILE"
rm -f "$_TELEMETRY_LANGFUSE_CAPTURE_PROVIDER_URL_FILE"
assert_exit "capture startup failure fails before launch" 1 telemetry_langfuse_start_capture

finish

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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fake="$tmp/fake-capture"
cat > "$fake" <<'EOF'
#!/usr/bin/env bash
printf 'started\n' > "$ICODEX_LANGFUSE_CAPTURE_STATE_FILE"
printf 'project=%s\n' "$ICODEX_TELEMETRY_PROJECT" >> "$ICODEX_LANGFUSE_CAPTURE_STATE_FILE"
printf 'session=%s\n' "$ICODEX_TELEMETRY_SESSION_ID" >> "$ICODEX_LANGFUSE_CAPTURE_STATE_FILE"
trap 'printf stopped >> "$ICODEX_LANGFUSE_CAPTURE_STATE_FILE"; exit 0' TERM
while :; do sleep 1; done
EOF
chmod +x "$fake"

ICODEX_LANGFUSE_CAPTURE_BIN="$fake"
ICODEX_LANGFUSE_CAPTURE_PID_FILE="$tmp/capture.pid"
ICODEX_LANGFUSE_CAPTURE_STATE_FILE="$tmp/capture.state"

telemetry_langfuse_start_capture
first_pid="$(cat "$ICODEX_LANGFUSE_CAPTURE_PID_FILE")"
kill -0 "$first_pid" 2>/dev/null
assert_eq "capture process running" "0" "$?"
assert_contains "state has project" "$(cat "$ICODEX_LANGFUSE_CAPTURE_STATE_FILE")" "project=repo"
assert_contains "state has session" "$(cat "$ICODEX_LANGFUSE_CAPTURE_STATE_FILE")" "session=icodex-test-session"

telemetry_langfuse_start_capture
second_pid="$(cat "$ICODEX_LANGFUSE_CAPTURE_PID_FILE")"
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
ICODEX_LANGFUSE_CAPTURE_BIN="$bad"
rm -f "$ICODEX_LANGFUSE_CAPTURE_PID_FILE"
assert_exit "capture startup failure fails before launch" 1 telemetry_langfuse_start_capture

finish

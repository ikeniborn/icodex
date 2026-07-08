#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/telemetry/telemetry.sh"
source "$ROOT/lib/telemetry/otel.sh"
source "$ROOT/lib/telemetry/langfuse.sh"
source "$ROOT/lib/launcher/launch.sh"

tmp="$(mktemp -d)"
cleanup_tmp() {
  if [[ -f "${long_child_pid_file:-}" ]]; then
    kill "$(cat "$long_child_pid_file")" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup_tmp EXIT

fake_codex="$tmp/codex"
cat > "$fake_codex" <<'EOF'
#!/usr/bin/env bash
: > "$ICODEX_TEST_ARGS_FILE"
for arg in "$@"; do
  printf '<%s>\n' "$arg" >> "$ICODEX_TEST_ARGS_FILE"
done
exit "${ICODEX_TEST_EXIT_CODE:-0}"
EOF
chmod +x "$fake_codex"

ICODEX_BIN="$fake_codex"
export ICODEX_BIN

direct_after="$tmp/direct-after"
direct_args="$tmp/direct-args"
(
  source "$ROOT/lib/core/logging.sh"
  source "$ROOT/lib/telemetry/telemetry.sh"
  source "$ROOT/lib/launcher/launch.sh"
  ICODEX_BIN="$fake_codex"
  ICODEX_TEST_ARGS_FILE="$direct_args"
  ICODEX_TEST_EXIT_CODE=13
  export ICODEX_BIN ICODEX_TEST_ARGS_FILE ICODEX_TEST_EXIT_CODE
  ICODEX_TELEMETRY=off
  launch_codex "alpha beta"
  printf 'after\n' > "$direct_after"
)
direct_rc="$?"
assert_eq "off launch preserves direct exec exit code" "13" "$direct_rc"
if [[ -e "$direct_after" ]]; then
  echo "FAIL [off launch does not return after exec]"
  FAIL=$((FAIL+1))
else
  echo "PASS [off launch does not return after exec]"
  PASS=$((PASS+1))
fi
assert_eq "off launch preserves direct arg" "<alpha beta>" "$(cat "$direct_args")"

wrapped_cleanup="$tmp/wrapped-cleanup"
telemetry_register_cleanup "printf cleanup > '$wrapped_cleanup'"
ICODEX_TEST_ARGS_FILE="$tmp/wrapped-args"
ICODEX_TEST_EXIT_CODE=23
export ICODEX_TEST_ARGS_FILE ICODEX_TEST_EXIT_CODE
launch_codex_wrapped "one two" 'special!$&*' "--flag=value with space"
wrapped_rc="$?"
assert_eq "telemetry launch preserves child exit code" "23" "$wrapped_rc"
assert_eq "telemetry launch runs cleanup" "cleanup" "$(cat "$wrapped_cleanup")"
assert_eq "telemetry launch preserves passthrough args" "$(printf '<one two>\n<special!$&*>\n<--flag=value with space>')" "$(cat "$ICODEX_TEST_ARGS_FILE")"

pii_args="$tmp/pii-args"
pii_stop="$tmp/pii-stop"
start_pii_proxy_server() {
  PII_PROXY_ACTIVE_PORT=15432
  return 0
}
stop_pii_proxy_server() {
  printf stopped > "$pii_stop"
}
ICODEX_TEST_ARGS_FILE="$pii_args"
ICODEX_TEST_EXIT_CODE=0
ICODEX_USE_PII_PROXY_RESOLVED=true
export ICODEX_TEST_ARGS_FILE ICODEX_TEST_EXIT_CODE ICODEX_USE_PII_PROXY_RESOLVED
launch_codex_wrapped "pii payload"
pii_wrapped_rc="$?"
assert_eq "telemetry pii launch exit code" "0" "$pii_wrapped_rc"
assert_contains "telemetry pii launch routes openai base" "$(cat "$pii_args")" '<openai_base_url="http://127.0.0.1:15432/v1">'
assert_eq "telemetry pii launch stops proxy" "stopped" "$(cat "$pii_stop")"
ICODEX_USE_PII_PROXY_RESOLVED=false
export ICODEX_USE_PII_PROXY_RESOLVED

long_child="$tmp/long-child"
long_ready="$tmp/long-ready"
long_child_pid_file="$tmp/long-child.pid"
cat > "$long_child" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$$" > "$ICODEX_TEST_CHILD_PID_FILE"
printf ready > "$ICODEX_TEST_READY_FILE"
trap 'exit 0' TERM INT
while :; do sleep 0.05; done
EOF
chmod +x "$long_child"

signal_cleanup="$tmp/signal-cleanup"
(
  source "$ROOT/lib/core/logging.sh"
  source "$ROOT/lib/telemetry/telemetry.sh"
  source "$ROOT/lib/launcher/launch.sh"
  ICODEX_BIN="$long_child"
  ICODEX_TEST_READY_FILE="$long_ready"
  ICODEX_TEST_CHILD_PID_FILE="$long_child_pid_file"
  export ICODEX_BIN ICODEX_TEST_READY_FILE ICODEX_TEST_CHILD_PID_FILE
  telemetry_register_cleanup "printf cleanup > '$signal_cleanup'"
  launch_codex_wrapped
  exit "$?"
) &
wrapper_pid="$!"
for _ in {1..100}; do
  [[ -f "$long_ready" ]] && break
  sleep 0.01
done
if [[ ! -f "$long_ready" ]]; then
  echo "FAIL [signal test child became ready]"
  FAIL=$((FAIL+1))
else
  echo "PASS [signal test child became ready]"
  PASS=$((PASS+1))
fi
kill -TERM "$wrapper_pid"
wait "$wrapper_pid"
term_rc="$?"
assert_eq "telemetry TERM launch exits with conventional status" "143" "$term_rc"
assert_eq "telemetry TERM launch runs cleanup" "cleanup" "$(cat "$signal_cleanup" 2>/dev/null)"
if [[ -f "$long_child_pid_file" ]]; then
  sleep 0.1
  kill -0 "$(cat "$long_child_pid_file")" 2>/dev/null
  child_alive="$?"
  assert_eq "telemetry TERM launch reaps child" "1" "$child_alive"
fi

home="$tmp/home"
mkdir -p "$home"
cfg="$home/config.toml"
printf '[sandbox]\nmode = "workspace-write"\n' > "$cfg"
ICODEX_HOME_DIR="$home"
ICODEX_PROJECT_ROOT="$tmp/project"
ICODEX_ROOT="$ROOT"
mkdir -p "$ICODEX_PROJECT_ROOT"
export ICODEX_HOME_DIR ICODEX_PROJECT_ROOT ICODEX_ROOT

ICODEX_TELEMETRY=off
ICODEX_OTEL_ENDPOINT='bad endpoint'
unset ICODEX_LANGFUSE_BASE_URL ICODEX_LANGFUSE_PUBLIC_KEY ICODEX_LANGFUSE_SECRET_KEY
before="$(cat "$cfg")"
telemetry_setup "$cfg"
setup_rc="$?"
assert_eq "off setup succeeds despite unused bad telemetry config" "0" "$setup_rc"
assert_eq "off setup does not write otel config" "$before" "$(cat "$cfg")"

ICODEX_TELEMETRY=otel
ICODEX_OTEL_ENDPOINT="http://127.0.0.1:4318"
telemetry_setup "$cfg"
setup_rc="$?"
assert_eq "otel setup succeeds" "0" "$setup_rc"
assert_contains "otel setup writes region" "$(cat "$cfg")" "# icodex:telemetry-otel:start"

fake_capture="$tmp/fake-capture"
cat > "$fake_capture" <<'EOF'
#!/usr/bin/env bash
printf 'started\n' > "$LANGFUSE_CAPTURE_STATE_FILE"
printf 'http://127.0.0.1:18766/v1\n' > "$LANGFUSE_CAPTURE_PROVIDER_URL_FILE"
trap 'printf stopped >> "$LANGFUSE_CAPTURE_STATE_FILE"; exit 0' TERM
while :; do sleep 1; done
EOF
chmod +x "$fake_capture"

_TELEMETRY_LANGFUSE_CAPTURE_BIN="$fake_capture"
_TELEMETRY_LANGFUSE_CAPTURE_PID_FILE="$tmp/langfuse.pid"
_TELEMETRY_LANGFUSE_CAPTURE_STATE_FILE="$tmp/langfuse.state"
_TELEMETRY_LANGFUSE_CAPTURE_PROVIDER_URL_FILE="$tmp/langfuse-provider.url"
ICODEX_TELEMETRY=langfuse
ICODEX_LANGFUSE_BASE_URL="http://127.0.0.1:3000"
ICODEX_LANGFUSE_PUBLIC_KEY="pk-test"
ICODEX_LANGFUSE_SECRET_KEY="sk-test"
export ICODEX_TELEMETRY ICODEX_LANGFUSE_BASE_URL ICODEX_LANGFUSE_PUBLIC_KEY ICODEX_LANGFUSE_SECRET_KEY
telemetry_setup "$cfg"
setup_rc="$?"
assert_eq "langfuse setup succeeds" "0" "$setup_rc"
assert_contains "langfuse setup starts capture" "$(cat "$_TELEMETRY_LANGFUSE_CAPTURE_STATE_FILE")" "started"
assert_contains "langfuse setup writes provider route" "$(cat "$cfg")" "# icodex:telemetry-langfuse-provider:start"
assert_contains "langfuse setup selects capture provider" "$(cat "$cfg")" 'model_provider = "icodex_capture"'
assert_eq "langfuse setup removes otel-only region" "0" "$(grep -c '# icodex:telemetry-otel:start' "$cfg")"
telemetry_cleanup
assert_contains "langfuse cleanup stops capture" "$(cat "$_TELEMETRY_LANGFUSE_CAPTURE_STATE_FILE")" "stopped"
assert_exit "cleanup safe when no capture started" 0 telemetry_cleanup

no_url_capture="$tmp/no-url-capture"
cat > "$no_url_capture" <<'EOF'
#!/usr/bin/env bash
printf 'started\n' > "$LANGFUSE_CAPTURE_STATE_FILE"
trap 'printf stopped >> "$LANGFUSE_CAPTURE_STATE_FILE"; exit 0' TERM
while :; do sleep 1; done
EOF
chmod +x "$no_url_capture"
_TELEMETRY_LANGFUSE_CAPTURE_BIN="$no_url_capture"
_TELEMETRY_LANGFUSE_CAPTURE_PID_FILE="$tmp/no-url.pid"
_TELEMETRY_LANGFUSE_CAPTURE_STATE_FILE="$tmp/no-url.state"
_TELEMETRY_LANGFUSE_CAPTURE_PROVIDER_URL_FILE="$tmp/no-url-provider.url"
rm -f "$_TELEMETRY_LANGFUSE_CAPTURE_PID_FILE" "$_TELEMETRY_LANGFUSE_CAPTURE_PROVIDER_URL_FILE"
ICODEX_TELEMETRY=langfuse
telemetry_setup "$cfg" >/dev/null 2>&1
setup_rc="$?"
assert_eq "langfuse setup fails when provider url missing" "1" "$setup_rc"
assert_contains "langfuse setup cleans failed capture" "$(cat "$_TELEMETRY_LANGFUSE_CAPTURE_STATE_FILE")" "stopped"

ICODEX_TELEMETRY=off
telemetry_setup "$cfg"
setup_rc="$?"
assert_eq "off setup removes telemetry regions" "0" "$setup_rc"
assert_eq "off setup removed provider region" "0" "$(grep -c '# icodex:telemetry-langfuse-provider:start' "$cfg")"

finish

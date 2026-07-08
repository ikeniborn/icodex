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
trap 'rm -rf "$tmp"' EXIT

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
trap 'printf stopped >> "$LANGFUSE_CAPTURE_STATE_FILE"; exit 0' TERM
while :; do sleep 1; done
EOF
chmod +x "$fake_capture"

_TELEMETRY_LANGFUSE_CAPTURE_BIN="$fake_capture"
_TELEMETRY_LANGFUSE_CAPTURE_PID_FILE="$tmp/langfuse.pid"
_TELEMETRY_LANGFUSE_CAPTURE_STATE_FILE="$tmp/langfuse.state"
ICODEX_TELEMETRY=langfuse
ICODEX_LANGFUSE_BASE_URL="http://127.0.0.1:3000"
ICODEX_LANGFUSE_PUBLIC_KEY="pk-test"
ICODEX_LANGFUSE_SECRET_KEY="sk-test"
export ICODEX_TELEMETRY ICODEX_LANGFUSE_BASE_URL ICODEX_LANGFUSE_PUBLIC_KEY ICODEX_LANGFUSE_SECRET_KEY
telemetry_setup "$cfg"
setup_rc="$?"
assert_eq "langfuse setup succeeds" "0" "$setup_rc"
assert_contains "langfuse setup starts capture" "$(cat "$_TELEMETRY_LANGFUSE_CAPTURE_STATE_FILE")" "started"
telemetry_cleanup
assert_contains "langfuse cleanup stops capture" "$(cat "$_TELEMETRY_LANGFUSE_CAPTURE_STATE_FILE")" "stopped"
assert_exit "cleanup safe when no capture started" 0 telemetry_cleanup

finish

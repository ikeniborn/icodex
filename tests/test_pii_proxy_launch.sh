#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/launcher/launch.sh"

type launch_codex_with_optional_pii >/dev/null 2>&1 || {
  echo "FAIL [launch_codex_with_optional_pii exists]"
  exit 1
}

tmp="$(mktemp -d)"
export ICODEX_BIN="$tmp/codex"
cat > "$ICODEX_BIN" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$ICODEX_BIN.args"
SH
chmod +x "$ICODEX_BIN"

out_args() { cat "$ICODEX_BIN.args" 2>/dev/null || true; }

export ICODEX_LAUNCH_NO_EXEC=1
launch_codex --model test
assert_eq "normal launch args" "--model"$'\n'"test" "$(out_args)"

start_pii_proxy_server() { PII_PROXY_ACTIVE_PORT=23456; return 0; }
stop_pii_proxy_server() { :; }
export ICODEX_USE_PII_PROXY_RESOLVED=true
launch_codex_with_optional_pii --model test
args="$(out_args)"
assert_contains "pii adds config flag" "$args" "-c"
assert_contains "pii adds openai_base_url" "$args" "openai_base_url"
assert_contains "pii adds local port" "$args" "http://127.0.0.1:23456/v1"

start_pii_proxy_server() { return 1; }
assert_exit "start failure fail-secure" 1 launch_codex_with_optional_pii

rm -rf "$tmp"
finish

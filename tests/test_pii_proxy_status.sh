#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/pii-proxy/status.sh"

tmp="$(mktemp -d)"
export ICODEX_PII_PROXY_VENV="$tmp/venv"
export ICODEX_PII_PROXY_SERVER_SCRIPT="$tmp/server.py"
export ICODEX_PII_PROXY_LOG_DIR="$tmp/logs"
export ICODEX_PII_PROXY_PID_DIR="$tmp/pid"

out="$(check_pii_proxy_status)"
assert_contains "missing status says not installed" "$out" "not installed"

mkdir -p "$ICODEX_PII_PROXY_VENV/bin" "$ICODEX_PII_PROXY_LOG_DIR" "$ICODEX_PII_PROXY_PID_DIR"
touch "$ICODEX_PII_PROXY_VENV/bin/python3" "$ICODEX_PII_PROXY_SERVER_SCRIPT"
chmod +x "$ICODEX_PII_PROXY_VENV/bin/python3"
echo "rules" > "$ICODEX_PII_PROXY_VENV/pii_proxy_engine"
echo "32123" > "$ICODEX_PII_PROXY_LOG_DIR/server.port"
out="$(check_pii_proxy_status)"
assert_contains "status engine" "$out" "engine: rules"
assert_contains "status port" "$out" "port: 32123"

rm -rf "$tmp"
finish

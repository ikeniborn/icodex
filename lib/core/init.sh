#!/usr/bin/env bash
# Global paths & identity. ICODEX_ROOT is set by the entrypoint; derive if absent.
: "${ICODEX_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

ICODEX_SHARED_DIR="$ICODEX_ROOT/.codex-isolated"   # stable shared store (assets)
ICODEX_HOMES_DIR="$ICODEX_ROOT/.codex-homes"       # parent of per-project homes
ICODEX_HOME_DIR="$ICODEX_SHARED_DIR"               # placeholder; set per run in setup_codex_home
ICODEX_PROJECT_ROOT=""                             # set per run in resolve_codex_home
ICODEX_BIN="$ICODEX_SHARED_DIR/bin/codex"
ICODEX_STAMP="$ICODEX_SHARED_DIR/bin/.codex-version"
ICODEX_LOCKFILE="$ICODEX_ROOT/.codex-lockfile.json"
ICODEX_CONFIG="$ICODEX_ROOT/.codex_config"
ICODEX_PROJECT_ID="$(basename "$ICODEX_ROOT")"
ICODEX_REPO="openai/codex"

ICODEX_PII_PROXY_VENV="$ICODEX_SHARED_DIR/pii-proxy-venv"
ICODEX_PII_PROXY_SERVER_SCRIPT="$ICODEX_SHARED_DIR/pii-proxy-server.py"
ICODEX_PII_PROXY_LOG_DIR="$ICODEX_SHARED_DIR/pii-proxy-logs"
ICODEX_PII_PROXY_PID_DIR="$ICODEX_SHARED_DIR/pii-proxy-pid"
ICODEX_PII_PROXY_PID_FILE="$ICODEX_PII_PROXY_PID_DIR/session.pid"
ICODEX_USE_PII_PROXY="${ICODEX_USE_PII_PROXY:-false}"
ICODEX_PII_ENGINE="${ICODEX_PII_ENGINE:-rules}"
ICODEX_PII_MASKING_LEVEL="${ICODEX_PII_MASKING_LEVEL:-standard}"
ICODEX_PII_MASK_TOKEN="${ICODEX_PII_MASK_TOKEN:-REDACTED}"
ICODEX_PII_LOG_LEVEL="${ICODEX_PII_LOG_LEVEL:-info}"
ICODEX_PII_PROXY_PORT="${ICODEX_PII_PROXY_PORT:-0}"
ICODEX_PII_PROXY_PORT_MIN="${ICODEX_PII_PROXY_PORT_MIN:-20000}"
ICODEX_PII_PROXY_PORT_MAX="${ICODEX_PII_PROXY_PORT_MAX:-40000}"
ICODEX_PII_UPSTREAM_URL="${ICODEX_PII_UPSTREAM_URL:-https://api.openai.com/v1}"
ICODEX_PII_CONNECT_TIMEOUT="${ICODEX_PII_CONNECT_TIMEOUT:-10}"
ICODEX_PII_READ_TIMEOUT="${ICODEX_PII_READ_TIMEOUT:-300}"
ICODEX_PII_SPACY_EN_MODEL="${ICODEX_PII_SPACY_EN_MODEL:-en_core_web_lg}"
ICODEX_PII_SPACY_RU_MODEL="${ICODEX_PII_SPACY_RU_MODEL:-ru_core_news_lg}"

# Portable sha256 of stdin → lowercase hex digest only.
_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

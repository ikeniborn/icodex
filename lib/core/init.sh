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

# Portable sha256 of stdin → lowercase hex digest only.
_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

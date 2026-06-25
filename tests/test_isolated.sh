#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/config/isolated.sh"

tmp="$(mktemp -d)"
ICODEX_HOME_DIR="$tmp/.codex-isolated"
unset CODEX_HOME

setup_codex_home
assert_eq  "CODEX_HOME exported" "$ICODEX_HOME_DIR" "${CODEX_HOME:-}"
assert_exit "bin dir created" 0 test -d "$ICODEX_HOME_DIR/bin"

rm -rf "$tmp"
finish

#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

tmp="$(mktemp -d)"
ICODEX_ROOT="$tmp"
source "$ROOT/lib/core/init.sh"

assert_eq "home dir"   "$tmp/.codex-isolated"          "$ICODEX_HOME_DIR"
assert_eq "bin path"   "$tmp/.codex-isolated/bin/codex" "$ICODEX_BIN"
assert_eq "stamp path" "$tmp/.codex-isolated/bin/.codex-version" "$ICODEX_STAMP"
assert_eq "lockfile"   "$tmp/.codex-lockfile.json"     "$ICODEX_LOCKFILE"
assert_eq "config"     "$tmp/.codex_config"            "$ICODEX_CONFIG"
assert_eq "repo"       "openai/codex"                  "$ICODEX_REPO"

# _sha256 of the empty string is the well-known constant
digest="$(printf '' | _sha256)"
assert_eq "_sha256 empty" "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" "$digest"

rm -rf "$tmp"
finish

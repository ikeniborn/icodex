#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/binary/detect.sh"
source "$ROOT/lib/binary/lockfile.sh"

ICODEX_UNAME_S="Linux"; ICODEX_UNAME_M="x86_64"

setup_case() {
  tmp="$(mktemp -d)"
  ICODEX_ROOT="$tmp"
  ICODEX_HOME_DIR="$tmp/.codex-isolated"
  ICODEX_BIN="$ICODEX_HOME_DIR/bin/codex"
  ICODEX_STAMP="$ICODEX_HOME_DIR/bin/.codex-version"
  ICODEX_LOCKFILE="$tmp/.codex-lockfile.json"
  ICODEX_REPO="openai/codex"
  mkdir -p "$ICODEX_HOME_DIR/bin"
  _sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum|awk '{print $1}'; else shasum -a 256|awk '{print $1}'; fi; }
  # Build a fixture tarball containing an executable `codex`
  local stage="$tmp/stage"; mkdir -p "$stage"
  printf '#!/bin/sh\necho codex-fixture 0.0.0\n' > "$stage/codex"; chmod +x "$stage/codex"
  FIXTURE_TAR="$tmp/fixture.tar.gz"
  tar -czf "$FIXTURE_TAR" -C "$stage" codex
  FIXTURE_SHA="$(_sha256 < "$FIXTURE_TAR")"
  DL_CALLS=0
}

source "$ROOT/lib/binary/install.sh"

# --- Case A: clean install with matching pinned sha succeeds ---
setup_case
_download() { DL_CALLS=$((DL_CALLS+1)); cp "$FIXTURE_TAR" "$2"; }   # offline seam
lockfile_write "$ICODEX_LOCKFILE" "rust-v9.9.9" "codex-x86_64-unknown-linux-musl.tar.gz" "$FIXTURE_SHA"
assert_exit "install succeeds" 0 install_ensure
assert_exit "binary installed & executable" 0 test -x "$ICODEX_BIN"
assert_eq   "stamp == pinned tag" "rust-v9.9.9" "$(cat "$ICODEX_STAMP")"
rm -rf "$tmp"

# --- Case B: idempotent — second call does not re-download ---
setup_case
_download() { DL_CALLS=$((DL_CALLS+1)); cp "$FIXTURE_TAR" "$2"; }
lockfile_write "$ICODEX_LOCKFILE" "rust-v9.9.9" "codex-x86_64-unknown-linux-musl.tar.gz" "$FIXTURE_SHA"
install_ensure >/dev/null 2>&1
before="$DL_CALLS"
install_ensure >/dev/null 2>&1
assert_eq "no second download" "$before" "$DL_CALLS"
rm -rf "$tmp"

# --- Case C: sha mismatch stops install (tamper guard) ---
setup_case
_download() { DL_CALLS=$((DL_CALLS+1)); cp "$FIXTURE_TAR" "$2"; }
lockfile_write "$ICODEX_LOCKFILE" "rust-v9.9.9" "codex-x86_64-unknown-linux-musl.tar.gz" "deadbeef_wrong_sha"
assert_exit "mismatch -> non-zero" 1 install_ensure
assert_exit "binary NOT installed" 1 test -x "$ICODEX_BIN"
rm -rf "$tmp"

finish

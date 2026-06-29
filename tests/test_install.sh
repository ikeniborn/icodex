#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/core/init.sh"
source "$ROOT/lib/config/env.sh"
source "$ROOT/lib/binary/detect.sh"
source "$ROOT/lib/binary/lockfile.sh"

ICODEX_UNAME_S="Linux"; ICODEX_UNAME_M="x86_64"

setup_case() {
  tmp="$(mktemp -d)"
  ICODEX_ROOT="$tmp"
  ICODEX_HOME_DIR="$tmp/.codex-isolated"
  ICODEX_SHARED_DIR="$ICODEX_HOME_DIR"   # in tests the home IS the shared store
  ICODEX_BIN="$ICODEX_HOME_DIR/bin/codex"
  ICODEX_STAMP="$ICODEX_HOME_DIR/bin/.codex-version"
  ICODEX_LOCKFILE="$tmp/.codex-lockfile.json"
  ICODEX_CONFIG="$tmp/.codex_config"
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

# _curl_proxy_args emits "--proxy <url>" only when a proxy is set and not disabled
unset ICODEX_DISABLE_PROXY
out="$(ICODEX_PROXY='http://p:8080' _curl_proxy_args | tr '\n' ' ')"
assert_eq "proxy args when set"     "--proxy http://p:8080 " "$out"

out="$(ICODEX_PROXY='http://p:8080' ICODEX_DISABLE_PROXY=1 _curl_proxy_args | tr '\n' ' ')"
assert_eq "no args when disabled"   "" "$out"

out="$(unset ICODEX_PROXY; _curl_proxy_args | tr '\n' ' ')"
assert_eq "no args when unset"      "" "$out"

# --- uv dependency: copied into the permanent icodex install dir and persisted ---
setup_case
UV_FIXTURE="$tmp/source-uv"
printf '#!/bin/sh\necho uv-fixture\n' > "$UV_FIXTURE"; chmod +x "$UV_FIXTURE"
_uv_source_bin() { printf '%s\n' "$UV_FIXTURE"; }
_install_uv_from_network() { return 99; }
assert_exit "uv dependency installed" 0 ensure_uv_dependency
assert_exit "uv installed in isolated bin" 0 test -x "$ICODEX_HOME_DIR/bin/uv"
assert_eq "CODEX_UV_BIN persisted" "$ICODEX_HOME_DIR/bin/uv" "$(grep '^CODEX_UV_BIN=' "$ICODEX_CONFIG" | cut -d= -f2-)"
unset CODEX_UV_BIN UV_BIN
load_config "$ICODEX_CONFIG"
assert_eq "CODEX_UV_BIN maps to UV_BIN" "$ICODEX_HOME_DIR/bin/uv" "${UV_BIN:-}"
rm -rf "$tmp"

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

# --- Case D: --update resolves latest, installs, and rewrites the lockfile pin ---
setup_case
_download() { DL_CALLS=$((DL_CALLS+1)); cp "$FIXTURE_TAR" "$2"; }
_resolve_latest() { echo "rust-v1.2.3"; }
assert_exit "update installs" 0 install_ensure --update
assert_exit "update binary present" 0 test -x "$ICODEX_BIN"
assert_eq "update stamp" "rust-v1.2.3" "$(cat "$ICODEX_STAMP")"
assert_eq "update lockfile version" "rust-v1.2.3" "$(lockfile_get "$ICODEX_LOCKFILE" version)"
assert_eq "update lockfile sha" "$FIXTURE_SHA" "$(lockfile_get "$ICODEX_LOCKFILE" sha256)"
assert_eq "update lockfile asset" "codex-x86_64-unknown-linux-musl.tar.gz" "$(lockfile_get "$ICODEX_LOCKFILE" asset)"
rm -rf "$tmp"

# --- Case D2: --update accepts a new sha instead of comparing against the old pin ---
setup_case
_download() { DL_CALLS=$((DL_CALLS+1)); cp "$FIXTURE_TAR" "$2"; }
_resolve_latest() { echo "rust-v1.2.3"; }
lockfile_write "$ICODEX_LOCKFILE" "rust-v0.9.0" "codex-x86_64-unknown-linux-musl.tar.gz" "old_sha"
assert_exit "update ignores old sha pin" 0 install_ensure --update
assert_eq "update rewrites old sha" "$FIXTURE_SHA" "$(lockfile_get "$ICODEX_LOCKFILE" sha256)"
rm -rf "$tmp"

# --- Case D3: --update prints visible progress stages ---
setup_case
_download() { DL_CALLS=$((DL_CALLS+1)); cp "$FIXTURE_TAR" "$2"; }
_resolve_latest() { echo "rust-v1.2.3"; }
out="$(install_ensure --update 2>&1)"
assert_contains "update logs resolve" "$out" "resolving latest codex release"
assert_contains "update logs download" "$out" "downloading codex-x86_64-unknown-linux-musl.tar.gz"
assert_contains "update logs verify" "$out" "verifying sha256"
assert_contains "update logs extract" "$out" "extracting codex binary"
assert_contains "update logs lockfile" "$out" "writing lockfile"
rm -rf "$tmp"

# --- Case D4: failed binary replacement stops update before stamp/lockfile rewrite ---
setup_case
_download() { DL_CALLS=$((DL_CALLS+1)); command cp "$FIXTURE_TAR" "$2"; }
_resolve_latest() { echo "rust-v1.2.3"; }
printf '#!/bin/sh\necho old-codex\n' > "$ICODEX_BIN"; chmod +x "$ICODEX_BIN"
printf '%s\n' "rust-v0.9.0" > "$ICODEX_STAMP"
lockfile_write "$ICODEX_LOCKFILE" "rust-v0.9.0" "codex-x86_64-unknown-linux-musl.tar.gz" "old_sha"
cp() { return 1; }
assert_exit "update fails if binary replacement fails" 1 install_ensure --update
unset -f cp
assert_eq "failed update keeps old stamp" "rust-v0.9.0" "$(cat "$ICODEX_STAMP")"
assert_eq "failed update keeps old lockfile sha" "old_sha" "$(lockfile_get "$ICODEX_LOCKFILE" sha256)"
rm -rf "$tmp"

# --- Case E: empty pinned sha = trust-on-first-use (no mismatch, installs) ---
setup_case
_download() { DL_CALLS=$((DL_CALLS+1)); cp "$FIXTURE_TAR" "$2"; }
lockfile_write "$ICODEX_LOCKFILE" "rust-v9.9.9" "codex-x86_64-unknown-linux-musl.tar.gz" ""
assert_exit "empty sha trust-on-first-use" 0 install_ensure
assert_exit "empty sha binary present" 0 test -x "$ICODEX_BIN"
rm -rf "$tmp"

finish

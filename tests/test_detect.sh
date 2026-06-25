#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/binary/detect.sh"

ICODEX_UNAME_S="Linux"  ICODEX_UNAME_M="x86_64"
assert_eq "linux x86_64" "codex-x86_64-unknown-linux-musl.tar.gz" "$(detect_asset)"

ICODEX_UNAME_S="Linux"  ICODEX_UNAME_M="aarch64"
assert_eq "linux aarch64" "codex-aarch64-unknown-linux-musl.tar.gz" "$(detect_asset)"

ICODEX_UNAME_S="Darwin" ICODEX_UNAME_M="arm64"
assert_eq "darwin arm64" "codex-aarch64-apple-darwin.tar.gz" "$(detect_asset)"

ICODEX_UNAME_S="Darwin" ICODEX_UNAME_M="x86_64"
assert_eq "darwin x86_64" "codex-x86_64-apple-darwin.tar.gz" "$(detect_asset)"

ICODEX_UNAME_S="Plan9" ICODEX_UNAME_M="x86_64"
assert_exit "unsupported OS -> 1" 1 detect_asset

finish

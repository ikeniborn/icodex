#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/binary/lockfile.sh"

tmp="$(mktemp -d)"; lf="$tmp/lock.json"

lockfile_write "$lf" "rust-v0.142.2" "codex-x86_64-unknown-linux-musl.tar.gz" "abc123"
assert_eq "version round-trip" "rust-v0.142.2"                              "$(lockfile_get "$lf" version)"
assert_eq "asset round-trip"   "codex-x86_64-unknown-linux-musl.tar.gz"     "$(lockfile_get "$lf" asset)"
assert_eq "sha round-trip"     "abc123"                                     "$(lockfile_get "$lf" sha256)"

assert_exit "missing file -> 1" 1 lockfile_get "$tmp/nope.json" version

rm -rf "$tmp"
finish

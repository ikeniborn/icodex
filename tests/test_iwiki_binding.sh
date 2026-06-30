#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/iwiki/iwiki.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- seeds .iwiki.toml with domain == project basename when absent ---
export ICODEX_PROJECT_ROOT="$tmp/myproj"
export ICODEX_HOME_DIR="$tmp/home"
mkdir -p "$ICODEX_PROJECT_ROOT" "$ICODEX_HOME_DIR"
ensure_iwiki_binding
toml="$(cat "$ICODEX_PROJECT_ROOT/.iwiki.toml")"
assert_contains "seed read domain"  "$toml" 'read = ["myproj"]'
assert_contains "seed write domain" "$toml" 'write = "myproj"'
assert_eq "home symlink created" "0" "$([[ -L "$ICODEX_HOME_DIR/.iwiki.toml" ]] && echo 0 || echo 1)"
assert_eq "symlink target" "$ICODEX_PROJECT_ROOT/.iwiki.toml" "$(readlink "$ICODEX_HOME_DIR/.iwiki.toml")"

# --- never overwrites an existing project .iwiki.toml ---
printf 'read = ["custom"]\nwrite = "custom"\n' > "$ICODEX_PROJECT_ROOT/.iwiki.toml"
ensure_iwiki_binding
toml="$(cat "$ICODEX_PROJECT_ROOT/.iwiki.toml")"
assert_contains "existing preserved" "$toml" 'read = ["custom"]'
assert_eq "no basename overwrite" "0" "$(grep -c 'myproj' "$ICODEX_PROJECT_ROOT/.iwiki.toml")"

# --- idempotent: symlink stable across a second run ---
before="$(readlink "$ICODEX_HOME_DIR/.iwiki.toml")"
ensure_iwiki_binding
assert_eq "symlink stable" "$before" "$(readlink "$ICODEX_HOME_DIR/.iwiki.toml")"

# --- re-points a stale home symlink ---
rm -f "$ICODEX_HOME_DIR/.iwiki.toml"
ln -s "$tmp/old-target" "$ICODEX_HOME_DIR/.iwiki.toml"
ensure_iwiki_binding
assert_eq "stale symlink re-pointed" "$ICODEX_PROJECT_ROOT/.iwiki.toml" "$(readlink "$ICODEX_HOME_DIR/.iwiki.toml")"

# --- no-op when project root unset ---
unset ICODEX_PROJECT_ROOT
assert_exit "unset project root -> noop 0" 0 ensure_iwiki_binding

# --- no-op when home unset ---
export ICODEX_PROJECT_ROOT="$tmp/myproj"; unset ICODEX_HOME_DIR
assert_exit "unset home -> noop 0" 0 ensure_iwiki_binding

# --- pre-existing REAL file at home .iwiki.toml is left untouched ---
export ICODEX_PROJECT_ROOT="$tmp/proj2"
export ICODEX_HOME_DIR="$tmp/home2"
mkdir -p "$ICODEX_PROJECT_ROOT" "$ICODEX_HOME_DIR"
printf 'sentinel\n' > "$ICODEX_HOME_DIR/.iwiki.toml"
ensure_iwiki_binding
assert_eq "home real file not symlink" "1" "$([[ -L "$ICODEX_HOME_DIR/.iwiki.toml" ]] && echo 0 || echo 1)"
assert_contains "home real file untouched" "$(cat "$ICODEX_HOME_DIR/.iwiki.toml")" "sentinel"

# --- dangling symlink at project root .iwiki.toml is preserved ---
export ICODEX_PROJECT_ROOT="$tmp/proj3"
export ICODEX_HOME_DIR="$tmp/home3"
mkdir -p "$ICODEX_PROJECT_ROOT" "$ICODEX_HOME_DIR"
ln -s "$tmp/nonexistent-target" "$ICODEX_PROJECT_ROOT/.iwiki.toml"
ensure_iwiki_binding
assert_eq "project dangling symlink is symlink" "0" "$([[ -L "$ICODEX_PROJECT_ROOT/.iwiki.toml" ]] && echo 0 || echo 1)"
assert_eq "project dangling symlink target preserved" "$tmp/nonexistent-target" "$(readlink "$ICODEX_PROJECT_ROOT/.iwiki.toml")"

finish

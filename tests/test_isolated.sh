#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

tmp="$(mktemp -d)"
ICODEX_ROOT="$tmp"
source "$ROOT/lib/core/init.sh"     # defines ICODEX_SHARED_DIR/HOMES_DIR/_sha256
source "$ROOT/lib/config/isolated.sh"

# Build a shared store fixture: plugins dir + config template
mkdir -p "$ICODEX_SHARED_DIR/plugins"
printf 'sandbox_mode = "workspace-write"\n' > "$ICODEX_SHARED_DIR/config.toml"

# Run from a non-git working dir so resolve_project_root falls back to pwd -P
work="$tmp/work/sub"; mkdir -p "$work"
unset CODEX_HOME
( cd "$work" && declare -f >/dev/null )   # no-op guard

cd "$work"
export GIT_CEILING_DIRECTORIES="$tmp"   # keep git from finding a repo above tmp on CI hosts
resolve_codex_home
want_hash="$(printf '%s' "$work" | _sha256 | cut -c1-12)"
assert_eq "project root is cwd"   "$work" "$ICODEX_PROJECT_ROOT"
assert_eq "home id basename+hash" "$ICODEX_HOMES_DIR/sub-$want_hash" "$ICODEX_HOME_DIR"

setup_codex_home
assert_eq  "CODEX_HOME exported" "$ICODEX_HOME_DIR" "${CODEX_HOME:-}"
assert_exit "home created"       0 test -d "$ICODEX_HOME_DIR"
assert_exit "plugins symlink"    0 test -L "$ICODEX_HOME_DIR/plugins"
assert_eq  "plugins -> shared"   "$ICODEX_SHARED_DIR/plugins" "$(readlink "$ICODEX_HOME_DIR/plugins")"
assert_exit "auth symlink"       0 test -L "$ICODEX_HOME_DIR/auth.json"
assert_eq  "auth -> shared"      "$ICODEX_SHARED_DIR/auth.json" "$(readlink "$ICODEX_HOME_DIR/auth.json")"
assert_exit "config copied"      0 test -f "$ICODEX_HOME_DIR/config.toml"

# idempotent: a second setup leaves the symlinks intact and does not clobber config edits
printf 'edited = true\n' >> "$ICODEX_HOME_DIR/config.toml"
before="$(cat "$ICODEX_HOME_DIR/config.toml")"
setup_codex_home
assert_eq "config not clobbered on re-run" "$before" "$(cat "$ICODEX_HOME_DIR/config.toml")"

# setup_shared_dirs makes the shared bin dir
setup_shared_dirs
assert_exit "shared bin dir" 0 test -d "$ICODEX_SHARED_DIR/bin"

cd "$ROOT"
rm -rf "$tmp"
finish

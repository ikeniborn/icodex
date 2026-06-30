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
mkdir -p "$ICODEX_SHARED_DIR/skills"
mkdir -p "$ICODEX_SHARED_DIR/hooks"
printf 'sandbox_mode = "workspace-write"\n' > "$ICODEX_SHARED_DIR/config.toml"
printf '{"hooks":{}}\n' > "$ICODEX_SHARED_DIR/hooks.json"
printf '#!/usr/bin/env python3\n' > "$ICODEX_SHARED_DIR/hooks/example.py"
# skills fixture: a user skill plus a codex-managed .system dir
mkdir -p "$ICODEX_SHARED_DIR/skills/sample-skill" "$ICODEX_SHARED_DIR/skills/.system"
printf 'name: sample\n' > "$ICODEX_SHARED_DIR/skills/sample-skill/SKILL.md"
# rules fixture: the execution-policy file
mkdir -p "$ICODEX_SHARED_DIR/rules"
printf 'prefix_rule(pattern=["git"], decision="allow")\n' > "$ICODEX_SHARED_DIR/rules/default.rules"
# AGENTS.md base fixture (the global guidance that must reach the home)
printf '# Base guidelines\nLine one.\n' > "$ICODEX_SHARED_DIR/AGENTS.md"

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
assert_exit "skills symlink"     0 test -L "$ICODEX_HOME_DIR/skills"
assert_eq  "skills -> shared"    "$ICODEX_SHARED_DIR/skills" "$(readlink "$ICODEX_HOME_DIR/skills")"
assert_exit "hooks symlink"      0 test -L "$ICODEX_HOME_DIR/hooks"
assert_eq  "hooks -> shared"     "$ICODEX_SHARED_DIR/hooks" "$(readlink "$ICODEX_HOME_DIR/hooks")"
assert_exit "hooks json symlink" 0 test -L "$ICODEX_HOME_DIR/hooks.json"
assert_eq  "hooks json -> shared" "$ICODEX_SHARED_DIR/hooks.json" "$(readlink "$ICODEX_HOME_DIR/hooks.json")"
assert_exit "auth symlink"       0 test -L "$ICODEX_HOME_DIR/auth.json"
assert_eq  "auth -> shared"      "$ICODEX_SHARED_DIR/auth.json" "$(readlink "$ICODEX_HOME_DIR/auth.json")"
assert_exit "config copied"      0 test -f "$ICODEX_HOME_DIR/config.toml"
assert_exit "skills symlink"     0 test -L "$ICODEX_HOME_DIR/skills"
assert_eq  "skills -> shared"    "$ICODEX_SHARED_DIR/skills" "$(readlink "$ICODEX_HOME_DIR/skills")"
assert_exit "rules symlink"      0 test -L "$ICODEX_HOME_DIR/rules"
assert_eq  "rules -> shared"     "$ICODEX_SHARED_DIR/rules" "$(readlink "$ICODEX_HOME_DIR/rules")"
assert_exit "AGENTS.md created"  0 test -f "$ICODEX_HOME_DIR/AGENTS.md"
agents="$(cat "$ICODEX_HOME_DIR/AGENTS.md")"
assert_contains "AGENTS base marker start" "$agents" "<!-- icodex:base:start -->"
assert_contains "AGENTS base content"      "$agents" "Base guidelines"
assert_contains "AGENTS base marker end"   "$agents" "<!-- icodex:base:end -->"

# idempotent: a second setup leaves the symlinks intact and does not clobber config edits
printf 'edited = true\n' >> "$ICODEX_HOME_DIR/config.toml"
before="$(cat "$ICODEX_HOME_DIR/config.toml")"
setup_codex_home
assert_eq "config not clobbered on re-run" "$before" "$(cat "$ICODEX_HOME_DIR/config.toml")"

# base region re-syncs when the shared AGENTS.md changes
printf '# Base guidelines v2\nNew line.\n' > "$ICODEX_SHARED_DIR/AGENTS.md"
setup_codex_home
assert_contains "AGENTS base re-synced" "$(cat "$ICODEX_HOME_DIR/AGENTS.md")" "New line."
assert_exit "old base line removed" 1 grep -qF "Line one." "$ICODEX_HOME_DIR/AGENTS.md"

# a foreign (caveman-style) region outside the base markers must survive a re-sync;
# this run also stabilizes region order to [foreign][base]
printf '\n<!-- icodex:caveman:start -->\nCAVEMAN\n<!-- icodex:caveman:end -->\n' >> "$ICODEX_HOME_DIR/AGENTS.md"
setup_codex_home
agents_after="$(cat "$ICODEX_HOME_DIR/AGENTS.md")"
assert_contains "foreign region preserved"   "$agents_after" "CAVEMAN"
assert_contains "base region still present"   "$agents_after" "New line."

# idempotent: with the shared AGENTS.md unchanged and order already stable, a
# further setup leaves AGENTS.md byte-identical
before_agents="$(cat "$ICODEX_HOME_DIR/AGENTS.md")"
setup_codex_home
assert_eq "AGENTS.md stable on re-run" "$before_agents" "$(cat "$ICODEX_HOME_DIR/AGENTS.md")"

# setup_shared_dirs makes the shared bin dir
setup_shared_dirs
assert_exit "shared bin dir" 0 test -d "$ICODEX_SHARED_DIR/bin"

cd "$ROOT"
rm -rf "$tmp"
finish

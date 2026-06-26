#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/scripts/vendor-superpowers.sh"   # sourcing must not execute the wrapper

tmp="$(mktemp -d)"
# fake scratch cache with auto-derived marketplace name, nested .git + .gitignore
SRC="$tmp/scratch/plugins/cache/superpowers-dev/superpowers/6.0.3"
mkdir -p "$SRC/.codex-plugin" "$SRC/.git" "$SRC/skills/brainstorming"
printf '{}' > "$SRC/.codex-plugin/plugin.json"
printf 'tmp/\n' > "$SRC/.gitignore"
printf 'x\n'    > "$SRC/skills/brainstorming/.gitignore"

DEST="$tmp/.codex-isolated/plugins/cache"
_vendor_normalize "$SRC" "$DEST" superpowers 6.0.3
out="$DEST/superpowers/superpowers/6.0.3"

assert_exit "canonical path created"        0 test -f "$out/.codex-plugin/plugin.json"
assert_exit "nested .git stripped"          1 test -d "$out/.git"
assert_eq   "no nested .gitignore remains"  "0" "$(find "$out" -name .gitignore | wc -l | tr -d ' ')"
assert_exit "skill content preserved"       0 test -d "$out/skills/brainstorming"

rm -rf "$tmp"
finish

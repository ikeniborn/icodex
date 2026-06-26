#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/symlink/symlink.sh"

tmp="$(mktemp -d)"
ICODEX_ROOT="$tmp/repo"; mkdir -p "$ICODEX_ROOT"
printf '#!/usr/bin/env bash\n' > "$ICODEX_ROOT/icodex.sh"; chmod +x "$ICODEX_ROOT/icodex.sh"
ICODEX_LINK_DIR="$tmp/bin"

# creates the symlink pointing at icodex.sh
install_symlink >/dev/null 2>&1
assert_exit "symlink created"        0 test -L "$tmp/bin/icodex"
assert_eq   "points to icodex.sh"    "$ICODEX_ROOT/icodex.sh" "$(readlink "$tmp/bin/icodex")"

# idempotent: a second call leaves a correct symlink and returns 0
assert_exit "idempotent returns 0"   0 install_symlink
assert_exit "still a symlink"        0 test -L "$tmp/bin/icodex"

# a stale symlink (wrong target) is repaired
ln -sf /nowhere/icodex "$tmp/bin/icodex"
install_symlink >/dev/null 2>&1
assert_eq   "stale symlink repaired" "$ICODEX_ROOT/icodex.sh" "$(readlink "$tmp/bin/icodex")"

# an existing NON-symlink file is left untouched (no clobber)
rm -f "$tmp/bin/icodex"; printf 'mine\n' > "$tmp/bin/icodex"
install_symlink >/dev/null 2>&1
assert_eq   "non-symlink preserved"  "mine" "$(cat "$tmp/bin/icodex")"
assert_exit "not turned into symlink" 1 test -L "$tmp/bin/icodex"

# a leading ~/ in ICODEX_LINK_DIR is expanded to $HOME
HOME="$tmp/home" ICODEX_LINK_DIR="~/bin" install_symlink >/dev/null 2>&1
assert_exit "tilde dir expanded" 0 test -L "$tmp/home/bin/icodex"

rm -rf "$tmp"
finish

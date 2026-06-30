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

# --- ensure_path_entry: append a PATH export to the detected shell profile ---
# The link dir is kept OUT of the call's PATH so the function takes the write path;
# PATH is set to a minimal set so the function's helpers (grep/mkdir/...) resolve.
H1="$tmp/h1"; mkdir -p "$H1"
HOME="$H1" SHELL="/bin/bash" PATH="/usr/bin:/bin" ICODEX_LINK_DIR="$H1/.local/bin" ensure_path_entry >/dev/null 2>&1
assert_exit "bash profile created"      0 test -f "$H1/.bashrc"
assert_eq   "bash marker written"       "1" "$(grep -c 'added by icodex' "$H1/.bashrc" 2>/dev/null || echo 0)"
assert_eq   "bash export references dir" "1" "$(grep -c '.local/bin' "$H1/.bashrc" 2>/dev/null || echo 0)"

# idempotent: a second call does not duplicate the entry
HOME="$H1" SHELL="/bin/bash" PATH="/usr/bin:/bin" ICODEX_LINK_DIR="$H1/.local/bin" ensure_path_entry >/dev/null 2>&1
assert_eq   "bash entry not duplicated" "1" "$(grep -c 'added by icodex' "$H1/.bashrc" 2>/dev/null || echo 0)"

# already on PATH: profile is left untouched (not even created)
H2="$tmp/h2"; mkdir -p "$H2"
HOME="$H2" SHELL="/bin/bash" PATH="/usr/bin:/bin:$H2/.local/bin" ICODEX_LINK_DIR="$H2/.local/bin" ensure_path_entry >/dev/null 2>&1
assert_exit "no profile when already on PATH" 1 test -f "$H2/.bashrc"

# fish: writes fish_add_path to config.fish
H3="$tmp/h3"; mkdir -p "$H3"
HOME="$H3" SHELL="/usr/bin/fish" PATH="/usr/bin:/bin" ICODEX_LINK_DIR="$H3/.local/bin" ensure_path_entry >/dev/null 2>&1
assert_eq   "fish config written" "1" "$(grep -c 'fish_add_path' "$H3/.config/fish/config.fish" 2>/dev/null || echo 0)"

# unknown shell: manual hint only, no profile written
H4="$tmp/h4"; mkdir -p "$H4"
HOME="$H4" SHELL="/bin/unknownsh" PATH="/usr/bin:/bin" ICODEX_LINK_DIR="$H4/.local/bin" ensure_path_entry >/dev/null 2>&1
assert_exit "unknown shell writes no bashrc" 1 test -f "$H4/.bashrc"

# a pre-existing manual PATH edit (no marker) is respected — no duplicate added
H5="$tmp/h5"; mkdir -p "$H5"
printf 'export PATH="%s/.local/bin:$PATH"\n' "$H5" > "$H5/.bashrc"
HOME="$H5" SHELL="/bin/bash" PATH="/usr/bin:/bin" ICODEX_LINK_DIR="$H5/.local/bin" ensure_path_entry >/dev/null 2>&1
assert_eq "manual export not duplicated" "1" "$(grep -c '.local/bin' "$H5/.bashrc" 2>/dev/null || echo 0)"

rm -rf "$tmp"
finish

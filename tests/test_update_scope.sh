#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

tmp="$(mktemp -d)"
work="$tmp/repo"
mkdir -p "$work/lib/plugin" "$work/lib/core" "$work/lib/command" "$work/lib/binary" \
  "$work/lib/config" "$work/lib/proxy" "$work/lib/symlink" "$work/lib/launcher" \
  "$work/.codex-isolated/bin"

cp "$ROOT/icodex.sh" "$work/icodex.sh"
cp -R "$ROOT/lib" "$work/"
chmod +x "$work/icodex.sh"

cat >> "$work/lib/plugin/superpowers.sh" <<'EOF_STUB'
ensure_superpowers_wiring() {
  echo "ERROR: ensure_superpowers_wiring called during update" >&2
  return 99
}
EOF_STUB

cat > "$work/lib/plugin/iwiki.sh" <<'EOF_STUB'
ensure_iwiki_wiring() {
  echo "ERROR: ensure_iwiki_wiring called during update" >&2
  return 98
}
EOF_STUB

cat >> "$work/lib/core/validation.sh" <<'EOF_STUB'
require_tools() { return 0; }
EOF_STUB

cat >> "$work/lib/binary/install.sh" <<'EOF_STUB'
install_ensure() {
  [[ "${1:-}" == "--update" ]] || return 97
  echo "install_ensure $1" > "$ICODEX_ROOT/update-called"
  return 0
}
ensure_uv_dependency() {
  echo "uv" > "$ICODEX_ROOT/uv-called"
  return 0
}
EOF_STUB

cat >> "$work/lib/symlink/symlink.sh" <<'EOF_STUB'
install_symlink() { echo "symlink" > "$ICODEX_ROOT/symlink-called"; }
EOF_STUB

out="$("$work/icodex.sh" --update 2>&1)"
rc=$?
assert_eq "update exits zero" "0" "$rc"
assert_eq "install update called" "install_ensure --update" "$(cat "$work/update-called")"
assert_eq "uv dependency ensured" "uv" "$(cat "$work/uv-called")"
assert_eq "symlink refreshed" "symlink" "$(cat "$work/symlink-called")"
assert_eq "superpowers not called" "0" "$(grep -c 'ensure_superpowers_wiring called' <<<"$out")"
assert_eq "iwiki not called" "0" "$(grep -c 'ensure_iwiki_wiring called' <<<"$out")"

rm -rf "$tmp"
finish

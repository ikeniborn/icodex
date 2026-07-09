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
  echo "ERROR: ensure_superpowers_wiring called during install/update" >&2
  return 99
}
EOF_STUB

cat >> "$work/lib/plugin/loen.sh" <<'EOF_STUB'
ensure_loen_wiring() {
  echo "ERROR: ensure_loen_wiring called during install/update" >&2
  return 98
}
EOF_STUB

cat >> "$work/lib/core/validation.sh" <<'EOF_STUB'
require_tools() { return 0; }
EOF_STUB

cat >> "$work/lib/binary/install.sh" <<'EOF_STUB'
install_ensure() {
  if [[ "${1:-}" == "--update" ]]; then
    echo "install_ensure --update" > "$ICODEX_ROOT/update-called"
    return 0
  fi
  if [[ -z "${1:-}" ]]; then
    echo "install_ensure install" > "$ICODEX_ROOT/install-called"
    return 0
  fi
  return 97
}
ensure_uv_dependency() {
  echo "uv" >> "$ICODEX_ROOT/uv-called"
  return 0
}
EOF_STUB

cat >> "$work/lib/symlink/symlink.sh" <<'EOF_STUB'
install_symlink() { echo "symlink" >> "$ICODEX_ROOT/symlink-called"; }
EOF_STUB

update_out="$("$work/icodex.sh" --update 2>&1)"
update_rc=$?
assert_eq "update exits zero" "0" "$update_rc"
assert_eq "install update called" "install_ensure --update" "$(cat "$work/update-called")"
assert_contains "uv dependency ensured on update" "$(cat "$work/uv-called")" "uv"
assert_contains "symlink refreshed on update" "$(cat "$work/symlink-called")" "symlink"
assert_eq "superpowers not called on update" "0" "$(grep -c 'ensure_superpowers_wiring called' <<<"$update_out")"
assert_eq "loen not called on update" "0" "$(grep -c 'ensure_loen_wiring called' <<<"$update_out")"

install_out="$("$work/icodex.sh" --install 2>&1)"
install_rc=$?
assert_eq "install exits zero" "0" "$install_rc"
assert_eq "install ensure called" "install_ensure install" "$(cat "$work/install-called")"
assert_eq "superpowers not called on install" "0" "$(grep -c 'ensure_superpowers_wiring called' <<<"$install_out")"
assert_eq "loen not called on install" "0" "$(grep -c 'ensure_loen_wiring called' <<<"$install_out")"
assert_exit "install/update did not vendor LoEn" 1 test -d "$work/.codex-isolated/plugins/cache/ikeniborn/loen"

rm -rf "$tmp"
finish

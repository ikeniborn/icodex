#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

entry="$(cat "$ROOT/icodex.sh")"
assert_contains "entrypoint sources caveman module" "$entry" "caveman/caveman"
assert_contains "entrypoint calls caveman wiring"   "$entry" "ensure_caveman_wiring"

# ensure_caveman_wiring must run after ensure_superpowers_wiring on the run path.
sp_line="$(grep -n 'ensure_superpowers_wiring' "$ROOT/icodex.sh" | grep -v source | tail -1 | cut -d: -f1)"
cv_line="$(grep -n 'ensure_caveman_wiring' "$ROOT/icodex.sh" | tail -1 | cut -d: -f1)"
assert_eq "caveman wiring runs after superpowers" "1" \
  "$([[ -n "$sp_line" && -n "$cv_line" && "$cv_line" -gt "$sp_line" ]] && echo 1 || echo 0)"

example="$(cat "$ROOT/.codex_config.example")"
assert_contains "config example documents the var" "$example" "ICODEX_CAVEMAN_MODE"

finish

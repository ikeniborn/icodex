#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

script="$ROOT/scripts/vendor-caveman.sh"
assert_exit "vendor script exists"      0 test -f "$script"
assert_exit "vendor script executable"  0 test -x "$script"
body="$(cat "$script")"
assert_contains "targets upstream SKILL.md" "$body" "JuliusBrussee/caveman"
assert_contains "writes reference snapshot" "$body" "upstream-SKILL.md"

finish

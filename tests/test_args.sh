#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/command/args.sh"

reset() { ICODEX_CMD="run"; ICODEX_NO_PROXY=0; ICODEX_SET_PROXY=""; ICODEX_PASSTHROUGH=(); }

reset; parse_args --proxy "http://p:8080"
assert_eq "proxy url captured" "http://p:8080" "$ICODEX_SET_PROXY"
assert_eq "cmd still run"      "run"           "$ICODEX_CMD"

reset; parse_args --update
assert_eq "update cmd" "update" "$ICODEX_CMD"

reset; parse_args --no-proxy exec "hi"
assert_eq "no-proxy flag" "1" "$ICODEX_NO_PROXY"
assert_eq "passthrough joined" "exec hi" "${ICODEX_PASSTHROUGH[*]}"

reset; parse_args --model o3 -q
assert_eq "unknown flags passthrough" "--model o3 -q" "${ICODEX_PASSTHROUGH[*]}"

reset; parse_args -- --help
assert_eq "after -- goes to codex" "--help" "${ICODEX_PASSTHROUGH[*]}"

assert_contains "help text" "$(print_help)" "Usage:"

reset; if ( parse_args --proxy ) 2>/dev/null; then rc=0; else rc=1; fi
assert_eq "missing proxy url -> nonzero" "1" "$rc"

finish

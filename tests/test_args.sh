#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/command/args.sh"

reset() {
  ICODEX_CMD="run"
  ICODEX_DISABLE_PROXY=0
  ICODEX_SET_PROXY=""
  ICODEX_PASSTHROUGH=()
  ICODEX_FULL_ACCESS=0
  ICODEX_PROFILE_TOPIC=""
  ICODEX_PROFILE_TASK=""
}

reset; parse_args --proxy "http://p:8080"
assert_eq "proxy url captured" "http://p:8080" "$ICODEX_SET_PROXY"
assert_eq "cmd still run"      "run"           "$ICODEX_CMD"

reset; parse_args --update
assert_eq "update cmd" "update" "$ICODEX_CMD"

reset; parse_args --no-proxy exec "hi"
assert_eq "no-proxy flag" "1" "$ICODEX_DISABLE_PROXY"
assert_eq "passthrough joined" "exec hi" "${ICODEX_PASSTHROUGH[*]}"

reset; parse_args --model gpt-x
assert_eq "ordinary model flag passthrough" "--model gpt-x" "${ICODEX_PASSTHROUGH[*]}"

reset; parse_args --run-task demo build
assert_eq "run-task command" "profile-run-task" "$ICODEX_CMD"
assert_eq "run-task topic" "demo" "$ICODEX_PROFILE_TOPIC"
assert_eq "run-task task" "build" "$ICODEX_PROFILE_TASK"
assert_eq "run-task has no passthrough" "" "${ICODEX_PASSTHROUGH[*]}"

reset; parse_args --orchestrate demo
assert_eq "orchestrate command" "profile-orchestrate" "$ICODEX_CMD"
assert_eq "orchestrate topic" "demo" "$ICODEX_PROFILE_TOPIC"
assert_eq "orchestrate has no passthrough" "" "${ICODEX_PASSTHROUGH[*]}"

for args in "--run-task" "--run-task demo" "--run-task demo build extra" "--orchestrate" "--orchestrate demo extra"; do
  reset
  read -r -a argv <<<"$args"
  if ( parse_args "${argv[@]}" ) 2>/dev/null; then rc=0; else rc=1; fi
  assert_eq "$args rejects invalid arity" "1" "$rc"
done

reset; parse_args --export-profile-history archive.json
assert_eq "export history is not wrapper command" "run" "$ICODEX_CMD"
assert_eq "export history passthrough" "--export-profile-history archive.json" "${ICODEX_PASSTHROUGH[*]}"

reset; parse_args --import-profile-history archive.json
assert_eq "import history is not wrapper command" "run" "$ICODEX_CMD"
assert_eq "import history passthrough" "--import-profile-history archive.json" "${ICODEX_PASSTHROUGH[*]}"

reset; parse_args -- --help
assert_eq "after -- goes to codex" "--help" "${ICODEX_PASSTHROUGH[*]}"

assert_contains "help text" "$(print_help)" "Usage:"

reset; if ( parse_args --proxy ) 2>/dev/null; then rc=0; else rc=1; fi
assert_eq "missing proxy url -> nonzero" "1" "$rc"

reset; parse_args --full-access
assert_eq "full-access sets flag" "1" "$ICODEX_FULL_ACCESS"
assert_eq "full-access keeps run cmd" "run" "$ICODEX_CMD"

reset; parse_args --full-access -- foo
assert_eq "full-access then passthrough" "foo" "${ICODEX_PASSTHROUGH[*]}"

assert_contains "help documents full-access" "$(print_help)" "--full-access"

finish

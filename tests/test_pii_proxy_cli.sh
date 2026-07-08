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
  ICODEX_USE_PII_PROXY_FLAG=0
}

reset; parse_args --pii-proxy
assert_eq "pii flag set" "1" "$ICODEX_USE_PII_PROXY_FLAG"
assert_eq "pii flag keeps run" "run" "$ICODEX_CMD"

reset; parse_args --install-pii-proxy
assert_eq "install pii command" "install-pii-proxy" "$ICODEX_CMD"

reset; parse_args --check-pii-proxy
assert_eq "check pii command" "check-pii-proxy" "$ICODEX_CMD"

reset; parse_args --pii-proxy -- model prompt
assert_eq "pii passthrough" "model prompt" "${ICODEX_PASSTHROUGH[*]}"

help="$(print_help)"
assert_contains "help documents --pii-proxy" "$help" "--pii-proxy"
assert_contains "help documents install pii" "$help" "--install-pii-proxy"
assert_contains "help documents check pii" "$help" "--check-pii-proxy"
assert_contains "help documents config toggle" "$help" "ICODEX_USE_PII_PROXY"

finish

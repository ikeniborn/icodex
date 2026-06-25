#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"

# log_error writes to stderr and includes the message
err="$(log_error "boom" 2>&1 >/dev/null)"
assert_contains "log_error to stderr" "$err" "boom"

# log_info returns 0
log_info "hi" 2>/dev/null
assert_eq "log_info returns 0" "0" "$?"

finish

#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/core/validation.sh"

# All tools present (real environment) → 0
assert_exit "tools present" 0 require_tools

# Simulate a missing tool by overriding the seam
_has() { [[ "$1" != "tar" ]]; }   # pretend tar is absent
assert_exit "missing tar -> 1" 1 require_tools

finish

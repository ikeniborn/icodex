#!/usr/bin/env bash
# Dependency-free test helpers for icodex (mirrors the iclaude tests/ pattern).
set -uo pipefail

PASS=0
FAIL=0

assert_eq() { # <desc> <expected> <actual>
  local desc="$1" exp="$2" act="$3"
  if [[ "$exp" == "$act" ]]; then
    echo "PASS [$desc]"; PASS=$((PASS+1))
  else
    echo "FAIL [$desc]: expected '$exp' got '$act'"; FAIL=$((FAIL+1))
  fi
}

assert_exit() { # <desc> <expected_code> <cmd...>
  local desc="$1" exp="$2"; shift 2
  local code=0
  "$@" >/dev/null 2>&1 || code=$?
  if [[ "$code" == "$exp" ]]; then
    echo "PASS [$desc]"; PASS=$((PASS+1))
  else
    echo "FAIL [$desc]: exit $code want $exp"; FAIL=$((FAIL+1))
  fi
}

assert_contains() { # <desc> <haystack> <needle>
  local desc="$1" hay="$2" need="$3"
  if grep -qF -- "$need" <<<"$hay"; then
    echo "PASS [$desc]"; PASS=$((PASS+1))
  else
    echo "FAIL [$desc]: '$need' not found"; FAIL=$((FAIL+1))
  fi
}

finish() {
  echo "---"
  echo "PASS=$PASS FAIL=$FAIL"
  [[ "$FAIL" -eq 0 ]]
}

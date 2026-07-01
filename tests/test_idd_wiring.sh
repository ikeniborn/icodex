#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

assert_exit "idd module exists" 0 test -f "$ROOT/lib/idd/idd.sh"
if [[ ! -f "$ROOT/lib/idd/idd.sh" ]]; then
  finish
  exit $?
fi

export ICODEX_SHARED_DIR="$ROOT/.codex-isolated"
log_warn() { :; }

source "$ROOT/lib/caveman/caveman.sh"
source "$ROOT/lib/idd/idd.sh"

# Opt-out with only the shared base hooks must keep the shared symlink.
export ICODEX_HOME_DIR="$tmp/off-home"
mkdir -p "$ICODEX_HOME_DIR"
ln -s "$ICODEX_SHARED_DIR/hooks.json" "$ICODEX_HOME_DIR/hooks.json"
export ICODEX_IDD=off
ensure_idd_wiring
hooks_off_base="$(cat "$ICODEX_HOME_DIR/hooks.json")"
assert_eq "opt-out base hooks stays symlink" "0" "$([[ -L "$ICODEX_HOME_DIR/hooks.json" ]] && echo 0 || echo 1)"
assert_eq "opt-out base removes chain-gate" "0" "$(grep -c 'chain-gate.py' <<<"$hooks_off_base")"

# Home hooks.json starts as a symlink to the shared base file, like isolated.sh.
export ICODEX_HOME_DIR="$tmp/home"
mkdir -p "$ICODEX_HOME_DIR"
ln -s "$ICODEX_SHARED_DIR/hooks.json" "$ICODEX_HOME_DIR/hooks.json"

# Compose with caveman first, matching the launch path.
export ICODEX_CAVEMAN_MODE=full
ensure_caveman_wiring

unset ICODEX_IDD || true
ensure_idd_wiring
hooks="$(cat "$ICODEX_HOME_DIR/hooks.json")"
assert_contains "default-on adds gate" "$hooks" "chain-gate.py"
assert_contains "default-on adds nudge (--post)" "$hooks" 'chain-gate.py\" --post'
assert_exit "result is valid json" 0 python3 -c "import json; json.load(open('$ICODEX_HOME_DIR/hooks.json'))"
assert_contains "base block-secrets preserved" "$hooks" "block-secrets.py"
assert_contains "base redact-secrets preserved" "$hooks" "redact-secrets.py"
assert_contains "caveman hook preserved" "$hooks" "caveman-hook.py"
assert_contains "caveman event preserved" "$hooks" "UserPromptSubmit"

ensure_idd_wiring
count="$(grep -c "chain-gate.py" "$ICODEX_HOME_DIR/hooks.json")"
assert_eq "idempotent (gate+nudge = 2 refs)" "2" "$count"

export ICODEX_IDD=off
ensure_idd_wiring
hooks_off="$(cat "$ICODEX_HOME_DIR/hooks.json")"
assert_exit "opt-out result is valid json" 0 python3 -c "import json; json.load(open('$ICODEX_HOME_DIR/hooks.json'))"
assert_eq "opt-out removes chain-gate" "0" "$(grep -c 'chain-gate.py' <<<"$hooks_off")"
assert_contains "opt-out keeps block-secrets" "$hooks_off" "block-secrets.py"
assert_contains "opt-out keeps redact-secrets" "$hooks_off" "redact-secrets.py"
assert_contains "opt-out keeps caveman hook" "$hooks_off" "caveman-hook.py"

finish

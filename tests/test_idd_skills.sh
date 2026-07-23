#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

SK="$ROOT/.codex-isolated/skills"
export ICODEX_ROOT="$ROOT"
export ICODEX_SHARED_DIR="$ROOT/.codex-isolated"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/plugin/superpowers.sh"
SP="$(_superpowers_pinned_cache_dir)/skills"

parse_frontmatter() { # <file> — exit 0 iff YAML frontmatter has name + description
  python3 - "$1" <<'PY'
import sys, yaml
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
assert lines and lines[0].strip() == "---"
fm = []
for ln in lines[1:]:
    if ln.strip() == "---":
        break
    fm.append(ln)
d = yaml.safe_load("\n".join(fm))
assert isinstance(d, dict) and d.get("name") and d.get("description")
PY
}

assert_before() { # <desc> <haystack> <first> <second>
  local desc="$1" hay="$2" first="$3" second="$4"
  local first_line second_line
  first_line="$(grep -nF -- "$first" <<<"$hay" | head -n1 | cut -d: -f1)"
  second_line="$(grep -nF -- "$second" <<<"$hay" | head -n1 | cut -d: -f1)"
  if [[ -n "$first_line" && -n "$second_line" && "$first_line" -lt "$second_line" ]]; then
    echo "PASS [$desc]"; PASS=$((PASS+1))
  else
    echo "FAIL [$desc]: '$first' must appear before '$second'"; FAIL=$((FAIL+1))
  fi
}

# check-chain: one unified validator, four stage profiles.
CC="$SK/check-chain/SKILL.md"
assert_exit "check-chain SKILL.md exists" 0 test -f "$CC"
if [[ -f "$CC" ]]; then
  body="$(cat "$CC")"
  assert_contains "check-chain name frontmatter" "$body" "name: check-chain"
  assert_contains "check-chain has a description" "$body" "description:"
  assert_contains "check-chain references intent_hash" "$body" "intent_hash"
  assert_contains "check-chain references spec_hash" "$body" "spec_hash"
  assert_contains "check-chain references plan_hash" "$body" "plan_hash"
  assert_contains "check-chain covers result stage" "$body" "result_check"
  assert_contains "check-chain approval requires OK first" "$body" 'Human approval is requested only after this stage returns `OK`'
  assert_exit "check-chain frontmatter parses" 0 parse_frontmatter "$CC"
fi

# fix-intent: intent capture skill.
FI="$SK/fix-intent/SKILL.md"
assert_exit "fix-intent SKILL.md exists" 0 test -f "$FI"
if [[ -f "$FI" ]]; then
  body="$(cat "$FI")"
  assert_contains "fix-intent name frontmatter" "$body" "name: fix-intent"
  assert_contains "fix-intent has a description" "$body" "description:"
  assert_contains "fix-intent runs check before approval" "$body" 'Run `$check-chain intent'
  assert_before "fix-intent check-chain before approval" "$body" 'Run `$check-chain intent' 'On approval: set `Status: approved`'
  assert_exit "fix-intent frontmatter parses" 0 parse_frontmatter "$FI"
fi

BR="$SP/brainstorming/SKILL.md"
assert_exit "brainstorming SKILL.md exists" 0 test -f "$BR"
if [[ -f "$BR" ]]; then
  body="$(cat "$BR")"
  assert_contains "brainstorming runs spec check before approval" "$body" 'Run `$check-chain spec <path>`'
  assert_contains "brainstorming distinguishes provisional feedback" "$body" "provisional design-section feedback"
  assert_contains "brainstorming needs_work returns to source" "$body" 'verdict is `needs_work`'
  assert_before "brainstorming check-chain before spec approval" "$body" 'Run `$check-chain spec <path>`' "Only proceed once the user approves the checked spec"
  assert_before "brainstorming fixes before successful recheck" "$body" '2. If the verdict is `needs_work`' '3. If the verdict is `OK`'
  assert_before "brainstorming approval before commit" "$body" "approves the checked spec" "commit the spec document once"
  assert_before "brainstorming commit before plan handoff" "$body" "commit the spec document once" "Invoke the writing-plans skill"
  assert_contains "brainstorming commits after checked spec approval" "$body" "commit the spec document once"
fi

WP="$SP/writing-plans/SKILL.md"
assert_exit "writing-plans SKILL.md exists" 0 test -f "$WP"
if [[ -f "$WP" ]]; then
  body="$(cat "$WP")"
  assert_contains "writing-plans runs plan check before approval" "$body" 'Run `$check-chain plan <path>`'
  assert_contains "writing-plans needs_work returns to source" "$body" 'verdict is `needs_work`'
  assert_before "writing-plans check-chain before plan approval" "$body" 'Run `$check-chain plan <path>`' "Only after the user approves the checked plan"
  assert_before "writing-plans fixes before successful recheck" "$body" '2. If the verdict is `needs_work`' '3. If the verdict is `OK`'
  assert_before "writing-plans approval before commit" "$body" "approves the checked plan" "Commit the approved plan"
  assert_before "writing-plans commit before execution handoff" "$body" "Commit the approved plan" "offer execution choice"
  assert_contains "writing-plans offers execution after checked plan" "$body" 'After the plan has passed `$check-chain plan <path>`'
fi

finish

#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
cd "$ROOT"

assert_not_contains() { # <desc> <haystack> <needle>
  local desc="$1" hay="$2" need="$3"
  if grep -qF -- "$need" <<<"$hay"; then
    echo "FAIL [$desc]: unexpected '$need' found"; FAIL=$((FAIL+1))
  else
    echo "PASS [$desc]"; PASS=$((PASS+1))
  fi
}

SK=".codex-isolated/skills"
export ICODEX_ROOT="$ROOT"
export ICODEX_SHARED_DIR="$ROOT/.codex-isolated"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/plugin/superpowers.sh"
SP="$(_superpowers_pinned_cache_dir)/skills"

CC="$(cat "$SK/check-chain/SKILL.md")"
FI="$(cat "$SK/fix-intent/SKILL.md")"
HR="$(cat "$SK/html-report/SKILL.md")"
CR="$(cat "$SK/html-report/references/chain-report.md")"
BR="$(cat "$SP/brainstorming/SKILL.md")"
WP="$(cat "$SP/writing-plans/SKILL.md")"

assert_contains "check-chain forbids intermediate HTML reports" "$CC" 'Intermediate stages (`intent`, `spec`, `plan`) do not invoke `html-report`'
assert_contains "check-chain result owns optional final report" "$CC" 'Only the `result` stage may offer to generate or refresh the chain HTML report'
assert_contains "check-chain result asks before final report" "$CC" 'Ask the user in Russian whether to generate the HTML report'
assert_contains "check-chain result skips declined final report" "$CC" 'If the user declines, do not invoke `html-report`'
assert_contains "check-chain final report covers whole task" "$CC" "single final report for the completed task"
assert_contains "check-chain final report describes concrete changes" "$CC" "concrete Russian description of the specific change made within this task"
assert_contains "check-chain final report records obtained result" "$CC" "what result was obtained"
assert_contains "check-chain final report requires process diagrams when needed" "$CC" "Add process diagrams when workflow"
assert_contains "check-chain cached non-result stays markdown-only" "$CC" 'Cached quick-exit runs for `intent`, `spec`, and `plan` do not regenerate HTML'
assert_contains "html-report documents result-only chain mode" "$HR" 'In `mode: chain`, the caller is the `result` stage'
assert_contains "chain-report documents result-only offer" "$CR" 'The HTML report may be offered only at `check-chain result`'
assert_contains "chain-report documents declined report skip" "$CR" 'If the user declines, no HTML report is generated or refreshed'
assert_contains "chain-report documents concrete change descriptions" "$CR" "concrete Russian description of the specific change made within this task"

assert_not_contains "fix-intent does not require generated HTML approval" "$FI" "generated HTML report"
assert_not_contains "fix-intent does not present intent HTML" "$FI" "intent HTML report"
assert_not_contains "brainstorming does not regenerate spec HTML" "$BR" "regenerate the HTML report"
assert_not_contains "brainstorming does not require generated HTML approval" "$BR" "generated HTML report"
assert_not_contains "writing-plans does not require checked HTML approval" "$WP" "checked HTML report"
assert_not_contains "writing-plans does not require generated HTML approval" "$WP" "generated HTML report"
assert_contains "brainstorming keeps intermediate review terminal-only" "$BR" "terminal review summary"
assert_contains "writing-plans keeps intermediate review terminal-only" "$WP" "terminal review summary"
assert_not_contains "brainstorming does not offer intermediate HTML" "$BR" "offer to generate the HTML report"
assert_not_contains "writing-plans does not offer intermediate HTML" "$WP" "offer to generate the HTML report"

finish

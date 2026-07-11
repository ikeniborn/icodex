#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
cd "$ROOT"

CC=".codex-isolated/skills/check-chain/SKILL.md"
HR=".codex-isolated/skills/html-report/SKILL.md"
CR=".codex-isolated/skills/html-report/references/chain-report.md"
README_RU="docs/README.ru.md"

cc_text="$(cat "$CC")"
hr_text="$(cat "$HR")"
cr_text="$(cat "$CR")"
readme_ru_text="$(cat "$README_RU")"

assert_contains "check-chain has Russian terminal summary section" "$cc_text" "### Step 4B — Russian terminal review summaries"
assert_contains "check-chain summary applies to intent spec plan" "$cc_text" 'For `intent`, `spec`, and `plan`, print a Russian terminal review summary after the stage verdict is known'
assert_contains "check-chain OK summary heading" "$cc_text" '#### `OK` summary'
assert_contains "check-chain needs_work summary heading" "$cc_text" '#### `needs_work` summary'
assert_contains "check-chain OK includes approval question" "$cc_text" 'The `OK` summary includes `Что нужно подтвердить`'
assert_contains "check-chain needs_work forbids approval question" "$cc_text" 'The `needs_work` summary must not ask the user to approve the stage'
assert_contains "check-chain English markdown source of truth" "$cc_text" 'English markdown artifacts remain the source of truth'
assert_contains "check-chain summaries are not gate state" "$cc_text" 'The Russian summary is not machine-readable gate state'
assert_contains "check-chain summary no invention" "$cc_text" 'Do not invent requirements, risks, decisions, dependencies, acceptance criteria, or scope in the summary'
assert_contains "check-chain no external translation" "$cc_text" 'Do not use external translation services or runtime network calls'
assert_contains "check-chain result-only html remains" "$cc_text" 'Only the `result` stage generates or refreshes the chain HTML report'
assert_contains "check-chain pre-result no html" "$cc_text" 'The `intent`, `spec`, and `plan` summaries do not invoke `html-report`'

assert_contains "html-report final result only" "$hr_text" '`mode: chain` is the final-result HTML path'
assert_contains "html-report not pre-result surface" "$hr_text" 'It is not used for `intent`, `spec`, or `plan` terminal review summaries'
assert_contains "html-report no direct chain reads still" "$hr_text" "does not read intent, spec, plan, or result markdown sources in chain mode"

assert_contains "chain-report generated only at result" "$cr_text" 'The HTML report is generated only at `check-chain result`'
assert_contains "chain-report terminal review before result" "$cr_text" 'Before `result`, the user reviews Russian terminal summaries printed by `check-chain intent`, `check-chain spec`, and `check-chain plan`'
assert_contains "chain-report markdown feedback loop" "$cr_text" 'Feedback before implementation is applied to the English markdown source first'

assert_contains "readme documents Russian terminal review" "$readme_ru_text" "русское резюме в терминале"
assert_contains "readme documents English artifacts" "$readme_ru_text" "английские markdown-артефакты"
assert_contains "readme documents final html result" "$readme_ru_text" "HTML-отчёт формируется"

finish

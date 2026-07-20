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
assert_contains "check-chain result html is optional" "$cc_text" 'HTML report generation is optional even at `result`'
assert_contains "check-chain result asks before html" "$cc_text" 'Ask the user in Russian whether to generate the HTML report'
assert_contains "check-chain result honors html refusal" "$cc_text" 'If the user declines, do not invoke `html-report`'
assert_contains "check-chain pre-result no html" "$cc_text" 'The `intent`, `spec`, and `plan` summaries do not invoke `html-report`'
assert_contains "check-chain spec challenges errors and completeness" "$cc_text" 'The `spec` stage must challenge the design for errors, completeness, requirement coverage, acceptance criteria, risks, mitigations, and human checkpoints'
assert_contains "check-chain spec reports found errors" "$cc_text" '`Найденные ошибки и спорные места`'
assert_contains "check-chain spec reports fixed items" "$cc_text" '`Что исправлено или доработано`'
assert_contains "check-chain spec reports design outcome" "$cc_text" '`Что будет спроектировано`'
assert_contains "check-chain spec reports closed requirements" "$cc_text" '`Какие требования будут закрыты`'
assert_contains "check-chain spec reports acceptance criteria" "$cc_text" '`Критерии приёмки`'
assert_contains "check-chain spec reports missing requirements" "$cc_text" '`Каких требований или критериев не хватает`'
assert_contains "check-chain plan challenges errors and completeness" "$cc_text" 'The `plan` stage must challenge the plan for errors, completeness, expected outputs, solved problems, verification evidence, and human checkpoints'
assert_contains "check-chain plan reports found errors" "$cc_text" '`Найденные ошибки и спорные места`'
assert_contains "check-chain plan reports fixed items" "$cc_text" '`Что исправлено или доработано`'
assert_contains "check-chain plan reports implementation outcome" "$cc_text" '`Что будет реализовано`'
assert_contains "check-chain plan reports closed problems" "$cc_text" '`Какие проблемы будут закрыты`'
assert_contains "check-chain plan reports remaining work" "$cc_text" '`Что ещё нужно доработать`'
assert_contains "check-chain plan recursive review loop" "$cc_text" 'Plan review may recurse: finding -> fix the English source artifact -> rerun `check-chain plan` -> print a fresh Russian summary'
assert_contains "check-chain plan asks user on forks" "$cc_text" 'Ask the user only when a real fork remains'
assert_contains "check-chain routine fixable findings self repair" "$cc_text" 'For routine fixable findings, fix the English source instead of asking the user for a verdict'
assert_contains "check-chain verdicts only on real forks" "$cc_text" 'Request user verdicts only when a real fork remains'
assert_contains "check-chain plan forbids result claims" "$cc_text" 'During `plan`, describe expected outcomes only; actual implementation evidence belongs to `result`'

assert_contains "html-report final result only optional" "$hr_text" '`mode: chain` is the optional final-result HTML path'
assert_contains "html-report not pre-result surface" "$hr_text" 'It is not used for `intent`, `spec`, or `plan` terminal review summaries'
assert_contains "html-report no direct chain reads still" "$hr_text" "does not read intent, spec, plan, or result markdown sources in chain mode"

assert_contains "chain-report offered only at result" "$cr_text" 'The HTML report may be offered only at `check-chain result`'
assert_contains "chain-report refusal skips generation" "$cr_text" 'If the user declines, no HTML report is generated or refreshed'
assert_contains "chain-report terminal review before result" "$cr_text" 'Before `result`, the user reviews Russian terminal summaries printed by `check-chain intent`, `check-chain spec`, and `check-chain plan`'
assert_contains "chain-report markdown feedback loop" "$cr_text" 'Feedback before implementation is applied to the English markdown source first'

assert_contains "readme documents Russian terminal review" "$readme_ru_text" "русское резюме в терминале"
assert_contains "readme documents English artifacts" "$readme_ru_text" "английские markdown-артефакты"
assert_contains "readme documents optional final html result" "$readme_ru_text" 'на `check-chain result` агент спрашивает, нужен ли HTML-отчёт'
assert_contains "readme documents declined html skipped" "$readme_ru_text" "если пользователь отказывается, HTML не создаётся и не обновляется"
assert_contains "readme documents spec design review" "$readme_ru_text" "проверяет дизайн на ошибки и полноту"
assert_contains "readme documents spec design outcome" "$readme_ru_text" "что будет спроектировано"
assert_contains "readme documents spec acceptance criteria" "$readme_ru_text" "какие критерии приёмки подтверждают дизайн"
assert_contains "readme documents plan error review" "$readme_ru_text" "проверяет план на ошибки и полноту"
assert_contains "readme documents plan expected outcome" "$readme_ru_text" "что будет реализовано"
assert_contains "readme documents plan closed problems" "$readme_ru_text" "какие проблемы или требования план закрывает"

finish

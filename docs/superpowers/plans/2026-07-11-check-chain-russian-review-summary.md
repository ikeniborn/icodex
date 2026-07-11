---
review:
  plan_hash: 6eb85afa5df5b657
  last_run: 2026-07-11
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-07-11-check-chain-russian-review-summary-intent.md
  spec: docs/superpowers/specs/2026-07-11-check-chain-russian-review-summary-design.md
---
# Check-Chain Russian Review Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a documented `check-chain` contract where `intent`, `spec`, and `plan` print Russian terminal review summaries while final HTML remains `result`-only.

**Architecture:** This is an instruction-contract change, not a Bash wrapper runtime change. `check-chain` owns the terminal summary contract because it owns stage verdicts, findings, artifact links, and approval flow. `html-report` stays the final-result HTML renderer and does not become a pre-implementation review surface.

**Tech Stack:** Markdown skill instructions, dependency-free Bash tests with `tests/helpers.sh`, iwiki documentation updates through MCP tools.

---

## File Structure

- Create `tests/test_check_chain_russian_review_summary.sh`: focused contract test for terminal-summary behavior and result-only HTML boundaries.
- Modify `.codex-isolated/skills/check-chain/SKILL.md`: add Russian terminal review summaries for `intent`, `spec`, and `plan`; define `OK` and `needs_work` forms; keep result-only HTML.
- Modify `.codex-isolated/skills/html-report/SKILL.md`: clarify that chain HTML is final-result-only and not used for pre-result review.
- Modify `.codex-isolated/skills/html-report/references/chain-report.md`: clarify the final report scope and the terminal review flow before implementation.
- Modify `docs/README.ru.md`: add a short Russian user-facing note about IDD -> SDD review: English artifacts, Russian terminal approval summaries, final HTML at `result`.
- Update `docs/TODO.md` through `check-chain plan` after the plan is checked.
- Update iwiki page `testing-and-project-state`, heading `Superpowers Artifacts`, after implementation changes are complete.

## Task 1: Add Failing Contract Test

**Files:**
- Create: `tests/test_check_chain_russian_review_summary.sh`
- Test: `bash tests/test_check_chain_russian_review_summary.sh`

- [ ] **Step 1: Create the focused test**

Create `tests/test_check_chain_russian_review_summary.sh` with this exact content:

```bash
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
assert_contains "readme documents final html result" "$readme_ru_text" "итоговый HTML-отчёт"

finish
```

- [ ] **Step 2: Run the focused test and confirm the expected failure**

Run:

```bash
bash tests/test_check_chain_russian_review_summary.sh
```

Expected: the command exits non-zero with several `FAIL` lines for the missing Russian terminal summary contract strings.

- [ ] **Step 3: Commit the failing test**

Run:

```bash
git add tests/test_check_chain_russian_review_summary.sh
git commit -m "test(chain): cover Russian terminal review summaries"
```

Expected: one commit containing only `tests/test_check_chain_russian_review_summary.sh`.

## Task 2: Add `check-chain` Terminal Summary Contract

**Files:**
- Modify: `.codex-isolated/skills/check-chain/SKILL.md`
- Test: `bash tests/test_check_chain_russian_review_summary.sh`

- [ ] **Step 1: Insert the terminal summary section**

In `.codex-isolated/skills/check-chain/SKILL.md`, insert this section after `### Step 4 — final verdict` and before `### Step 4A — docs and wiki consistency`:

```markdown
### Step 4B — Russian terminal review summaries

For `intent`, `spec`, and `plan`, print a Russian terminal review summary after the stage verdict is known. The summary is the user-facing review surface before implementation; it does not replace the English markdown artifact and does not create HTML.

English markdown artifacts remain the source of truth for the IDD -> SDD chain. If the user requests changes, fix the English markdown source first, rerun the relevant `check-chain <stage>`, and print a fresh Russian summary.

The Russian summary is not machine-readable gate state, is not written into frontmatter, and is not consumed by downstream automation. It is explanatory terminal output only.

#### `OK` summary

When the stage returns `OK`, print an approval-oriented summary with these Russian sections:

1. `Что проверено` — stage key, artifact path, verdict, and linked artifacts.
2. `Что означает документ` — concise explanation of the artifact meaning.
3. `Покрытие и связи` — how the artifact covers upstream outcomes, requirements, or plan steps.
4. `Риски и ограничения` — approval-relevant constraints, hard limits, human checkpoints, and known risks.
5. `Что нужно подтвердить` — the exact approval question for the user.
6. `Source anchors` — paths, section names, finding IDs, hashes, or short fragments that make the summary traceable.

The `OK` summary includes `Что нужно подтвердить` because approval is allowed only after the stage passes.

#### `needs_work` summary

When the stage returns `needs_work`, print a blocker-oriented summary with these Russian sections:

1. `Что проверено` — stage key and artifact path.
2. `Почему этап не прошёл` — open CRITICAL findings and important WARNING findings in Russian.
3. `Что исправить` — concrete source changes needed before rerun.
4. `Source anchors` — finding IDs, paths, section names, hashes, or short fragments.

The `needs_work` summary must not ask the user to approve the stage.

#### Summary language and anchors

All explanatory terminal-review text is Russian. Technical terms may remain untranslated when translation would reduce precision: paths, function names, code identifiers, stage keys, hash keys, finding IDs, and short source fragments.

Do not invent requirements, risks, decisions, dependencies, acceptance criteria, or scope in the summary. Every summary statement must be anchored in the current artifact body, linked chain artifacts, frontmatter review state, result evidence when applicable, or conversation context available to the stage.

Do not use external translation services or runtime network calls. The summary is written by the agent from the checked source material.

The `intent`, `spec`, and `plan` summaries do not invoke `html-report`; only the `result` stage generates or refreshes the chain HTML report.
```

- [ ] **Step 2: Clarify stage-specific summary content**

In the same file, after the section from Step 1, add:

```markdown
#### Stage-specific summary focus

- `intent`: objective, desired outcomes, health metrics, hard constraints, autonomy zones, stop rules, and what the user approves before design work proceeds.
- `spec`: implementation direction, requirements, acceptance criteria, component and boundary decisions, risks, mitigations, and coverage of linked intent outcomes when available.
- `plan`: execution order, dependencies, touched artifacts, verification commands, expected evidence, human checkpoints, and coverage of linked spec requirements when available.
- `result`: no separate terminal approval summary is required because the final Russian HTML report is the closeout artifact.
```

- [ ] **Step 3: Run the focused test and confirm partial progress**

Run:

```bash
bash tests/test_check_chain_russian_review_summary.sh
```

Expected: all `check-chain` assertions pass; `html-report`, `chain-report`, and `README.ru.md` assertions still fail.

- [ ] **Step 4: Commit the `check-chain` contract update**

Run:

```bash
git add .codex-isolated/skills/check-chain/SKILL.md
git commit -m "docs(chain): add Russian terminal review summary contract"
```

Expected: one commit modifying only `.codex-isolated/skills/check-chain/SKILL.md`.

## Task 3: Clarify `html-report` Final-Result Boundary

**Files:**
- Modify: `.codex-isolated/skills/html-report/SKILL.md`
- Modify: `.codex-isolated/skills/html-report/references/chain-report.md`
- Test: `bash tests/test_check_chain_russian_review_summary.sh`

- [ ] **Step 1: Update `html-report` chain boundary**

In `.codex-isolated/skills/html-report/SKILL.md`, under `### Chain-mode final payload boundary`, add this paragraph after the first paragraph:

```markdown
`mode: chain` is the final-result HTML path. It is not used for `intent`, `spec`, or `plan` terminal review summaries. Before implementation, `check-chain` prints Russian terminal summaries directly and keeps English markdown artifacts as the source of truth.
```

- [ ] **Step 2: Update `chain-report` caller contract**

In `.codex-isolated/skills/html-report/references/chain-report.md`, replace the first paragraph with:

```markdown
`mode: chain` produces ONE unified HTML report for a whole IDD→SDD task. The HTML report is generated only at `check-chain result`, after implementation evidence exists. Earlier `intent`, `spec`, and `plan` validations update frontmatter and `docs/TODO.md`, then print Russian terminal review summaries for approval; they do not create or refresh HTML.
```

- [ ] **Step 3: Update `chain-report` review flow**

In the `## Review Flow` section of `.codex-isolated/skills/html-report/references/chain-report.md`, replace the first paragraph with:

```markdown
Before `result`, the user reviews Russian terminal summaries printed by `check-chain intent`, `check-chain spec`, and `check-chain plan`. Feedback before implementation is applied to the English markdown source first, then the relevant `check-chain <stage>` validation is rerun and a fresh Russian terminal summary is printed. No HTML is regenerated until `check-chain result`.
```

- [ ] **Step 4: Run the focused test and confirm partial progress**

Run:

```bash
bash tests/test_check_chain_russian_review_summary.sh
```

Expected: `check-chain`, `html-report`, and `chain-report` assertions pass; `README.ru.md` assertions still fail.

- [ ] **Step 5: Commit report-boundary updates**

Run:

```bash
git add .codex-isolated/skills/html-report/SKILL.md .codex-isolated/skills/html-report/references/chain-report.md
git commit -m "docs(report): keep chain HTML result-only"
```

Expected: one commit modifying only the two `html-report` instruction files.

## Task 4: Document User-Facing Review Workflow

**Files:**
- Modify: `docs/README.ru.md`
- Test: `bash tests/test_check_chain_russian_review_summary.sh`

- [ ] **Step 1: Add the Russian review workflow section**

In `docs/README.ru.md`, add this section after the current introduction and before `## Как работает изоляция`:

```markdown
## Review flow для IDD -> SDD

В цепочке `intent -> spec -> plan -> result` английские markdown-артефакты остаются source of truth: именно они проходят проверки, попадают в plan/result reconciliation и читаются агентами.

Перед выполнением работ пользователь принимает смысл на русском: `check-chain intent`, `check-chain spec` и `check-chain plan` после проверки печатают русское резюме в терминале. Если нужны правки, они вносятся в английский artifact, затем соответствующий `check-chain <stage>` запускается снова и печатает новое резюме.

Промежуточный HTML для `intent`, `spec` и `plan` не создаётся. Итоговый HTML-отчёт формируется только на `check-chain result`, когда уже есть implementation evidence, diff reconciliation, verification evidence и documentation evidence.
```

- [ ] **Step 2: Run the focused test and confirm it passes**

Run:

```bash
bash tests/test_check_chain_russian_review_summary.sh
```

Expected: output ends with `FAIL=0`.

- [ ] **Step 3: Commit repository docs update**

Run:

```bash
git add docs/README.ru.md
git commit -m "docs(readme): explain Russian chain review flow"
```

Expected: one commit modifying only `docs/README.ru.md`.

## Task 5: Verify, Update Wiki, And Run Result Checks

**Files:**
- Modify through MCP: iwiki domain `icodex`, page `testing-and-project-state`, heading `Superpowers Artifacts`
- Modify through check-chain: `docs/TODO.md`
- Modify through check-chain: `docs/superpowers/plans/2026-07-11-check-chain-russian-review-summary.md`
- Generate through check-chain result: `docs/superpowers/reports/check-chain-russian-review-summary-results.html`
- Test: focused test and full Bash suite

- [ ] **Step 1: Run the focused test**

Run:

```bash
bash tests/test_check_chain_russian_review_summary.sh
```

Expected: `PASS` lines for all assertions and final `FAIL=0`.

- [ ] **Step 2: Run related existing report tests**

Run:

```bash
bash tests/test_chain_report_quality.sh
bash tests/test_chain_result_report_contract.sh
```

Expected: both commands exit `0`.

- [ ] **Step 3: Run the full Bash suite**

Run:

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: command exits `0`. If a pre-existing unrelated failure appears, record the failing test, command output summary, and why it is unrelated before continuing.

- [ ] **Step 4: Update iwiki documentation**

Use MCP tools:

1. `wiki_status`
2. `wiki_bind(read=["icodex"], write="icodex")`
3. `wiki_read_page(domain="icodex", slug="testing-and-project-state")`
4. `wiki_update_page(domain="icodex", slug="testing-and-project-state", heading="Superpowers Artifacts", source="docs/README.ru.md", new_body=<updated English section>)`
5. `wiki_lint(domain="icodex")`

The updated `Superpowers Artifacts` wiki section must state:

```markdown
`docs/superpowers/` stores design and execution artifacts:

- `intents/`: English intent docs captured by IDD. After `$check-chain intent <path>` passes, the user reviews a Russian terminal summary before approval.
- `specs/`: English SDD design specs. After `$check-chain spec <path>` passes, the user reviews a Russian terminal summary before implementation planning proceeds.
- `plans/`: English implementation plans. After `$check-chain plan <path>` passes, the user reviews a Russian terminal summary before inline or subagent execution starts. The same plan frontmatter later stores `result_check:` for the result audit.
- `reports/`: final chain HTML result reports created at `$check-chain result <plan>`.
- `notes/`: longer methodology notes.

For IDD/SDD chain topics, `intent`, `spec`, and `plan` validation is English-source/Russian-review: `$check-chain <stage>` updates frontmatter and `docs/TODO.md`, then prints a Russian explanatory terminal summary. User feedback is applied to the English markdown source first, then the relevant stage check is rerun.

Intermediate stages do not generate or refresh HTML. The generated HTML report under `docs/superpowers/reports/<topic>-results.html` is created at `$check-chain result <plan>` as a single final closeout artifact for the completed task.
```

Expected: `wiki_lint` reports no broken refs, stale pages, or contradictions for the updated page.

- [ ] **Step 5: Run `check-chain result` for this plan**

Invoke the check-chain skill in Codex, not as a shell command:

$check-chain result docs/superpowers/plans/2026-07-11-check-chain-russian-review-summary.md

Expected: result reconciliation reports all plan steps complete, no open CRITICAL findings, docs/wiki evidence recorded, `result_check.verdict: OK`, `docs/TODO.md` row closed with `Result: OK`, and `docs/superpowers/reports/check-chain-russian-review-summary-results.html` generated.

- [ ] **Step 6: Commit final verification artifacts**

Run:

```bash
git add docs/TODO.md docs/superpowers/plans/2026-07-11-check-chain-russian-review-summary.md docs/superpowers/reports/check-chain-russian-review-summary-results.html
git commit -m "docs(chain): record Russian review summary result"
```

Expected: one commit containing the plan result frontmatter, task-log closure, and generated final report.

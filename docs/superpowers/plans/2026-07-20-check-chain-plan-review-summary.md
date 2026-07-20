---
review:
  plan_hash: 30a20ea61e342580
  last_run: 2026-07-20
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-07-20-check-chain-plan-review-summary-intent.md
  spec: docs/superpowers/specs/2026-07-20-check-chain-plan-review-summary-design.md
result_check:
  verdict: OK
  plan_hash: 30a20ea61e342580
  last_run: 2026-07-20
  reviewed: true
  docs_checked: true
---
# Check-Chain Review Summaries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Strengthen `check-chain spec` and `check-chain plan` so they critically review errors and completeness, then print Russian terminal summaries of found issues, fixes, expected design or implementation results, covered requirements, and user forks. Make final HTML optional and offered only at `check-chain result`.

**Architecture:** This is a contract-level change in skill instructions, tests, repository docs, and iwiki. No wrapper runtime, hook, frontmatter schema, TODO schema, or pre-result no-HTML boundary changes.

**Tech Stack:** Markdown skill instructions, dependency-free Bash tests, iwiki MCP documentation updates.

---

## File Structure

- Modify `tests/test_check_chain_russian_review_summary.sh`: extend the existing focused contract test with spec-specific, plan-specific, and optional result HTML assertions.
- Modify `tests/test_chain_report_quality.sh`: update chain report contract assertions from mandatory HTML generation to optional result-stage offer.
- Modify `tests/test_chain_result_report_contract.sh`: update result-only report assertions from mandatory generation to optional result-stage offer.
- Modify `.codex-isolated/skills/check-chain/SKILL.md`: add skeptical spec summary, keep skeptical plan summary, and make result HTML optional.
- Modify `.codex-isolated/skills/html-report/SKILL.md`: document chain mode as the optional renderer invoked only after user acceptance.
- Modify `.codex-isolated/skills/html-report/references/chain-report.md`: document result-stage offer/refusal behavior.
- Modify `docs/README.ru.md`: document stronger `check-chain spec`, stronger `check-chain plan`, and optional HTML on result.
- Update iwiki page `testing-and-project-state`, heading `Superpowers Artifacts`.
- Update iwiki page `plugin-and-hook-wiring`, heading `IDD Gate`.
- Update `docs/TODO.md` and chain artifact frontmatter hashes after source changes.

## Task 1: Add Failing Contract Assertions

**Files:**
- Modify: `tests/test_check_chain_russian_review_summary.sh`
- Test: `bash tests/test_check_chain_russian_review_summary.sh`

- [x] **Step 1: Add spec-specific assertions**

Assert that `check-chain` documents a `spec` design review summary with Russian sections for found errors, fixed items, expected design outcome, closed requirements, acceptance criteria, missing requirements, and user forks.

- [x] **Step 2: Add optional result HTML assertions**

Assert that `check-chain result` asks in Russian whether to generate HTML, skips `html-report` when the user declines, and that `html-report` / `chain-report.md` document chain mode as optional result-only output.

- [x] **Step 3: Add README assertions**

Assert that `docs/README.ru.md` documents stronger `check-chain spec` review and optional HTML behavior on `check-chain result`.

- [x] **Step 4: Run the focused test and verify RED**

Run:

```bash
bash tests/test_check_chain_russian_review_summary.sh
```

Expected evidence: the command exits non-zero because the new spec-review and optional HTML contract strings are not yet present.

## Task 2: Strengthen `check-chain` Spec/Plan Contract

**Files:**
- Modify: `.codex-isolated/skills/check-chain/SKILL.md`
- Test: `bash tests/test_check_chain_russian_review_summary.sh`

- [x] **Step 1: Keep recursive review-loop rule**

Preserve the source-fix recursion rule: finding -> fix English source artifact -> rerun the same `check-chain <stage>` -> print a fresh Russian summary. User verdicts are requested only for real forks.

- [x] **Step 2: Add spec-stage terminal summary contract**

Add `##### spec design review summary` with `OK` and `needs_work` Russian sections:

- `Что проверено`
- `Найденные ошибки и спорные места`
- `Что исправлено или доработано`
- `Что будет спроектировано`
- `Какие требования будут закрыты`
- `Критерии приёмки`
- `Оставшиеся решения пользователя`
- `Source anchors`
- `Что ещё нужно доработать`
- `Каких требований или критериев не хватает`
- `Где нужен пользователь`

- [x] **Step 3: Preserve plan-stage skeptical summary contract**

Keep the existing plan-specific summary contract for expected implementation outputs, closed problems, verification evidence, and human checkpoints.

- [x] **Step 4: Make result HTML optional**

Replace mandatory result HTML language with:

- HTML report generation is optional even at `result`;
- ask the user in Russian after the result verdict;
- if the user declines, do not invoke `html-report`;
- only `result` may offer HTML.

## Task 3: Update HTML Report Chain Contract

**Files:**
- Modify: `.codex-isolated/skills/html-report/SKILL.md`
- Modify: `.codex-isolated/skills/html-report/references/chain-report.md`
- Test: `bash tests/test_chain_report_quality.sh`
- Test: `bash tests/test_chain_result_report_contract.sh`

- [x] **Step 1: Update html-report chain mode**

Document `mode: chain` as the optional final-result HTML path invoked only after `check-chain result` asks and the user accepts.

- [x] **Step 2: Update chain-report reference**

Document that the HTML report may be offered only at `check-chain result` and that user refusal means no HTML is generated or refreshed.

- [x] **Step 3: Update related tests**

Change mandatory report-generation assertions to optional report-offer assertions while keeping self-contained Russian HTML requirements for accepted reports.

## Task 4: Update User-Facing Docs

**Files:**
- Modify: `docs/README.ru.md`
- Test: `bash tests/test_check_chain_russian_review_summary.sh`

- [x] **Step 1: Update the IDD -> SDD review flow**

Document that `check-chain spec` checks design errors/completeness, reports expected design output, names closed requirements, and lists acceptance criteria before planning.

- [x] **Step 2: Keep plan review docs**

Keep `check-chain plan` wording for plan errors/completeness, expected implementation results, covered problems/requirements, verification evidence, and real user forks.

- [x] **Step 3: Document optional result HTML**

State that only `check-chain result` asks whether the user wants an HTML report, and if the user declines, HTML is not created or refreshed.

## Task 5: Update Wiki And Verify Documentation Consistency

**Files:**
- Update through MCP: iwiki `icodex/testing-and-project-state`, heading `Superpowers Artifacts`
- Update through MCP: iwiki `icodex/plugin-and-hook-wiring`, heading `IDD Gate`
- Test: `wiki_lint(domain="icodex")`

- [x] **Step 1: Update `testing-and-project-state`**

Document that `check-chain spec` performs skeptical design review and `check-chain plan` performs skeptical plan review. Document optional result HTML behavior.

- [x] **Step 2: Update `plugin-and-hook-wiring`**

Document the same gate-level behavior where IDD approval and result flow are described.

- [x] **Step 3: Run wiki lint**

Run `wiki_lint(domain="icodex")` and resolve new lint failures.

## Task 6: Verification

**Files:**
- Update: `docs/TODO.md`
- Update: this plan frontmatter through local hash recalculation
- Test: focused, related, and full Bash suites

- [x] **Step 1: Run focused and related tests**

Run:

```bash
bash tests/test_check_chain_russian_review_summary.sh
bash tests/test_chain_report_quality.sh
bash tests/test_chain_result_report_contract.sh
```

Expected evidence: all three commands exit `0`.

- [x] **Step 2: Run the full suite**

Run:

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected evidence: command exits `0`, or any failure is recorded with command output summary and unrelated/pre-existing rationale.

- [x] **Step 3: Do not regenerate HTML without consent**

Because result HTML is now optional and the user has not requested a fresh final HTML report in this execution pass, do not invoke `html-report` or refresh `docs/superpowers/reports/check-chain-plan-review-summary-results.html`.

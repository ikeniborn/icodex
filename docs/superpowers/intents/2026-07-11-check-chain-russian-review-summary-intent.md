---
review:
  intent_hash: e6f0b56ec28c24f3
  last_run: 2026-07-11
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
---
# Intent: check-chain Russian review summary

**Date:** 2026-07-11
**Status:** approved

## Objective

Improve the pre-implementation review workflow for `check-chain` without turning English markdown artifacts into Russian source files or adding pre-result HTML reports.

The current chain keeps intent, spec, and plan artifacts in English, but the user needs to review and approve their meaning in Russian before inline or subagent execution starts. A pre-execution HTML report is possible, but it would add a second report lifecycle and blur which artifact is authoritative before implementation. The simpler workflow is to keep markdown as the English source of truth, print a Russian explanatory review summary in the terminal for `intent`, `spec`, and `plan`, and keep the final HTML report only for `result`.

## Desired Outcomes

- After `check-chain intent`, `check-chain spec`, or `check-chain plan` returns `OK`, the user receives a Russian terminal review summary that is sufficient to approve the stage or request changes without reading the whole English markdown artifact.
- English intent, spec, and plan markdown files remain the only source of truth passed through the IDD -> SDD chain.
- User feedback before implementation is applied to the English markdown source artifact first, then the relevant `check-chain <stage>` run is repeated and a fresh Russian terminal summary is shown.
- `check-chain result` remains the only stage that creates or refreshes the final Russian HTML report.
- All explanatory review text shown to the user is Russian, while technical terms, file paths, function names, identifiers, stage keys, and code references may remain untranslated.

## Health Metrics

- The existing `review:` and `result_check:` frontmatter contract remains compatible with `chain-gate.py`.
- `docs/TODO.md` schema, stage cells, and status semantics do not change.
- Intent, spec, and plan stages do not generate or update HTML reports before `result`.
- Russian terminal summaries remain review surfaces only and do not become a second source of truth.
- Summaries do not invent requirements, risks, decisions, dependencies, or acceptance criteria that are absent from the checked source artifacts, linked chain artifacts, frontmatter, or conversation context.
- The existing final result HTML report behavior and Russian-only visible text rule remain intact.

## Strategic Context

- Interacts with: `.codex-isolated/skills/check-chain/SKILL.md`, `.codex-isolated/skills/html-report/SKILL.md`, `.codex-isolated/skills/html-report/references/chain-report.md`, `docs/superpowers/intents/`, `docs/superpowers/specs/`, `docs/superpowers/plans/`, `docs/superpowers/reports/`, `docs/TODO.md`, `chain-gate.py`, and the project iwiki domain page that describes Superpowers artifacts.
- Priority trade-off: trust first, then Russian review ergonomics, then output length and speed.

## Constraints

### Steering (behavioral guidance)

- Prefer Russian terminal summaries for `intent`, `spec`, and `plan` over pre-execution HTML reports.
- Keep each Russian summary explanatory, not a mechanical line-by-line translation.
- Summaries should help the user understand purpose, planned change, coverage, risks, decisions, and the exact approval question for the current stage.
- Use source anchors such as section names, paths, stage keys, and short fragments to keep the Russian explanation traceable to English artifacts.
- Keep the final result HTML report as the closeout artifact after implementation evidence exists.

### Hard (architectural enforcement)

- Keep all intent, spec, plan, implementation docs, wiki pages, and test comments in English unless a separate project rule says otherwise.
- Do not generate or refresh pre-result HTML reports for `intent`, `spec`, or `plan`.
- Do not change `chain-gate.py`, the frontmatter shape, `docs/TODO.md` format, or stage verdict semantics for this workflow.
- Do not use external translation services, runtime network calls, CDN assets, or external report assets.
- Do not let Russian summaries add scope, requirements, dependencies, risks, decisions, or acceptance criteria without a source anchor.
- Do not make the Russian summary a machine-readable gate state.

## Autonomy Zones

- Full autonomy (reversible, low risk): update skill instructions, focused tests, repository docs, and iwiki pages to describe Russian terminal review summaries and result-only HTML.
- Guarded (log + confidence threshold): choose the exact Russian terminal summary section names and order, as long as gate semantics and source-of-truth rules do not change.
- Proposal-first (needs approval): change `chain-gate.py`, frontmatter shape, `docs/TODO.md` schema, result verdict rules, or reintroduce pre-execution HTML reports.
- No autonomy (human only): make Russian text the chain source of truth, use external translation/network dependencies, or generate unanchored summaries.

> These zones OVERRIDE subagent-driven-development's "continuous execution,
> don't pause" default. Any task touching proposal-first / no-go decisions
> is marked HUMAN CHECKPOINT in the plan.

## Stop Rules

- Halt if: satisfying the workflow requires changing `chain-gate.py`, frontmatter shape, TODO schema, or verdict semantics.
- Halt if: a design requires pre-result HTML generation for `intent`, `spec`, or `plan`.
- Halt if: Russian summaries cannot be traced back to checked source artifacts, linked chain artifacts, frontmatter, or conversation context.
- Escalate if: the summary format becomes so large that it duplicates the full markdown artifact, or if a translation dependency appears necessary.
- Done when: `check-chain` clearly specifies that `intent`, `spec`, and `plan` print Russian terminal review summaries after `OK` and before approval.
- Done when: the summary format covers the stage goal, what changes, coverage, risks, decisions, source anchors, and the approval question.
- Done when: `check-chain result` remains the only HTML report generation stage.
- Done when: focused tests cover the Russian terminal review-summary contract and absence of pre-result HTML.
- Done when: repository docs and iwiki agree with the updated workflow.

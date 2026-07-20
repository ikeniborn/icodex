---
review:
  intent_hash: 4b81a9b065d66111
  last_run: 2026-07-20
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
---
# Intent: check-chain review summaries

**Date:** 2026-07-20
**Status:** approved

## Objective

Strengthen the `check-chain spec` and `check-chain plan` review workflows so design and plan artifacts are challenged for errors and completeness, and so the Russian terminal output clearly tells the user what was checked, what problems were found, what was fixed or must be fixed, what will be designed or implemented, and which user problems, requirements, or acceptance criteria the artifact closes.

The current `check-chain` skill already prints Russian terminal summaries for `intent`, `spec`, and `plan`, but the `spec` and `plan` stages are too approval-oriented when they pass and too thin when the user asks again to check mistakes, completeness, and final outcomes. The spec review must become a critical design audit, and the plan review must become a critical pre-implementation audit, not only structural passes.

Result HTML is not a mandatory artifact. It is offered only at `check-chain result`, after implementation evidence exists, and is not generated or refreshed when the user declines.

## Desired Outcomes

- After `$check-chain spec`, the user receives a Russian terminal summary that explicitly names detected design errors or states that no blocking errors remain.
- The spec summary explains what was corrected by the review cycle, what will be designed, which requirements or intent outcomes are covered, and which acceptance criteria prove the design is complete enough for planning.
- After `$check-chain plan`, the user receives a Russian terminal summary that explicitly names detected plan errors or states that no blocking errors remain.
- The plan summary explains what was corrected by the review cycle or what source changes are still required before rerun.
- The plan summary explains what will be implemented if the plan is executed and which requested problems or requirements will be closed.
- Repeated user requests such as "Проверь план на ошибки и полноту. Опиши какие результаты выполнения плана? Что будет в итоге?" are answered with plan-specific coverage, expected results, and closure information, not a generic approval prompt.
- Ambiguous plan choices, disputed scope, and conflicting source material trigger a user checkpoint; routine fixable gaps are recorded as findings and the checker loops until no blocking issues remain.
- `check-chain result` asks whether to generate the final HTML report; if the user declines, no HTML report is created or refreshed.

## Health Metrics

- The `review:` frontmatter contract and `chain-gate.py` compatibility do not change.
- `docs/TODO.md` schema and stage semantics do not change.
- English intent, spec, and plan markdown remain the source of truth.
- The strengthened spec and plan output remains Russian terminal text only and does not create pre-result HTML.
- The final HTML report is optional at `check-chain result` and depends on explicit user acceptance.
- The plan checklist remains deterministic: new checks are explicit, closed, and anchored in source artifacts.
- Summaries do not invent implementation results that only `check-chain result` can prove from a diff.

## Strategic Context

- Interacts with: `.codex-isolated/skills/check-chain/SKILL.md`, `.codex-isolated/skills/html-report/SKILL.md`, `.codex-isolated/skills/html-report/references/chain-report.md`, `tests/test_check_chain_russian_review_summary.sh`, `tests/test_chain_report_quality.sh`, `tests/test_chain_result_report_contract.sh`, `docs/README.ru.md`, `docs/TODO.md`, `docs/superpowers/intents/`, `docs/superpowers/specs/`, `docs/superpowers/plans/`, and the `icodex` iwiki pages that document Superpowers artifacts and IDD gate behavior.
- Priority trade-off: trust first, then review clarity, then output length.

## Constraints

### Steering (behavioral guidance)

- Make spec validation skeptical: the checker should challenge missing requirements, weak acceptance criteria, unclear component or boundary decisions, uncovered intent outcomes, unmitigated risks, and hidden human decisions.
- Make plan validation skeptical: the checker should challenge missing outputs, unstated solved problems, vague implementation claims, weak verification, and hidden human decisions.
- Keep the Russian terminal summary concise but concrete enough for approval or correction without rereading the full English spec or plan.
- Treat recursive review as a source-fix loop: finding -> fix English artifact -> rerun same stage -> fresh Russian summary.
- Ask the user only when the checker reaches a real fork: contradictory sources, scope decisions, or ambiguity that cannot be resolved from artifacts and conversation.

### Hard (architectural enforcement)

- Do not change `chain-gate.py`, `review:` frontmatter shape, `result_check:` shape, or TODO table schema.
- Do not make Russian summaries machine-readable gate state.
- Do not generate or refresh HTML before `check-chain result`.
- Do not generate or refresh result HTML unless the user accepts the result-stage report offer.
- Do not claim implementation evidence, closed bugs, or actual diff results during `plan`; only describe expected outcomes and source-level issues.
- Do not use external services or network calls to produce Russian terminal summaries.

## Autonomy Zones

- Full autonomy (reversible, low risk): update skill instructions, focused tests, repository docs, chain artifacts, and iwiki pages for the strengthened spec/plan review and optional result HTML contract.
- Guarded (log + confidence threshold): choose exact Russian section names and wording for spec and plan review summaries while preserving source anchors and no-invention rules.
- Proposal-first (needs approval): change gate semantics, frontmatter schema, TODO schema, result verdict rules, or introduce pre-result HTML.
- No autonomy (human only): approve disputed product scope, accept contradictory source material, or redefine the user's requested outcome.

> These zones OVERRIDE subagent-driven-development's "continuous execution,
> don't pause" default. Any task touching proposal-first / no-go decisions
> is marked HUMAN CHECKPOINT in the plan.

## Stop Rules

- Halt if: strengthening the spec or plan review requires changing `chain-gate.py`, frontmatter schema, TODO schema, or result verdict rules.
- Halt if: a spec or plan ambiguity cannot be resolved from the user request, intent, spec, plan, docs, or iwiki.
- Escalate if: the plan summary would need to assert actual implementation results before implementation exists.
- Escalate if: result HTML generation is requested before `check-chain result`.
- Done when: `check-chain` requires the spec stage to challenge design errors, completeness, requirement coverage, acceptance criteria, risks, mitigations, and human checkpoints.
- Done when: `check-chain spec` Russian terminal summaries include found errors, fixed or required corrections, expected design outcome, closed requirements, and acceptance criteria.
- Done when: `check-chain` requires the plan stage to challenge errors, completeness, outputs, solved problems, verification evidence, and human checkpoints.
- Done when: `check-chain plan` Russian terminal summaries include found errors, fixed or required corrections, expected implementation outcome, and closed problems or requirements.
- Done when: `check-chain result` asks whether to generate the final HTML report and skips `html-report` when the user declines.
- Done when: focused tests cover the strengthened spec review, plan review, and optional result HTML contract.
- Done when: repository docs and the `icodex` iwiki pages describe the stronger spec/plan review and optional result HTML behavior.

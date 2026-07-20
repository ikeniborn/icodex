---
review:
  spec_hash: 52a062c0c013674e
  last_run: 2026-07-20
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-07-20-check-chain-plan-review-summary-intent.md
---
# Design: check-chain review summaries

**Date:** 2026-07-20
**Status:** approved
**Topic:** check-chain-plan-review-summary

## Objective

Strengthen the `check-chain spec` and `check-chain plan` contracts so validation is skeptical and the Russian terminal summaries answer the user's review questions directly: what was checked, what errors were found, what was fixed or still needs fixing, what will be designed or implemented, and which requested problems, requirements, or acceptance criteria the artifact closes.

This is an instruction-contract and documentation change. The existing Bash wrapper runtime, `chain-gate.py`, frontmatter schema, TODO schema, and pre-result no-HTML boundary stay unchanged. Result HTML becomes an optional report offer at `check-chain result`, not a mandatory artifact.

## Acceptance (from intent)

### Desired Outcomes

- After `$check-chain spec`, the user receives a Russian terminal summary that explicitly names detected design errors or states that no blocking errors remain.
- The spec summary explains what was corrected by the review cycle, what will be designed, which requirements or intent outcomes are covered, and which acceptance criteria prove the design is complete enough for planning.
- After `$check-chain plan`, the user receives a Russian terminal summary that explicitly names detected plan errors or states that no blocking errors remain.
- The plan summary explains what was corrected by the review cycle or what source changes are still required before rerun.
- The plan summary explains what will be implemented if the plan is executed and which requested problems or requirements will be closed.
- Repeated user requests such as "Проверь план на ошибки и полноту. Опиши какие результаты выполнения плана? Что будет в итоге?" are answered with plan-specific coverage, expected results, and closure information, not a generic approval prompt.
- Ambiguous choices, disputed scope, and conflicting source material trigger a user checkpoint; routine fixable gaps are recorded as findings and the checker loops until no blocking issues remain.
- `check-chain result` asks whether to generate the final HTML report; if the user declines, no HTML report is created or refreshed.

### Health Metrics

- The `review:` frontmatter contract and `chain-gate.py` compatibility do not change.
- `docs/TODO.md` schema and stage semantics do not change.
- English intent, spec, and plan markdown remain the source of truth.
- The strengthened spec and plan output remains Russian terminal text only and does not create pre-result HTML.
- The final HTML report is optional at `check-chain result` and depends on explicit user acceptance.
- The plan checklist remains deterministic: new checks are explicit, closed, and anchored in source artifacts.
- Summaries do not invent implementation results that only `check-chain result` can prove from a diff.

### Done When

- `check-chain` requires the spec stage to challenge design errors, completeness, requirement coverage, acceptance criteria, risks, mitigations, and human checkpoints.
- `check-chain spec` Russian terminal summaries include found errors, fixed or required corrections, expected design outcome, closed requirements, and acceptance criteria.
- `check-chain` requires the plan stage to challenge errors, completeness, outputs, solved problems, verification evidence, and human checkpoints.
- `check-chain plan` Russian terminal summaries include found errors, fixed or required corrections, expected implementation outcome, and closed problems or requirements.
- `check-chain result` asks whether to generate the final HTML report and skips `html-report` when the user declines.
- Focused tests cover the strengthened spec review, plan review, and optional result HTML contract.
- Repository docs and the `icodex` iwiki pages describe the stronger spec/plan review and optional result HTML behavior.

## Non-Goals

- Do not implement a separate executable checker.
- Do not change `chain-gate.py`, frontmatter shape, TODO schema, or result verdict semantics.
- Do not generate or refresh HTML for `intent`, `spec`, or `plan`.
- Do not generate or refresh result HTML unless the user accepts the result-stage report offer.
- Do not make Russian terminal output a source artifact or machine-readable state.
- Do not claim actual implementation results during `spec` or `plan`; those stages describe design intent and expected outcomes only.

## Requirements

### R1: Skeptical Spec Summary

The `spec` terminal summary must require critical review of design substance, not only generic approval. It must report:

- detected design errors or that no blocking errors remain;
- source-level corrections already made or still required;
- what will be designed: requirements, component boundaries, workflow, or report behavior;
- which user tasks, intent outcomes, or requirements the spec covers;
- acceptance criteria, DoD, or evidence that will later prove the design is complete enough for planning;
- unresolved human checkpoints when the checker cannot decide safely.

### R2: Skeptical Plan Checklist

The `plan` checklist must require critical review of plan substance, not only structure. It must check that each plan step has:

- a concrete expected output;
- an explicit user problem, desired outcome, or spec requirement it closes;
- no unsupported "implementation is done" claims before result evidence exists;
- no hidden unresolved human decision;
- no vague "study", "improve", "check", or "work through" step without a source change, decision, or evidence artifact.

### R3: Recursive Review Loop

The shared finding-handling flow must explicitly describe recursion for all stages, and especially `spec` and `plan`: findings cause English source fixes, the same stage reruns, and a fresh Russian summary is printed. The checker should ask the user only for true forks: conflicting artifacts, disputed scope, or an unresolvable human decision.

### R4: Plan `OK` Summary

The `plan` `OK` summary must include Russian sections that answer:

- what was checked;
- what errors were found and fixed, or that no blocking errors remain;
- what will be implemented by the plan;
- which problems, outcomes, or requirements will be closed;
- what verification evidence should appear after execution;
- which human checkpoints remain before implementation.

### R5: Plan `needs_work` Summary

The `plan` `needs_work` summary must include Russian sections that answer:

- why the plan failed;
- which errors are blocking or important;
- what must be corrected in the English plan/spec/intent before rerun;
- which expected results or problem closures are missing or unsupported;
- what user clarification is needed when the checker cannot decide safely.

### R6: Optional Result HTML

`check-chain result` must ask the user in Russian whether to generate the final HTML report after the result verdict is known. If the user declines, the skill must not invoke `html-report` and must not create or refresh `docs/superpowers/reports/<topic>-results.html`.

`html-report` chain mode remains the renderer for accepted result-stage reports only. It must not be used for `intent`, `spec`, or `plan`.

### R7: Source Anchors And No-Invention Boundary

The strengthened summaries must remain anchored in the current spec, plan, linked intent, frontmatter findings, docs/wiki context, or conversation context. They must not invent actual implementation evidence, completed bugs, or shipped behavior before `result`.

### R8: Documentation Consistency

Repository docs and the `icodex` iwiki pages that describe Superpowers artifacts, IDD gate behavior, or chain-mode reports must mention that `check-chain spec` and `check-chain plan` now include skeptical Russian review summaries and that final HTML is optional at `check-chain result`.

## Design

### Skill Instruction Changes

Update `.codex-isolated/skills/check-chain/SKILL.md` in four places:

- Strengthen Step 3 finding-handling with an explicit recursive source-fix loop and user checkpoints for unresolved forks.
- Replace the generic spec and plan summary focus with stage-specific terminal review contracts for `OK` and `needs_work` summaries.
- Replace mandatory result HTML language with an optional result-stage offer and refusal path.
- Expand the `plan checklist` closed checks for coverage, verifiability, and consistency to challenge missing outputs, solved-problem mapping, unsupported completion claims, and hidden human decisions.

Update `.codex-isolated/skills/html-report/SKILL.md` and `references/chain-report.md` so chain mode is documented as an optional renderer invoked only after the result-stage report offer is accepted.

### Test Changes

Extend `tests/test_check_chain_russian_review_summary.sh` because it already guards the Russian terminal summary contract. Add assertions for the new spec-review, plan-review, and optional result HTML strings rather than creating a second overlapping test file.

Update `tests/test_chain_report_quality.sh` and `tests/test_chain_result_report_contract.sh` so they guard result-only optional HTML instead of mandatory final report generation.

### Documentation Changes

Update `docs/README.ru.md` in the IDD -> SDD review flow section. The new text should say that `check-chain spec` checks the design for errors and completeness, reports what will be designed and which acceptance criteria prove it, `check-chain plan` reports expected implementation results and covered user problems, and `check-chain result` asks whether to generate HTML.

Update iwiki pages:

- `testing-and-project-state`, heading `Superpowers Artifacts`;
- `plugin-and-hook-wiring`, heading `IDD Gate`;
- pages that document chain-mode HTML if they describe mandatory report generation.

## Error Handling

- If the spec or plan has routine fixable gaps, record findings, fix the English source artifact, and rerun the same stage.
- If the spec or plan implies a scope decision that the user did not authorize, stop and ask the user.
- If the spec summary cannot map requirements to acceptance criteria or covered outcomes, return `needs_work`.
- If the plan summary cannot map a step to an expected output or closed problem, return `needs_work`.
- If the user declines result HTML, record terminal evidence and skip `html-report`.
- If docs/wiki contradict the strengthened behavior, update docs/wiki before the stage passes.

## Testing Strategy

Run the focused contract test:

```bash
bash tests/test_check_chain_russian_review_summary.sh
```

Run related chain report tests:

```bash
bash tests/test_chain_report_quality.sh
bash tests/test_chain_result_report_contract.sh
```

Run the full Bash suite:

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

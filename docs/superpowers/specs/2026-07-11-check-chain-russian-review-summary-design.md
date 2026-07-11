---
review:
  spec_hash: dc27bb335244f9e2
  last_run: 2026-07-11
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-07-11-check-chain-russian-review-summary-intent.md
---
# Design: check-chain Russian review summaries

**Date:** 2026-07-11
**Status:** approved
**Topic:** check-chain-russian-review-summary

## Objective

Improve the pre-implementation approval workflow for `check-chain` while preserving English markdown artifacts as the chain source of truth.

Intent, spec, and plan documents stay English because they are passed through the IDD -> SDD chain and later used by agents, validation, and result reconciliation. The user-facing approval surface before implementation should be Russian, but it should not become a second source document and should not require pre-result HTML generation.

This design adds Russian terminal review summaries to `check-chain` for `intent`, `spec`, and `plan`. The final HTML report remains a `result`-only closeout artifact.

## Acceptance (from intent)

### Desired Outcomes

- After `check-chain intent`, `check-chain spec`, or `check-chain plan` returns `OK`, the user receives a Russian terminal review summary that is sufficient to approve the stage or request changes without reading the whole English markdown artifact.
- English intent, spec, and plan markdown files remain the only source of truth passed through the IDD -> SDD chain.
- User feedback before implementation is applied to the English markdown source artifact first, then the relevant `check-chain <stage>` run is repeated and a fresh Russian terminal summary is shown.
- `check-chain result` remains the only stage that creates or refreshes the final Russian HTML report.
- All explanatory review text shown to the user is Russian, while technical terms, file paths, function names, identifiers, stage keys, and code references may remain untranslated.

### Health Metrics

- The existing `review:` and `result_check:` frontmatter contract remains compatible with `chain-gate.py`.
- `docs/TODO.md` schema, stage cells, and status semantics do not change.
- Intent, spec, and plan stages do not generate or update HTML reports before `result`.
- Russian terminal summaries remain review surfaces only and do not become a second source of truth.
- Summaries do not invent requirements, risks, decisions, dependencies, or acceptance criteria that are absent from the checked source artifacts, linked chain artifacts, frontmatter, or conversation context.
- The existing final result HTML report behavior and Russian-only visible text rule remain intact.

### Done When

- `check-chain` clearly specifies that `intent`, `spec`, and `plan` print Russian terminal review summaries after `OK` and before approval.
- The summary format covers the stage goal, what changes, coverage, risks, decisions, source anchors, and the approval question.
- `check-chain result` remains the only HTML report generation stage.
- Focused tests cover the Russian terminal review-summary contract and absence of pre-result HTML.
- Repository docs and iwiki agree with the updated workflow.

## Non-Goals

- Do not generate or update pre-result HTML reports for `intent`, `spec`, or `plan`.
- Do not change `chain-gate.py`.
- Do not change `review:` or `result_check:` frontmatter shape.
- Do not change `docs/TODO.md` schema or stage semantics.
- Do not add any external translation service, runtime network dependency, CDN asset, or external report asset.
- Do not make the Russian terminal summary a machine-readable gate state.
- Do not translate English markdown artifacts into Russian.

## Architecture

### Responsibility Boundary

`check-chain` owns the terminal review summary because it already owns validation, verdicts, frontmatter review state, chain artifact links, and stage-specific findings. Keeping the summary in `check-chain` prevents `html-report` from becoming a pre-implementation review system and avoids a second report lifecycle.

`html-report` remains the renderer for the final `result` report only. It should continue to accept a complete final payload from `check-chain result` and produce one self-contained Russian HTML closeout report.

### Source Of Truth

English markdown artifacts remain authoritative:

- intent: objective, outcomes, constraints, autonomy, and stop rules;
- spec: design requirements, boundaries, acceptance, risks, and validation strategy;
- plan: execution steps, dependencies, touched artifacts, and verification commands.

The Russian terminal summary is a review surface. If the user requests a change, the agent edits the relevant English markdown artifact, reruns the matching `check-chain <stage>`, and shows a fresh summary.

### Gate Compatibility

No existing machine-readable gate contract changes. `chain-gate.py` continues to rely on frontmatter fields and verdict semantics:

- `review.<stage>_hash`;
- `review.phases`;
- `review.findings`;
- `chain.intent`;
- `chain.spec`;
- `result_check.verdict`;
- `result_check.plan_hash`.

The terminal summary is not cached as gate state and is not consumed by downstream automation.

## Terminal Summary Contract

For `intent`, `spec`, and `plan`, `check-chain` prints a Russian review block after the stage verdict is known.

### `OK` Summary

When the stage passes, the summary is an approval-oriented explanation. It must include:

- `Что проверено`: stage, artifact path, verdict, and relevant linked artifacts.
- `Что означает документ`: concise Russian explanation of the artifact's meaning.
- `Покрытие и связи`: how the artifact covers upstream outcomes, requirements, or plan steps.
- `Риски и ограничения`: approval-relevant constraints, hard limits, human checkpoints, and known risks.
- `Что нужно подтвердить`: the exact approval question for the user.
- `Source anchors`: paths, section names, finding IDs, hashes, or short fragments that make the summary traceable.

The approval question is only shown when verdict is `OK`.

### `needs_work` Summary

When the stage does not pass, the summary explains blockers instead of asking for approval. It must include:

- `Что проверено`: stage and artifact path.
- `Почему этап не прошёл`: open CRITICAL findings and important WARNING findings in Russian.
- `Что исправить`: concrete source changes needed before rerun.
- `Source anchors`: finding IDs, paths, section names, hashes, or short fragments.

The `needs_work` summary must not ask the user to approve the stage.

### Language Rules

All explanatory terminal-review text is Russian. Technical terms may remain untranslated when translation would reduce precision:

- paths;
- function names;
- code identifiers;
- stage keys such as `intent`, `spec`, `plan`, `result`;
- hash keys;
- finding IDs;
- short source fragments.

The summary should be explanatory, not a mechanical line-by-line translation of the markdown artifact.

### No-Invention Rule

Every summary statement must be anchored in one of these sources:

- current artifact body;
- linked chain artifacts;
- frontmatter review state;
- result evidence when the stage is `result`;
- conversation context available to the stage.

The summary must not add new requirements, risks, decisions, dependencies, acceptance criteria, or scope.

## Stage-Specific Behavior

### Intent

The `intent` summary explains:

- objective and why the change matters;
- desired outcomes;
- health metrics;
- hard constraints;
- autonomy zones;
- stop rules;
- what the user approves before brainstorming/design work proceeds.

### Spec

The `spec` summary explains:

- implementation direction;
- requirements and acceptance criteria;
- component and boundary decisions;
- risk and mitigation choices;
- how the spec satisfies linked intent outcomes when an intent is available;
- what the user approves before implementation planning starts.

### Plan

The `plan` summary explains:

- execution order;
- plan-step dependencies;
- touched files, skills, docs, reports, tests, or wiki pages;
- verification commands and expected evidence;
- human checkpoints from autonomy zones;
- how plan steps cover linked spec requirements when a spec is available;
- what the user approves before inline or subagent execution starts.

### Result

`result` does not need the same terminal approval surface. It continues to create or refresh the single final Russian HTML report after implementation evidence exists.

The terminal output for `result` may still include a concise path/verdict message, but the user-facing explanatory closeout artifact is the HTML report.

## Documentation Updates

The implementation should update:

- `.codex-isolated/skills/check-chain/SKILL.md`: Russian terminal summary contract for `intent`, `spec`, and `plan`; `OK` and `needs_work` forms; source-anchor/no-invention rules; result-only HTML rule.
- `.codex-isolated/skills/html-report/SKILL.md`: clarify that chain HTML remains final-result-only and is not used for pre-result review summaries.
- `.codex-isolated/skills/html-report/references/chain-report.md`: clarify final report scope and terminal review flow before implementation.
- Repository docs such as `docs/README.ru.md` when they describe the IDD -> SDD review workflow.
- The project iwiki page that describes Superpowers artifacts and report behavior.

## Testing Strategy

Add a focused Bash test, `tests/test_check_chain_russian_review_summary.sh`, that checks the instruction contracts without network access.

The test should verify:

- `check-chain` documents Russian terminal review summaries for `intent`, `spec`, and `plan`.
- `check-chain` documents both `OK` and `needs_work` summary forms.
- The `OK` form includes an approval question and the `needs_work` form does not.
- English markdown artifacts remain the source of truth.
- No pre-result HTML is generated or refreshed for `intent`, `spec`, or `plan`.
- `check-chain result` remains the only HTML report generation stage.
- No external translation service or network dependency is allowed.
- Summary content must be anchored and must not invent requirements or decisions.
- `html-report` and `chain-report` references describe final-result-only HTML and terminal review before implementation.

Run the focused test during implementation:

```bash
bash tests/test_check_chain_russian_review_summary.sh
```

Run the full Bash suite after implementation unless an unrelated known failure blocks it:

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

## Error Handling

- If the stage has open CRITICAL findings, print the `needs_work` summary and stop downstream progression.
- If linked intent or spec artifacts are missing, the summary states that the upstream artifact is unavailable and limits coverage claims to available sources.
- If a source section is too vague to summarize confidently, the summary should say which section needs clarification rather than inventing meaning.
- If terminal output would become too large, keep the Russian summary concise and move long evidence into source anchors rather than duplicating the full markdown body.
- If the workflow appears to require pre-result HTML or gate contract changes, stop and escalate because those are outside the approved intent.

## Open Decisions

No open decisions remain for the first implementation. Reintroducing pre-execution HTML reports, changing gate contracts, or making Russian text a source artifact remains proposal-first.

---
review:
  intent_hash: d2eb391d9d69b9e7
  last_run: 2026-07-06
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
---
# Intent: check-chain report quality

**Date:** 2026-07-06
**Status:** approved

## Objective

Improve the `check-chain` HTML report so it becomes the primary user-facing artifact that explains the IDD -> SDD chain. The report must do more than show validation status: it must describe what will be built, which decisions and dependencies matter, how intent/spec/plan/result relate, and why the user can approve or request changes without reading every markdown source first.

The current report is too compressed. Intent, spec, and plan tabs summarize important source documents into short tables, but they do not carry enough narrative detail, implementation context, dependency maps, or visual explanations. The example report at `/home/altuser/Документы/Project/vision/docs/superpowers/reports/passport-kie-vlm-debate-results.html` shows the failure mode: intent is reduced to one-line section summaries, spec is mainly a requirements table, schemas are absent, and unchecked tabs remain placeholders.

## Desired Outcomes

- A user can open the generated report after `/check-chain intent`, `/check-chain spec`, or `/check-chain plan` and understand the planned change without reading the source markdown artifacts first.
- Intent, spec, and plan tabs include enough narrative detail to explain the objective, outcomes, implementation direction, dependencies, risks, constraints, and approval-relevant trade-offs.
- The report includes visual maps for flows, dependencies, coverage, and stage relationships where those maps make the change easier to understand.
- The report uses expandable or interactive sections to preserve depth without turning the first view into noise.
- Cached quick-exit runs keep the same full report shape and do not replace a rich tab with a thinner status-only tab.

## Health Metrics

- `check-chain` remains deterministic: closed validation checklists stay closed, and the report must not invent requirements that are absent from intent, spec, plan, result evidence, or the conversation context.
- The generated HTML remains self-contained and offline-readable: no CDN, no network fetches, no external images, and no dev server requirement.
- The chain report merge contract stays intact: only the owned tab is replaced; non-owned tabs are preserved.
- Existing `chain-gate.py` compatibility stays intact: the frontmatter contract, review blocks, result blocks, hashes, and verdict semantics do not change unless explicitly approved later.
- `docs/TODO.md` status behavior stays unchanged.
- Report depth stays readable: detailed evidence is organized with expandable sections, filters, or small inline interactions instead of long unstructured blocks.

## Strategic Context

- Interacts with: `.codex-isolated/skills/check-chain/SKILL.md`, `.codex-isolated/skills/html-report/SKILL.md`, `.codex-isolated/skills/html-report/references/chain-report.md`, `chain-gate.py`, `docs/superpowers/intents/`, `docs/superpowers/specs/`, `docs/superpowers/plans/`, `docs/superpowers/reports/`, `docs/TODO.md`, and the project iwiki domain.
- Priority trade-off: trust first, then readability and visual completeness, then generation speed and report size.

## Constraints

### Steering (behavioral guidance)

- Prefer enriching the `check-chain` owned-tab payload contract over moving source-document interpretation into `html-report`, because `html-report` chain mode currently acts as a renderer and merge layer.
- Keep `html-report` responsible for self-contained rendering, tab preservation, theme support, and reusable report components.
- Use narrative summaries, coverage maps, dependency diagrams, and expandable detail blocks to make each tab useful as a standalone explanation.
- Use inline SVG, CSS diagrams, `<details>`, filters, and small custom inline JavaScript when they materially improve report usability.
- If a vendored JavaScript library is proposed, justify why custom inline JavaScript or CSS/SVG is insufficient.

### Hard (architectural enforcement)

- Generate all HTML report user-facing text in Russian only.
- Keep all markdown artifacts, including intent, spec, plan, and implementation documentation, in English only.
- Do not use CDN scripts, runtime network access, external images, or report assets outside the single generated HTML file.
- Do not require a local dev server to read or interact with the report.
- Do not change the `chain-gate.py` frontmatter contract, `docs/TODO.md` format, or chain stage verdict semantics without a separate proposal-first decision.
- Do not let `html-report` read chain source documents directly in chain mode without a separate proposal-first decision.
- Do not generate new requirements, dependencies, or decisions without textual anchors in the source artifacts or conversation context.
- Do not let cached quick-exit produce a smaller or less informative tab than a full validation run.

## Autonomy Zones

- Full autonomy (reversible, low risk): update `check-chain` and `html-report` skill instructions for enriched payload blocks, narrative report sections, inline CSS/SVG diagrams, `<details>` sections, small custom inline JavaScript, and validation expectations.
- Guarded (log + confidence threshold): add a vendored inline JavaScript library only when the plan records its purpose, size impact, offline behavior, and fallback; use inline script only when CSS/SVG cannot express the interaction clearly.
- Proposal-first (needs approval): change the `chain-gate.py` frontmatter contract, change `docs/TODO.md`, change stage verdict semantics, make `html-report` read chain source documents in chain mode, or introduce a large vendored visualization library.
- No autonomy (human only): add CDN/runtime network dependencies, external report assets, a dev-server-only report, or generated requirements without source anchors.

> These zones OVERRIDE subagent-driven-development's "continuous execution,
> don't pause" default. Any task touching proposal-first / no-go decisions
> is marked HUMAN CHECKPOINT in the plan.

## Stop Rules

- Halt if: the design requires changing `chain-gate.py` compatibility, frontmatter shape, or TODO status semantics to achieve the report quality goal.
- Halt if: the report would depend on CDN, network access, external files, or a dev server.
- Halt if: enriched summaries cannot be traced back to intent/spec/plan/result content or the conversation.
- Escalate if: a vendored JavaScript library appears necessary, the generated report approaches the `html-report` size warning threshold, or the renderer cannot preserve non-owned tabs byte-for-byte.
- Done when: generated intent/spec/plan report tabs include narrative overview, implementation explanation, dependency/coverage maps, risks/constraints, expandable detail, and full phase/finding/verdict evidence.
- Done when: cached quick-exit regenerates the same full owned-tab block set.
- Done when: the existing chain-gate/frontmatter/TODO contracts remain compatible.
- Done when: focused checks and the relevant Bash test suite pass, and a self-contained offline HTML report can be opened without external resources.

---
review:
  spec_hash: db4760d8b624fcfa
  last_run: 2026-07-06
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-07-06-check-chain-report-quality-intent.md
---
# Design: enriched check-chain HTML reports

**Date:** 2026-07-06
**Status:** draft
**Topic:** check-chain-report-quality

## Objective

Improve the `check-chain` chain-mode HTML report so it becomes the primary user-facing explanation of the IDD -> SDD chain. The report must explain the planned or validated change, not only show pass/fail state.

The current report contract is too thin for the user's approval workflow. The observed failure mode is visible in `/home/altuser/Документы/Project/vision/docs/superpowers/reports/passport-kie-vlm-debate-results.html`: the intent tab compresses core decisions into one-line summaries, the spec tab is mainly a requirements table, the plan/result tabs can remain placeholders, and the report does not show functional flow, dependency relationships, or approval-relevant trade-offs.

This design keeps `check-chain` as the semantic extractor and keeps `html-report` as the renderer and tab merge layer. The report user-facing text is Russian only. All markdown artifacts, including this design, remain English.

## Acceptance (from intent)

### Desired Outcomes

- A user can open the generated report after `/check-chain intent`, `/check-chain spec`, or `/check-chain plan` and understand the planned change without reading the source markdown artifacts first.
- Intent, spec, and plan tabs include enough narrative detail to explain the objective, outcomes, implementation direction, dependencies, risks, constraints, and approval-relevant trade-offs.
- The report includes visual maps for flows, dependencies, coverage, and stage relationships where those maps make the change easier to understand.
- The report uses expandable or interactive sections to preserve depth without turning the first view into noise.
- Cached quick-exit runs keep the same full report shape and do not replace a rich tab with a thinner status-only tab.
- User acceptance happens from the generated HTML report. Markdown artifacts remain the editable source of truth, but they are not the review surface the user is expected to approve.

### Health Metrics

- `check-chain` remains deterministic: closed validation checklists stay closed, and the report must not invent requirements that are absent from intent, spec, plan, result evidence, or the conversation context.
- The generated HTML remains self-contained and offline-readable: no CDN, no network fetches, no external images, and no dev server requirement.
- The chain report merge contract stays intact: only the owned tab is replaced; non-owned tabs are preserved.
- Existing `chain-gate.py` compatibility stays intact: the frontmatter contract, review blocks, result blocks, hashes, and verdict semantics do not change unless explicitly approved later.
- `docs/TODO.md` status behavior stays unchanged.
- Report depth stays readable: detailed evidence is organized with expandable sections, filters, or small inline interactions instead of long unstructured blocks.

### Done When

- Generated intent/spec/plan report tabs include narrative overview, implementation explanation, dependency/coverage maps, risks/constraints, expandable detail, and full phase/finding/verdict evidence.
- The review loop is explicit: the user reviews the HTML report, requested changes are made in markdown source artifacts, and `check-chain` regenerates the report before the next approval.
- Cached quick-exit regenerates the same full owned-tab block set.
- The existing chain-gate/frontmatter/TODO contracts remain compatible.
- Focused checks and the relevant Bash test suite pass, and a self-contained offline HTML report can be opened without external resources.

## Non-Goals

- Do not change `chain-gate.py`.
- Do not change the `review:` or `result_check:` frontmatter contract.
- Do not change `docs/TODO.md` schema or status semantics.
- Do not make `html-report` read chain source documents directly in chain mode.
- Do not introduce CDN, runtime network access, external assets, or a dev-server requirement.
- Do not add a large vendored visualization library in the first implementation. That remains proposal-first.

## Architecture

### 1. Responsibility Boundary

`check-chain` owns semantic extraction. It reads the relevant chain artifact and frontmatter, then reconstructs the full owned-tab payload on every run, including cached quick-exit runs. The payload must include narrative, visualization data, source anchors, phase state, findings, and summary.

`html-report` owns rendering and merging. In `mode: chain`, it receives the owned tab content from `check-chain`, writes or updates `docs/superpowers/reports/<topic>-results.html`, preserves non-owned tabs, keeps theme support, and validates that the report is self-contained.

This preserves the existing chain-mode model documented in `html-report/references/chain-report.md`: the renderer reads only the target report as a merge source, not the intent/spec/plan/result markdown artifacts.

### 2. Contract Compatibility

No machine-readable gate state moves into the HTML report. `chain-gate.py` continues to read only the existing frontmatter state:

- `review.<stage>_hash`
- `review.phases`
- `review.findings`
- `chain.intent`
- `chain.spec`
- `result_check.verdict`
- `result_check.plan_hash`

The enriched report is a user-facing artifact. It must not become a hidden source of gate truth.

### 3. Language Boundary

All generated report text visible to the user must be Russian. This includes headings, diagram labels, notes, findings table labels, filters, fallback messages, and summaries.

All markdown artifacts stay English. This includes intent, spec, plan, implementation notes, wiki pages, and test comments. Source text can be quoted in its original language only when used as a short anchor or code/path reference.

### 4. HTML-First Review Workflow

The generated HTML report is the approval surface for users. Intent, spec, plan, and result markdown files stay as editable source artifacts, but the user should not be expected to review or approve those markdown files directly when a chain report exists.

The review loop is:

1. `check-chain <stage>` validates the markdown source and regenerates the owned HTML report tab.
2. The user reviews the HTML report.
3. If the user has comments, the agent updates the relevant markdown source artifact.
4. The agent reruns `check-chain <stage>` so the HTML report reflects the updated source.
5. The user approves the regenerated HTML report.

This makes the HTML report the single user-facing artifact while preserving markdown as the auditable source of truth.

## Enriched Payload Contract

`check-chain` must extend the current owned-tab payload. The existing six blocks remain required:

1. heading;
2. artifact summary;
3. diagram block;
4. phase or verdict results;
5. findings;
6. final summary.

The new contract refines block 2 and block 3 into a richer stage-specific payload.

### Common Blocks For Every Stage

Every checked tab must include:

- `Executive overview`: one to three Russian paragraphs explaining what the stage proves and why the user should care.
- `Source anchors`: links or labels for the exact source sections used to build the narrative and diagrams.
- `Approval lens`: a compact section answering what is safe, what is risky, what is blocked, and what needs human approval.
- `Mandatory semantic visualization`: at least one stage-specific diagram or compact matrix.
- `Expandable evidence`: raw section details, long findings, source fragments, and mappings placed under `<details>`.
- `Phase/findings/verdict evidence`: the current validation state from frontmatter.

If the source artifact lacks enough structure for a full diagram, the tab must show a compact matrix plus an explicit Russian fallback note. It must not silently omit the semantic visualization block.

## Mandatory Rich Diagrams

Rich diagrams are mandatory for `intent`, `spec`, and `plan`; `result` gets the same treatment when diff evidence exists. Diagrams are semantic views, not decoration. Each one must answer at least one approval question:

- What changes?
- Why is it safe?
- What depends on it?
- What proves it?
- Where must a human decide?

### Intent Diagrams

The intent tab must include these semantic views:

- `Outcome Chain`: problem/objective -> desired outcomes -> done-when criteria.
- `Constraint Matrix`: steering constraints vs hard constraints, including language, offline, and security constraints.
- `Autonomy Map`: full, guarded, proposal-first, and no-go decision zones.
- `Context Map`: systems, modules, people, docs, and skills that interact with the change.

If the intent source does not provide enough data for one of these views, `check-chain` emits a compact "source lacks structure" matrix for that view.

### Spec Diagrams

The spec tab must include these semantic views:

- `Requirement Coverage Map`: intent outcome -> spec requirement -> acceptance criterion.
- `Component Graph`: modules, files, skills, docs, and boundaries affected by the design.
- `Data Flow`: source artifacts -> `check-chain` extraction -> enriched payload -> `html-report` rendering -> user approval.
- `Risk/Mitigation Map`: constraint or risk -> mitigation or design response.

The spec report must make it possible to understand what will be implemented and where the boundaries are without opening the markdown spec first.

### Plan Diagrams

The plan tab must include these semantic views:

- `Step DAG`: dependency order between implementation steps.
- `Artifact Impact Map`: plan step -> files, skills, docs, report sections, or tests touched.
- `Verification Map`: plan step -> command/check -> expected evidence.
- `Human Checkpoint Flow`: proposal-first or no-go decisions derived from autonomy zones.

The plan report must make it clear how the implementation will proceed, which order constraints exist, and how each step will be verified.

### Result Diagrams

The result tab keeps existing reconciliation and adds richer evidence views:

- `Diff Reconciliation Graph`: plan steps -> changed paths -> DONE/PARTIAL/MISSING/EXCESS.
- `Outcome Evidence Map`: intent outcomes and spec requirements -> diff or test evidence.
- `Excess/Gap Map`: unplanned changes and missing work, grouped by severity.

If the result stage is reached before implementation and `git diff` is empty, the report should keep a clear "pending implementation" state instead of pretending a result exists.

## Rendering And Interaction

The first implementation uses self-contained HTML, CSS, inline SVG, and small custom inline JavaScript only when it improves usability.

### Baseline Rendering

`html-report` should support or preserve:

- inline SVG diagrams for flows, DAGs, component graphs, risk maps, and reconciliation maps;
- CSS-based matrices, cards, badges, and status blocks;
- `<details>` for source anchors, raw findings, and long evidence;
- theme toggle;
- four chain tabs and marker-based merge.

### Small Inline JavaScript

Small inline JavaScript is allowed as an enhancement for:

- filtering findings, requirements, or plan steps;
- highlighting linked entities such as outcome -> requirement -> plan step;
- expand/collapse all controls;
- tab-local search.

Inline JavaScript must not load external resources. It must not become required for reading the report: the default HTML content must remain useful if script execution is disabled.

### Vendored Libraries

A vendored visualization library is not part of this implementation. It remains proposal-first and requires a separate justification covering:

- why CSS/SVG/custom inline JavaScript is insufficient;
- library size impact;
- offline behavior;
- fallback behavior;
- maintenance and security considerations.

## Skill Instruction Changes

### `check-chain/SKILL.md`

Add an `Enriched chain report payload` section under the HTML report step. It must specify:

- common enriched blocks;
- mandatory rich diagrams per stage;
- stage-specific extraction rules;
- source-anchor rules;
- Russian HTML and English markdown language rule;
- cached quick-exit full-regeneration rule;
- fallback note behavior when source structure is insufficient;
- no invention rule for diagrams and narratives.

The existing phase checklists remain closed and unchanged. Enriched report generation may summarize validated source material, but it must not introduce extra validation criteria.

### `html-report/SKILL.md`

Clarify that chain mode accepts enriched owned-tab HTML from the caller. It must preserve the existing boundary:

- no direct reads of intent/spec/plan/result markdown in chain mode;
- target report read only as the merge source;
- non-owned tabs preserved;
- one self-contained HTML file;
- no external dependencies.

The skill should explicitly allow inline SVG, `<details>`, CSS diagrams, and small inline JavaScript under the guarded self-validation rules.

### `html-report/references/chain-report.md`

Expand the chain report reference with:

- semantic block expectations for owned tabs;
- mandatory visualization expectations;
- optional inline JavaScript boundaries;
- additional self-validation items for enriched tabs;
- Russian user-facing text requirement.

The marker contract remains unchanged.

## Data Flow

1. User or agent invokes `check-chain <stage>`.
2. `check-chain` resolves the artifact, validates it, updates frontmatter, and computes final verdict as it does today.
3. `check-chain` extracts report semantics from the current artifact body, frontmatter, chain links, and result diff evidence when applicable.
4. `check-chain` builds a full Russian owned-tab payload containing narrative, diagrams, matrices, details, findings, and summary.
5. `html-report` merges the owned tab into `docs/superpowers/reports/<topic>-results.html`.
6. `docs/TODO.md` is updated as it is today.
7. The user reviews and approves the HTML report, not the markdown source directly.
8. If the user requests changes, markdown sources are edited and the relevant `check-chain` stage is rerun to regenerate the report.
9. On cached quick-exit, `check-chain` repeats steps 3-5 from current source/frontmatter so the tab stays rich.

## Error Handling

- If a required semantic view cannot be derived from source anchors, emit a compact matrix and a Russian fallback note instead of fabricating content.
- If the report content would require external resources, stop and report the violation.
- If inline JavaScript is used, log that it is an enhancement and ensure core content remains visible without it.
- If chain report markers are missing or corrupted, keep the existing `html-report` recovery behavior and validate all four tab markers after merge.
- If enriched extraction conflicts with frontmatter state, frontmatter remains authoritative for verdicts and phase state.

## Validation Plan

Focused validation should include:

- a text check that `check-chain/SKILL.md` documents all mandatory diagrams for intent, spec, plan, and result;
- a text check that HTML report user-facing text is specified as Russian-only and markdown artifacts as English-only;
- a text check that user approval is specified as HTML-report-first, with markdown edits followed by report regeneration;
- a text check that `html-report` chain mode still does not read chain markdown sources directly;
- a text check that no CDN, external resource, or `script src` allowance is introduced;
- a marker-contract check for the chain report reference;
- the relevant Bash tests for skill routing, IDD wiring, and smoke behavior.

Full validation remains:

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

## Open Decisions

No open decisions remain for the first implementation. Large vendored JavaScript visualization libraries are explicitly out of scope and require a later proposal-first decision.

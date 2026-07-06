---
review:
  plan_hash: 035b24e3424a165b
  last_run: 2026-07-06
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-07-06-check-chain-report-quality-intent.md
  spec: docs/superpowers/specs/2026-07-06-check-chain-report-quality-design.md
result_check:
  verdict: OK
  plan_hash: 035b24e3424a165b
  last_run: 2026-07-06
---
# Check-Chain Report Quality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich the `check-chain` chain-mode HTML report contract so users approve IDD/SDD artifacts through a Russian HTML report with mandatory semantic diagrams, while markdown remains the English editable source.

**Architecture:** `check-chain` becomes the semantic extractor for report payloads and owns stage-specific narrative, source anchors, diagrams, and fallback matrices. `html-report` remains the self-contained renderer and tab merge layer; it receives enriched owned-tab HTML from `check-chain` and does not read chain markdown sources directly.

**Tech Stack:** Bash tests with `tests/helpers.sh`, markdown skill instructions, zero-dependency offline HTML, CSS, inline SVG, optional small inline JavaScript.

---

## File Structure

- Modify `.codex-isolated/skills/check-chain/SKILL.md`: add the enriched payload contract under `Step 5 — HTML report`, including mandatory diagrams for intent/spec/plan/result, language rules, source anchors, cached quick-exit, and HTML-first approval.
- Modify `.codex-isolated/skills/html-report/SKILL.md`: clarify renderer boundaries, Russian report text, enriched owned-tab input, inline SVG/`details`/small inline JavaScript support, and no direct chain source reads.
- Modify `.codex-isolated/skills/html-report/references/chain-report.md`: expand chain-mode expectations for semantic blocks, mandatory visualizations, marker preservation, inline JavaScript boundaries, and HTML-first review flow.
- Create `tests/test_chain_report_quality.sh`: focused dependency-free test that fails until all report-quality contracts are documented.
- Update `docs/TODO.md`, `docs/superpowers/reports/check-chain-report-quality-results.html`, and the plan frontmatter through `/check-chain plan` after the plan is written.

## Task 1: Add Failing Contract Test

**Files:**
- Create: `tests/test_chain_report_quality.sh`

- [ ] **Step 1: Create the focused test file**

Add this exact file:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
cd "$ROOT"

CC=".codex-isolated/skills/check-chain/SKILL.md"
HR=".codex-isolated/skills/html-report/SKILL.md"
CR=".codex-isolated/skills/html-report/references/chain-report.md"

cc_text="$(cat "$CC")"
hr_text="$(cat "$HR")"
cr_text="$(cat "$CR")"

assert_contains "check-chain documents enriched payload" "$cc_text" "## Enriched chain report payload"
assert_contains "check-chain keeps existing six blocks" "$cc_text" "The existing six owned-tab blocks remain mandatory"
assert_contains "check-chain requires Russian HTML text" "$cc_text" "All HTML report user-facing text is Russian"
assert_contains "check-chain keeps markdown English" "$cc_text" "All markdown artifacts remain English"
assert_contains "check-chain documents HTML-first approval" "$cc_text" "The user approves the generated HTML report"
assert_contains "check-chain documents markdown feedback loop" "$cc_text" "feedback is fixed in markdown source artifacts"
assert_contains "check-chain prohibits invented report content" "$cc_text" "Do not invent requirements, dependencies, decisions, risks, or diagrams"
assert_contains "check-chain cached exit stays rich" "$cc_text" "Cached quick-exit runs must regenerate the same full enriched owned-tab payload"

for diagram in \
  "Outcome Chain" \
  "Constraint Matrix" \
  "Autonomy Map" \
  "Context Map" \
  "Requirement Coverage Map" \
  "Component Graph" \
  "Data Flow" \
  "Risk/Mitigation Map" \
  "Step DAG" \
  "Artifact Impact Map" \
  "Verification Map" \
  "Human Checkpoint Flow" \
  "Diff Reconciliation Graph" \
  "Outcome Evidence Map" \
  "Excess/Gap Map"
do
  assert_contains "check-chain mandatory diagram $diagram" "$cc_text" "$diagram"
done

assert_contains "html-report accepts enriched owned tab" "$hr_text" "chain mode accepts a fully enriched owned-tab payload from the caller"
assert_contains "html-report does not read chain sources" "$hr_text" "does not read intent, spec, plan, or result markdown sources in chain mode"
assert_contains "html-report allows inline svg" "$hr_text" "inline SVG"
assert_contains "html-report allows small inline js" "$hr_text" "small inline JavaScript"
assert_contains "html-report keeps self-contained report" "$hr_text" "no CDN"
assert_contains "html-report preserves non-owned tabs" "$hr_text" "preserve the non-owned tabs"

assert_contains "chain-report semantic blocks" "$cr_text" "Semantic owned-tab blocks"
assert_contains "chain-report mandatory visualizations" "$cr_text" "Mandatory rich visualizations"
assert_contains "chain-report html-first review" "$cr_text" "HTML-first review flow"
assert_contains "chain-report source fallback" "$cr_text" "source lacks enough structure"
assert_contains "chain-report marker contract preserved" "$cr_text" "Markers are the exact literal strings"

finish
```

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
bash tests/test_chain_report_quality.sh
```

Expected: FAIL lines for missing enriched payload, mandatory diagrams, HTML-first approval, and renderer contract strings.

- [ ] **Step 3: Commit the failing test**

Run:

```bash
git add tests/test_chain_report_quality.sh
git commit -m "test(chain): cover enriched report quality contract"
```

Expected: one commit containing only `tests/test_chain_report_quality.sh`.

## Task 2: Enrich `check-chain` Report Contract

**Files:**
- Modify: `.codex-isolated/skills/check-chain/SKILL.md`
- Test: `tests/test_chain_report_quality.sh`

- [ ] **Step 1: Insert the enriched payload section**

In `.codex-isolated/skills/check-chain/SKILL.md`, immediately after the current owned-tab payload block and before `On a cached quick-exit`, insert this markdown:

```markdown
#### Enriched chain report payload

The existing six owned-tab blocks remain mandatory, but they are the minimum shape, not the desired depth. Reconstruct a full enriched owned-tab payload on every run, including cached quick-exit runs.

All HTML report user-facing text is Russian. This includes headings, diagram labels, notes, table headers, filters, fallback messages, findings labels, and summaries. All markdown artifacts remain English: intent, spec, plan, implementation docs, wiki pages, and test comments.

The user approves the generated HTML report. Markdown artifacts are the editable source of truth, but they are not the user approval surface when a chain report exists. If the user gives feedback, feedback is fixed in markdown source artifacts first, then the relevant `check-chain <stage>` run regenerates the HTML report for the next review.

Do not invent requirements, dependencies, decisions, risks, or diagrams. Every narrative sentence and every diagram edge must be anchored in the current artifact body, linked chain artifacts, frontmatter, result diff evidence, or the conversation context available to the stage. If the source lacks enough structure for a diagram, emit a compact matrix plus a Russian note: `В источнике недостаточно структуры для полноценной схемы; показана компактная матрица.`

Every checked stage tab must include these common semantic blocks:

1. Executive overview — one to three Russian paragraphs explaining what the stage proves and why it matters.
2. Source anchors — section labels or paths for the source material behind the narrative and diagrams.
3. Approval lens — what is safe, what is risky, what is blocked, and what needs human approval.
4. Mandatory semantic visualization — the stage-specific diagrams below, or a fallback matrix with the explicit source-lacks-structure note.
5. Expandable evidence — raw section details, long mappings, source fragments, and findings under `<details>`.
6. Phase/findings/verdict evidence — current validation state from frontmatter.

Mandatory rich visualizations by stage:

- `intent`:
  - `Outcome Chain`: problem/objective → desired outcomes → done-when criteria.
  - `Constraint Matrix`: steering constraints vs hard constraints, including language, offline, and security constraints.
  - `Autonomy Map`: full, guarded, proposal-first, and no-go decision zones.
  - `Context Map`: systems, modules, people, docs, and skills that interact with the change.
- `spec`:
  - `Requirement Coverage Map`: intent outcome → spec requirement → acceptance criterion.
  - `Component Graph`: modules, files, skills, docs, and boundaries affected by the design.
  - `Data Flow`: source artifacts → `check-chain` extraction → enriched payload → `html-report` rendering → user approval.
  - `Risk/Mitigation Map`: constraint or risk → mitigation or design response.
- `plan`:
  - `Step DAG`: dependency order between implementation steps.
  - `Artifact Impact Map`: plan step → files, skills, docs, report sections, or tests touched.
  - `Verification Map`: plan step → command/check → expected evidence.
  - `Human Checkpoint Flow`: proposal-first or no-go decisions derived from autonomy zones.
- `result`:
  - `Diff Reconciliation Graph`: plan steps → changed paths → DONE/PARTIAL/MISSING/EXCESS.
  - `Outcome Evidence Map`: intent outcomes and spec requirements → diff or test evidence.
  - `Excess/Gap Map`: unplanned changes and missing work, grouped by severity.

Cached quick-exit runs must regenerate the same full enriched owned-tab payload from the current source artifacts and stored frontmatter, not a thinner status-only tab.
```

- [ ] **Step 2: Run the focused test and confirm partial progress**

Run:

```bash
bash tests/test_chain_report_quality.sh
```

Expected: check-chain assertions pass; html-report and chain-report assertions still fail.

- [ ] **Step 3: Commit check-chain contract update**

Run:

```bash
git add .codex-isolated/skills/check-chain/SKILL.md
git commit -m "docs(chain): require enriched check-chain report payload"
```

Expected: one commit modifying only `.codex-isolated/skills/check-chain/SKILL.md`.

## Task 3: Enrich `html-report` Renderer Contract

**Files:**
- Modify: `.codex-isolated/skills/html-report/SKILL.md`
- Test: `tests/test_chain_report_quality.sh`

- [ ] **Step 1: Add the chain-mode renderer boundary**

In `.codex-isolated/skills/html-report/SKILL.md`, under `## Workflow` after the recipe list that mentions `references/chain-report.md`, insert this markdown:

```markdown
### Chain-mode enriched payload boundary

In `mode: chain`, `html-report` is a renderer and merge layer. It does not read intent, spec, plan, or result markdown sources in chain mode. It reads only the existing caller-supplied target report as a merge source, then replaces the owned tab content passed by the caller.

`html-report` chain mode accepts a fully enriched owned-tab payload from the caller. That payload may include narrative blocks, tables, `<details>`, inline SVG, CSS diagrams, and small inline JavaScript. Preserve the non-owned tabs byte-for-byte except for the single active `checked` radio state.

All chain report user-facing text must remain Russian. Markdown source artifacts and implementation docs remain English outside the generated HTML report.

Small inline JavaScript is allowed only as progressive enhancement for filtering, linked-entity highlighting, expand/collapse controls, or tab-local search. The report must remain readable when JavaScript is disabled. No CDN, no `<script src>`, no fetch, no external images, and no sibling assets.
```

- [ ] **Step 2: Tighten the self-validation checklist**

In the `Self-Validation Checklist`, add these bullets before the `mode: chain only` subsection:

```markdown
- [ ] In `mode: chain`, no direct reads of intent/spec/plan/result markdown sources are required by this skill.
- [ ] In `mode: chain`, enriched owned-tab content is accepted from the caller and non-owned tabs are preserved.
- [ ] Any inline JavaScript is small, bounded, and progressive; core report content remains visible without it.
```

- [ ] **Step 3: Run the focused test and confirm partial progress**

Run:

```bash
bash tests/test_chain_report_quality.sh
```

Expected: check-chain and html-report assertions pass; chain-report reference assertions still fail.

- [ ] **Step 4: Commit html-report contract update**

Run:

```bash
git add .codex-isolated/skills/html-report/SKILL.md
git commit -m "docs(report): define enriched chain renderer boundary"
```

Expected: one commit modifying only `.codex-isolated/skills/html-report/SKILL.md`.

## Task 4: Expand Chain Report Reference

**Files:**
- Modify: `.codex-isolated/skills/html-report/references/chain-report.md`
- Test: `tests/test_chain_report_quality.sh`

- [ ] **Step 1: Add semantic block expectations**

In `.codex-isolated/skills/html-report/references/chain-report.md`, after the `## Caller contract` section and before `## Document skeleton + boundary markers`, insert this markdown:

```markdown
## Semantic owned-tab blocks

The caller owns the stage semantics and passes complete owned-tab HTML. The tab should contain:

- executive overview;
- artifact summary;
- source anchors;
- approval lens;
- mandatory semantic visualization;
- expandable evidence using `<details>`;
- phase, findings, and final verdict evidence.

All visible report text is Russian. Source anchors may include English markdown section names, paths, code identifiers, and short source fragments.

## Mandatory rich visualizations

Every checked intent/spec/plan tab must include semantic diagrams or compact matrices. Result tabs include the same treatment when diff evidence exists.

- Intent: `Outcome Chain`, `Constraint Matrix`, `Autonomy Map`, `Context Map`.
- Spec: `Requirement Coverage Map`, `Component Graph`, `Data Flow`, `Risk/Mitigation Map`.
- Plan: `Step DAG`, `Artifact Impact Map`, `Verification Map`, `Human Checkpoint Flow`.
- Result: `Diff Reconciliation Graph`, `Outcome Evidence Map`, `Excess/Gap Map`.

If the source lacks enough structure for a full diagram, render a compact matrix plus the explicit Russian fallback note: `В источнике недостаточно структуры для полноценной схемы; показана компактная матрица.`

## HTML-first review flow

The generated report is the user approval surface. Markdown chain artifacts remain the editable source of truth. When the user requests changes, update the relevant markdown source first, rerun the owning `check-chain <stage>`, and present the regenerated HTML report for the next approval.

Small inline JavaScript may support filtering, highlighting, expand/collapse controls, or tab-local search, but the report must remain readable without JavaScript. Never add CDN or external runtime dependencies.
```

- [ ] **Step 2: Run the focused test and confirm it passes**

Run:

```bash
bash tests/test_chain_report_quality.sh
```

Expected: `PASS` for every assertion and `FAIL=0`.

- [ ] **Step 3: Commit chain-report reference update**

Run:

```bash
git add .codex-isolated/skills/html-report/references/chain-report.md
git commit -m "docs(report): add semantic chain report reference"
```

Expected: one commit modifying only `.codex-isolated/skills/html-report/references/chain-report.md`.

## Task 5: Run Focused And Full Validation

**Files:**
- Read-only validation over changed files and tests.

- [ ] **Step 1: Run focused report-quality test**

Run:

```bash
bash tests/test_chain_report_quality.sh
```

Expected: `FAIL=0`.

- [ ] **Step 2: Run existing skill and IDD tests**

Run:

```bash
bash tests/test_idd_skills.sh
bash tests/test_skill_routing.sh
bash tests/test_smoke.sh
```

Expected: each command exits 0 and prints `FAIL=0` for helper-based tests.

- [ ] **Step 3: Run full Bash suite**

Run:

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: command exits 0. If a pre-existing unrelated failure appears, record the failing test name and rerun the focused checks from steps 1-2.

## Task 6: Validate Plan And Update Chain Artifacts

**Files:**
- Modify: `docs/superpowers/plans/2026-07-06-check-chain-report-quality.md`
- Modify: `docs/TODO.md`
- Modify: `docs/superpowers/reports/check-chain-report-quality-results.html`

- [ ] **Step 1: Run plan validation**

Run:

```bash
check-chain plan docs/superpowers/plans/2026-07-06-check-chain-report-quality.md
```

Expected: plan review frontmatter is written with `structure`, `coverage`, `dependencies`, `verifiability`, and `consistency` passed; the HTML report Plan tab is regenerated; `docs/TODO.md` marks Plan as `✓`.

- [ ] **Step 2: Verify chain report remains self-contained**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
s = Path("docs/superpowers/reports/check-chain-report-quality-results.html").read_text()
for tab in ("intent", "spec", "plan", "result"):
    assert s.count(f"<!-- TAB:{tab} START -->") == 1
    assert s.count(f"<!-- TAB:{tab} END -->") == 1
assert s.count('class="tab-radio" hidden checked') == 1
for bad in ("src=", "href=", "http://", "https://", "//"):
    assert bad not in s
print("chain report self-contained")
PY
```

Expected: prints `chain report self-contained`.

- [ ] **Step 3: Commit plan validation artifacts**

Run:

```bash
git add docs/superpowers/plans/2026-07-06-check-chain-report-quality.md docs/TODO.md docs/superpowers/reports/check-chain-report-quality-results.html
git commit -m "docs(plan): validate check-chain report quality plan"
```

Expected: commit contains only plan frontmatter, TODO row update, and regenerated report tab.

## Task 7: Update Wiki After Behavior Documentation Changes

**Files:**
- iwiki domain: `icodex`

- [ ] **Step 1: Update the relevant iwiki page**

Use MCP `wiki_update_page` or `wiki_write_page` for domain `icodex`.

Recommended target:

- Existing page: `testing-and-project-state`
- Heading: `Superpowers Artifacts`

Replacement section body:

```markdown
`docs/superpowers/` stores design and execution artifacts:

- `intents/`: approved intent docs when a task needs IDD intent capture.
- `specs/`: SDD design specs.
- `plans/`: implementation plans.
- `reports/`: result reports and HTML reports.
- `notes/`: longer methodology notes.

For IDD/SDD chain topics, the generated HTML report under `docs/superpowers/reports/<topic>-results.html` is the user-facing approval artifact. Intent, spec, plan, and result markdown files remain the English editable source of truth. User feedback is applied to those markdown sources first, then `check-chain <stage>` regenerates the Russian HTML report for review.
```

- [ ] **Step 2: Run wiki lint**

Use MCP `wiki_lint` for domain `icodex`.

Expected: no broken references. Existing advisory stale/long-lead warnings may remain if unrelated to this change.

- [ ] **Step 3: Record wiki update in final summary**

In the final implementation summary, include the page and heading updated plus the lint result.

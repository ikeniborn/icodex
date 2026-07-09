---
name: check-chain
description: Use to validate the IDD→SDD chain (intent → spec → plan → result). Triggers on "$check-chain", "check chain", and "validate intent/spec/plan/result"; this is the remediation the chain-gate hook points to. Runs the whole chain (sequential gate) with no argument, or a single stage with "$check-chain <stage>".
---

# check-chain — unified IDD→SDD chain validator

One skill, two run modes, four stage profiles over one shared core. Replaces the
former `check-intent`, `check-spec`, `check-plan`, `check-result` commands.

## Subagent Routing

Agent: `chain-auditor`

Use a subagent when phase scans, section-hash evidence, result diff reconciliation, or report/task-log update checks would pollute the main context with large intermediate output.

Stay in the main context for user confirmations, final verdict handling, frontmatter writes, the final result report, task-log row updates, and downstream chain stop/go decisions.

Return summary:
- decision: `OK`, `needs_work`, or `uncertain`
- evidence: artifact paths, hashes, phases, findings, and matched diff paths
- risks: CRITICAL findings, stale hashes, missing artifacts, unresolved verdicts, or uncertainty
- next_action: the smallest main-context action required

Stop rule: any CRITICAL finding, hash mismatch uncertainty, missing artifact, or result reconciliation uncertainty halts downstream stages until the main context resolves it. Main context keeps confirmations, final verdicts, frontmatter writes, report merges, task-log row updates, and downstream stop/go decisions.

## Invocation & argument parsing

Codex skill form:

```
$check-chain                       → whole chain (sequential gate)
$check-chain <stage>               → that stage only      (stage ∈ intent|spec|plan|result)
$check-chain <stage> <path>        → that stage, explicit file
$check-chain <path>                → infer stage from the file's directory, single-stage
```

Parse `$ARGUMENTS`:
- First token in `intent|spec|plan|result` → the target stage.
- A token that is a path → the explicit artifact file.
- No stage and no path → whole-chain mode.
- A lone path with no stage → resolve the stage from the directory (`intents/`→intent,
  `specs/`→spec, `plans/`→plan). `result` is never inferred from a path (it shares
  `plans/` with `plan`); it must be named explicitly.

## Shared core (applied by every stage)

### Canonical hashing (MANDATORY)

Run bash via the Bash tool; never recompute "in your head".
- **Body hash** (excludes frontmatter):
  ```bash
  awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2{print}' <FILE> | sha256sum | cut -c1-16
  ```
- **Section hash** — the body from a `##`/`###` heading to the next heading of the same
  or higher level (exclusive), piped through `sha256sum | cut -c1-16`.
- If frontmatter is absent (`fm` < 2) — hash the whole file: `sha256sum <FILE> | cut -c1-16`.

### Step 0 — quick exit by state

If frontmatter has a `review:` block, `current_body_hash == review.<hash_key>` AND every
phase `status == passed` AND no finding with `severity == CRITICAL ∧ verdict == open` →
output `OK (cached, hash match)` and finish. (`result` uses `result_check.verdict == OK`
with a matching `plan_hash`.) Otherwise continue. The advisory `alignment` phase is not
recomputed on a hash match — trust the previous run.

### Step 1 — scope resolution

Locate the stage artifact by: explicit path arg → by `<topic>` in the stage dir → the
most-recently-modified file in the stage dir. If not found, report
«Не найден <stage>. Укажи путь: `$check-chain <stage> path/to/file.md`» and stop.

### Step 2 — target confirmation & init state

Report «Буду проверять: `<путь>`. Верно?» and, after confirmation: read the frontmatter;
if there is no `review:` block, scaffold one for the stage's phase set; compute section
hashes; reset any finding whose `section_hash` changed to `verdict: open`; update the
stage hash + `last_run`; maintain the `chain:` block for downstream stages
(`spec` → `chain.intent`; `plan` → `chain.intent` + `chain.spec`; `intent` writes none).
Never edit the artifact body — only its frontmatter.

This is only target confirmation, not artifact approval. Do not ask the user to approve
an intent, spec, or plan before the stage has been checked and returned `OK`.

### Frontmatter contract (MANDATORY shape)

`chain-gate.py` reads this exact shape. `phases` is a **map keyed by phase name**
(never a list); `findings` is a list. Emit:

```yaml
---
review:
  <stage>_hash: <16-hex body hash>
  last_run: <YYYY-MM-DD>
  phases:
    structure: { status: passed }      # one key per phase; status ∈ passed|in_progress
    coverage:  { status: passed }
  findings:
    - id: F-001
      phase: structure
      severity: CRITICAL               # CRITICAL|WARNING|INFO
      section: "<heading>"
      section_hash: <16-hex>
      fragment: "<≤140-char quote or null>"
      text: "<what is wrong>"
      fix: "<how to fix>"
      verdict: open                    # open|accepted|wontfix|fixed
chain:
  intent: <path or null>               # spec adds chain.intent; plan adds intent+spec
  spec: <path or null>
---
```

For the `result` stage the block is `result_check:` with `verdict: OK|needs_work`,
`plan_hash`, `last_run` (no `phases`/`findings`).

### Step 3 — phase execution & finding-handling

Phases run strictly sequentially; phase N+1 starts only when phase N has no CRITICAL with
`verdict: open`. For each phase apply its **closed checklist** (do NOT extend) to the
body. For each finding: dedupe by `section + text + section_hash`; otherwise create
`id: F-NNN` (monotonic), `phase`, `severity`, `section`, `section_hash`, `fragment`
(≤140-char quote, `null` for structural), `text`, `fix`, `verdict: open`, `verdict_at: null`.
Write the updated frontmatter; report the phase; request verdicts (CRITICAL mandatory
`accepted|wontfix|fixed`, WARNING desirable, INFO optional). All CRITICAL closed →
`phase.status = passed`; else `in_progress`, stop and ask to fix and rerun.

### Step 4 — final verdict

Apply the Step 0 exit criterion: `OK` or «требует доработки: <N> critical open, <M> warning open».

Human approval is requested only after this stage returns `OK`. If the verdict is not
OK, fix the markdown source first, rerun this same stage, and keep the artifact
unapproved.

### Step 4A — docs and wiki consistency

Every stage must check whether its verdict changes documented behavior, architecture,
workflow, command semantics, approval rules, or user-facing report output. If yes,
update the repository docs that describe the change before final approval. When the
iwiki MCP server has a bound domain for this project, update the relevant wiki page
through `wiki_write_page`, `wiki_update_page`, or `wiki_delete_page`, then run
`wiki_lint`. Broken refs, stale pages for changed sources, or wiki text that contradicts
the checked artifact keep the stage at `needs_work`.

For `intent`, `spec`, and `plan`, documentation evidence is recorded in the validation
summary and frontmatter findings only; do not generate a stage HTML report. For
`result`, the final chain HTML report must include documentation evidence: changed
docs/wiki pages, unchanged-with-rationale docs, and the `wiki_lint` result when iwiki
is bound.

### Step 5 — Result-only HTML report

Intermediate stages (`intent`, `spec`, `plan`) do not invoke `html-report`; they update
frontmatter and `docs/TODO.md` only. Cached quick-exit runs for `intent`, `spec`, and `plan` do not regenerate HTML. This removes per-step HTML work from the IDD→SDD chain.

Only the `result` stage generates or refreshes the chain HTML report. It invokes the
`html-report` skill (`skill: "html-report"`) with `mode: chain`, output
`docs/superpowers/reports/<topic>-results.html`, and passes a complete single final
report for the completed task. Determine `<topic>` from the plan basename minus `.md`,
strip the `^YYYY-MM-DD-` date prefix, and strip a trailing `-plan` suffix if present;
fallback to the bare basename.

The final report is built from the current intent, spec, plan, result reconciliation,
review findings, verification evidence, documentation evidence, and TODO row state. It
is one self-contained Russian HTML file: all visible report text must be Russian-only
except technical terms, paths, code identifiers, stage keys, hash keys, and short source
fragments. It may use tabs or sections for readability, but it is generated once from
the `result` stage, not incrementally by stage-owned tab merges.

**Final report payload (MANDATORY).** Reconstruct the full block set from current chain
artifacts and result evidence:

1. `<h2>` heading — «Итоговый отчёт — <topic> — <last_run>».
2. Executive summary — task goal, implementation outcome, and final verdict.
3. Artifact summary — intent outcomes, spec requirements, plan steps, and result status.
4. Change inventory — every changed file or artifact grouped by implementation, tests,
   docs, wiki, skills, hooks, plugins, or generated assets; each row needs a brief,
   concrete Russian description of the specific change made within this task, why it
   changed, what result was obtained, and what evidence verifies it.
5. Reconciliation tables — plan step coverage, diff paths, outcome/spec coverage, and
   excess or missing work.
6. Review and verification evidence — code review findings, fixed bugs, commands run,
   and pass/fail evidence.
7. Documentation evidence — repository docs, iwiki updates, unchanged-with-rationale
   docs, and `wiki_lint` result when iwiki is bound.
8. Decision propagation — any implementation-time decision drift and the artifacts that
   were updated or intentionally left unchanged.
9. Findings and summary — every finding plus the `OK` / `needs_work` verdict.

## Enriched final report payload

The final report blocks above are the minimum shape, not the desired depth. Reconstruct
a full enriched report on every `result` run, including cached quick-exit result runs.

All HTML report user-facing text is Russian only. This includes headings, diagram labels,
notes, table headers, filters, fallback messages, findings labels, summaries, navigation
labels, button labels, tooltips, titles, and placeholders. English is allowed only for technical terms, code identifiers, file paths, stage keys (`intent`, `spec`, `plan`, `result`), hash keys, source section names, and short source fragments that would lose meaning if translated.
Canonical diagram names below are internal identifiers; visible diagram titles in HTML
must be Russian unless the title is itself a technical term.
All markdown artifacts remain English: intent, spec, plan, implementation docs, wiki
pages, and test comments.

Visible Russian title map for canonical diagram identifiers:

- Outcome Chain -> Цепочка результатов
- Constraint Matrix -> Матрица ограничений
- Autonomy Map -> Карта автономии
- Context Map -> Карта контекста
- Requirement Coverage Map -> Карта покрытия требований
- Component Graph -> Граф компонентов
- Data Flow -> Поток данных
- Risk/Mitigation Map -> Карта рисков и мер
- Step DAG -> Граф шагов
- Artifact Impact Map -> Карта влияния на артефакты
- Verification Map -> Карта проверок
- Human Checkpoint Flow -> Поток человеческих контрольных точек
- Diff Reconciliation Graph -> Граф сверки diff
- Outcome Evidence Map -> Карта свидетельств результатов
- Excess/Gap Map -> Карта лишнего и пропусков
- Code Review Findings Map -> Карта замечаний code review
- Documentation Evidence Map -> Карта документационных свидетельств
- Decision Propagation Map -> Карта распространения решений
- Change Inventory Map -> Карта изменений
- Process Flow Map -> Карта процесса

The generated HTML report is a final closeout artifact at `result`, not the approval
surface for intermediate `intent`, `spec`, or `plan` stages. Markdown artifacts remain
the editable source of truth. If the user gives feedback on intent/spec/plan before
implementation, fix the markdown source first and rerun the relevant `check-chain
<stage>`; no HTML is regenerated until `check-chain result`.

Do not invent requirements, dependencies, decisions, risks, or diagrams. Every narrative
sentence and every diagram edge must be anchored in the current artifact body, linked
chain artifacts, frontmatter, result diff evidence, or the conversation context available
to the stage. If the source lacks enough structure for a diagram, emit a compact matrix
plus a Russian note: `В источнике недостаточно структуры для полноценной схемы; показана
компактная матрица.`

The final report must include these common semantic blocks:

1. Executive overview — one to three Russian paragraphs explaining what the stage proves
   and why the completed task meets or does not meet the chain.
2. Source anchors — section labels or paths for the source material behind the narrative
   and diagrams.
3. Approval lens — what is safe, what is risky, what is blocked, and what needs human
   approval.
4. Mandatory semantic visualization — the diagrams below, or a fallback matrix with the
   explicit source-lacks-structure note. Add process diagrams when workflow, approval
   flow, hook order, command flow, or multi-step execution changed; add architecture or
   dependency diagrams when the diff changes boundaries between skills, hooks, plugins,
   scripts, docs, or runtime artifacts. If no diagram is warranted, record a Russian
   rationale explaining why a table is clearer than a diagram.
5. Expandable evidence — raw section details, long mappings, source fragments, and
   findings under `<details>`.
6. Phase/findings/verdict evidence — current validation state from frontmatter and
   `result_check`.

Mandatory rich visualizations in the final report:

- `intent`:
  - `Outcome Chain`: problem/objective → desired outcomes → done-when criteria.
  - `Constraint Matrix`: steering constraints vs hard constraints, including language,
    offline, and security constraints.
  - `Autonomy Map`: full, guarded, proposal-first, and no-go decision zones.
  - `Context Map`: systems, modules, people, docs, and skills that interact with the
    change.
- `spec`:
  - `Requirement Coverage Map`: intent outcome → spec requirement → acceptance criterion.
  - `Component Graph`: modules, files, skills, docs, and boundaries affected by the
    design.
  - `Data Flow`: source artifacts → `check-chain` extraction → enriched payload →
    `html-report` rendering → user approval.
  - `Risk/Mitigation Map`: constraint or risk → mitigation or design response.
- `plan`:
  - `Step DAG`: dependency order between implementation steps.
  - `Artifact Impact Map`: plan step → files, skills, docs, report sections, or tests
    touched.
  - `Verification Map`: plan step → command/check → expected evidence.
  - `Human Checkpoint Flow`: proposal-first or no-go decisions derived from autonomy
    zones.
- `result`:
  - `Diff Reconciliation Graph`: plan steps → changed paths → DONE/PARTIAL/MISSING/EXCESS.
  - `Outcome Evidence Map`: intent outcomes and spec requirements → diff or test evidence.
  - `Excess/Gap Map`: unplanned changes and missing work, grouped by severity.
  - `Change Inventory Map`: changed file or artifact → Russian change description → evidence.
  - `Code Review Findings Map`: changed code paths → reviewed risk → bug finding → fix evidence.
  - `Documentation Evidence Map`: behavior/architecture/user-facing change → doc or wiki update evidence.
  - `Decision Propagation Map`: implementation decision drift → intent/spec/plan/doc/wiki updates.
  - `Process Flow Map`: before/after process or approval flow when workflow changed.

Cached quick-exit runs for `result` must regenerate the same full enriched report from
the current source artifacts, stored frontmatter, and `result_check`, not a thinner
status-only report.

### Step 6 — TODO.md upsert

After the verdict, upsert the chain's row in `docs/TODO.md` keyed by `<topic>` (see the
Task Log convention in `CLAUDE.md`). Create the file with the header row if absent. Mark
this stage's cell `✓` on `OK` (`–` if it still needs work); `intent` opens the row, a
missing upstream stage is `n/a`; `result` on `OK` closes the row (`Result: OK`,
`Status: done`, `Closed: <today>`).

## Rules (prohibited)

- Extending a phase checklist — the closed list keeps the check deterministic and the
  hash-cache reproducible.
- Inventing requirements absent from the source (and the conversation, for `intent`).
- Editing the artifact body (frontmatter is the only exception).
- Writing «вероятно подразумевается» without a textual anchor.
- (`result`) Closing with `OK` while confirmed bugs, missing plan work, failed checks,
  or required documentation updates remain unresolved.

## Stage profiles

| stage | dir | glob | hash key | state block | phases |
|---|---|---|---|---|---|
| intent | intents/ | *-intent.md | intent_hash | review | structure, completeness, clarity, consistency, alignment(advisory) |
| spec | specs/ | *-design.md | spec_hash | review | structure, coverage, clarity, consistency |
| plan | plans/ | *.md | plan_hash | review | structure, coverage, dependencies, verifiability, consistency |
| result | plans/ | *.md | plan_hash | result_check | non-phased: git diff reconciliation |

### intent checklist

#### Phase 1: structure (CRITICAL)

Closed checklist (do NOT extend):
- Placeholders: `TODO`, `TBD`, `???`, `FIXME`
- All 7 template sections present: Objective, Desired Outcomes, Health Metrics, Strategic Context, Constraints, Autonomy Zones, Stop Rules
- Empty bullets / empty sections
- Broken internal section links (§X.Y, [link](#anchor))
- Duplicate section headings

#### Phase 2: completeness (CRITICAL)

Closed checklist (do NOT extend):
- Each constraint is bound to steering XOR hard (not both, not neither)
- Autonomy Zones cover all 4 zones (Full / Guarded / Proposal-first / No autonomy) or carry an explicit N/A for a zone
- Stop Rules contain ≥1 `Done when:` criterion
- Health Metrics are non-empty
- Strategic Context contains both `Interacts with:` and `Priority trade-off:`

#### Phase 3: clarity

Closed checklist (do NOT extend):
- Desired Outcomes are observable / user-facing, NOT implementation steps. An outcome phrased as "implemented / code written / function added" → **CRITICAL**. Observable but vague → WARNING.
- `Done when:` — a measurable result, not "code written". If it names an act of implementation instead of an observable result → **CRITICAL**.
- Health Metrics are measurable (a named metric, not a mood) → WARNING.
- Vague terms without a criterion: «быстро», «удобно», «надёжно», «достаточно», «при необходимости» → WARNING.

#### Phase 4: consistency (CRITICAL for contradictions)

Closed checklist (do NOT extend):
- Use the diff of changed sections from Step 2 (init-state) — do NOT recompute hashes; provide a summary of changes
- Intra-doc contradictions: constraint vs Desired Outcome; Health Metric vs Objective → CRITICAL
- **Status-guard:** if the body contains `**Status:** approved` but there is an open CRITICAL finding → create a `[CRITICAL]` finding «approved, но документ не валиден». Do NOT edit the `**Status:**` line — only the finding.

#### Phase 5: alignment (advisory — INFO/WARNING, NOT a gate, do NOT recompute on hash match)

Closed checklist (do NOT extend). Never emits CRITICAL; never blocks a phase transition or the final verdict:
- Conversation: do Objective and Desired Outcomes cover the original task the user described in the conversation? Is there an objective the user did not ask for? → INFO
- iwiki: does the intent contradict a documented decision, or do Health Metrics ignore components that reference this area? → WARNING. Requires the iwiki MCP tools `wiki_search` / `wiki_related` (bind the project domain first via `wiki_bind`).
- If the iwiki MCP server / `wiki_search` are unavailable — skip silently (like IDD Step 0). Do not block, do not mention the absence.

---
Next step: superpowers:brainstorming

### spec checklist

#### Phase 1: structure

Closed checklist (do NOT extend):
- Placeholders: `TODO`, `TBD`, `???`, `FIXME`
- Broken internal section links (§X.Y, [link](#anchor))
- Section numbering (gaps, duplicate numbers)
- Duplicate section headings

#### Phase 2: coverage

Closed checklist:
- Each task from the conversation context is covered by ≥1 spec requirement
- Each spec requirement is bound to a task (no "extras")
- Contradictions between requirements (§X says A, §Y says ¬A)

#### Phase 3: clarity

Closed checklist:
- Ambiguous wording without a criterion: «быстро», «удобно», «при необходимости», «достаточно», «надёжно»
- Requirements without an explicit DoD / acceptance criterion
- Inconsistent terms (one entity — different names)

#### Phase 4: consistency

Closed checklist:
- Use the diff of changed sections already computed in Step 2 (init-state) — do NOT recompute hashes
- Summary of changed sections and related findings

### plan checklist

#### Phase 1: structure

Closed checklist:
- Placeholders: `TODO`, `TBD`, `???`, `FIXME`
- Step/task numbering (gaps, duplicates)
- Duplicate step headings

#### Phase 2: coverage

Closed checklist:
- Each spec requirement is covered by ≥1 plan step
- Each plan step is bound to a spec requirement (no "extras")

#### Phase 3: dependencies

Closed checklist:
- Step order: using the result of step M in step N → M < N
- Cyclic dependencies between steps
- Artifact availability (a file/function mentioned in a step is created in a previous step)

#### Phase 4: verifiability

Closed checklist:
- Each step has a measurable definition of done (DoD)
- Steps with no explicit result ("work through", "study", "improve" without an output)
- Steps with no verification command / expected output

#### Phase 5: consistency

Closed checklist:
- Use the diff of changed plan/spec sections already computed in Step 2 (init-state) — do NOT recompute hashes
- Summary of changed sections

### result reconciliation and review

Result includes a focused code review in addition to diff reconciliation. It verifies
that the plan was executed, the implementation is not obviously buggy, required checks
were run, confirmed bugs were fixed, and documentation stayed current.

#### Step 1. Load the plan

- Read the plan file from `$ARGUMENTS`
- Extract `chain.intent` and `chain.spec` from the frontmatter
- If absent — extract `<topic>` from the plan filename (`YYYY-MM-DD-<topic>-plan.md`) and run:
  ```bash
  find docs/superpowers/intents/ -name "*<topic>*intent.md" 2>/dev/null | head -1
  find docs/superpowers/specs/   -name "*<topic>*design.md" 2>/dev/null | head -1
  ```
- If the plan is not found — report: «Не найден план. Укажи путь: `$check-chain result path/to/plan.md`» and stop
- If the intent or spec is not found — warn the user, continue with the available documents

#### Step 2. Load the documents

- **Intent doc:** read the Objective, Desired Outcomes, Constraints sections
- **Spec:** read the requirements sections and Success Criteria
- **Plan:** read all steps (both `[ ]` and `[x]`)

#### Step 3. Get the git diff

```bash
git diff HEAD
```

If `--since=<ref>` is passed: `git diff <ref>`.

If the diff is empty — report: «Нет незакоммиченных изменений. Запусти после внесения изменений или передай `--since=<ref>`.»

#### Step 4. Match plan steps against the diff

For each plan step:

1. Extract explicit file paths from the step text
2. Check for those files in `git diff HEAD`
3. For steps without explicit paths — semantic matching:
   - `DONE` — the changes in the diff clearly and fully match the step description
   - `PARTIAL` — the diff contains related changes but misses part of the described action (e.g. the step says "rename and rewrite X" but the diff only renames)
   - `MISSING` — there is no evidence of the step in the diff

Additionally — find `EXCESS`: files changed in the diff with no corresponding plan step.

#### Step 5. Check intent + spec coverage

- For each Desired Outcome from the intent doc: is it reflected in the diff?
- For each requirement / Success Criterion from the spec: is it reflected in the diff?
- Uncovered → a finding referencing the specific outcome/requirement

#### Step 6. Focused code review

Review every changed implementation, test, script, config, and documentation path in
the diff. This is not a broad repository review; limit findings to regressions and
risks introduced by the current result diff.

Closed checklist (do NOT extend):

- Correctness: logic errors, missing branches, wrong defaults, stale state, broken
  path handling, malformed data handling, or command injection risks introduced by
  the diff.
- Integration: changed APIs, hooks, skills, CLI flags, config keys, or file contracts
  still match their callers and documented contracts.
- Tests: new or changed behavior has focused tests, and verification commands recorded
  by the plan were run or have a documented blocker.
- Error handling: realistic failure modes introduced by the diff are handled or
  intentionally surfaced.
- Docs: behavior, architecture, user-facing workflow, or chain-contract changes are
  reflected in project docs and iwiki when the project has a bound iwiki domain.

Findings use the same severity table below. Each bug finding must name the changed path,
the concrete failure mode, the fix required, and the evidence needed to prove the fix.

#### Step 7. Fix bugs, verify, and update docs

Fix every confirmed bug before writing `result_check.verdict: OK`. Apply the smallest
source change that resolves the finding, rerun the relevant test or command, and record
the evidence in the final report. If a finding cannot be fixed in this pass, keep it open
and set `result_check.verdict: needs_work`.

Documentation evidence is required for behavior, architecture, or user-facing changes.
When iwiki is bound for the project, update the relevant wiki page through iwiki MCP
tools and rerun `wiki_lint`; otherwise update the repository docs that describe the
changed behavior. Missing required documentation is at least `WARNING`; stale or
contradictory documentation for the changed behavior is `CRITICAL`.

If implementation changed an approved decision, contract, scope boundary, command
semantics, report language rule, or verification strategy, propagate that decision
through the chain before result can pass:

1. Update the earliest affected markdown artifact (`intent`, `spec`, or `plan`) so it
   describes the implementation that actually shipped, including the reason for the
   decision change.
2. Rerun the affected upstream `check-chain <stage>` validations so their frontmatter
   hashes, findings, and TODO cells match the revised source.
3. Update repository docs and iwiki pages that present the old decision.
4. Rerun `check-chain result <plan>` after those updates, using the new diff evidence.

Do not write `result_check.verdict: OK` while intent, spec, plan, repository docs, or iwiki describe stale decisions. A stale cross-chain artifact is `CRITICAL`; an intentionally unchanged artifact requires a recorded rationale in the final report.

#### Step 8. Build the report

Emit the single final report through the shared **Step 5 — Result-only HTML report**
flow (`html-report`, `mode: chain`) with the full final payload. The reconciliation
content must include:

- Reconciliation table — one row per plan step → badge `DONE` / `PARTIAL` / `MISSING` /
  `EXCESS` (from reconciliation Step 4), with the matched diff paths.
- Coverage — each Desired Outcome and each requirement / Success Criterion (from
  reconciliation Step 5) → reflected in the diff, or a finding.
- Code review findings — every changed path reviewed in Step 6, with bug/risk status,
  severity, fix evidence, and verification evidence.
- Documentation evidence — repository docs and iwiki pages updated or intentionally
  unchanged, with `wiki_lint` result when iwiki is bound.
- Decision propagation — every implementation-time decision change mapped to the
  updated intent/spec/plan/docs/wiki artifact or an explicit unchanged rationale.
- Findings — every `[CRITICAL]` / `[WARNING]` / `[INFO]` from the severity table.
- Summary — the `verdict` badge (`OK` / `needs_work`).

Do not depend on existing intent / spec / plan report tabs. Build this report from the
current markdown artifacts and result evidence.

#### Step 9. Write the state into the plan frontmatter

After the report, write a machine-readable block into the **plan frontmatter** (do NOT
touch the plan body — it is the merge-gate pass signal for idd-gate).

1. Compute the plan body hash via the canonical algorithm (see above).
2. Determine the verdict: `OK` if there are no open CRITICAL findings, no MISSING plan
   steps, no confirmed unfixed bugs, no failed required verification command, and no
   stale required documentation; otherwise `needs_work`.
3. Create the `result_check:` block (or update the existing one) in the plan frontmatter:
   ```yaml
   result_check:
     verdict: OK | needs_work
     plan_hash: <plan body hash>
     last_run: <today>
     reviewed: true
     docs_checked: true
   ```
   If the plan has no frontmatter — add it at the start of the file
   (`---` … `---`) without changing the body.

#### Severity

| Severity | Condition |
|----------|-----------|
| `[CRITICAL]` | A plan step is entirely absent from the diff; a confirmed bug remains unfixed; a required verification command fails; docs contradict changed behavior; intent/spec/plan/wiki still describe a stale decision |
| `[WARNING]` | A step is partially done; excess changes have no link to the plan; required documentation evidence is missing; verification evidence is incomplete |
| `[INFO]` | A semantic discrepancy; an intent outcome is partially reflected; documentation is intentionally unchanged with rationale |

## Run modes

### Whole chain (sequential gate) — no stage argument

1. Resolve `<topic>` from the argument or the most-recently-modified artifact; locate
   every existing stage file for that topic.
2. Confirm the set once: «Проверю chain `<topic>`: intent=…, spec=…, plan=…. Верно?»
3. For each stage in `[intent, spec, plan, result]`:
   - artifact absent → record it (`Intent: n/a` etc.) and continue;
   - Step 0 quick-exit passes → `✓ cached`, continue;
   - else run the stage's full Step 1–6 (findings → verdicts → frontmatter → TODO cell; only `result` generates the final HTML report);
   - stage ends `needs_work` (open CRITICAL) → STOP: «chain остановлен на `<stage>`,
     почини и перезапусти». Do not run downstream stages.
4. `result` needs a `git diff`. Reached with an empty diff → emit INFO
   «result pending implementation», chain verdict «OK up to plan», leave the TODO
   `Result` cell `–` (not `done`). Non-empty diff → reconcile; on `OK` close the row.
5. Print the chain summary and, when `result` ran, the path to the final HTML report.

### Single stage — `$check-chain <stage> [path]`

Run Step 0–6 for exactly that one stage. `intent`, `spec`, and `plan` write validation
frontmatter plus the TODO cell and do not generate HTML. `result` additionally writes
the single final report for the completed task.

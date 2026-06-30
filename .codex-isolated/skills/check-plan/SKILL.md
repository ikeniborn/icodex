---
name: check-plan
description: >-
  Validate a plan doc (docs/superpowers/plans/*.md) against the IDD->SDD phase model before executing-plans or subagent-driven-development. Triggers on "/check-plan", "check the plan", "validate plan". Run from a clean-context subagent after a plan is written; reports verdicts to the main session. Skip for hotfixes.
---

Check the plan against the specification, using the phase model and the state in frontmatter.

Supported arguments:
- Path to the plan file — if not provided, it is resolved automatically
- Path to the specification — if not provided, it is resolved automatically

## Algorithm

### Canonical hashing algorithm (MANDATORY)

All hashes via a single pipeline (frontmatter must stay live, otherwise quick-exit won't match). Run bash through the Bash tool; never recompute "in your head".

- **Document body hash** (excludes frontmatter):
  ```bash
  awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2{print}' <FILE> | sha256sum | cut -c1-16
  ```
- **Section hash** — the section body from a `##`/`###` heading up to the next heading of the same or higher level (exclusive), piped through `sha256sum | cut -c1-16`.
- If frontmatter is absent (`fm` < 2) — hash the whole file: `sha256sum <FILE> | cut -c1-16`.

### Step 0. Quick exit by state

If the plan has frontmatter with a `review:` block, `plan_hash` matches the plan body AND `spec_hash` matches the spec body AND:
- `∀ phase: status == passed`
- `∀ finding: verdict ∈ {accepted, wontfix, fixed}`
- `count(severity == CRITICAL ∧ verdict == open) == 0`

→ output `OK (cached, hash match)` and finish. Otherwise — continue.

### Step 1. Determine scope

- If the task name/topic is known — find the plan in `docs/superpowers/plans/`, the spec in `docs/superpowers/specs/`
- If a path is passed in `$ARGUMENTS` — work with the specified plan
- Otherwise — the most recently modified file in `docs/superpowers/plans/`
- Spec: match by name, or the most recently modified file in `docs/superpowers/specs/`
- If not found — report: «Не найден план. Укажи путь: `/check-plan path/to/plan.md`»

Additionally — determine `intent_path`:
- Read the spec frontmatter: if the field `chain.intent` is present — use it
- Otherwise — extract `<topic>` from the plan filename (`YYYY-MM-DD-<topic>-plan.md`) and run:
  ```bash
  find docs/superpowers/intents/ -name "*<topic>*intent.md" 2>/dev/null | head -1
  ```
- If not found — `intent_path = null`

### Step 2. Confirm the files and initialize state

1. Report: «Буду проверять план: `<путь>` против спеки: `<путь>`. Верно?»
2. After confirmation:
   - Read the plan frontmatter. If there is no `review:` block — initialize:
     ```yaml
     review:
       plan_hash: <sha256 of the plan body>
       spec_hash: <sha256 of the spec body>
       last_run: <today>
       phases:
         structure:     { status: pending }
         coverage:      { status: pending }
         dependencies:  { status: pending }
         verifiability: { status: pending }
         consistency:   { status: pending }
       findings: []
     ```
   - Compute hashes of the plan sections (steps/tasks)
   - For existing findings whose `section_hash` changed — `verdict: open`
   - Update `plan_hash`, `spec_hash`, `last_run`
   - If there is no `chain:` block in the plan frontmatter — add:
     ```yaml
     chain:
       intent: <intent_path or null>
       spec:   <path to the spec>
     ```
   - If `chain:` already exists — update both fields to the resolved values

### Step 3. Phase execution

Phases run strictly sequentially. Phase N+1 starts only if phase N has no open CRITICAL.

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

### Finding-handling logic

1. Do NOT duplicate existing findings with the same `section + text + section_hash`
2. New ones → `id: F-NNN` (monotonic), `phase`, `severity`, `section`, `section_hash`, `fragment` (a quote of the offending text, ≤140 chars; `null` for structural findings), `text` (what the problem is), `fix` (proposed fix), `verdict: open`, `verdict_at: null`
3. Write the updated frontmatter to the file
4. Phase report + verdict request (CRITICAL mandatory: `accepted | wontfix | fixed`; WARNING desirable; INFO optional)
5. All CRITICAL of the phase closed → `phase.status = passed`, move on; otherwise → `in_progress`, stop and ask to fix

### Step 4. Final verdict

Apply the exit criterion. Output: `OK` or «требует доработки: <N> critical, <M> warning».

### Step 5. HTML report for the user

After the final verdict (including the quick-exit branch `OK (cached, hash match)`) invoke the `html-report` skill via the Skill tool (`skill: "html-report"`) and assemble one self-contained `.html` — a human-readable artifact for the user.

Report goal: show the plan steps' **dependencies** and **overlaps** with diagrams, not just list findings. Pass the skill three blocks (all mandatory):

1. **Резюме плана** — steps/tasks with their definitions of done (DoD); each step on its own table row.
2. **Схемы зависимостей и пересечений** (mandatory; an SVG node-edge graph for dependency edges, a matrix/table for overlaps):
   - **Граф зависимостей шагов** — an SVG node-edge graph: nodes are steps, edges are "the result of step M is used in step N" (direction M→N, M<N). Highlight cycles and order violations if the `dependencies` phase found any.
   - **Пересечения** — a matrix: steps touching the same artifact/file (overlap by artifacts), and/or requirement coverage — where one requirement is closed by several steps or one step closes several requirements (from the `coverage` phase).
3. **Результаты проверки** — for each of the 5 phases (structure / coverage / dependencies / verifiability / consistency) its `status`; a findings table (`id`, `severity`, `section`, `fragment`, `text`, `fix`, `verdict`); a summary (CRITICAL open / WARNING open); the final verdict; the chain (`intent → spec → plan`, if `intent_path` is known).

**Determine `<topic>` (the shared chain key — all 4 `check-*` commands must converge on one file).** Take the basename of the plan file without `.md`, then:
1. strip the date prefix `^[0-9]{4}-[0-9]{2}-[0-9]{2}-`;
2. strip the stage suffix — `-intent`, `-design`, or `-plan` — **if present** (on a plan `-plan` is optional: `…-foo.md` and `…-foo-plan.md` both yield one `<topic> = foo`);
3. the remainder is `<topic>`.
**Fallback:** if the basename is not recognized (no date/suffix matching the pattern) — `<topic>` = the basename without `.md` as-is. Do NOT include the date in `<topic>` (chain stages may have different dates).

Artifact parameters (pass them to the skill explicitly):
- **Mode:** `mode: chain`, `tab: plan`. The skill updates ONLY the `plan` tab; it preserves the other 3 tabs (Intent / Spec / Plan / Result) verbatim. If the file does not exist — it creates all 4 (unvisited ones with the placeholder «Этап ещё не проверен»).
- **Output path (explicit argument):** `docs/superpowers/reports/<topic>-results.html` — a single chain report, without a subdirectory and without a date prefix. This is a caller-supplied path (Full zone): the skill creates the `docs/superpowers/reports/` directory if absent; the first run creates the file with 4 tabs, a rerun merges only its own tab.
- **Data — inline:** the three blocks above are passed in the call itself. The skill does NOT read the sources itself and does NOT halt over an "unreadable source" — the data is already provided.
- Language — Russian: all report text (headings, descriptions, findings, summaries) is in Russian.

After writing, tell the user the path to the `.html`.

### Step 6. Register the task in docs/TODO.md

After the final verdict (including the quick-exit branch `OK (cached, hash match)`), upsert this chain's task into `docs/TODO.md` — see the **Task Log** section in CLAUDE.md for the table format. Key the row by the `<topic>` determined in Step 5:
- If `docs/TODO.md` is absent — create it with the header row first.
- If no row for `<topic>` exists yet — append one with `Status: in-progress`, `Opened: <today>`, marking `Intent`/`Spec` `n/a` if those stages were never checked.
- Mark `Plan: ✓` when the verdict is `OK` (`–` if it still needs work); keep `Status: in-progress`.

## Rules

**Prohibited:**
- Extending the phase checklists — an open list makes the check non-deterministic and breaks the hash-cache/quick-exit, so findings are not reproducible between runs
- Inventing requirements absent from the spec — the validator checks the plan against the spec, it does not generate requirements; an extra requirement = a false finding the author cannot close
- Editing the plan or spec body (the plan frontmatter is the exception) — the plan body is the merge-gate signal for idd-gate; editing it invalidates hashes and mixes the reviewer and author roles
- Writing «шаг подразумевает» without a reference to the text — a finding without a textual anchor is unprovable and the author cannot resolve it

## Report format

```
## Проверка плана [дата]

### Файлы
- План: <путь> (plan_hash: <short>, prev: <short>)
- Спека: <путь> (spec_hash: <short>, prev: <short>)

### Фаза 1: structure — passed | in_progress | skipped
- Новые findings: N
  - F-001 [CRITICAL] §X.Y — <text>
    - fragment: «<цитата>» (или «—» для структурных находок)
    - fix: <предложение>

### Фаза 2: coverage — ...
### Фаза 3: dependencies — ...
### Фаза 4: verifiability — ...
### Фаза 5: consistency — ...

### Сводка
- CRITICAL open: N
- WARNING open: M
- Вердикт: OK | требует доработки
```

Append to the end of the report:
```
---
Previous step: <spec_path>
```
If `intent_path` is known — also add the line:
```
Chain: <intent_path> → <spec_path> → <plan_path>
```

$ARGUMENTS

# AGENTS.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## Getting Started

**Load docs before exploring code — they encode decisions invisible in raw code.**

## Skill Availability

The `Available skills` catalog injected into the current turn is authoritative.
Never mark a listed skill unavailable because a filesystem scan, `find`, or `rg` did
not locate its `SKILL.md`; use the catalog source locator instead. Report a skill as
unavailable only when it is absent from that catalog or its listed source cannot be read.

At the start of any task in an unfamiliar area, or after a gap of more than 1 day:

1. **If the generated `Remote iwiki project scope` section is present**, it takes precedence: load `.iwiki.toml`, normalize only its domain names, and call `wiki_bind` with its complete `read`, `write`, and `primary` scope before `wiki_status`, searches, task-ledger, or any other wiki call. On a missing, invalid, or rejected scope, report a brief reason, make no mutating wiki call, and retain `completion-pending`; never infer a replacement scope. Otherwise, if the iwiki MCP server is connected, call `wiki_status`. If it reports a domain bound to this project (convention: domain name == project basename), `wiki_bind(read=[<domain>], write=<domain>)`, then `wiki_search "<task topic>"` → retrieve relevant sections; `wiki_lint` → check doc health. (No server / no project domain → skip; iwiki is not set up for this project.)
2. Map the `docs/` layout into context (complements iwiki's semantic search with a structural overview):
   ```bash
   tree -L 2 docs/ || find docs -maxdepth 2 | sort   # fallback when `tree` is absent
   ```
   Depth `-L 2` is chosen for the current project — its `docs/` nests at most 2 directory
   levels (e.g. `docs/superpowers/specs/`), so level 2 shows the full directory skeleton plus
   top-level files without flooding context with every leaf file. Raise the level for deeper trees.

Skip only when: familiar area, same session.

## Keep Docs Current (MANDATORY)

**After every change that alters functionality, architecture, or behavior — and only when the iwiki MCP server reports a domain bound to this project (`wiki_status`) — update the wiki via the MCP tools before responding to the user.**

- Pick the write tool by intent — all three auto-reindex the domain and auto-commit the base on success, so no manual `wiki_index` follows:
  - **New page** → `wiki_write_page(domain, slug, markdown, source=<changed-source>)`. Refuses to overwrite an existing page.
  - **Existing page** → `wiki_update_page(domain, slug, heading, new_body, source=<changed-source>)`. Rewrites one `##` section in place.
  - **Stale / removed source** → `wiki_delete_page(domain, slug)`. Drops the page and its vectors.
- Call `wiki_index(domain)` only to rebuild after out-of-band edits (markdown changed on disk without a tool) or a sync conflict — never as a routine step after a write.
- Run `wiki_lint` — no broken `[[refs]]`, no orphan or stale pages.
- Writes auto-commit the base locally; `wiki_sync` publishes those commits to the git remote (pull-rebase-push) — run it only when sharing the base across machines.
- Skip only for changes that touch no functionality, architecture, or behavior (typo, comment, formatting).

Always use the iwiki MCP tools (`wiki_status`, `wiki_bind`, `wiki_search`, `wiki_related`, `wiki_read_page`, `wiki_list_domains`, `wiki_list_pages`, `wiki_write_page`, `wiki_update_page`, `wiki_delete_page`, `wiki_index`, `wiki_create_domain`, `wiki_lint`, `wiki_sync`) — never the old plugin skills or the `iwiki_engine` CLI.

## Wiki Task Ledger

**Every direct, chain, and LoEn task, including read-only analysis, has one task-tagged iwiki page at `reference/tasks/<topic>`. It is the sole durable task index.**

- Bounded discovery may derive domain, topic, and route without a page. Before durable implementation or task-specific read-only analysis, parent creates or resolves the page through `task-ledger`.
- Parent agent is the sole writer: it serializes page creation, lifecycle changes, durable evidence, and `Changelog` events. Before delegation record `dispatch`; each subagent returns its ID, role, outcome, changed paths, checks, blockers, and proposed changelog text; parent records `return` before the next transition.
- Task pages use lifecycle `in-progress`, `blocked`, `completion-pending`, or `done`. `TODO` stays workflow-specific; chain gate outcomes and LoEn milestones are appended to `Changelog`, never stored as repository table cells.
- Keep task history in linked, bounded history segments. The task page `Changelog` is a compact manifest; it links to the first and active `reference/task-history/<topic>-<sequence>` segment. Each segment holds at most 20 events and links to its successor, so no event is lost before close while each write stays bounded.
- `reference/domain-changelog` records only domain-level changes (standards, releases, migrations, and cross-task decisions) with task-page links. It is not a task index and does not duplicate routine task events.
- `wiki_lint` may report `reference/tasks/*` as an orphan because task status is found by tag search. Treat this expected advisory as non-blocking unless another finding targets that task page.
- On iwiki MCP outage, execution may continue with redacted local spool evidence. Durable status is unavailable, spool state is non-authoritative, and the task must not report `done` until replay, successful page write, empty spool, and clean task-page lint.
- When iwiki is connected but the project domain is absent, execution may continue with redacted local spool evidence; normal page resolution cannot occur. Durable status is unavailable, lifecycle is `completion-pending`, and the task must not report `done` until the domain and task page are available, replay succeeds, the spool is empty, and task-page lint is clean.
- Do not add direct hooks that write wiki. MCP operations remain interactive parent actions. `task_spool.py` never calls MCP.

## Task Topic and Thread Title

**Every task must define one canonical `<topic>` before durable work starts for the
workflow artifacts the agent can control.**

- `<topic>` is a semantic, English, lowercase kebab-case slug: words joined by hyphens, e.g. `thread-title-task-naming-policy`.
- Use the same `<topic>` across applicable controlled surfaces:
  - iwiki task-page slug `reference/tasks/<topic>`;
  - Superpowers chain topic, for IDD->SDD work;
  - LoEn topic directory, for LoEn loop work;
  - git branch suffix: `dev-<topic>`.
- Thread title is best-effort only: if the platform exposes a title-control
  mechanism, set or request the same `<topic>` there. If no such mechanism is
  available, state the chosen `<topic>` in the conversation and do not block
  work merely because the UI title cannot be changed.
- Do not use vague topics such as `fix`, `update`, `work`, `misc`, `phase1`, or `changes`.
- Prefer topics that describe the task domain and intended outcome, not just the implementation step.
- If a branch already exists, derive `<topic>` from the branch suffix unless it is vague.
- If controlled artifacts such as task-page slug, chain/LoEn topic, and branch name
  disagree, stop and normalize them to one `<topic>` before continuing. Do not
  treat an inaccessible UI thread title as a blocking artifact.

## Workflow Route Selection

Classify the workflow before invoking `fix-intent`, `superpowers:brainstorming`, or
creating chain artifacts. Superpowers skills are selected tools; using an applicable
scoped skill does not by itself select `chain`. This rule overrides generic Superpowers
wording that treats every behavior change as requiring brainstorming.

Before selecting a workflow, perform bounded routing discovery from only the request and
project signals strictly necessary to derive domain, topic, and route. It creates no chain
artifacts and is not implementation; it must not perform task-specific analysis, reproduction,
or test execution before the task page is resolved. Resolve the wiki task page before any
task-specific analysis or durable work. The interactive model-switch gate applies before
implementation or durable artifact creation, not before routing discovery.

Absence of evidence is not evidence for chain. Recommend **direct** when discovery shows
the request or diagnosis is bounded, no chain trigger is evidenced, and a verification
or next discovery step is known. Unknown defect cause alone starts scoped debugging, not
chain. Typical examples: known-cause local fixes, typos, formatting, focused tests for
existing behavior, mechanical configuration or documentation edits, and read-only review.

Recommend **chain** only when the user explicitly requests it or discovery shows that a
durable approved intent is needed for a new capability or module, a public contract,
schema or migration, security/concurrency/transaction/data-invariant behavior, or coupled
subsystem work. Chain does not imply spec and plan: that decision occurs only after
`$check-chain intent` returns `OK`.

After intent validation, perform intent-scoped repository analysis and recommend
`execute` by default when implementation and verification are bounded. It implements
directly from the approved intent and marks Spec and Plan n/a. Recommend `full` only when
both an enumerated design-risk category and a named unresolved design decision are present:
a new module boundary, public compatibility strategy, architecture choice,
schema/migration/security/concurrency/transaction/data-integrity invariant, or coupled
subsystem design. Merely touching one of these areas is insufficient. General uncertainty,
task size, or the word "non-trivial" are not triggers.

Recommend **loen** only for tasks that operate a durable LoEn workspace through its own
loop lifecycle.

At task start, state the recommendation and its evidence. Do not invoke `fix-intent` or
start chain until the user accepts that recommendation; an explicit chain request counts
as acceptance. After intent validation, report `execute` or `full` with evidence and wait
before starting `full`. Prefer `execute` when no full trigger is evidenced.

Direct work creates no formal intent, spec, plan, or `check-chain` artifact, but always resolves a wiki task page.
The exception is an explicit direct topic: `@topic <kebab-case-topic>` is a user approval
to create `docs/profiles/<topic>.yaml` with the initial `engineering` profile and bind it
to the current local session. The next user prompt is the continuation confirmation;
its wording is not a protocol field. This does not alter the chain/App Server profile path.
`@topic` is submitted as plain prompt text, not selected from Codex autocomplete: when
the `@` menu opens, press `Esc`, finish `@topic <kebab-case-topic>`, then press Enter.
Direct work must not invoke `fix-intent`, `superpowers:brainstorming`,
`superpowers:writing-plans`, `superpowers:subagent-driven-development`, or
`superpowers:executing-plans`. Scoped systematic debugging, TDD, and verification remain
allowed. `superpowers:finishing-a-development-branch` remains available after verified
direct or chain work. If direct scope crosses a chain trigger, stop and recommend chain.

```text
Workflow recommendation: direct | chain | loen
Continuation after intent: execute | full | n/a
Evidence: <bounded facts or qualifying trigger>
Intent required: yes | no
Confirmation required: yes | no
```

## Chain Order

After the user accepts chain, keep selected transitions gated by `check-chain`:

**LoEn carve-out:** tasks that start, continue, audit, repair, research, review, or
govern durable LoEn workspaces through `loen:loop-*` skills use the LoEn lifecycle
only. Do not run `fix-intent`, `superpowers:brainstorming`,
`superpowers:writing-plans`, `superpowers:subagent-driven-development`,
`superpowers:executing-plans`, `superpowers:finishing-a-development-branch`, or
`$check-chain` merely because a LoEn loop is active. LoEn loop artifacts live in
`docs/loen/<topic>/`; parent mirrors material lifecycle evidence to the shared task
page `TODO` and `Changelog` unless the user explicitly chooses the IDD->SDD chain for a
separate non-LoEn change.

1. `fix-intent` creates or updates `docs/superpowers/intents/*-intent.md`.
2. `$check-chain intent` validates the intent.
3. Record `workflow.route: chain` and `workflow.continuation: execute|full` in intent
   frontmatter after the user accepts the continuation recommendation.
4. For `execute`, skip brainstorming and writing-plans, implement from the approved
   intent with scoped implementation skills, then run `$check-chain result <intent>`.
5. For `full`, run `superpowers:brainstorming` -> `$check-chain spec` ->
   `superpowers:writing-plans` -> `$check-chain plan` -> plan execution.
6. Run `$check-chain result <plan>` for `full`; result reconciliation always precedes
   branch finishing.

The Codex hook `.codex-isolated/hooks/chain-gate.py` enforces transitions when it
can see them. It must gate both explicit `Skill` events and Codex skill-loading
signals such as reading `skills/<name>/SKILL.md` through `Read` or `Bash`. It is a
transition gate only: validation state still comes from frontmatter written by the
`check-chain` skill.

## Model and Reasoning Recommendations

Recommend only; never edit TOML, select profiles, start sessions, or claim a switch.
The user switches with `/model` and verifies with `/status`.

### Execution Routes

Rules refer only to stable semantic routes, never model branding:

| Route | Capability target | Effort target |
|-------|-------------------|---------------|
| `mechanical` | Lowest-cost capable coding model | baseline |
| `engineering` | Balanced general coding model | baseline |
| `synthesis` | Strongest reasoning model for design synthesis | baseline |
| `deep` | Strongest single-agent reasoning model | deep |
| `escalation` | Strongest model after evidenced failure | maximum |
| `parallel-audit` | Strongest agentic model for independent audits | parallel |

### Current Catalog Mapping

Exact model IDs live only here. Update this table when the Codex catalog changes; do not
rewrite classification or workflow rules.

| Route | Current model | Current effort |
|-------|---------------|----------------|
| `mechanical` | `gpt-5.6-luna` | `medium` |
| `engineering` | `gpt-5.6-terra` | `medium` |
| `synthesis` | `gpt-5.6-sol` | `medium` |
| `deep` | `gpt-5.6-sol` | `high` |
| `escalation` | `gpt-5.6-sol` | `max` |
| `parallel-audit` | `gpt-5.6-sol` | `ultra` |

Resolve the semantic route through the current catalog before recommending a switch. If
the mapped entry is absent from `/model`, keep the semantic route, describe its capability
and effort targets, mark resolution `unresolved`, and ask the user to select the current
equivalent. Never substitute a model by name from memory.

### Checkpoints

Reassess at direct task start, after chain or LoEn checks/reviews, and before next work:

| Boundary | Baseline |
|----------|----------|
| Direct task start -> execution | Classify task |
| Direct check/review -> next work | Reclassify if evidence changed |
| Start -> chain intent or coordination | `engineering` |
| Intent OK -> continuation decision | `engineering` |
| Intent execute -> implementation | Classify task |
| Intent full -> spec | `synthesis` |
| Spec OK -> plan | `synthesis` |
| Plan OK -> implementation | Classify each task |
| Implementation task complete -> task review | `engineering` |
| Task review complete -> next task | Classify next task |
| Execution -> bounded result check | `engineering` |
| Execution -> cross-system or critical result check | `deep` |
| Result OK -> routine follow-up | `engineering` |

At LoEn loop start and after each check or review, classify the next work with the same
execution routes. LoEn workflow selection never implies a stronger model.

For `needs_work`, remain in the stage, change strategy, rerun, and reassess. The verdict
alone never requires escalation.

Workflow and execution routes are independent: direct does not imply `mechanical`, and
chain does not imply `deep`. Repeat classification after failed checks, scope changes,
or newly discovered invariants.

### Task Transition Gate

A task-scoped recommendation expires when that task reaches review or completion, or
when execution moves to another plan task. Never assume that the active session profile
or the recommendation for the previous task is suitable for the next task.

**Orchestrated branch:** the runner validates shared registry and direct project manifest,
then the hook accepts only correlated local handoff/session evidence. Matching
routed evidence replaces manual `/status` confirmation for that protected task only. The
hook validates evidence; it never selects or changes model.

**Interactive branch:** retain route classification, `/model` switch request,
downgrade/escalation handling, and critical-migration rules. A platform-reported successful
model switch is sufficient confirmation for that switch. Request `/status` only when no
successful platform switch event is available.

**Delegated-agent branch:** when delegation is explicitly authorized, resolve the
subtask's semantic execution route independently before spawning. Pass the exact mapped
`model` and `reasoning_effort` to `spawn_agent` with `fork_turns` set to `none` or a
positive value. Do not request `/status` or user switch confirmation for the child agent;
the parent records the route, evidence, and resolved mapping in its delegation request.
Do not inherit the parent route automatically. Reclassify before every follow-up task
whose scope or evidence changes.

For interactive work, before a task that requires a model switch:

1. Identify the next work and classify its execution route independently from current
   evidence.
2. Resolve the recommended exact model and effort through the current catalog mapping.
3. Establish the active exact model and effort from either a successful platform switch
   event after the requested switch or the latest `/status`. If neither is available,
   request `/status` before asking the user to switch.
4. Compare the active and recommended mappings. If they differ, report
   `Switch required: yes`, ask the user to switch with `/model`, and stop before the task.
5. Resume after a successful platform switch event or after the user confirms that
   `/status` shows the recommended mapping; the user may instead explicitly decline the
   switch under the downgrade or escalation rules below.

For `direct` work on the `mechanical` or `engineering` route, report the recommended
mapping but continue when the active mapping is unknown. Do not request `/status` unless
the user asks to change models or evidence reclassifies the task to `synthesis`, `deep`,
or `escalation`.

Apply the same gate when a scope change or newly discovered invariant reclassifies work
inside an active task. A matching active mapping uses `Decision: keep` and does not
require another switch.

### Classification

Choose the lowest sufficient route:

1. **`mechanical`** only if work is fully defined, single-component, has known cause and
   verification, and changes no contract, schema, migration, concurrency, security, or
   data invariant.
2. **`synthesis`** for specification or planning synthesis without a deep trigger.
3. **`deep`** when evidence shows an unknown reproduced-defect cause, artifact/code
   contradiction, public compatibility change, transactional/concurrent/distributed
   invariants, migration/security/data risk, two or more coupled subsystem boundaries,
   or result reconciliation across coupled invariants.
4. **`engineering`** otherwise.

Never inherit a higher route. File count, task length, one failure, or a stage name are
not triggers. Gather ambiguous evidence at the lower route.

### Exceptional Routes

Use **`escalation`** only after two different `deep` strategies fail, reviewers
contradict the same invariant, a required test remains unexplained after strategy
change, an enumerated critical invariant set cannot be decomposed safely, or critical
migration reconciliation has credible data-loss risk.

Every critical migration requires a separate final integration review at `deep` or
higher, regardless of its implementation route.

Use **`parallel-audit`** only as a separate run with at least two independent read-only
audit directions, no shared writes, and one consolidation step. Never use it inside
active subagent orchestration.

Implementers never revise accepted intent, spec, or plan. Return drift to the earliest
gate. Never retry without changing strategy.

### Switch Handling

Use `keep`, `downgrade`, `escalate`, or `separate-run` (`parallel-audit`). If the active
mapping is unknown, ask the user to check `/status`, mark switch confirmation `pending`,
and stop before the next task; never guess or inherit the previous task's recommendation.

Wait when switching is required. A successful platform switch event confirms the resulting
mapping; request `/status` only when that event is unavailable. A declined downgrade may
continue with the extra cost recorded and switch confirmation marked `declined`. A declined
escalation stops the next work until explicit risk acceptance, also recorded as `declined`.
Critical-migration final review cannot be waived.

```text
Workflow: direct | chain | loen
Continuation: execute | full | n/a
Checkpoint: <check and verdict>
Next work: <stage or task>
Execution route: <semantic route>
Current mapping: <exact model / effort | unknown>
Recommended mapping: <exact model / effort | unresolved>
Decision: keep | downgrade | escalate | separate-run
Evidence: <artifact, finding, failure, invariant, or risk>
Higher route rejected because: <reason or n/a for parallel-audit>
Switch required: yes | no
Switch confirmation: n/a | pending | confirmed | declined
```

## Project Status Reports

**When the user asks for project status, progress, or "what's the state of X", read task-tagged iwiki pages only.**

- Bind the project domain, search task-tagged pages, and read relevant pages. Lead with lifecycle counts or requested topic; report lifecycle, `TODO`, pending delivery, evidence, and task-page lint findings.
- Report `completion-pending` explicitly. List every `in-progress` task opened more than 14 days ago.
- If iwiki is unavailable, say durable status is unavailable. Local spool evidence is non-authoritative; do not infer status from repository files or silently reconcile it.

## Language Rules

- **Conversations and questions**: Russian — to match user expectations.
- **Documentation and code comments**: English — to keep docs universally readable.

## Copy-Friendly Command Output

**Bash/Python commands the user runs must be copy-pasteable straight from the terminal.**

- Put every runnable command in a fenced code block (```` ```bash ```` / ```` ```python ````) — never inline in prose.
- No leading indentation inside the fence. The first column is column 1, so copying grabs no stray spaces.
- One command per line. No trailing whitespace.
- No shell prompt prefixes (`$`, `>`, `#`) — they get copied too and break paste.
- Don't wrap long commands with manual line breaks; let the terminal soft-wrap, or use explicit `\` continuations.

## Think Before Coding

**Don't assume. Surface tradeoffs. Ask when unclear.**

Before implementing:
- State assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so.
- If something is unclear, stop. Name what's confusing. Ask.

## Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No unrequested features — scope creep compounds review cost.
- No abstractions for single-use code — increases cognitive load without reuse benefit.
- No "flexibility" not requested — premature generalization adds maintenance burden.
- No error handling for impossible scenarios — dead code misleads readers.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer call this overcomplicated?" If yes, simplify.

## Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't improve adjacent code or formatting — unrelated changes bloat diffs and risk regressions.
- Don't refactor things that aren't broken — stability is a feature.
- Match existing style — consistency beats personal preference.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:
- Remove imports/variables/functions YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

Test: every changed line must trace directly to the user's request.

## Branch Workflow

**Don't commit to main. Develop on a branch. Merge back only via PR.**

- Never commit work directly to the main branch (`master` / `main` / `prod`), and never merge or push to it directly — close every branch through a PR into main.
- **Branch naming is mandatory: `dev-<name>`, created from the selected up-to-date base branch (main by default).** Words inside `<name>` are joined with `-` (e.g. `dev-route-policy`). No exceptions.
- **If the project has long-lived branches beyond `master` / `main` / `prod`** (e.g. `dev`, `develop`, `staging`, `release/*`), always ask first — which branch to base the new `dev-*` off, and which branch to open the PR against. Don't assume.
- **When creating a `dev-*` branch, check existing local `dev-*` branches first.**
  - **No existing `dev-*` branch** → do not offer or create a worktree; create the branch in the main worktree.
  - **Another `dev-*` branch already exists** → ask first: create a worktree for the new branch now?
    - **Yes** → create the branch in a sibling worktree at `../<project>-<branch>` and do all the work there.
    - **No** → create the branch in place and keep working in the main worktree.
- For parallel work on several tasks, create one git worktree per branch.
- **Worktree naming is mandatory: `../<project>-<branch>`** — a sibling directory named with the project basename and the full branch name. Example: project `icodex`, branch `dev-route-policy` → sibling worktree `../icodex-dev-route-policy`.

### Git Worktrees and VS Code

When a `dev-*` task uses a worktree, create it atomically from the selected base branch in the mandatory sibling path. Open that folder directly in VS Code if needed; do not create linked worktrees inside the repository root.

```bash
base="<base-branch>"
branch="dev-<topic>"
root="$(git rev-parse --show-toplevel)"
project="$(basename "$root")"
parent="$(dirname "$root")"
git fetch origin "$base"
git worktree add -b "$branch" "$parent/$project-$branch" "origin/$base"
code --new-window "$parent/$project-$branch"
```

If the branch already exists, attach it at the same path. Verify with `git worktree list --porcelain`. After creating its PR, remove the worktree through Git and run `git worktree prune`.

Use **@skill:git-workflow** for commit messages and PR creation.

## Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals (verify by running real code or tests):
- "Add validation" → "Run the code with invalid inputs, confirm it rejects them"
- "Fix the bug" → "Reproduce it by running the affected path, confirm the fix removes it"
- "Refactor X" → "Run X before and after, confirm identical observable behavior"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

## Mode: Piecemeal Growth

Piecemeal growth designs from forces that exist now: executable requirements, current workflows, and failures that have actually occurred. Like a desire path, the shape follows observed traffic; it is not paved in anticipation of journeys nobody has taken.

In this mode, keep the implementation as narrow as the present contract. Do not add configurability, concurrency, fallback paths, validation, or abstractions for possible future uses. Make assumptions explicit and let violations fail loudly, so new pressure is visible instead of being absorbed by speculative machinery.

When a new requirement or repeated failure appears, repair the design locally. Generalize only once reality has shown what the generalization must support.

This is not an argument against integrity at real boundaries: protect durable data, external callers, security, and failures with demonstrated likelihood or cost. It is an argument against paying complexity for imagined ones.

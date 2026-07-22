# AGENTS.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## Getting Started

**Load docs before exploring code — they encode decisions invisible in raw code.**

At the start of any task in an unfamiliar area, or after a gap of more than 1 day:

1. **If the iwiki MCP server is connected**, call `wiki_status`. If it reports a domain bound to this project (convention: domain name == project basename), `wiki_bind(read=[<domain>], write=<domain>)`, then `wiki_search "<task topic>"` → retrieve relevant sections; `wiki_lint` → check doc health. (No server / no project domain → skip; iwiki is not set up for this project.)
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

## Task Log (docs/TODO.md)

**Every elaboration task that runs through the IDD→SDD chain (intent → spec → plan → result) is tracked as one row in `docs/TODO.md`: opened when work starts, closed when it finishes.**

Purpose: a single human-readable index of what is being worked on and what is done — **one row per chain `<topic>`** (the shared chain key the `check-chain` skill converges on; in Codex, invoke it as `$check-chain`), never per finding or per step.

- **One file, one table.** `docs/TODO.md` holds a single Markdown table, one row per `<topic>`.
- **Columns:** `Topic | Status | Intent | Spec | Plan | Result | Opened | Closed | Notes`.
  - `Status`: `in-progress` while any stage is still open; `done` once `$check-chain result` returns `OK`.
  - Stage cells (`Intent` / `Spec` / `Plan`): `✓` once that stage's `$check-chain <stage>` passes (verdict `OK`, including a cached quick-exit); `–` if not reached yet; `n/a` if the stage does not exist for this topic (e.g. no intent).
  - `Result`: `OK` / `needs_work` / `–`.
  - `Opened` / `Closed`: ISO date (`YYYY-MM-DD`). `Closed` stays empty until the task is `done`.
  - `Notes`: optional one-line context.
- **Upsert, never duplicate.** Keyed by `<topic>`: update the matching row in place if it exists, otherwise append a new one.
- **Lifecycle (driven by the `check-chain` skill via `$check-chain` in Codex):**
  - The first `$check-chain <stage>` run for a topic **opens** the row (`Opened: <today>`, `Status: in-progress`). Normally that is `$check-chain intent`; if there is no intent, `$check-chain spec` opens it and marks `Intent: n/a`.
  - `$check-chain spec` / `$check-chain plan` mark their own stage cell `✓` and keep `Status: in-progress`.
  - `$check-chain result` **closes** the row on verdict `OK` (`Result: OK`, `Status: done`, `Closed: <today>`); on `needs_work` it sets `Result: needs_work` and leaves the row open.
- **Create on demand.** If `docs/TODO.md` is absent, the first `$check-chain <stage>` run creates it with the header row, then appends.
- **Manual rows are allowed.** A task may be added by hand before any `$check-chain <stage>` run; the skill then updates the matching `<topic>` row instead of duplicating it.

## Task Topic and Thread Title

**Every task must define one canonical `<topic>` before work starts for the
workflow artifacts the agent can control.**

- `<topic>` is a semantic, English, lowercase kebab-case slug: words joined by hyphens, e.g. `thread-title-task-naming-policy`.
- Use the same `<topic>` across applicable controlled surfaces:
  - `docs/TODO.md` `Topic`;
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
- If controlled artifacts such as TODO topic, chain/LoEn topic, and branch name
  disagree, stop and normalize them to one `<topic>` before continuing. Do not
  treat an inaccessible UI thread title as a blocking artifact.

## Superpowers Chain Order

**For every non-trivial behavior, architecture, CLI/API, or feature change, keep the
Superpowers workflow gated by `check-chain`, except LoEn loop workspaces:**

**LoEn carve-out:** tasks that start, continue, audit, repair, research, review, or
govern durable LoEn workspaces through `loen:loop-*` skills use the LoEn lifecycle
only. Do not run `fix-intent`, `superpowers:brainstorming`,
`superpowers:writing-plans`, `superpowers:subagent-driven-development`,
`superpowers:executing-plans`, `superpowers:finishing-a-development-branch`, or
`$check-chain` merely because a LoEn loop is active. LoEn task state lives in
`docs/loen/<topic>/` and the global `docs/TODO.md` row uses LoEn stage cells
(`Intent: n/a`, `Spec: n/a`, `Plan: n/a`) unless the user explicitly chooses the
IDD->SDD chain for a separate non-LoEn change.

1. `fix-intent` creates or updates `docs/superpowers/intents/*-intent.md`.
2. `$check-chain intent` validates the intent before any brainstorming starts.
3. `superpowers:brainstorming` creates or updates `docs/superpowers/specs/*-design.md`.
4. `$check-chain spec` validates the spec before any implementation plan starts.
5. `superpowers:writing-plans` creates or updates `docs/superpowers/plans/*.md`.
6. `$check-chain plan` validates the plan before any implementation starts.
7. `superpowers:subagent-driven-development` is preferred for execution; use
   `superpowers:executing-plans` only when subagents are unavailable or the task is
   small enough for inline execution.
8. `$check-chain result` reconciles the implementation diff against the plan, spec,
   and intent before finishing the branch.

The Codex hook `.codex-isolated/hooks/chain-gate.py` enforces transitions when it
can see them. It must gate both explicit `Skill` events and Codex skill-loading
signals such as reading `skills/<name>/SKILL.md` through `Read` or `Bash`. It is a
transition gate only: validation state still comes from frontmatter written by the
`check-chain` skill.

## Project Status Reports

**When the user asks for project status, progress, or "what's the state of X", build the answer from two sources together — never one alone: `docs/TODO.md` (what is being worked on) and the project's iwiki domain (what is documented as true).**

- **Read both first.** Read `docs/TODO.md` for the task index; if the iwiki MCP server reports a domain bound to this project (`wiki_status`), `wiki_bind` then `wiki_search`/`wiki_read_page` for the topic. If iwiki is not set up, report from `docs/TODO.md` alone and say so.
- **Report shape:** lead with overall state (counts of `in-progress` vs `done` rows, or the specific topic's row), then per-topic detail (stage cells `Intent`/`Spec`/`Plan`/`Result`), then a **Discrepancies** section.
- **Reconcile the two sources and surface every mismatch.** Examples of discrepancies to flag:
  - Topic is `done` in `docs/TODO.md` but the wiki has no page (or a stale page) covering it.
  - Wiki documents a feature/behavior that has no matching `<topic>` row in `docs/TODO.md`.
  - `docs/TODO.md` says a stage passed (`✓` / `Result: OK`) but the wiki still describes the old behavior, or `wiki_lint` flags the topic's page as stale/orphan.
  - Status, dates, or scope disagree between the two.
- **No silent reconciliation.** Report discrepancies; do not fix `docs/TODO.md` or the wiki as a side effect of a status request. If none exist, state "TODO and wiki agree" explicitly.

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
- **Branch naming is mandatory: `dev-<name>`, created from the up-to-date main branch.** Words inside `<name>` are joined with `-` (e.g. `dev-fix-phase1`). No exceptions.
- **If the project has long-lived branches beyond `master` / `main` / `prod`** (e.g. `dev`, `develop`, `staging`, `release/*`), always ask first — which branch to base the new `dev-*` off, and which branch to open the PR against. Don't assume.
- **When creating a `dev-*` branch, check existing local `dev-*` branches first.**
  - **No existing `dev-*` branch** → do not offer or create a worktree; create the branch in the main worktree.
  - **Another `dev-*` branch already exists** → ask first: create a worktree for the new branch now?
    - **Yes** → create the branch in a sibling worktree at `../<project>-<branch>` and do all the work there.
    - **No** → create the branch in place and keep working in the main worktree.
- For parallel work on several tasks, create one git worktree per branch.
- **Worktree naming is mandatory: `../<project>-<branch>`** — a sibling directory named with the project basename and the full branch name. Example: project `icodex`, branch `dev-fix-phase1` → sibling worktree `../icodex-dev-fix-phase1`.

### Git Worktrees and VS Code

When a `dev-*` task must run in a worktree, create it so both Git and VS Code can discover it reliably:

- Prefer VS Code's native worktree flow when work starts from VS Code: Source Control → Source Control Repositories → repository menu (`...`) → Worktrees → Create Worktree. Worktrees created this way appear in VS Code immediately.
- For CLI-created worktrees, place them next to the main checkout as sibling folders named `../<project>-<branch>`. Do not place linked worktrees inside the repository root unless the project already has an ignored worktree directory and the user explicitly wants that layout. Project-prefixed sibling folders avoid nested-repository status noise, avoid name collisions across repositories, and are easy to open as separate VS Code windows.
- Create the branch and worktree atomically from the up-to-date base branch; do not first check out the new `dev-*` branch in the main checkout and then try to add a worktree for the same branch.
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
- If the `dev-*` branch already exists and is not checked out in any worktree, attach it to the canonical path:
  ```bash
  branch="dev-<topic>"
  root="$(git rev-parse --show-toplevel)"
  project="$(basename "$root")"
  parent="$(dirname "$root")"
  git worktree add "$parent/$project-$branch" "$branch"
  code --new-window "$parent/$project-$branch"
  ```
- If worktrees were created outside VS Code and do not appear there, enable the repository explorer and worktree detection in VS Code settings:
  ```json
  {
    "scm.repositories.explorer": true,
    "git.detectWorktrees": true,
    "git.detectWorktreesLimit": 50
  }
  ```
- Verify both layers before working: `git worktree list --porcelain` shows the path and branch; VS Code Source Control Repositories shows the worktree under the repository's Worktrees node. If VS Code still misses it, run `Git: Open Worktree in New Window` or open the `<project>-dev-*` folder directly.
- To inspect multiple worktrees together, use a multi-root workspace and add each `<project>-dev-*` folder as a separate root; Source Control then shows each root as its own provider.
- To copy ignored local-only files into VS Code-created worktrees, configure `git.worktreeIncludeFiles` with explicit glob patterns. Keep secrets out of tracked files.
- Remove worktrees only through Git, never by deleting the folder directly:
  ```bash
  branch="dev-<topic>"
  root="$(git rev-parse --show-toplevel)"
  project="$(basename "$root")"
  parent="$(dirname "$root")"
  git worktree remove "$parent/$project-$branch"
  git worktree prune
  ```

- After the PR is created, remove the branch's worktree — don't leave stale worktrees around.

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

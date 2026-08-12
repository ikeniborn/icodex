---
chain:
  intent: docs/superpowers/intents/2026-08-12-wiki-task-tracking-intent.md
review:
  spec_hash: b39858880d9ab1b8
  last_run: 2026-08-12
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
  findings: []
---

# Wiki Task Tracking Design

**Date:** 2026-08-12
**Status:** draft
**Intent:** `docs/superpowers/intents/2026-08-12-wiki-task-tracking-intent.md`

## Acceptance (from intent)

### Desired Outcomes

- A new agent finds current project and task context through iwiki without relying on
  `docs/TODO.md`.
- The parent agent and its subagents observe one authoritative task status.
- The wiki retains an ordered changelog of material task lifecycle transitions.
- Each task has a canonical lowercase-kebab-case topic and a matching iwiki task page.

### Done When

- The task page records the final state and lifecycle history, `wiki_lint` reports no
  new violations, and lifecycle tests pass.

## Scope

This design moves task tracking for direct, chain, and LoEn workflows from
`docs/TODO.md` to per-topic pages in the bound project iwiki domain. It covers ordinary
direct tasks, including small fixes and read-only analysis, whether or not the user used
`@topic`. It also defines parent/subagent ownership, offline delivery, status reporting,
and migration of the legacy task table.

This design changes only `icodex`. It does not change `iwiki-mcp`, add an MCP method,
extend the iwiki OKF vocabulary, run `wiki_sync`, or publish outside the locally bound
wiki store.

## Requirements

### R1. Canonical Task Identity

Every task MUST receive one English lowercase-kebab-case `<topic>` before work starts.
The topic MUST match the task-page suffix and every applicable controlled artifact,
including `dev-<topic>`, chain artifacts, profile manifest, and LoEn directory.

Bounded routing discovery MAY read the request, project binding, and minimum repository
context needed to derive the canonical topic and workflow. It MUST NOT perform the
task-specific analysis or implementation that the task page exists to track.

Acceptance:

- A direct, chain, or LoEn task with a valid topic resolves exactly one task-page slug.
- A conflicting controlled topic blocks work until the parent normalizes it.

### R2. Per-Topic Wiki Page

The authoritative task record MUST be one page at `reference/tasks/<topic>` in the
project's bound iwiki domain. Because the current server vocabulary has no task type or
in-progress status, page frontmatter MUST use supported `type: reference` and
`status: stable`; live task state belongs in the Markdown body. The page MUST carry the
`task` tag and contain these second-level sections exactly once:

- `Current State`
- `TODO`
- `Subtasks`
- `Evidence`
- `Changelog`

Each required section MUST begin with one descriptive lead paragraph of at most 250
characters, followed by a blank line before lists or tables. Headings deeper than `##`
MUST NOT be used. This preserves an unbounded changelog while satisfying the current
iwiki section-formation contract.

`Current State` MUST record topic, workflow route, lifecycle status, opened date,
closed date when done, parent identity, and pending-delivery state. `TODO` MUST express
workflow-specific stages without imposing chain stages on direct or LoEn work.

Acceptance:

- The page passes structural validation and `wiki_lint` without a new OKF finding.
- A changelog longer than 250 characters remains lint-clean because only its lead
  paragraph is length-limited.
- `wiki_search` using task tag plus exact topic returns the authoritative page.
- No central mutable TODO page is required to derive task status.

### R3. Lifecycle and Changelog

Lifecycle status MUST be one of `in-progress`, `blocked`, `completion-pending`, or
`done`. The changelog MUST append material events in order: open, route selection,
subagent dispatch and return, scope or decision change, blocker, verification result,
and close. It MUST NOT log every tool call or intermediate read.

Each event MUST carry an evidence hash over canonical redacted evidence and an
idempotency key derived only from topic, event kind, and that evidence hash. Timestamp,
actor, and summary MUST NOT change the key. Replay MUST skip a key already present on
the page. Existing entries
MUST NOT be rewritten except to repair a confirmed malformed or secret-bearing entry
under proposal-first authority.

Acceptance:

- Replaying the same event does not create a second changelog entry.
- Material lifecycle transitions appear in chronological order.
- A task cannot enter `done` before final evidence is recorded.

### R4. Parent and Subagent Ownership

Only the parent agent MUST mutate task state or changelog sections. A subagent MUST read
the task context supplied by the parent and return structured evidence containing its
subtask ID, role, outcome, changed paths, checks, blockers, and proposed changelog text.
The parent MUST record dispatch before delegation and record return before the next
lifecycle transition. All subtasks share the parent topic page; subagents MUST NOT
create their own task pages for delegated work.

Acceptance:

- Delegation instructions explicitly prohibit subagent wiki writes.
- Concurrent subagent results are serialized by the parent without lost entries.
- Each dispatched subtask has one terminal return status and evidence record.

### R5. Offline Delivery Spool

When iwiki is unavailable, work MAY continue, but the parent MUST write pending events
atomically under
`$CODEX_HOME/state/iwiki-task-spool/<project>/<topic>.json`. The spool is a delivery
queue, not an authoritative task state. It MUST contain only redacted structured events,
their ordering, and idempotency keys. It MUST NOT contain credentials, environment
values, raw command output, or a duplicate durable project task database.

At the next available parent checkpoint, the parent MUST read or create the task page,
load its durable idempotency keys, then replay pending events in order. The parent MUST
confirm each event on the wiki page before removing it from the spool. A task with
pending events MUST use `completion-pending`; `done` is fail-closed until replay,
verification evidence, and `wiki_lint` succeed.

Acceptance:

- Interrupted writes leave either the old valid spool or the new valid spool, never a
  partial JSON file.
- Ordered replay suppresses duplicate idempotency keys.
- An unavailable server does not block execution, but pending delivery blocks `done`.

### R6. Workflow Integration

`check-chain` MUST replace TODO-row upserts and TODO-cell references with task-page
section updates. Intent, spec, plan, and result verdicts MUST update the matching
workflow TODO state and append a changelog event. Cached checks MUST avoid duplicate
events.

LoEn skills, runtime artifacts, and enforcement hooks MUST stop creating or updating
`docs/TODO.md`. LoEn keeps its authoritative loop artifacts in `docs/loen/<topic>/` and
uses the shared task-page only for cross-workflow task status, lifecycle history, and
evidence links.

Direct work MUST create or resolve its task page after bounded routing discovery and
before durable implementation or task-specific read-only analysis. `@topic` remains an
optional explicit topic/profile command, not a precondition for direct tracking.

Acceptance:

- Focused tests cover direct, chain, and LoEn use of the same task-page contract.
- No runtime, skill, hook, or instruction creates a new `docs/TODO.md` task row.
- Existing chain hashes, LoEn loop state, and direct profile behavior remain intact.

### R7. Status Reporting

Project status reports MUST read the bound iwiki domain as the sole durable task index.
They MUST search task-tagged pages, read the relevant page bodies, report lifecycle and
workflow TODO state, and list in-progress tasks older than 14 days. They MUST report
pending-delivery state and lint findings. They MUST NOT reconcile against
`docs/TODO.md` after migration.

When iwiki is unavailable, status reporting MUST say durable status is unavailable and
may report session/spool delivery evidence as non-authoritative. It MUST NOT infer a
durable project status from local artifacts alone.

Acceptance:

- Status output identifies current, completed, stalled, and completion-pending tasks
  from wiki pages.
- No status-report rule names `docs/TODO.md` as a live source.

### R8. Legacy Archive Migration

Before deleting `docs/TODO.md`, the implementation MUST create one immutable wiki page
at `reference/tasks-legacy-archive`. It MUST preserve every legacy table row, original
column values, and a migration note with source path and date. Historical rows MUST NOT
be expanded into individual task pages.

The migration MUST compare source and archive topic count and exact topic set before
removing the repository file. References that describe live task tracking MUST move to
the new per-topic contract; historical explanations MAY link to the archive.

Acceptance:

- Archive and source have equal row counts and identical topic sets before deletion.
- `docs/TODO.md` is absent after verified migration.
- Repository search finds no active instruction or runtime dependency on
  `docs/TODO.md`; historical migration references are explicitly marked as such.

### R9. Secret-Safe Evidence

Task pages, changelog entries, subtask evidence, and spool events MUST contain summaries,
paths, hashes, exit status, and test counts only. They MUST NOT contain tokens,
credentials, environment values, authentication files, or raw potentially sensitive
tool output. The parent MUST redact before any wiki or spool write.

Acceptance:

- Tests reject representative token, credential, and environment-value payloads.
- Recorded evidence remains sufficient to identify the check and its outcome without
  reproducing raw output.

### R10. Cross-Agent Standard Synchronization

The approved intent and design contract MUST be summarized in the shared devops wiki
page `concept/wiki-task-ledger`. That page MUST describe the same per-topic page,
mandatory direct/chain/LoEn coverage, parent-only writes, offline spool, idempotency,
redaction, and fail-closed completion rules. It MUST state that each project's rollout
remains a separate project task and MUST NOT claim that updating the shared concept has
already migrated another repository.

Acceptance:

- The devops concept contains no active rule for central mutable task indexes, separate
  changelog pages, unsupported `type: task`, or omission of direct tasks.
- The devops concept links the `icodex` intent and spec as source anchors and records
  project-local rollout boundaries.
- The devops domain passes `wiki_lint` without a new finding caused by the update.

## Architecture

### Task Contract

The contract is instruction-first. A compact shared task-page template and event schema
define exact sections, lifecycle values, ownership, redaction, and idempotency. Agent
rules and workflow skills consume this same contract. Existing executable LoEn hooks
that currently write the repository TODO must instead stop doing so; they may emit
structured delivery evidence for the parent, but MUST NOT call iwiki directly because
MCP ownership belongs to the interactive parent agent.

### Data Flow

1. Parent performs bounded discovery to resolve the project domain and canonical topic.
2. Parent searches the exact task-page slug and creates the page if absent.
3. Parent reads current lifecycle and durable idempotency keys, then replays and
   acknowledges pending spool events in order.
4. Parent updates current sections and appends material events at workflow checkpoints.
5. Parent records subagent dispatch, delegates read-only task context, receives
   structured evidence, and serializes the result.
6. On MCP failure, parent atomically queues redacted events and marks completion
   pending in session state.
7. On recovery, parent replays in order, confirms page state, runs `wiki_lint`, and
   removes delivered spool state.

### Failure Boundaries

- Missing project domain: execution may proceed with spool delivery evidence; durable
  completion is blocked.
- Conflicting page state: halt and request proposal-first reconciliation.
- Wiki write failure: retain event in spool; do not claim durable transition.
- Duplicate delivery: detect idempotency key and treat as successful replay.
- `wiki_lint` regression caused by the task page: keep completion pending until fixed.
- Pre-existing unrelated lint findings: report them without treating them as introduced
  regressions.

## Components and Changes

- `.codex-isolated/AGENTS.md`: replace repository task-log and two-source status rules;
  define mandatory direct/chain/LoEn task pages and parent/subagent ownership.
- `.codex-isolated/skills/context-awareness/SKILL.md`: surface exact task-page context
  and pending-delivery state during Phase 0.
- `.codex-isolated/skills/check-chain/SKILL.md`: replace TODO row/cell operations with
  task-page lifecycle events and wiki-only result evidence.
- `.codex-isolated/agents/chain-auditor.toml` and routing tests: review task-page
  readiness while leaving all writes to the parent.
- `plugins/loen/`: remove runtime TODO writer behavior and align skills, docs, and
  enforcement evidence with parent-owned wiki updates.
- Direct-topic and workflow guidance: require task-page creation for all direct work;
  preserve `@topic` profile behavior.
- README and project docs: describe wiki-only task tracking, outage semantics, and
  legacy archive.
- `devops:concept/wiki-task-ledger`: synchronize the cross-agent standard while keeping
  other project rollouts explicitly separate.
- Tests: add contract, outage, delegation, migration, status-report, chain, LoEn, and
  direct coverage.

## Testing Strategy

Focused tests MUST validate:

- Required page sections, canonical topic/slug mapping, supported iwiki metadata, and
  lifecycle transitions.
- Atomic spool replacement, ordered replay, duplicate suppression, redaction, and
  fail-closed completion.
- Parent-only writes and structured subagent dispatch/return evidence.
- `check-chain` stage updates without TODO rows or duplicate cached events.
- LoEn hooks no longer creating `docs/TODO.md` while preserving loop artifacts.
- Mandatory direct task-page rules for explicit and inferred topics, including
  read-only work.
- Legacy archive row-count and exact-topic reconciliation before file removal.
- Wiki-only status reports and the older-than-14-days signal.
- Shared devops concept consistency with the approved project contract.
- Repository search proving no active `docs/TODO.md` dependency remains.

The existing focused IDD, profile, LoEn, routing, documentation, and full Bash suites
MUST remain green. Final verification MUST run `wiki_lint(domain="icodex")` and confirm
no new broken, orphan, stale, missing-source, tag-drift, or OKF findings.

## Risks and Mitigations

- **MCP unavailable during work:** atomic spool permits execution; completion remains
  pending until durable replay.
- **Parallel agent races:** only parent writes; subagents return evidence.
- **Duplicate retry events:** stable idempotency keys make replay safe.
- **Unsupported iwiki task vocabulary:** supported reference metadata plus body-level
  lifecycle avoids server changes.
- **Secret leakage:** redacted schemas prohibit raw output and sensitive values before
  both wiki and spool writes.
- **Migration loss:** exact topic-set and row-count comparison gates deletion of the
  repository task table.

## Human Checkpoints

- Changing lifecycle semantics, deleting or archiving any wiki page, or resolving
  conflicting task state remains proposal-first.
- `wiki_sync`, external publication, and secret disclosure remain prohibited.
- Removal of `docs/TODO.md` is authorized only after the accepted archive migration
  checks pass.

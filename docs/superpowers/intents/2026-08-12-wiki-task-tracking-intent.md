---
workflow:
  route: chain
  continuation: full
review:
  intent_hash: 7ff475fcef481a21
  last_run: 2026-08-12
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
---

# Intent: wiki-task-tracking

**Date:** 2026-08-12
**Status:** approved

## Objective

Make the iwiki MCP domain the single source of truth for work performed by agents in a
project. It must provide durable project memory and per-topic temporary task context,
while recording material task changes in a wiki changelog.

## Desired Outcomes

- A new agent finds current project and task context through iwiki without relying on
  `docs/TODO.md`.
- The parent agent and its subagents observe one authoritative task status.
- The wiki retains an ordered changelog of material task lifecycle transitions.
- Each task has a canonical lowercase-kebab-case topic and a matching iwiki task page.

## Health Metrics

- Parallel subagents do not race to write task state or changelog entries.
- The chain lifecycle remains reproducible.
- Work can continue safely when the iwiki server is unavailable.
- Changelog entries never contain secrets.

## Strategic Context

- Interacts with: parent agents, subagents, `check-chain`, task and status reporting,
  the iwiki MCP server, and the git repository.
- Priority trade-off: trust > speed > cost.

## Constraints

### Steering (behavioral guidance)

- Use iwiki task pages for durable task state, topic context, and changelog history.
- Make each material lifecycle transition observable in the task page.
- Keep task lifecycle writes serialized through the parent agent.

### Hard (architectural enforcement)

- Use only iwiki MCP `wiki_*` tools for wiki operations.
- Do not create or update `docs/TODO.md` as task tracking state.
- Only the parent agent may write task status or changelog state.
- An unavailable iwiki server must not block task execution; preserve explicit local
  evidence for later synchronization.
- Never write secrets to a task page or changelog.
- Bootstrap exception: the current `check-chain` gate may update the one
  `wiki-task-tracking` row in `docs/TODO.md` until this migration replaces that gate;
  no other new task may use the repository task log.

## Autonomy Zones

- Full autonomy: read wiki context, search task pages, and collect implementation
  evidence.
- Guarded: parent updates a task page and changelog after a verifiable lifecycle
  transition.
- Proposal-first: change task lifecycle semantics; delete or archive wiki pages; resolve
  conflicting task states.
- No autonomy: run `wiki_sync`, publish outside the local iwiki store, or disclose any
  secret.

## Stop Rules

- Halt if task states conflict or a required wiki write fails.
- Escalate if the conflict cannot be reconciled from task-page evidence.
- Done when the task page records the final state and lifecycle history, `wiki_lint`
  reports no new violations, and lifecycle tests pass.

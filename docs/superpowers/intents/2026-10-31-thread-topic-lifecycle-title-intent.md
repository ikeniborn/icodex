---
review:
  intent_hash: e76b5047a3b650d6
  last_run: 2026-10-31
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
workflow:
  route: chain
  continuation: execute
---
# Intent: thread-topic-lifecycle-title

**Date:** 2026-10-31
**Status:** approved

## Objective

Show the canonical task topic and its completion state in the Codex thread title.
Replace unrelated automatic titles after the task topic becomes known.

## Desired Outcomes

- After a successful task-ledger write establishes an active task, its current session
  has the persisted thread name `<topic>-inprogress`.
- After a successful task-ledger write confirms lifecycle `done`, that session has the
  persisted thread name `<topic>-done`.
- When the task resumes with lifecycle `in-progress`, its name returns to
  `<topic>-inprogress`.
- Canonical topic, branch suffix, profile name, and wiki slug contain no lifecycle suffix.
- Failed wiki writes and unrelated page writes do not rename the current thread.
- A rename failure produces a concise diagnostic and leaves task execution available.

## Health Metrics

- Existing profile routing and direct-topic tests retain their current passing behavior.
- The full Bash test suite passes on the final implementation state.
- A local integration check reads the expected persisted name through the installed
  Codex App Server after each lifecycle transition, without an inference request.
- Git contains no session logs, credentials, or mutable title state.

## Strategic Context

- Interacts with: task-ledger MCP results, Codex PostToolUse hooks, launcher hook wiring,
  the current session ID, and Codex App Server `thread/name/set`.
- Priority trade-off: trust > speed > cost.
- Thread naming is best effort. A running client may display the persisted change only
  after refreshing or reopening its thread list.

## Constraints

### Steering

- Derive the title from the canonical task-page topic and explicit lifecycle state.
- Apply `-done` only to durable task completion, never to turn completion or process exit.
- Keep the change scoped to lifecycle naming and its documentation and tests.
- Retain the last name for `blocked` and `completion-pending` states.

### Hard

- Use the official `thread/name/set` protocol and the exact current session identifier.
- Do not edit Codex SQLite databases or rollout files directly.
- Limit automatic updates to successful task-page writes in the configured project primary.
- Do not make wiki mutations from a hook.
- Do not change profile selection, model, effort, or inference behavior.
- Bound rename execution time and preserve the parent task when the rename fails.
- This intent permits an App Server metadata call from the separate lifecycle-title hook.
  The prohibition in the direct-topic-profile intent still applies to profile hooks.
- Do not commit or push to master. Deliver the change through a PR targeting master.

## Autonomy Zones

- Full autonomy: implement reversible naming changes, tests, documentation, and the PR.
- Guarded: apply metadata updates only after matching successful task-page responses.
- Proposal-first: change the approved lifecycle mapping or introduce another title authority.
- No autonomy: modify credentials, widen wiki scope, or merge the PR without authorization.

## Stop Rules

- Halt if: the installed App Server cannot update a persisted thread by its exact ID.
- Escalate if: implementation requires direct database writes or a change to profile routing.
- Done when: active, completed, and resumed task scenarios read back the expected persisted
  titles; failed and unrelated writes leave titles unchanged; required tests pass;
  repository and wiki documentation describe the behavior; a PR targets master.

---
review:
  intent_hash: f1d4a929bb3f5a44
  last_run: 2026-08-13
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
result_check:
  verdict: OK
  source: intent
  intent_hash: f1d4a929bb3f5a44
  last_run: 2026-08-13
---
# Intent: task-ledger-changelog-behavior

**Date:** 2026-08-13
**Status:** approved

## Objective

Keep complete, auditable material-event history throughout an open task without rewriting and reindexing the whole task changelog for every new event. Add a domain-level changelog for cross-task changes, remove the task-page orphan contradiction, and align the shared devops standard.

## Desired Outcomes

- An open task retains every material event while recording a new event without rewriting the entire accumulated history.
- A closed task retains a complete, verifiable event history.
- Each domain has a separate changelog for significant domain-level changes, linked to relevant task pages.
- A newly created task page may be reported as an orphan, but that expected advisory does not block closure when no other task-page finding exists.
- `docs/TODO.md` remains absent from task tracking.

## Health Metrics

- Event idempotency and chronological ordering remain intact.
- Secret-safe redaction and offline spool/replay remain intact.
- Task-page search by `task` tag and topic remains intact.
- The parent remains the sole wiki writer; subagents never write wiki state.
- Existing Bash tests and `wiki_lint` remain passing for new findings.

## Strategic Context

- Interacts with: `task-ledger`, `task_spool.py`, `check-chain`, the `icodex` iwiki domain, and the shared `devops` standard.
- Priority trade-off: integrity and auditability over minimizing the number of wiki writes.

## Constraints

### Steering (behavioral guidance)

- Keep the design narrow; the domain changelog must not duplicate every task event.
- Make the active task history efficient to write and read without hiding its contents.

### Hard (architectural enforcement)

- Do not lose history before a topic is closed.
- Do not turn `TODO` into a changelog.
- Do not introduce a central mutable task index.
- Preserve parent-only wiki writes and secret-safe task evidence.
- Preserve completion requirements: replay, successful page write, and lint without a new task-page finding.

## Autonomy Zones

- Full autonomy (reversible, low risk): modify local skills, scripts, tests, project documentation, and `icodex` wiki pages to satisfy the approved outcomes.
- Guarded (log + confidence threshold): select archive and domain-entry formats only with focused tests and lint evidence.
- Proposal-first (needs approval): update the shared `devops` task-ledger standard after preparing exact compatible wording.
- No autonomy (human only): modify `iwiki-mcp` itself or publish changes outside the project and bound wiki domains.

## Stop Rules

- Halt if: retaining complete history requires an unavailable MCP capability.
- Escalate if: the domain-journal policy conflicts with idempotency, replay, or the no-central-index invariant.
- Done when: tests prove bounded task-event writes and complete/replayable history; `wiki_lint` has no new task-page finding beyond the expected task-page orphan advisory; and the `icodex` and `devops` documentation agree on the policy.

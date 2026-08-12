---
name: task-ledger
description: Use when starting, updating, delegating, completing, or reporting a direct, chain, or LoEn project task that needs authoritative iwiki lifecycle state.
---

# Task Ledger

Track every direct, chain, and LoEn task, including read-only work. The parent agent is the sole writer; task state lives on iwiki, never in a repository ledger.

## Required flow

1. Call `wiki_status`; bind the project domain for read/write when present.
2. Resolve one English lowercase-kebab-case topic; stop on conflicting controlled topics.
3. Read or create `reference/tasks/<topic>` with `type: reference`, `status: stable`, and tag `task`.
4. Load durable event keys, then replay pending spool events in order; acknowledge only after confirmed page replay.
5. Keep exactly `## Current State`, `## TODO`, `## Subtasks`, `## Evidence`, and `## Changelog`. Each starts with a <=250-character lead paragraph and blank line; use no heading deeper than `##`.
6. Parent records material events. Before delegation record `dispatch`; subagents never write wiki and return subtask ID, role, outcome, changed paths, checks, blockers, and proposed changelog text. Record `return` before the next transition.
7. On MCP failure, enqueue redacted events with `scripts/task_spool.py` and use `completion-pending`.
8. Set `done` only after final evidence, successful wiki write, empty spool, and `wiki_lint` without a new task-page finding.

## State and events

Lifecycle: `in-progress`, `blocked`, `completion-pending`, `done`. Material event kinds: `open`, `route`, `dispatch`, `return`, `decision`, `blocker`, `verification`, `close`; append them chronologically, not every tool call.

`Current State` records topic, route, lifecycle, opened, closed (when done), parent, and pending-delivery. `TODO` is workflow-specific and must not impose chain stages on direct or LoEn work.

Input schema is exactly `{kind, occurred_at, actor, summary, evidence}`; persisted event schema adds canonical `evidence_hash` and `event_id`. Evidence is `{paths, checks, hashes}`. Paths are repository-relative; checks contain only name, passed/failed status, and integer exit code; hashes are lowercase hex. Never record credentials, environment values, auth files, or raw command output.

Idempotency key: SHA-256 of topic, kind, and canonical redacted evidence hash, truncated to 16 hex characters. Exclude timestamp, actor, and summary. Page replay happens outside helper: skip page keys already durable, then acknowledge confirmed events.

## Boundaries and reporting

`task_spool.py` is dependency-free local storage only and must never call MCP; never modify iwiki-mcp, call `wiki_sync`, or create a subagent task page. It is a redaction backstop: reject controls, secret assignments, authentication/credential paths, `.env` paths, symlinks, and non-regular spool targets before writing. Status reports search task-tagged pages, read relevant pages, report lifecycle/TODO/pending delivery/lint findings, and list `in-progress` tasks older than 14 days. If iwiki is unavailable, say durable status is unavailable; spool evidence is non-authoritative.

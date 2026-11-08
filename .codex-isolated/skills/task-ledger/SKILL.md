---
name: task-ledger
description: Use when starting, updating, delegating, completing, or reporting a direct, chain, or LoEn project task that needs authoritative iwiki lifecycle state.
---

# Task Ledger

Track every direct, chain, and LoEn task, including read-only work. The parent agent is the sole writer; task state lives on iwiki, never in a repository ledger.


## Call economy

Reuse the verified binding within the same MCP session, project, normalized scope, and configured policy.
Reuse the recorded status and effective policy when that binding remains valid.
After a reconnect, configuration or project change, uncertain session continuity, or defaulted response, bind and verify again.
Apply all binding error and policy mismatch rules regardless of earlier evidence.
Do not repeat startup calls merely because another skill or conversation turn starts.
Search once per task and read selected content before relying on it.
Repeat retrieval for expanded scope, conflicting evidence, or a new unresolved question.
Run lint after a completed write batch and before closure; reuse it until another write.
Run startup lint only for a requested health audit or relevant unresolved lint finding.
Conversational explanations based only on supplied text require no task page or wiki calls.
Exclude project investigation, changes, status reports, and new project conclusions from that exception.
Retain graph readiness checks before relevant code analysis and all source maintenance requirements.
These rules scope the startup steps below; they do not relax CAS, recovery, GWT, evidence, or completion gates.

Batch material events at the next durable checkpoint without omitting decisions, blockers, checks, or gate outcomes.
Persist dispatch before delegation and return before the next transition.
Persist blockers and handoff state before yielding control.
Persist pending evidence before closure; never defer it beyond the task's completion claim.
Preserve every event in linked history segments and retain the spool recovery contract.

## Required flow

1. For local stdio or remote HTTP, first load and normalize the project `.iwiki.toml` scope and call `wiki_bind` with its full `read`, `write`, and `primary` values before `wiki_status`; never narrow to the project basename. Hosted HTTP carries explicitly configured mode and snapshot-age policy through `project_policy`; local stdio omits both policy arguments. Read [iwiki MCP binding and maintenance](../context-awareness/references/iwiki-mcp.md) before binding; every rebind resends the complete policy. After hosted bind, require `wiki_status` to report `binding_source: session` and the requested primary. Rebind and repeat on a defaulted answer. Read the effective specification mode from status: exact override, tenant-wide override, carried project mode, hosted default, then built-in `optional`; `source: hosted_override` is legitimate, while `project_mode_suppressed: true` reports refusal. A rejected bind, `binding_not_selected`, or unresolved primary substitution permits no task-page mutation; any binding mismatch retains `completion-pending`. An unaccepted mode mismatch retains `completion-pending` and blocks only mutating specification calls; ordinary non-specification Wiki and task-page work remains available when session binding and provenance are valid. Under generated remote-scope instructions, missing, invalid, or rejected scope permits no mutating call and retains `completion-pending`.
2. Resolve one English lowercase-kebab-case topic; stop on conflicting controlled topics.
3. Read or create `reference/tasks/<topic>` with `type: reference`, `status: stable`, and tag `task`.
4. Load durable event keys, then replay pending spool events in order; acknowledge only after confirmed page replay. Read the current page revision before every PostgreSQL page mutation and pass it as `expected_revision`; for one-section updates also pass `expected_section_hash` when available.
5. Keep exactly `## Current State`, `## TODO`, `## Subtasks`, `## Evidence`, and `## Changelog`. Each starts with a <=250-character lead paragraph and blank line; use no heading deeper than `##`.
6. Parent records material events. Before delegation record `dispatch`; subagents never write wiki and return subtask ID, role, outcome, changed paths, checks, blockers, and proposed changelog text. Record `return` before the next transition.
7. On MCP failure, enqueue redacted events with `scripts/task_spool.py` and use `completion-pending`.
8. Set `done` only after final evidence, successful wiki write, empty spool, and `wiki_lint` without a new task-page finding.

PostgreSQL mutations returning `conflict` or `section_conflict` changed nothing. Re-read the current page/section, preserve concurrent events or state, rebuild the intended bounded update, and retry once with the new revision/hash. A second conflict becomes `completion-pending` plus a blocker; never overwrite from stale content.

If iwiki is connected but the project domain is absent, the task page cannot be read or created. Parent may continue with redacted spool events, report durable status unavailable, and retain `completion-pending`; completion remains fail-closed until a bound domain permits replay, wiki write, and lint. This differs from the normal bound-domain flow above.

## State and events

Lifecycle: `in-progress`, `blocked`, `completion-pending`, `done`. Material event kinds: `open`, `route`, `dispatch`, `return`, `decision`, `blocker`, `verification`, `gate`, `close`; append them chronologically, not every tool call.

`Current State` records topic, route, lifecycle, opened, closed (when done), parent, and pending-delivery. `TODO` is workflow-specific and must not impose chain stages on direct or LoEn work.

Input schema is exactly `{kind, occurred_at, actor, summary, evidence}`; persisted event schema adds canonical `evidence_hash` and `event_id`. Evidence is `{paths, checks, hashes}`. Paths are repository-relative; checks contain only name, passed/failed status, and integer exit code; hashes are lowercase hex. Never record credentials, environment values, auth files, or raw command output.

Idempotency key: SHA-256 of topic, kind, and canonical redacted evidence hash, truncated to 16 hex characters. Exclude timestamp, actor, and summary. Page replay happens outside helper: skip page keys already durable, then acknowledge confirmed events.

## Thread lifecycle titles

After resolving the canonical topic, announce `Топик: <topic>` in user-visible commentary before task-specific work.
Repeat the announcement when switching topics or starting work in another session.
Before starting or resuming work, create the task page or replace `Current State` with `Lifecycle: in-progress`.
Reading an existing page does not trigger naming.
Reuse this lifecycle write within the same active task session; do not repeat it for every prompt.
Read the current revision immediately before replacing the section and preserve unrelated state fields.
If binding or storage is unavailable, announce the topic and retain the existing `completion-pending` recovery flow.


1. In `## Current State`, write exactly one plain `Lifecycle: <state>` field outside code fences.
2. Use `in-progress`, `blocked`, `completion-pending`, or `done` as the state.
3. When updating lifecycle, replace `Current State` through `wiki_update_page`.
4. Preserve the existing completion gates before writing `Lifecycle: done`.
5. Keep title suffixes out of the canonical topic, task-page slug, profile name, and branch name.
6. Do not replace an automatic lifecycle title with the bare topic.
7. If naming fails, report the failure and continue the task.

Use this field layout within the section:

```text
Topic: example-topic. Route: direct. Lifecycle: in-progress.
```

The installed icodex `thread-title.py` hook observes successful task-page writes in the project's configured primary domain.
Page creation reads `Current State`; updates must replace that section.
Other sections, failed writes, and history pages do not trigger naming.

| Lifecycle | Thread title |
|---|---|
| `in-progress` | `<topic>-inprogress` |
| `done` | `<topic>-done` |
| `blocked` or `completion-pending` | Previous title retained. |

Naming is best effort and does not establish task completion.
Distinguish persisted naming from client display refresh.
If naming is uncertain, read the persisted thread name before diagnosing a hook failure.
Report an unavailable read as unverified naming; do not infer success or failure from client display alone.
Existing sessions need a restart to load a newly installed hook; clients may need a refresh to display titles.
See `docs/thread-topic-lifecycle-title.md` in the icodex repository for runtime boundaries and verification commands.

## History segments and domain journal

Keep complete task history in linked history segments. The task page `Changelog` is a small manifest that links to the first and bounded active segment; it does not repeat past events. Each segment has exactly `## Events` and `## Next`, carries up to 20 events, and names its successor or `none`. A new event rewrites only the bounded active segment. On replay, the parent traverses history segments, loads their durable event IDs, then appends only missing events. Closing a topic leaves every segment reachable from the task page and preserves its full history.

The domain changelog is `reference/domain-changelog`. It contains curated domain-level changes such as standards, releases, migrations, and cross-task decisions, with links to affected task pages. Do not add routine task events there and do not use it as a task index.

An `orphans` entry for `reference/tasks/*` is an expected task-page orphan advisory on Git: status discovery uses the `task` tag rather than an inbound central index. It does not block closure unless `wiki_lint` reports another finding for that task page. PostgreSQL lint does not compute orphan or stale-source findings; closure there relies on successful page/segment writes plus link and section findings.

## Boundaries and reporting

`task_spool.py` is dependency-free local storage only and must never call MCP; never modify iwiki-mcp, invoke `wiki_sync`, or create a subagent task page. Threat model: launcher-created per-user `CODEX_HOME` is trusted even when mode 0775; helper-managed `state/iwiki-task-spool/<project>` dirs are owner-only 0700 and unsafe preexisting managed components are rejected, preventing cross-user mutation. It is a redaction backstop: reject controls, secret assignments, authentication/credential paths, `.env` paths, symlinks, and non-regular spool targets before writing. Status reports search task-tagged pages, read relevant pages, report lifecycle/TODO/pending delivery/lint findings, and list `in-progress` tasks older than 14 days. If iwiki is unavailable, say durable status is unavailable; spool evidence is non-authoritative.

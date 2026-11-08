# Thread lifecycle titles

The launcher installs `thread-title.py` as a `PostToolUse` hook on its next startup.
The hook observes successful `wiki_write_page` and `wiki_update_page` calls for
`reference/tasks/<topic>` in the project's configured primary domain.

## Lifecycle mapping

| Task lifecycle | Persisted thread name |
|---|---|
| `in-progress` | `<topic>-inprogress` |
| `done` | `<topic>-done` |
| `blocked` or `completion-pending` | Retain the last name. |

On page creation, the hook reads only `## Current State` from the submitted Markdown.
On an update, it reads only a successfully replaced `Current State` section.
Use one explicit `Lifecycle: in-progress` or `Lifecycle: done` field in that section.
The existing inline and bullet task-ledger layouts are supported.
Failed writes, other sections, history pages, and other domains do not change titles.
The hook does not infer a lifecycle from turn completion or process exit.

The canonical topic remains an English lowercase kebab-case slug. Profile names,
task-page slugs, and `dev-<topic>` branch names retain that slug without a status suffix.

## Runtime boundary

The hook uses the exact session ID from the hook payload and the current `CODEX_HOME`.
It starts the installed Codex App Server for `initialize` and `thread/name/set` only.
It sends no inference request and makes no wiki mutations. It does not edit the
Codex database or rollout files directly. Profile hooks do not use this exception.

Naming is best effort. The protocol exchange has an eight-second deadline, followed
by bounded child-process cleanup. A failure adds concise context for the agent and
keeps the task available. The previous name may remain until the next successful
lifecycle write. A thread must already be persisted before a separate App Server
can rename it. Ordinary sessions with an automatic title satisfy this condition.

A running client may need to refresh or reopen its thread list to display the
persisted change. This integration does not control client redraw behavior.
Existing sessions load the new hook after restarting icodex.

## Verification

Run the dependency-free hook and launcher tests:

```bash
bash tests/test_thread_title_hook.sh
bash tests/test_profile_wiring.sh
```

To verify persisted titles with the installed Codex binary, enable the integration
case. It creates an isolated temporary home and starts no model turn:

```bash
ICODEX_TITLE_INTEGRATION=1 bash tests/test_thread_title_hook.sh
```

## Task startup and resume

After resolving the canonical topic, announce `Топик: <topic>` in user-visible commentary before task-specific work.
At task startup or resume in another session, use `task-ledger` to create or replace `Current State` with `Lifecycle: in-progress`.
Reading an existing page does not trigger the hook.
Reuse the lifecycle write during the same active task session.
If binding or storage is unavailable, announce the topic and follow the task-ledger recovery rules.

The explicit `@topic` command supplies agent context and profile binding; it does not replace the lifecycle write.
If the displayed title remains unchanged, read the persisted name before diagnosing a hook failure.
Report an unavailable metadata read as unverified naming.

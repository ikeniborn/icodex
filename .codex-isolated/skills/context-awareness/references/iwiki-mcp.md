# iwiki MCP operational reference

Use live callable schemas and observed responses as the contract. This reference covers
hosted policy and graph maintenance; existing project scope, CAS, GWT, and task-ledger
rules still apply. Source guidance: iwiki-mcp pages `base-binding` (Hosted policy
resolution), `retrieval`, `concept/code-graph-runtime`, and `concept/code-graph-wiki-linking`.

## Binding and effective policy

For hosted HTTP, prefer `project_policy`: map explicitly configured `[specifications].mode`
to `specification_mode`, and `[code_graph].max_snapshot_age_seconds` to its same-named
policy field. `require_session_binding` is operator-only; never include it in `project_policy`.
Read its effective server value from status. Send only the two client-settable
policy values and the complete normalized scope, never the whole TOML. Never send both
`project_policy` and the deprecated top-level `specification_mode` alias. A later bind
replaces the policy wholesale: resend all configured policy fields on every rebind.
Use the alias only when the live schema lacks `project_policy` and the project declares
only specification mode; report any uncarried policy field instead of silently dropping it.
Local stdio omits both policy arguments and reads project configuration.

Read effective values and their sources from `wiki_status.policy.domains[]`, including
`policy.domains[].suppressed`; keep specification mode checks against `specifications`.
Precedence is per field: exact override, then tenant-wide override, then project value,
then hosted default, then built-in value. Operator overrides are legitimate. Project
values may only tighten policy: `disabled < optional < strict` and a
smaller snapshot age (`0` means infinity). `allow_project_mode=false` disables the project
tier for both client-settable fields. Session-binding enforcement has no project tier. Report suppression and honor the effective server value; never
relax policy to make stale snapshots pass. An unaccepted specification-mode mismatch
retains `completion-pending` and blocks specification mutations; ordinary Wiki work
remains available with a trusted binding.

For example, a project declaring strict mode and a 600-second snapshot age sends the
following **in addition to** its complete normalized `read`, `write`, and `primary`:

```json
{"project_policy":{"specification_mode":"strict","max_snapshot_age_seconds":600}}
```

If binding is lost, resend that same scope and policy before repeating the affected read.
Do not infer a new scope, change grants, or edit hosted configuration to repair a refusal.
An invalid bind leaves the old binding unchanged; that does not validate the requested one.

## Finding and reading pages

`wiki_search(mode=...)` accepts `hybrid`, `lexical`, or `semantic`. Use lexical for exact
names and identifiers; hybrid for mixed discovery; semantic for conceptual queries.
Lexical avoids query embedding but optional reranking may still run. The write-intent
search has a separate target-selection contract and is not a page mutation.

Search hits contain `domain`, `file`, `heading`, `chunk`, `score`, `hit`, and `source`.
Read the selected `file` as a page slug (remove its `.md` suffix), optionally scoped to
`heading`, before interpreting or editing its content. A result is a locator, not a
content excerpt. Never invent a `section_id` for `wiki_related`; use a real retrieved ID.

## Code rebuild jobs

Use `wiki_code_index` only on a local MCP server with the checkout and supported binding.
A PostgreSQL binding returns `source_unavailable`; hosted status reads a published snapshot.
`wait_seconds` must be within the configured full-build budget; values below 0.5 seconds
are floored to 0.5. It limits the caller wait, not the worker deadline. `rebuilding` plus
`job.id` means work continues, including publication, after the call returns.

Poll `wiki_code_status(job_id=<returned job.id>)` on that same server and binding; inspect
the job's `ready`/`failed` state separately from graph `state` and `fresh`. A later build
must not substitute for the requested job. `job_unknown` means this process cannot report
that handle (including a hosted server or expired history); report uncertainty and inspect
current graph readiness without claiming that job succeeded.
A response without the requested `job` is not completion evidence, even when warnings are
empty: `stale_snapshot` may omit `job_unknown`. Report that the build cannot be correlated
rather than repeatedly polling an error answer. A failed publication can
produce a failed job despite a ready local graph. Do not repeatedly start builds to poll.

## Wiki links versus source freshness

`wiki_links_stale` tracks derived Markdown links independently of source snapshot age.
After the last Wiki edit, if source is unchanged, use `wiki_code_refresh_links(domain=...)`
with the explicit intended writable domain and a trusted binding. It refreshes links
against the active ready PostgreSQL snapshot; `missing_snapshot` means there is none.
It parses no source, resolves no new source symbols, does not renew snapshot age, and
preserves snapshot/payload revisions and graph counts. Re-read status or lint to verify.
Ordinary prose edits can also mark links stale because the revision spans all pages.

Changed source requires local rebuilding and, for hosted reads, publication. Refreshing
links does not replace publication or make `fresh=false` acceptable for code analysis.
For publication, use the begin/batch/finalize/abort tools with the server-advertised limits;
never invent row schemas, hashes, or headers, and never add client domain or wiki identity.

## Maintenance boundaries

Page mutations already reindex; `wiki_index` is not a routine post-write operation.
PostgreSQL writes are durable without `wiki_sync`. OKF maintenance remains Git-only.
`wiki_migrate_okf` mutates even in plan mode: deterministic layout moves and reindexing
still run. Do not call it as read-only discovery or merely to inspect capabilities.

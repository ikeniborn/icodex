# iwiki MCP modes

## Local stdio

icodex registers `iwiki-mcp` as a local stdio MCP server on launch. Keep the active Git
binding in `.iwiki.toml`, or replace it with exactly one PostgreSQL example from that file.
For PostgreSQL, set `ICODEX_IWIKI_DB_PASSWORD` in the ignored `.codex_config`; the wrapper
forwards it as `IWIKI_DB_PASSWORD` without writing it to Codex TOML.

The local/internal sample uses `127.0.0.1` and `sslmode = "disable"` only for a database on
the same machine. The external sample uses `sslmode = "verify-full"`; its hostname must match
the database certificate and the client must trust its CA.

Start the local mode normally:

```bash
./icodex.sh
```

### System One shadow

The local stdio server can call a separate GPU System One endpoint during
`wiki_write_page` without changing the write result or stored metadata. Configure it in
the ignored `.codex_config`:

```text
ICODEX_IWIKI_SYSTEM1_SHADOW=true
ICODEX_IWIKI_SYSTEM1_BASE_URL=http://127.0.0.1:8000/v1
ICODEX_IWIKI_SYSTEM1_KEY=<separate-bearer-key>
ICODEX_IWIKI_SYSTEM1_MODEL=laya-iwiki
```

`ICODEX_IWIKI_SYSTEM1_KEY` is forwarded at runtime through Codex `env_vars`; it is never
written into generated `config.toml`. All three values affect only the local server in
local or dual mode. A hosted HTTP client does not send them because hosted inference is
configured in the server environment. The base URL is the API root ending in `/v1`; the
iwiki client appends `/systemone`.

### Code graph

Code graph supports Python, TypeScript, JavaScript, and Bash. Bash is opt-in, scans `.sh`
files only, and uses `sh:` entities. `wiki_code_index` needs a local Git/stdio MCP server with
the repository checkout and a configured `[code_graph]` table. The server never builds the graph
at startup; call `wiki_code_status`, then `wiki_code_index` when a rebuild is needed. Use graph
results only when status is `ready` and `fresh`. The wrapper supports `ICODEX_IWIKI_CODE_GRAPH_ENABLED`,
`ICODEX_IWIKI_CODE_GRAPH_MAX_FILE_BYTES`, `ICODEX_IWIKI_CODE_GRAPH_MAX_FILES`, and
`ICODEX_IWIKI_CODE_GRAPH_AUTO_REBUILD` overrides; project TOML remains the primary source
for languages, bounds, excludes, and publication/read modes.

PostgreSQL serves `wiki_code_status`, `wiki_code_search`, and `wiki_code_context` from a
published snapshot. It cannot index the client checkout: `wiki_code_index` returns
`source_unavailable`. Hosted graph results additionally require `binding_source: session`.
Hosted `wiki_code_publish_begin` / `_batch` / `_finalize` / `_abort` require an authenticated
writable primary. The begin response advertises server batch row and byte limits; clients must
respect them and cannot raise the hosted ceilings.

### Build jobs and Wiki-link maintenance

On a local server with the checkout, `wiki_code_index(wait_seconds=...)` limits the caller
wait rather than the build deadline. A `rebuilding` response with `job.id` leaves the worker
running through publication. Poll `wiki_code_status(job_id=...)` on the same server and binding.
Inspect that job's terminal `ready`/`failed` state separately from the graph's `state`/`fresh`.
`job_unknown` means the handle cannot be answered; current readiness does not prove that job
succeeded. A response without the requested `job` is not completion evidence, even if it
omits `job_unknown`; error answers can omit that warning. A publication failure can fail a job even when the local graph is ready.

After Wiki edits, `wiki_links_stale` is distinct from source snapshot freshness. For unchanged
source, `wiki_code_refresh_links(domain=...)` re-derives links against the active ready
PostgreSQL snapshot without parsing source, renewing snapshot age, or changing graph counts.
Name the intended writable domain explicitly, verify binding, and check status/lint after the
last Wiki write. `missing_snapshot` means no active ready snapshot exists. Changed source
still requires rebuilding and publication; link refresh cannot repair `fresh=false`.

## Hosted streamable HTTP

Hosted HTTP requires PostgreSQL. Copy `iwiki-http-server.toml.example` to an operator-managed
path outside the repository, replace example hosts and origins, and keep every password and
model credential in the service environment. The hosted server does not use project
`.iwiki.toml` and must not receive `iwiki_id`; bearer-token grants select its wiki and scope.

```bash
export IWIKI_SERVER_CONFIG=/etc/iwiki/server.toml
export IWIKI_DB_PASSWORD='<database-password>'
export IWIKI_LLM_BASE_URL='https://models.example.com/v1'
export IWIKI_LLM_KEY='<model-api-key>'
export IWIKI_EMBED_MODEL='embedding-model'
export IWIKI_EMBED_DIMENSIONS='1024'
iwiki-mcp serve --transport streamable-http
```

The endpoint is `/mcp`. Keep the listener on loopback and publish it through a TLS reverse
proxy that forwards the exact `Origin` and does not log `Authorization`.

A launch registers one or two managed iwiki servers, depending on what resolves.

| Condition | Registered |
|---|---|
| Remote URL and token resolve, local settings incomplete | `[mcp_servers.iwiki-remote]` over HTTP |
| No usable remote block — no URL configured, or its token does not resolve | `[mcp_servers.iwiki]` over stdio |
| Both resolve | `[mcp_servers.iwiki-remote]` over HTTP and `[mcp_servers.iwiki-local]` over stdio |

The name `iwiki-remote` identifies hosted HTTP explicitly. In dual mode it answers Markdown
and specification calls, while `iwiki-local` exists for `wiki_code_index` and code readers,
because a hosted server answers `source_unavailable` to an index request; it becomes the
full server only while the remote one is unreachable.

A remote URL whose token does not resolve does not cost the launch its wiki. The remote
block is skipped with a warning and a complete local set is still registered — as
`[mcp_servers.iwiki]`, since it is then the only server. Before this, an unresolved token
skipped the whole wiring and left the session with no iwiki at all.

### External MCP client

For an already hosted iwiki server, do not run `iwiki-mcp serve` locally and do not put a
PostgreSQL `[storage]` table in the client project binding. Set these values in `.codex_config`:

```text
ICODEX_IWIKI_REMOTE_URL=https://iwiki.example.com/mcp
ICODEX_IWIKI_REMOTE_TOKEN=<bearer-token>
```

When the remote URL and token resolve, icodex registers the remote server as `[mcp_servers.iwiki-remote]`
with the configuration shown in `iwiki-remote-mcp.toml.example`. The token is mapped only at runtime to
`IWIKI_REMOTE_TOKEN`, never written to TOML. The remote server resolves wiki identity and
read/write scope from the token; database and model credentials remain server-only.

In this remote-client mode, icodex also generates a short instruction in the active project
agent file. Before its first iwiki operation, the agent reads the normalized `read`, `write`, and
`primary` scope and, when present, `[specifications].mode` from the project-root `.iwiki.toml`.
It calls `wiki_bind` with the complete scope and carries explicitly configured policy through
`project_policy`: `[specifications].mode` becomes `specification_mode`, while
`[code_graph].max_snapshot_age_seconds` retains its field name.
`require_session_binding` is operator-only; never include it in `project_policy`.
Read its effective server value from status. Never send both `project_policy` and the deprecated top-level
`specification_mode` alias. Use the alias only when the live schema lacks `project_policy`
and the project declares only specification mode. A rebind replaces the policy wholesale;
resend all configured fields. Report uncarried fields and retain `completion-pending`.
Local stdio omits both policy arguments: its server reads project configuration.
This preflight runs before `wiki_status`, search, task-ledger, or any other wiki call.
The client never sends TOML text,
paths, `iwiki_id`, or credentials. A missing or invalid scope, or a rejected bind such as HTTP
403, fails closed: no heuristic fallback or mutating wiki call is allowed and lifecycle remains
`completion-pending`. Token grants remain the absolute maximum; a project TOML can request less
scope, never more.

After bind, `wiki_status` must report `binding_source: session`. If a status, a domain-free code
read, or a `wiki_spec_search` or `wiki_search` without `domains` reports `token_default` or
`binding_defaulted`, bind again with the exact project scope and
repeat the affected read. `wiki_search(intent="write")` prefers the bound primary over any
`domains` argument, so its target is defaulted under the fallback whatever the call names. A refused call answers `access_denied` whose `data` carries the
caller's own `binding_source` and an attributed `reason`; for `wiki_spec_resolve` that reason is
`invalid_domain`, `primary_not_selected`, `primary_not_writable`, or `not_bound_primary`, and the
last one reports a scenario outside the bound primary rather than a missing grant. Treat
`primary_substituted` with `requested_primary`,
`binding_not_selected`, a rejected bind, or an unexpected session as a mismatch: make no
mutation and retain `completion-pending` until resolved. Read effective per-domain specification
mode from `wiki_status`, not project TOML. Hosted precedence is per field: exact override, then tenant-wide override, then project
value, then hosted default, then built-in value. `source: hosted_override` is
legitimate and `project_mode_suppressed: true` reports refusal of the carried project mode. Only
an unaccepted mode mismatch permits ordinary Wiki work but no mutating specification call and
retains `completion-pending`.

Read `wiki_status.policy.domains[]` for effective values, sources, and `suppressed` fields.
Project policy only tightens hosted defaults: stronger specification mode or smaller snapshot
age (`0` means infinity). `allow_project_mode=false` disables the project tier for both
client-settable fields. Session-binding enforcement has no project tier. Report suppression and honor the server value.

Read search accepts `hybrid`, `lexical`, or `semantic`. Lexical suits exact identifiers and
skips query embedding, though optional reranking may still run. Hits are locators, so read
the selected page/heading before interpreting its content. Explicit domains passed to `wiki_search` win over ambient scope. Use `scope="all"` only for an
intentional whole-base search; `read=["all"]` is a literal domain, not a wildcard. Use
`wiki_update_page(code=...)` for a selector-only update. When a section update also changes code,
send the section fields plus `code` atomically.

Local stdio does not use this generated remote preflight. Its existing project binding remains
server-local through `.iwiki.toml` and the home symlink.

### Hosted mutation and maintenance contract

Hosted page storage is PostgreSQL. Before `wiki_update_page`, `wiki_insert_section`,
`wiki_move_section`, `wiki_delete_section`, or `wiki_delete_page`, read the current page and
pass its `revision` as `expected_revision`. For one-heading edits, a heading-scoped read also
returns `section_hash`; pass it as `expected_section_hash`. `conflict` and
`section_conflict` change nothing: re-read, preserve concurrent content, and retry the bounded
edit once.

`wiki_migrate_okf` mutates even in plan mode: deterministic layout moves and reindexing still
run. It is not a read-only discovery tool.

PostgreSQL writes are durable transactions. Do not call Git-only `wiki_sync`,
`wiki_remediation_plan`, or OKF maintenance tools; they return `unsupported_storage`.
`wiki_index` remains available for an explicit database reindex. `wiki_create_domain` works on
hosted HTTP only when the bearer token has creation authority and is unsupported for local
PostgreSQL stdio. Domain discovery is read-only. Domain-grant reads require explicit hosted
management work; grant set/revoke require hosted management authority and separate explicit user authorization.

PostgreSQL `wiki_lint` checks links and section structure but does not compute orphans, stale
sources, missing frontmatter, or tag drift. Empty lists for those categories are not proof of
health. Git lint retains the broader report; task/history orphans are expected advisories.

### `iwiki_id` ownership

Local PostgreSQL stdio reads `iwiki_id` from the project `.iwiki.toml` `[storage]` table. Hosted
HTTP is different: its server TOML must not contain `iwiki_id`, and an external client never sends
one. The hosted server derives the wiki identity and visible domain grants from the bearer token.
Create that token server-side for the intended wiki before configuring `ICODEX_IWIKI_REMOTE_URL`
and `ICODEX_IWIKI_REMOTE_TOKEN` in a client project.

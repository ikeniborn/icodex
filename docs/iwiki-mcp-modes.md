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
proxy that forwards the exact `Origin` and does not log `Authorization`. This wrapper currently
selects one managed transport per launch: remote configuration replaces local stdio when
`ICODEX_IWIKI_REMOTE_URL` is set.

### External MCP client

For an already hosted iwiki server, do not run `iwiki-mcp serve` locally and do not put a
PostgreSQL `[storage]` table in the client project binding. Set these values in `.codex_config`:

```text
ICODEX_IWIKI_REMOTE_URL=https://iwiki.example.com/mcp
ICODEX_IWIKI_REMOTE_TOKEN=<bearer-token>
```

When the remote URL is set, icodex replaces its managed local stdio server with the remote MCP
configuration shown in `iwiki-remote-mcp.toml.example`. The token is mapped only at runtime to
`IWIKI_REMOTE_TOKEN`, never written to TOML. The remote server resolves wiki identity and
read/write scope from the token; database and model credentials remain server-only.

In this remote-client mode, icodex also generates a short instruction in the active project
agent file. Before its first iwiki operation, the agent reads the normalized `read`, `write`, and
`primary` scope and, when present, `[specifications].mode` from the project-root `.iwiki.toml`.
It calls `wiki_bind` with the complete scope and passes `[specifications].mode` as
`specification_mode` only to hosted HTTP `wiki_bind`. Local stdio omits `specification_mode`:
its server reads project configuration and rejects client overrides. It does this before
`wiki_status`, search, task-ledger, or any other wiki call. The client never sends TOML text,
paths, `iwiki_id`, or credentials. A missing or invalid scope, or a rejected bind such as HTTP
403, fails closed: no heuristic fallback or mutating wiki call is allowed and lifecycle remains
`completion-pending`. Token grants remain the absolute maximum; a project TOML can request less
scope, never more.

After bind, `wiki_status` must report `binding_source: session`. If a status or domain-free code
read reports `token_default` or `binding_defaulted`, bind again with the exact project scope and
repeat the affected domain-free read. Treat `primary_substituted` with `requested_primary`,
`binding_not_selected`, a rejected bind, or an unexpected session as a mismatch: make no
mutation and retain `completion-pending` until resolved. Read effective per-domain specification
mode from `wiki_status`, not project TOML. Hosted precedence is exact override, then carried
project mode, then hosted default, then built-in `optional`. `source: hosted_override` is
legitimate and `project_mode_suppressed: true` reports refusal of the carried project mode. Only
an unaccepted mode mismatch permits ordinary Wiki work but no mutating specification call and
retains `completion-pending`.

Explicit domains passed to `wiki_search` win over ambient scope. Use `scope="all"` only for an
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

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

Code graph is a local Git/stdio cache for Python only; PostgreSQL and hosted HTTP do not
support it. The active `.iwiki.toml` disables it for this Bash repository. For a Python
project, set `[code_graph].enabled = true` and optionally bound it with
`max_rebuild_seconds`, `max_file_bytes`, `max_total_files`, `include_tests`, and safe
relative `exclude` paths. The wrapper also supports `ICODEX_IWIKI_CODE_GRAPH_ENABLED`,
`ICODEX_IWIKI_CODE_GRAPH_MAX_FILE_BYTES`, `ICODEX_IWIKI_CODE_GRAPH_MAX_FILES`, and
`ICODEX_IWIKI_CODE_GRAPH_AUTO_REBUILD` in `.codex_config`.

The server never builds this cache at startup; call `wiki_code_index` to build it.

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
generates only the local stdio registration.

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
agent file. Before its first iwiki operation, the agent reads only `read`, `write`, and `primary`
from the project-root `.iwiki.toml`, normalizes the domain names, then calls `wiki_bind` with
that complete scope. It does this before `wiki_status`, search, task-ledger, or any other wiki
call. The client never sends TOML text, paths, `iwiki_id`, or credentials. A missing or invalid
scope, or a rejected bind such as HTTP 403, fails closed: no heuristic fallback or mutating wiki
call is allowed and lifecycle remains `completion-pending`. Token grants remain the absolute
maximum; a project TOML can request less scope, never more.

Local stdio does not use this generated remote preflight. Its existing project binding remains
server-local through `.iwiki.toml` and the home symlink.

### `iwiki_id` ownership

Local PostgreSQL stdio reads `iwiki_id` from the project `.iwiki.toml` `[storage]` table. Hosted
HTTP is different: its server TOML must not contain `iwiki_id`, and an external client never sends
one. The hosted server derives the wiki identity and visible domain grants from the bearer token.
Create that token server-side for the intended wiki before configuring `ICODEX_IWIKI_REMOTE_URL`
and `ICODEX_IWIKI_REMOTE_TOKEN` in a client project.

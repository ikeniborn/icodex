---
review:
  spec_hash: 4b5000a79681cd75
  last_run: 2026-09-21
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
  findings:
    - id: F-001
      phase: clarity
      severity: WARNING
      section: R9
      section_hash: ad2fad1506b08c07
      fragment: "the reference must either carry them or point at the page that does"
      text: "The requirement allowed two readings - add full descriptions, or only cross-link - which would have produced different work."
      fix: "Settled on one: every registered tool gets a table row; a tool with a dedicated page gets a one-line summary plus a link."
      verdict: fixed
      verdict_at: 2026-09-21
    - id: F-002
      phase: consistency
      severity: WARNING
      section: R6
      section_hash: 32acff78ad733e26
      fragment: "iwiki-local then becomes the full server, writes included"
      text: "The intent's health metric says no page lands in the local Git base 'by accident'. R6 permits a deliberate write there during an outage, which widens the metric's meaning."
      fix: "Accepted as the user's explicit choice; R6 requires every such write to be recorded on the ledger for later reconciliation, so it is never silent."
      verdict: accepted
      verdict_at: 2026-09-21
chain:
  intent: 5f9ea0d56abe70b3
workflow:
  route: chain
  continuation: full
---

# Design: icodex-iwiki-dual-transport

**Date:** 2026-09-21
**Status:** draft
**Intent:** `docs/superpowers/intents/2026-09-21-icodex-iwiki-dual-transport-intent.md` (approved)

## 1. Problem

`ensure_iwiki_wiring` writes one managed region holding exactly one server. When
`ICODEX_IWIKI_REMOTE_URL` resolves, the remote HTTPS block replaces the local stdio block
outright, and `iwiki-mcp-integration#Required Settings` states that as the contract.

Two failures follow from it, both observed:

- `wiki_code_index` answers `source_unavailable` on a hosted server, and no local server
  exists to run it, so the code graph cannot be rebuilt from an icodex session. The
  `icodex` snapshot reported `fresh: false`, `error: "stale_snapshot"`,
  `age_seconds: 1327089`, `wiki_links_stale: true`.
- During the hosted outage of 2026-09-20 an icodex launch had no wiki at all, failing at
  `initialize` with `HTTP 502`, while iclaude kept working through the local half of its
  dual registration.

## 2. Acceptance (from intent)

Desired Outcomes, carried verbatim:

- `wiki_code_index` is callable from an icodex session, and after it runs
  `wiki_code_status` for the `icodex` domain answers `fresh: true` instead of
  `stale_snapshot`.
- When the remote endpoint is unreachable, an icodex launch still comes up with a working
  local iwiki server instead of no iwiki at all.
- Existing tool names keep working: `mcp__iwiki__*` still resolves, the GWT hook still
  matches `mcp__iwiki__wiki_update_page`, and the instructions already generated into
  AGENTS.md remain true.
- The division of roles is explicit to the agent: the local server is for code-graph work
  only, while every Markdown and specification call goes to the remote server.

Done when, carried verbatim: from an icodex session, `wiki_code_index` runs and
`wiki_code_status` for the `icodex` domain reports `fresh: true` with
`wiki_links_stale: false`; a launch with the remote endpoint unreachable still exposes a
working local iwiki server; all four iwiki test suites pass with no failures; and no
secret appears in the generated `config.toml`.

## 3. Modes and region shape

Three modes replace two. They differ only in what the single managed region contains.

| Condition | Region contents |
|---|---|
| Remote resolves, local set incomplete | `[mcp_servers.iwiki]` over HTTP |
| Remote absent, local set complete | `[mcp_servers.iwiki]` over stdio |
| Both resolve | `[mcp_servers.iwiki]` over HTTP, then `[mcp_servers.iwiki-local]` over stdio |

The name `iwiki` always belongs to the transport that serves Markdown and specifications.
The rule then holds by construction rather than by convention, and the hook matchers and
generated instructions that name `mcp__iwiki__*` stay correct in every mode. The local
server takes the suffixed name only when it is the second server.

One region, the existing markers, and the existing "region at end of file" property are
all unchanged.

## 4. Requirements

### R1 — Parameterize the block generators

`_iwiki_region_body` and `_iwiki_remote_region_body` take the server name as their first
argument and emit `[mcp_servers.<name>]` and `[mcp_servers.<name>.env]`. Their bodies are
otherwise unchanged, including the ordering rule that `command` and `env_vars` precede the
`.env` subtable header.

### R2 — Resolve both transports independently

`ensure_iwiki_wiring` resolves the remote set and the local set separately, then
concatenates one or two blocks into `body`. The local set is complete under today's
condition: a command, an LLM base URL, an LLM key, a project root, and either
`ICODEX_IWIKI_BASE_DIR` or `ICODEX_IWIKI_DB_PASSWORD` when the project `.iwiki.toml`
declares PostgreSQL storage.

### R3 — Strip the suffixed table too

`_iwiki_strip_existing_wiring` matches `^\[mcp_servers\.iwiki(-local)?(\]|\.)`. Without
this, moving from dual back to remote-only leaves a dead `[mcp_servers.iwiki-local]` in
`config.toml` forever, because the current pattern stops at `iwiki]` or `iwiki.`.

### R4 — A resolvable half is never lost to the other half

A remote URL whose token does not resolve currently skips the entire wiring and leaves the
session with no wiki. It must skip only the remote block; a complete local set is still
registered, as `iwiki`, because it is then the only server. An incomplete local set skips
only the local block. Neither set resolving writes no region and returns 0, as today. A
launch never fails because of iwiki.

### R5 — Warn only where a warning is actionable

Today an incomplete local set logs a warning. In dual mode that is the normal state for a
project with no local settings, so the warning is emitted only when no remote URL is
configured. Otherwise every launch would log a warning about a deliberate configuration.

### R6 — State the division of roles, including the outage case

The generated `iwiki-remote-scope` region in AGENTS.md gains a paragraph covering two
states:

- **Remote answering.** `iwiki-local` serves `wiki_code_index` and the three code readers
  only. Every Markdown and specification call goes to `iwiki`. The reason is named: the
  two servers address different stores, so a misrouted call writes a page into the local
  Git base instead of hosted PostgreSQL.
- **Remote unreachable** — not registered in the session, `initialize` failed, or calls
  return a transport error. `iwiki-local` then becomes the full server, writes included.
  Any such write must be recorded on the topic's ledger page as having landed in the local
  store, so it can be reconciled with the hosted copy afterwards. The rule is "write and
  record", never "write".

### R7 — Extend the GWT hook matchers

`ensure_iwiki_gwt_hook` adds the `mcp__iwiki-local__*` variants to both matchers, so the
gate applies to a write regardless of which server serves it. Without this the outage path
in R6 is exactly the path where the gate silently stops running.

### R8 — Correct the one-transport claim

`docs/iwiki-mcp-modes.md` and the wiki page `icodex/iwiki-mcp-integration` both state that
wiring selects one transport per launch. Both change with the implementation, not after
it. This is finding F-002 from the intent gate.

### R9 — Document the tools the rules do not cover

`docs/tools-reference.md` describes 21 of the 36 tools the server registers. Missing:
the nine code-graph tools (`wiki_code_status`, `wiki_code_search`, `wiki_code_context`,
`wiki_code_index`, `wiki_code_refresh_links`, and the four `wiki_code_publish_*`), the
three domain-grant tools, and the three specification tools. Some are covered by
`docs/code-graph.md` and `docs/specifications.md`, but an agent reading the reference
alone concludes those tools do not exist. Every registered tool gets a row in the
reference table; a tool with a dedicated page gets a one-line summary there plus a link to
that page, rather than a duplicated description that would drift.

`wiki_code_refresh_links` is the sharpest case: it is registered in `server.py`, described
in `docs/code-graph-publishing.md`, absent from `docs/tools-reference.md`, absent from the
iclaude rules entirely, and present in icodex only inside the generated instruction region.
An agent that cannot see it re-publishes a whole snapshot to fix stale links.

The reference lives in the `iwiki-mcp` repository, so this requirement is delivered by its
own pull request there, not by this one. The wiki pages describing agent tool usage are
updated directly through the MCP tools in the domain that owns them — the wiki has no pull
request.

### R10 — Follow-up work lands as its own pull request per project

The rule and instruction changes for the newly documented tools are separate pull
requests: one in `icodex` for the generated agent instructions, one in `iclaude` for its
rule file, and one in `iwiki-mcp` for R9's reference. None is part of this change. This
one is about the transport; those are about what agents are told the tools are. Keeping
them apart keeps each reviewable and each revertable.

Three repositories are therefore in play. This pull request changes only `icodex`
wiring, its tests, and its own docs.

### R11 — Roll out after merge

Merging is not delivery. After this change and the already-merged server change reach
master:

1. Install the new local server version from the checkout, so stdio sessions run it.
2. Rebuild and deploy the hosted server on the `framework` host, following
   `docs/deployment.md` in the iwiki-mcp repository.
3. Verify: a hosted `initialize` answers 200, the container reports `healthy`, and an
   icodex session reaches both transports.

The deployed image currently reports 0.7.286 against 0.7.288 in master, so the hosted
server does not yet carry the idle-timeout default.

## 5. Error handling

| Situation | Behaviour |
|---|---|
| Remote URL set, token unresolved | Skip the remote block, keep a complete local one as `iwiki`, log a warning |
| Local set incomplete, remote resolves | Skip the local block, no warning (R5) |
| Local set incomplete, no remote | Skip the local block, log a warning, as today |
| Neither resolves | No region, return 0 |
| `ICODEX_HOME_DIR` unset or `config.toml` absent | No-op, return 0 |

## 6. Testing

The 61 existing assertions in `tests/test_iwiki_wiring.sh` are unchanged. The remote case
there unsets the local variables, so no local block appears in it and its "remote has no
stdio command" assertions stay true.

New cases:

1. **Dual.** Remote and local both configured: the region holds both blocks,
   `[mcp_servers.iwiki]` carries `url`, `[mcp_servers.iwiki-local]` carries `command`, and
   neither secret appears literally.
2. **Dual to remote-only.** Rerunning with the local variables unset leaves no
   `[mcp_servers.iwiki-local]` — the R3 regression test.
3. **Remote without a token, local complete.** Exactly one stdio server, named `iwiki`.
4. **Dual idempotency.** A second run is byte-identical.
5. **Hook matchers.** `mcp__iwiki-local__wiki_update_page` in PreToolUse and
   `mcp__iwiki-local__wiki_status` in PostToolUse.

Startup cost is measured separately against the intent's health metric: wall clock from
launch to a usable session, three runs before and three after, threshold three seconds.

## 7. Out of scope

- Renaming the remote server. Forbidden by a hard constraint.
- Replacing the text-region mechanism with a TOML parser.
- Reconciling the local Git base with hosted PostgreSQL. The outage path records what it
  wrote; merging the two stores is its own task.
- The content of the follow-up rule changes in icodex and iclaude (R10) beyond requiring
  that they happen separately.

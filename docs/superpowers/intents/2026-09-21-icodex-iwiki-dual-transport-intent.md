# Intent: icodex-iwiki-dual-transport

**Date:** 2026-09-21
**Status:** approved

## Objective

`ensure_iwiki_wiring` registers exactly one iwiki transport per launch: when
`ICODEX_IWIKI_REMOTE_URL` is set, the remote HTTPS server replaces the managed local stdio
server outright. `iwiki-mcp-integration#Required Settings` states that rule as the
contract, and `docs/iwiki-mcp-modes.md` repeats it.

Two consequences have now been observed rather than predicted. First, `wiki_code_index`
answers `source_unavailable` on a hosted server and no local server exists to run it, so
the code graph cannot be rebuilt from an icodex session at all: `wiki_code_status` for the
`icodex` domain reports `fresh: false`, `error: "stale_snapshot"`, `age_seconds: 1327089`
— roughly fifteen days against a one-day limit — with `wiki_links_stale: true`. Second,
during the hosted outage of 2026-09-20 an icodex launch had no wiki whatsoever, failing at
`initialize` with `HTTP 502`, while iclaude kept working through the local half of its dual
registration.

Both settings needed for a local server are already present in `.codex_config`
(`ICODEX_IWIKI_COMMAND`, `ICODEX_IWIKI_BASE_DIR`, `ICODEX_IWIKI_LLM_BASE_URL`,
`ICODEX_IWIKI_LLM_KEY`), so the gap is in the wiring logic, not in the configuration.

Register the local stdio server **in addition to** the remote one when its settings
resolve, keeping the remote server under its existing name.

## Desired Outcomes

- `wiki_code_index` is callable from an icodex session, and after it runs
  `wiki_code_status` for the `icodex` domain answers `fresh: true` instead of
  `stale_snapshot`.
- When the remote endpoint is unreachable, an icodex launch still comes up with a working
  local iwiki server instead of no iwiki at all.
- Existing tool names keep working: `mcp__iwiki__*` still resolves, the GWT hook still
  matches `mcp__iwiki__wiki_update_page`, and the instructions already generated into
  AGENTS.md remain true.
- The division of roles is explicit to the agent: the local server is for code-graph work
  only, while every Markdown and specification call goes to the remote server. The two
  transports address different stores — a local Git base against hosted PostgreSQL — so an
  unstated split would silently write pages to the wrong one.

## Health Metrics

- No secret reaches `config.toml`. The bearer token and the LLM key stay in
  `env_vars` / `bearer_token_env_var`, never written literally.
- `tests/test_iwiki_wiring.sh` (61), `tests/test_iwiki_binding.sh` (14),
  `tests/test_iwiki_remote_scope.sh` (44), and `tests/test_iwiki_agent_contract.sh` (147)
  keep passing with no failures.
- Codex startup time does not visibly regress. A second stdio server runs its own
  embedding probe at launch, so the cost is real and must be measured rather than assumed.
- No page or scenario lands in the local Git base by accident. Wiki writes continue to
  reach hosted PostgreSQL.

## Strategic Context

- Interacts with: `lib/iwiki/iwiki.sh` (`ensure_iwiki_wiring`, `_iwiki_region_body`,
  `_iwiki_strip_existing_wiring`, `ensure_iwiki_gwt_hook`,
  `ensure_iwiki_remote_scope_instructions`), the generated `config.toml` region in each
  Codex home, the generated `iwiki-remote-scope` region in AGENTS.md, `hooks/gwt-gate.py`
  through its matchers, the four iwiki test suites, `docs/iwiki-mcp-modes.md` and
  `iwiki-mcp-integration` in the wiki, plus the iwiki-mcp server itself with its hosted
  PostgreSQL store and the local Git base at `iwiki-personal`.
- Priority trade-off: trust. Not breaking what works, and never writing to the wrong
  store, outrank both delivery speed and implementation economy.

## Constraints

### Steering (behavioral guidance)

- Follow the existing region mechanism rather than inventing a second one: strip, then
  rewrite, and stay idempotent.
- Prefer adding test cases over rewriting the ones that pass today.
- Keep the generated instruction short enough to stay readable next to the existing
  remote-scope block.

### Hard (architectural enforcement)

- The remote server keeps the name `[mcp_servers.iwiki]`. Renaming it is forbidden — the
  GWT hook matchers and the generated instructions depend on that name.
- A launch never fails because of iwiki. Unresolved local settings log a warning and skip
  the local block, exactly as today.
- Secrets are passed only through `env_vars` and `bearer_token_env_var`; never literal in
  TOML.
- While the remote transport is active, the local server is for code-graph calls only. The
  generated instruction must say so, and Markdown or specification calls must not be
  directed at it.

## Autonomy Zones

- Full autonomy (reversible, low risk): the wiring logic in `lib/iwiki/iwiki.sh`, new test
  cases, `docs/iwiki-mcp-modes.md`, and the wiki pages describing the mode.
- Guarded (log + confidence threshold): the shape of the generated `config.toml` region,
  as long as the remote block and its name are unchanged.
- Proposal-first (needs approval): editing any test that passes today, and editing the
  generated AGENTS.md instruction region.
- No autonomy (human only): `.codex_config`, which is untracked and belongs to the user.

> These zones OVERRIDE subagent-driven-development's "continuous execution,
> don't pause" default. Any task touching proposal-first / no-go decisions
> is marked HUMAN CHECKPOINT in the plan.

## Stop Rules

- Halt if: making the local server available requires renaming the remote one, or requires
  a change that would let a Markdown write reach the local Git base.
- Halt if: a test that passes today has to change for the new behaviour to pass — surface
  it and wait, per the autonomy zones.
- Escalate if: registering the second server measurably slows Codex startup, or the local
  server's embedding probe makes a launch hang.
- Done when: from an icodex session, `wiki_code_index` runs and `wiki_code_status` for the
  `icodex` domain reports `fresh: true` with `wiki_links_stale: false`; a launch with the
  remote endpoint unreachable still exposes a working local iwiki server; all four iwiki
  test suites pass with no failures; and no secret appears in the generated `config.toml`.

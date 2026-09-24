---
review:
  intent_hash: 5b3565f74aa25e99
  last_run: 2026-09-24
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings:
    - id: F-001
      phase: alignment
      severity: WARNING
      section: Constraints
      section_hash: 25821a94f28dff08
      fragment: "The hosted server is named `[mcp_servers.iwiki-remote]`"
      text: "The current iwiki integration page and dual-transport specification still preserve the remote name `iwiki`."
      fix: "Update the active wiki documentation and specification with the approved naming contract before result closure."
      verdict: accepted
      verdict_at: 2026-09-24
workflow:
  route: chain
  continuation: execute
result_check:
  verdict: OK
  source: intent
  intent_hash: 5b3565f74aa25e99
  last_run: 2026-09-24
  reviewed: true
  docs_checked: true
supersedes:
  - docs/superpowers/intents/2026-09-21-icodex-iwiki-dual-transport-intent.md#constraints
---

# Intent: iwiki-remote-server-name

**Date:** 2026-09-24
**Status:** approved

## Objective

Give the local and remote iwiki MCP servers unambiguous names. The dual-transport
configuration currently exposes the hosted server as `iwiki` and the local server as
`iwiki-local`; the generic remote name makes transport identity unclear to users and
agents. Rename the hosted server to `iwiki-remote` now so both names state their transport
directly.

This intent supersedes only the earlier dual-transport constraint that required the remote
server to keep the name `iwiki`. The remaining dual-transport behavior and store-routing
rules continue to apply.

## Desired Outcomes

- A dual-transport configuration exposes exactly `iwiki-local` and `iwiki-remote`.
- The legacy remote registration `[mcp_servers.iwiki]` is absent after managed wiring is
  regenerated.
- Both MCP servers initialize successfully and their tools remain callable.

## Health Metrics

- Local and remote MCP availability does not regress: initialization succeeds and a tool
  call through each configured server returns a valid response.
- Existing iwiki wiring, binding, remote-scope, and agent-contract tests pass with no
  failures.
- No secret is written literally to generated TOML, and unmanaged user configuration is
  unchanged.

## Strategic Context

- Interacts with: `lib/iwiki/iwiki.sh`, generated Codex `config.toml`, GWT hook matchers,
  generated remote-scope instructions, iwiki wiring tests, active iwiki documentation,
  and agents that select tools by MCP namespace.
- Priority trade-off: trust. Reliable MCP availability and correct tool routing outrank
  delivery speed and implementation cost.

## Constraints

### Steering (behavioral guidance)

- Preserve the existing managed-region, strip-then-rewrite, idempotent wiring approach.
- Keep the rename surgical: change transport identity and dependent matchers,
  documentation, and tests without altering unrelated iwiki behavior.
- Retain explicit instructions that Markdown and specification calls use the hosted
  server while local code-graph calls use the local server in dual mode.

### Hard (architectural enforcement)

- The hosted server is named `[mcp_servers.iwiki-remote]`; the local server in dual mode
  remains `[mcp_servers.iwiki-local]`.
- Managed legacy remote blocks named `[mcp_servers.iwiki]` are migrated automatically;
  unmanaged settings and secrets are not overwritten or exposed.
- Hook and generated-instruction tool namespaces must match Codex normalization for the
  hyphenated server names.
- Both MCP servers and their tools remain available after the rename.

## Autonomy Zones

- Full autonomy (reversible, low risk): implementation, focused tests, active
  documentation, and migration of managed generated blocks within the approved names.
- Guarded (log + confidence threshold): compatibility verification for hook matchers,
  normalized tool namespaces, and real local and remote MCP connections.
- Proposal-first (needs approval): selecting different server names, preserving a legacy
  alias, or expanding scope beyond the naming migration.
- No autonomy (human only): modifying credentials, tokens, or untracked user-owned
  configuration values.

> These zones OVERRIDE subagent-driven-development's "continuous execution,
> don't pause" default. Any task touching proposal-first / no-go decisions
> is marked HUMAN CHECKPOINT in the plan.

## Stop Rules

- Halt if: the rename makes either MCP server or any required tool unavailable.
- Halt if: migration would overwrite unmanaged user configuration or expose a secret.
- Escalate if: Codex tool-name normalization differs from the expected
  `mcp__iwiki_remote__*` or `mcp__iwiki_local__*` namespaces.
- Done when: dual mode exposes `iwiki-local` and `iwiki-remote`, exposes no legacy remote
  `iwiki` registration, a tool call succeeds through each server, and all relevant tests
  pass with no failures.

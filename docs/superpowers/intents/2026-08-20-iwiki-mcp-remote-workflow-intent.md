---
review:
  intent_hash: 6a754d4406d51e26
  last_run: 2026-08-20
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
workflow:
  route: chain
  continuation: execute
---

# Intent: iwiki-mcp-remote-workflow

**Date:** 2026-08-20
**Status:** approved

## Objective

Align icodex skills, rules, and hooks with the current iwiki-mcp API and make remote streamable-HTTP MCP operation safe and consistent, using iclaude as a behavioral reference.

## Desired Outcomes

- icodex correctly operates with remote streamable-HTTP MCP and the complete scope declared in `.iwiki.toml`.
- Skills, AGENTS rules, and hooks use current MCP tools and PostgreSQL revision/section-hash semantics where required.
- Focused Bash tests cover the remote scope and fail-closed behavior.
- Local stdio configuration retains current behavior.

## Health Metrics

- Server grants remain the final authorization boundary.
- Secrets are absent from command output and generated instructions.
- Existing Bash tests and local stdio configuration do not regress.

## Strategic Context

- Interacts with: `lib/iwiki/iwiki.sh`, generated `.codex-isolated/AGENTS.md`, skills, hooks, `.iwiki.toml`, tests, remote `iwiki-mcp`, and `iclaude` reference behavior.
- Priority trade-off: authorization correctness and trust over speed or convenience.

## Constraints

### Steering (behavioral guidance)

- Keep changes minimal and dependency-free.
- Use iclaude only as a behavioral reference verified against the current MCP API.
- Preserve local stdio behavior.

### Hard (architectural enforcement)

- Do not modify iwiki-mcp, server grants, tokens, or credentials.
- Bind the complete normalized scope from `.iwiki.toml` before any wiki operation.
- On missing, invalid, or rejected scope, fail closed: make no wiki writes and retain `completion-pending`.

## Autonomy Zones

- Full autonomy (reversible, low risk): update icodex skills, rules, hooks, documentation, and tests.
- Guarded (log + confidence threshold): transfer iclaude patterns only after verifying them against the current MCP API and focused tests.
- Proposal-first (needs approval): modify public remote-server semantics.
- No autonomy (human only): change grants, tokens, credentials, or iwiki-mcp.

## Stop Rules

- Halt if: compatibility requires a server-side iwiki-mcp change.
- Escalate if: iclaude contradicts the actual MCP API or required tests conflict.
- Done when: focused and full Bash suites pass, and rules and hooks are verified for remote scope plus fail-closed behavior.

---
review:
  intent_hash: 9d9683782d34f38b
  last_run: 2026-08-14
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
result_check:
  verdict: OK
  source: intent
  intent_hash: 9d9683782d34f38b
  last_run: 2026-08-14
---
# Intent: remote-iwiki-project-scope

**Date:** 2026-08-14
**Status:** approved

## Objective

In remote iwiki MCP mode, preserve each project's declared cross-domain scope by loading `.iwiki.toml` and binding that complete scope before task-specific wiki work. This prevents an agent from narrowing a session to only the primary/current project domain and losing access to allowed cross-domain records.

## Desired Outcomes

- Remote mode reads project-root `.iwiki.toml` fields `read`, `write`, and `primary`, normalizes only domain names, and calls `wiki_bind` with the complete declared scope before `wiki_status`, searches, task-ledger activity, or other wiki operations.
- A configured secondary write domain, such as `devops`, is usable without a manual agent bind when its grant allows it.
- A missing, invalid, or unauthorized scope fails closed: no heuristic expansion or mutating wiki call occurs and task lifecycle remains `completion-pending`.
- Primary-only configuration retains existing behavior.
- Generated agent instructions and documentation distinguish remote HTTP scope loading from local stdio behavior.

## Health Metrics

- Server grants remain the absolute authorization limit; no client scope can broaden them.
- Secrets, tokens, project paths, `iwiki_id`, and raw TOML contents do not appear in generated configuration, logs, or errors.
- Existing non-remote iwiki wiring and full Bash suite remain passing.

## Strategic Context

- Interacts with: `lib/iwiki/iwiki.sh`, generated agent instructions and iwiki skill content, `.iwiki.toml`, remote streamable HTTP MCP, Bash tests, and iwiki documentation.
- Priority trade-off: authorization correctness and fail-closed behavior over convenience.

## Constraints

### Steering (behavioral guidance)

- Keep scope parsing and wiring minimal and dependency-free.
- Preserve existing stdio behavior unless remote mode is explicitly configured.

### Hard (architectural enforcement)

- Do not modify `iwiki-mcp`; its grants are authoritative and cannot be bypassed.
- Never replace TOML scope with a project-basename or primary-only heuristic.
- Pass only normalized domain names to `wiki_bind`.
- On absent, invalid, or rejected TOML scope, do not issue mutating wiki calls and retain `completion-pending`.

## Autonomy Zones

- Full autonomy (reversible, low risk): change `icodex` Bash wiring, generated instructions, project documentation, and tests.
- Guarded (log + confidence threshold): choose parsing and generated-instruction insertion points only with focused regression tests.
- Proposal-first (needs approval): change remote server authorization semantics or scope grants.
- No autonomy (human only): modify `iwiki-mcp`, grants, tokens, or credentials.

## Stop Rules

- Halt if: satisfying the client-side flow requires a server-side `iwiki-mcp` change.
- Escalate if: existing generated instructions have no unambiguous remote-only injection point or tests show a conflict with server-authorized scope.
- Done when: focused tests prove complete normalized TOML scope is bound first, a missing grant produces no fallback write, primary-only behavior remains intact, no sensitive values are emitted, and the full Bash suite passes.

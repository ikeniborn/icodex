---
review:
  intent_hash: f9658846673f848e
  last_run: 2026-09-01
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
workflow:
  route: chain
  continuation: full
---

# Intent: iwiki-mcp-tooling-alignment

**Date:** 2026-09-01
**Status:** approved

## Objective

Update the agent-facing information in icodex after the iwiki-mcp upgrade. Treat the
live callable tool schemas and observed server behavior as the source of truth, then
align every applicable skill, instruction, rule, hook, and verification surface so
agents use the current server contract accurately.

## Desired Outcomes

- Agents select the current iwiki tool for Markdown read/write, specification,
  task-ledger, code-graph, binding, publication, discovery, and management intents.
- Agent-facing guidance uses current parameters and preserves the distinctions between
  local stdio and hosted HTTP, and between Git and PostgreSQL storage.
- Full project binding, PostgreSQL compare-and-swap, specification-mode, authorization,
  and fail-closed task lifecycle guarantees remain explicit and correct.
- Deprecated tools, parameters, assumptions, and routes are removed or marked as
  unsupported; hooks and focused tests reject mechanically detectable regressions.

## Health Metrics

- Existing task-ledger, chain, GWT, code-graph, and ordinary Wiki workflows remain
  usable.
- Every documented storage and transport branch matches a supported live server path.
- Authorization, optimistic concurrency, specification-mode, and lifecycle safeguards
  are not weakened.
- Accuracy and agent trust take priority over compactness or execution speed.

## Strategic Context

- Interacts with: isolated agent instructions, reusable skills, generated project-scope
  instructions, hooks, tests, iwiki-mcp Markdown and specification tools, code-graph
  read/publication tools, and hosted domain-authority tools.
- Priority trade-off: trust and accuracy first; speed and compactness are secondary.

## Constraints

### Steering (behavioral guidance)

- Prefer the smallest instruction or hook change that maps a demonstrated live contract.
- Keep tool selection intent-based and state the required storage, transport,
  authorization, and freshness preconditions near each operation.
- Preserve ordinary Wiki work when optional code-graph or specification projection
  context is unavailable.
- Verify affected agent surfaces with focused contract tests before the full suite.

### Hard (architectural enforcement)

- Load the full normalized project `.iwiki.toml` `read`, `write`, and `primary` scope
  before any Wiki call; pass project specification mode only where hosted `wiki_bind`
  accepts it, then verify the effective server-reported mode.
- Treat live callable schemas and observed server responses as the source of truth.
- Preserve PostgreSQL revision and section compare-and-swap, GWT context ordering,
  task-ledger durability, authorization boundaries, and fail-closed lifecycle behavior.
- Preserve all supported local/hosted and Git/PostgreSQL branches; do not route agents
  through legacy plugin skills or the `iwiki_engine` CLI.
- Do not expose secrets, mutate production state, or expand domain grants.

## Autonomy Zones

- Full autonomy (reversible, low risk): read-only server and repository discovery,
  isolated branch edits, local tests, and documentation consistency checks.
- Guarded (log + confidence threshold): authorized compare-and-swap updates to icodex
  Wiki documentation and task-ledger pages, followed by lint.
- Proposal-first (needs approval): remove a supported workflow, change a public agent
  contract, or weaken an enforcement hook.
- No autonomy (human only): expose credentials, mutate production services, or expand
  hosted domain grants.

> These zones OVERRIDE subagent-driven-development's "continuous execution,
> don't pause" default. Any task touching proposal-first / no-go decisions
> is marked HUMAN CHECKPOINT in the plan.

## Stop Rules

- Halt if: a live tool schema contradicts observed server behavior, or the active
  storage, transport, binding, or authorization state cannot be determined safely.
- Escalate if: alignment would require deleting a supported workflow, changing a public
  contract, or weakening an authorization, concurrency, specification, or lifecycle
  safeguard.
- Done when: every affected icodex agent surface matches the live iwiki-mcp contract;
  deprecated calls and assumptions are absent; focused and full validations pass;
  icodex Wiki/task documentation is current; and `wiki_lint` has no new blocking
  finding.

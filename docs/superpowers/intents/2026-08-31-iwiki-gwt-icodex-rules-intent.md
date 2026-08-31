---
review:
  intent_hash: 6e2a8d76ca6245a3
  last_run: 2026-08-31
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

# Intent: iwiki-gwt-icodex-rules

**Date:** 2026-08-31
**Status:** approved

## Objective

Give the isolated iCodex agent an authoritative workflow for iwiki Given-When-Then
specifications. The current agent policy covers ordinary Wiki pages, task-ledger,
code-graph use, skills, and hooks, but does not define when GWT scenarios apply or how
agents and hooks maintain them. This gap can cause missing specifications, guessed
bindings, or inappropriate workflow blocks.

## Desired Outcomes

- The iCodex agent distinguishes behavior that needs a GWT scenario from formatting,
  ordinary Wiki maintenance, and mechanical refactoring that does not change behavior.
- Before changing an existing scenario, the agent calls `wiki_spec_context`, preserves
  its stable scenario ID while the observable contract is unchanged, and treats the
  scenario, executable test, bindings, and verification evidence as one unit.
- After relevant changes, the agent runs focused and regression tests and calls
  `wiki_spec_resolve` when a ready code graph exists.
- A missing, stale, failed, or unreachable code graph remains fail-soft: the agent keeps
  declared selectors, uses repository search, runs executable tests, and records the
  unavailable resolution state without blocking ordinary Wiki work.
- Hooks enforce applicable ordering and policy boundaries without writing to Wiki or
  replacing interactive MCP calls.

## Health Metrics

- Ordinary Wiki pages and tasks without explicit GWT specifications acquire no new
  mandatory steps or blocking findings.
- The documented `disabled`, `optional`, and `strict` mode semantics remain unchanged.
- Existing `direct`, `chain`, and `loen` workflow tests gain no unrelated blocking path.
- No hook performs a mutating Wiki operation.
- Focused AGENTS, skill, hook, and relevant regression checks pass before completion.

## Strategic Context

- Interacts with: the isolated iCodex agent, available-skill catalog, hooks, iwiki MCP,
  task-ledger, executable tests, and the optional code graph.
- Priority trade-off: trust first; exact GWT policy and verifiable evidence take
  precedence over speed and cost.

## Constraints

### Steering (behavioral guidance)

- Use a GWT scenario for new observable domain behavior, a public contract, a bug
  reproduction, or a business invariant.
- Do not require a GWT scenario for formatting, ordinary Wiki maintenance, or mechanical
  refactoring with unchanged behavior.
- Maintain the scenario, executable test, implementation and verification bindings, and
  recorded evidence as one coherent unit.
- Limit repository changes to `.codex-isolated/AGENTS.md` unless verification identifies
  a concrete contradiction in an existing skill or hook.

### Hard (architectural enforcement)

- Use only the supported semantic tools: `wiki_spec_search`, `wiki_spec_context`, and
  `wiki_spec_resolve`.
- Call `wiki_spec_context` before changing an existing scenario.
- Preserve a stable scenario ID unless the observable behavioral contract changes.
- Treat graph absence, staleness, failure, and remote source unavailability as fail-soft.
- Hooks must not write to Wiki or replace MCP tool calls owned by the interactive parent.
- Agents and `wiki_bind` must not override the configured `disabled`, `optional`, or
  `strict` specification policy.

## Autonomy Zones

- Full autonomy (reversible, low risk): search and read GWT context, inspect declared
  selectors, run tests, and update bindings within the approved scope.
- Guarded (log + confidence threshold): create or change a scenario for explicit
  observable behavior, record verification evidence, and check lint and resolution
  findings.
- Proposal-first (needs approval): change a stable scenario ID, observable behavioral
  contract, specification mode, or task scope beyond the target agent policy.
- No autonomy (human only): bypass authorization, weaken strict findings, or give hooks
  authority to perform mutating Wiki calls.

> These zones OVERRIDE subagent-driven-development's "continuous execution,
> don't pause" default. Any task touching proposal-first / no-go decisions
> is marked HUMAN CHECKPOINT in the plan.

## Stop Rules

- Halt if: project binding or authorization is rejected, the scenario contract is
  contradictory, or a required executable test fails.
- Escalate if: available evidence cannot determine whether the observable contract
  changed, or a binding remains ambiguous after context and repository inspection.
- Done when: `.codex-isolated/AGENTS.md` unambiguously defines the GWT workflow and the
  boundary between skills, hooks, and MCP tools; focused and relevant regression checks
  pass; required iwiki documentation is current; and `wiki_lint` reports no new blocking
  finding.

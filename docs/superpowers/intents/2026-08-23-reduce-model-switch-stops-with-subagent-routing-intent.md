---
review:
  intent_hash: 0047d99c687c84f6
  last_run: 2026-08-23
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

# Intent: reduce-model-switch-stops-with-subagent-routing

**Date:** 2026-08-23
**Status:** approved

## Objective

Remove mandatory parent-session stops for `/status`, `/model`, and model downgrade or
escalation confirmation. The parent continues on its active model while task-specific
cost and capability routing happens primarily through delegated agents with explicit
model and reasoning-effort assignments.

The current interactive gate slows each workflow transition and shifts routine
orchestration onto the user. This intent supersedes the interactive stop behavior in the
model-routing policy while preserving explicit human control for risky or externally
visible actions and preserving validated orchestrated profile handoffs.

## Desired Outcomes

- Parent work does not stop for `/status`, `/model`, or confirmation of model downgrade
  or escalation recommendations.
- Eligible bounded independent subtasks use delegated agents with an explicitly selected
  semantic route, model, and reasoning effort.
- Simple work remains in the parent when delegation would cost more than execution.
- Risky actions and product or workflow decisions still require user confirmation at
  their established authority boundaries.

## Health Metrics

- The full existing test suite and new focused routing tests pass before completion.
- Every completion claim retains required verification evidence, and existing intent,
  spec, plan, and result gate tests remain green.
- Focused routing tests assign no strong child model to a mechanical subtask without an
  evidenced higher-route trigger.
- Focused routing tests keep representative single-step work in the parent instead of
  spawning a delegated agent.
- Policy and focused tests grant delegated agents no authority beyond the parent and the
  user request.

## Strategic Context

- Interacts with: parent agents, delegated agents, the model catalog, `spawn_agent`,
  workflow and check-chain gates, task-ledger ownership, profile routing, and user
  confirmation boundaries.
- Priority trade-off: speed first, trust and quality as a hard floor, then cost optimized
  through delegated-agent model selection.

## Constraints

### Steering (behavioral guidance)

- Keep parent model recommendations informational and non-blocking; continue on the
  active parent model.
- Delegate a bounded independent subtask only when the expected gain exceeds coordination
  cost.
- Select the lowest sufficient semantic route, model, and reasoning effort independently
  for each delegated subtask.
- Reuse a suitable delegated agent for related follow-up work when scope and evidence
  still match its assignment.

### Hard (architectural enforcement)

- Delegation must not bypass user confirmation for destructive, risky, or external
  actions.
- Delegated agents receive no additional authority and must not revise accepted intent,
  spec, or plan artifacts.
- The parent remains the sole task-ledger writer and consolidates delegated results.
- Do not run conflicting writes against the same files, and respect available concurrency
  limits.
- Unavailable preferred child models must not block safe parent work.
- Preserve validated orchestrated profile handoff behavior; remove only interactive
  parent-session model-switch stops.

## Autonomy Zones

- Full autonomy (reversible, low risk): select delegated-agent route, model, and effort;
  perform read-only discovery and tests; reuse an agent for a matching follow-up.
- Guarded (log + confidence threshold): delegate implementation with explicit file
  ownership, then have the parent review its diff and verification evidence.
- Proposal-first (needs approval): expand task scope, revise accepted intent/spec/plan,
  or perform actions with material external effects.
- No autonomy (human only): perform destructive or external actions outside the request,
  or grant a delegated agent broader authority than the parent.

> These zones OVERRIDE subagent-driven-development's "continuous execution,
> don't pause" default. Any task touching proposal-first / no-go decisions
> is marked HUMAN CHECKPOINT in the plan.

## Stop Rules

- Halt if: delegated file ownership conflicts, required user authority is absent, or an
  action risks irreversible effects.
- Escalate if: two different delegated-agent strategies fail on the same problem, or a
  critical security, migration, transaction, concurrency, or data-integrity invariant is
  discovered.
- Done when: parent flow requires no model/status stops; eligible subtasks receive an
  explicit child model and effort; simple work stays in the parent; policy, hooks, docs,
  and tests agree; and all required checks pass.

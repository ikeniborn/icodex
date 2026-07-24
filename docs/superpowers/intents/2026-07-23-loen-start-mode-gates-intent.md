---
review:
  intent_hash: c860c176e868b636
  last_run: 2026-07-23
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
---

# Intent: loen-start-mode-gates

**Date:** 2026-07-23
**Status:** approved

## Objective

Restore trust in `loop-start` by treating accidental execution without an informed mode choice and shallow topic development before planning as one workflow defect. The start flow must make the user's decisions explicit and prevent execution until each required checkpoint has been confirmed.

Close the implementation-review blockers that can silently weaken that trust after delivery: canonical policy values must hash exactly as documented, malformed duplicate authority fields must fail closed, audit decisions must always be timestamped, and project-specific validation-first Superpowers gates must survive deterministic re-vendoring and cache upgrades.

## Desired Outcomes

- `loop-start` requires separate confirmation of goal and context before generating a plan.
- The user explicitly selects the launch principle and, where applicable, its subtype before the plan can be approved.
- Plan approval and launch authorization are separate user decisions.
- `loop-run` cannot start unless all required confirmations are present and current.
- Missing, stale, contradictory, or legacy confirmation state produces a clear refusal and recovery path.
- Canonical policy hashes preserve JSON null semantics and reject ambiguous duplicate authority fields.
- Every checkpoint audit event carries a validated UTC timestamp.
- Re-vendoring or upgrading Superpowers preserves the icodex validation-first spec/plan gates and selects exactly the configured cache version.
- Chain task status and machine-readable `result_check` remain consistent.

## Health Metrics

- No execution path bypasses goal/context confirmation, mode selection, plan approval, or launch confirmation.
- Existing scope, verifier, budget, rollback, plan-hash, and governance-policy checks remain enforced.
- Reliability and user trust take priority over dialogue length; a longer start dialogue is acceptable.
- Non-execution work such as reading context and preparing drafts remains available before approval.
- The full repository test suite remains green after re-vendor simulation and runtime hardening.
- Upstream Superpowers content outside the project overlay remains unchanged.

## Strategic Context

- Interacts with: `loop-start`, `loop-plan`, the `loop.yaml` runtime contract, `loop-run` preflight, contract tests, LoEn templates, Superpowers vendoring and runtime wiring, `check-chain`, and human operators.
- Priority trade-off: trust > speed > cost.

## Constraints

### Steering (behavioral guidance)

- Present each checkpoint as a distinct decision with its current evidence summarized for the user.
- Do not ask users to re-enter information already collected; ask them to review, correct, or confirm it.
- Refusal messages must identify the failed checkpoint and the action needed to recover.
- Topic development must expose ambiguity, constraints, success criteria, scope, verification, and rollback before planning.
- Keep project-specific Superpowers changes explicit, reviewable, and replayable instead of relying on hand-edited generated cache state.

### Hard (architectural enforcement)

- Enforce checkpoints in all four layers: skill instructions, `loop.yaml`, `loop-run` preflight, and contract tests.
- Require checkpoints in this order: goal/context confirmation, mode/subtype selection, plan approval, launch confirmation.
- Keep plan approval distinct from launch confirmation; one cannot imply the other.
- Do not infer mode, subtype, approval, or launch authorization from defaults or prior conversational context.
- Treat legacy contracts without the new confirmation state as invalid; require explicit renewal through `loop-start`.
- Do not enable execution while any confirmation is missing, stale, or contradictory.
- Parse YAML null as a null value for canonical policy hashing; do not normalize it into the string `"null"`.
- Reject duplicate canonical authority keys instead of accepting first- or last-value wins.
- Require each checkpoint event to have a valid UTC RFC3339 timestamp.
- Apply the icodex Superpowers overlay fail-closed during vendoring and select the configured cache deterministically at runtime.
- Keep one canonical topic in this branch; the expanded chain must cover both LoEn runtime hardening and the IDD vendor-overlay follow-up.

## Autonomy Zones

- Full autonomy (reversible, low risk): read project context, collect facts, identify ambiguities, and prepare draft goal, context, and plan artifacts.
- Guarded (log + confidence threshold): validate completeness, hashes, scope, verifier, budget, rollback, governance policy, event timestamps, overlay application, and cache selection.
- Proposal-first (needs approval): finalize goal/context, select mode/subtype, and approve the plan.
- No autonomy (human only): authorize the actual `loop-run` launch.

> These zones OVERRIDE subagent-driven-development's "continuous execution,
> don't pause" default. Any task touching proposal-first / no-go decisions
> is marked HUMAN CHECKPOINT in the plan.

## Stop Rules

- Halt if: any required confirmation is missing, stale, contradictory, out of order, or absent from a legacy contract.
- Halt if: a canonical policy field is duplicated, a checkpoint event lacks a valid timestamp, an overlay cannot apply cleanly, or cache selection is ambiguous.
- Escalate if: goal/context remains ambiguous, requested mode conflicts with policy, required execution controls cannot be represented by the runtime contract, or an upstream Superpowers update conflicts with the project overlay.
- Done when: negative scenarios prove `loop-run` cannot start without all four ordered checkpoints, canonical policy fixtures match independent JSON vectors, duplicate authority fields and invalid timestamps fail closed, re-vendor/upgrade simulations preserve validation-first gates and select the configured cache, the full suite passes, and `result_check` agrees with `docs/TODO.md`.

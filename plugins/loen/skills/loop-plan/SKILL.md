---
name: loop-plan
description: Use when an existing LoEn topic needs its bounded plan replaced.
---

# LoEn Loop Plan

This skill is for existing topic replan only. New topics must use `loen:loop-start`.

## Procedure

1. Resolve and validate the topic slug, then require existing `1_goal.md`, `2_context.md`, and `loop.yaml`.
2. UPSTREAM VALIDATION: Validate confirmed goal_context hashes against current `1_goal.md` and `2_context.md`, then validate confirmed explicit mode and subtype. Validate the goal/context and mode checkpoints without inference. Stop on any missing, stale, unconfirmed, or inferred upstream field.
3. PLAN REGENERATION: Regenerate the complete candidate plan in memory from only those validated upstream inputs; do not write it yet.
4. PLAN INVALIDATION: Before writing changed `3_plan.md`, reset plan and launch and append one reset event for each. Reset the plan checkpoint and reset the launch checkpoint. Append a reset event for each reset checkpoint. Clear both confirmations and hashes, then write the candidate plan.
5. Keep one bounded pass with preconditions, steps, success-criterion mapping, exact checks and evidence, risks, rollback or recovery, and terminal condition.
6. PLAN APPROVAL REQUEST: Present the complete plan. Obtain separate explicit plan approval; refusal or ambiguity leaves plan unconfirmed and stops.
7. PLAN RESTORATION: Explicit approval restores plan only; launch remains unconfirmed. Hash the approved plan and append its plan confirmation event.

Never confirm launch or invoke `loen:loop-run`.

PROHIBITION: MUST NOT write `checkpoints.launch.confirmed: true`.

PROHIBITION: MUST NOT invoke `loen:loop-run`.

## Output

Report topic, changed plan, checks, plan hash, and approval state.

---
name: loop-plan
description: Use when an existing LoEn topic needs its bounded plan replaced.
---

# LoEn Loop Plan

This skill is for existing topic replan only. New topics must use `loen:loop-start`.

## Procedure

1. Resolve and validate the topic slug, then require existing `1_goal.md`, `2_context.md`, and `loop.yaml`.
2. Validate the goal/context and mode checkpoints, including current artifact hashes and a valid explicit mode/subtype. Stop on any missing, stale, or unconfirmed upstream field.
3. Reset the plan checkpoint and reset the launch checkpoint before changing `3_plan.md`. Clear their stored hashes and confirmations.
4. Append a reset event for each reset checkpoint to `attempts.jsonl`, including prior hashes, mode/subtype, outcome, and timestamp.
5. Rewrite `3_plan.md` from the fixed template using only confirmed upstream inputs. Keep one bounded pass with preconditions, steps, success-criterion mapping, exact checks and evidence, risks, rollback or recovery, and terminal condition.
6. Present the complete plan. Obtain separate explicit plan approval; refusal or ambiguity leaves plan unconfirmed and stops.
7. Hash the approved plan, confirm only the plan checkpoint, and append its confirmation event. Keep launch unconfirmed with empty hashes.

Never confirm launch or invoke `loen:loop-run`.

## Output

Report topic, changed plan, checks, plan hash, and approval state.

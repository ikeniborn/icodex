---
name: loop-plan
description: LoEn skill for converting goal and context artifacts into a bounded plan under docs/loen/<topic>/.
---

# LoEn Loop Plan

Use this skill when `docs/loen/<topic>/1_goal.md` exists and the loop needs a bounded execution plan.

## Procedure

1. Read `docs/loen/<topic>/1_goal.md`, `2_context.md` if present, and `loop.yaml`.
2. Write `3_plan.md` from `assets/templates/3_plan.md`.
3. Keep the plan bounded to one verifiable loop pass.
4. Include exact checks that later `loop-check` can run or inspect.

## Output

Report the selected topic, planned steps, and verification command list.

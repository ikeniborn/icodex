---
name: loop-act
description: LoEn skill for executing one bounded action step and recording action evidence under docs/loen/<topic>/.
---

# LoEn Loop Act

Use this skill when `docs/loen/<topic>/3_plan.md` identifies the next bounded action.

## Procedure

1. Read `docs/loen/<topic>/loop.yaml` and `3_plan.md`.
2. Execute exactly one bounded action from the active plan.
3. Write `4_act.md` from `assets/templates/4_act.md`.
4. Record files changed, commands run, and any observed result.

## Output

Report the action completed, changed paths, and the next check to run.

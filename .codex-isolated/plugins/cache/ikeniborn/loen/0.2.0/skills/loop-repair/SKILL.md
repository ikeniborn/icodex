---
name: loop-repair
description: LoEn skill for specializing a loop around failing tests, CI failures, or regressions under docs/loen/<topic>/.
---

# LoEn Loop Repair

Use this skill when evidence shows a failing test, CI failure, regression, or broken behavior.

## Procedure

1. Read failure evidence from `docs/loen/<topic>/5_check.md` or supplied logs.
2. Write repair context to `docs/loen/<topic>/2_context.md`.
3. Keep the repair plan focused on reproducing, isolating, fixing, and rechecking the failure.
4. Hand back to `loop-plan` or `loop-act` for execution.

## Output

Report the failing signal, suspected surface, and next bounded repair step.

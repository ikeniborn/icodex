---
name: loop-check
description: LoEn skill for running configured checks and recording evidence under docs/loen/<topic>/.
---

# LoEn Loop Check

Use this skill after a bounded action changes code, docs, or configuration.

## Procedure

1. Read check commands from `docs/loen/<topic>/3_plan.md` and `loop.yaml`.
2. Run each check from the repository root.
3. Write `5_check.md` from `assets/templates/5_check.md`.
4. Record command, exit code, and relevant output summary for each check.

## Output

Report pass/fail state and the evidence file path.

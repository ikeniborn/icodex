---
name: loop-reflect
description: LoEn skill for deciding keep, fix, revert, or handoff from evidence under docs/loen/<topic>/.
---

# LoEn Loop Reflect

Use this skill after checks produce evidence.

## Procedure

1. Read `docs/loen/<topic>/4_act.md` and `5_check.md`.
2. Decide one outcome: keep, fix, revert, or handoff.
3. Write `6_reflect.md` from `assets/templates/6_reflect.md`.
4. If the loop is complete, write `7_result.md` from `assets/templates/7_result.md`.
5. The parent mirrors the material lifecycle state and redacted decision, result,
   or handoff evidence to `reference/tasks/<topic>`. Hooks remain MCP-free;
   `docs/loen/<topic>/` remains authoritative for loop execution.

## Output

Report the decision, reason, and next LoEn skill if more work remains.

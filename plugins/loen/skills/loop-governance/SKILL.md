---
name: loop-governance
description: LoEn skill for scheduled or recurring checks with governance artifacts under docs/loen/<topic>/.
---

# LoEn Loop Governance

Use this skill when a LoEn topic represents a recurring check or scheduled governance pass.

## Procedure

1. Record recurrence, owner, and review requirement in `docs/loen/<topic>/loop.yaml`.
2. Keep scheduled activity advisory unless later integration enables stricter modes.
3. Record every run in the topic artifacts.
4. Require human review before any merge, release, or destructive operation.

## Output

Report schedule, latest evidence, required human decision, and next run condition.

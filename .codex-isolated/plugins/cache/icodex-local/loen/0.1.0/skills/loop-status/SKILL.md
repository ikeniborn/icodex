---
name: loop-status
description: LoEn skill for summarizing current topic state from artifacts under docs/loen/<topic>/.
---

# LoEn Loop Status

Use this skill when the user asks for the state of a LoEn topic or all active LoEn topics.

## Procedure

1. Read `docs/loen/<topic>/loop.yaml` and numbered artifact files.
2. Summarize current stage, latest evidence, open decisions, and next action.
3. Treat missing artifact files as missing state, not as implied chat state.

## Output

Report concise status with artifact paths and discrepancies.

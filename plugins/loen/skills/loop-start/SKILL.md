---
name: loop-start
description: LoEn skill for creating or selecting a topic and writing goal artifacts under docs/loen/<topic>/.
---

# LoEn Loop Start

Use this skill when the user asks to start a LoEn loop, create a durable loop topic, or turn an open-ended request into a bounded loop workspace.

## Procedure

1. Choose a short kebab-case topic from the user request.
2. Create or reuse `docs/loen/<topic>/`.
3. Write `1_goal.md` from `assets/templates/1_goal.md`.
4. Write `loop.yaml` from `assets/templates/loop.yaml`.
5. Record only durable task facts in `docs/loen/<topic>/`; do not use chat history as the source of truth.

## Output

Report the topic, artifact directory, and the next recommended LoEn skill.

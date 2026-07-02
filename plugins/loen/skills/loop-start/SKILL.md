---
name: loop-start
description: LoEn skill for creating or selecting a topic and writing goal artifacts under docs/loen/<topic>/.
---

# LoEn Loop Start

Use this skill when the user asks to start a LoEn loop, create a durable loop topic, or turn an open-ended request into a bounded loop workspace.

## Procedure

1. Choose a topic slug that matches `^[a-z0-9](?:[a-z0-9]|-(?=[a-z0-9])){0,78}[a-z0-9]?$`.
2. Reject empty slugs, path traversal, slashes, uppercase letters, spaces, leading dashes, trailing dashes, and repeated dashes.
3. Create or reuse `docs/loen/<topic>/`.
4. Create these files directly in the topic directory: `1_goal.md`, `2_context.md`, `3_plan.md`, `4_act.md`, `5_check.md`, `6_reflect.md`, `7_result.md`, `loop.yaml`, `attempts.jsonl`, `handoff.md`, and `audit.html`.
5. Create `docs/loen/<topic>/evidence/` for run evidence files such as `latest-test.json` and `latest-test.log`.
6. Write `loop.yaml` with `topic`, `mode`, `status`, `objective`, `current_stage`, `stage`, `created`, `updated`, `mutable_scope`, `protected_scope`, `quality_gates`, `verifier`, `budget`, `stop_conditions`, `handoff_conditions`, and `rollback_policy`.
7. Keep `docs/TODO.md` as the only global task registry; do not create a global LoEn audit index.
8. Record durable task facts in `docs/loen/<topic>/`; do not use chat history as the source of truth.

## Output

Report the topic, artifact directory, and the next recommended LoEn skill.

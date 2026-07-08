---
name: loop-start
description: LoEn skill for creating or selecting a topic and writing goal artifacts under docs/loen/<topic>/.
---

# LoEn Loop Start

Use this skill when the user asks to start a LoEn loop, create a durable loop topic, or turn an open-ended request into a bounded loop workspace.

## Procedure

1. Choose and validate a safe topic slug that matches `^[a-z0-9](?:[a-z0-9]|-(?=[a-z0-9])){0,78}[a-z0-9]?$`.
2. Reject empty slugs, path traversal, slashes, uppercase letters, spaces, leading dashes, trailing dashes, and repeated dashes.
3. Collect objective, success criteria, constraints, mutable scope, protected scope, verifier, budget, and rollback policy.
4. Ask the launch principle: `delivery` or `governance`.
5. If launch principle is `governance`, ask governance subtype: `report-only`, `auto-fix`, or `merge-release`.
6. Collect mode-specific parameters:
   - `delivery`: bounded deliverable, verifier command, max passes, stop conditions, and rollback policy.
   - `report-only`: report target, evidence requirements, recurrence or manual trigger, owner, and alert conditions.
   - `auto-fix`: allowed fix scope, `governance.auto_fix: true`, verifier command, max passes, and handoff conditions.
   - `merge-release`: `governance.auto_merge: true`, release target, merge strategy, verifier and evidence requirements, `release_policy.scope_limit`, and recovery policy.
7. Create or reuse `docs/loen/<topic>/`.
8. Create the standard topic files directly in the topic directory: `1_goal.md`, `2_context.md`, `3_plan.md`, `4_act.md`, `5_check.md`, `6_reflect.md`, `7_result.md`, `loop.yaml`, `attempts.jsonl`, `handoff.md`, and `audit.html`.
9. Create `docs/loen/<topic>/evidence/` for run evidence files such as `latest-test.json` and `latest-test.log`.
10. Write `1_goal.md` and `2_context.md` from collected durable facts.
11. Write `3_plan.md` with one bounded plan, verifier command, evidence path, mode policy, rollback or recovery policy, and terminal condition.
12. Present `3_plan.md` for human approval before enabling the runner.
13. After approval, write `loop.yaml` with `topic`, `mode`, `status`, `objective`, `current_stage`, `stage`, `created`, `updated`, `mutable_scope`, `protected_scope`, `quality_gates`, `verifier`, `budget`, `stop_conditions`, `handoff_conditions`, `rollback_policy`, `run.plan_approved: true`, `run.plan_hash`, `run.mode`, `run.subtype`, and policy fields.
14. Policy fields include `governance:` for governance topics and `release_policy:` for `merge-release`.
15. Keep `docs/TODO.md` as the only global task registry; do not create a global LoEn audit index.
16. Record durable task facts in `docs/loen/<topic>/`; do not use chat history as the source of truth.
17. Offer to start `loen:loop-run <topic>` immediately, or report that command for later.

## Output

Report the topic, artifact directory, selected mode/subtype, approval state, and `loen:loop-run <topic>` as the next recommended command.

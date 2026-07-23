---
name: loop-start
description: Use when a user asks to create a new durable LoEn topic workspace.
---

# LoEn Loop Start

Create and fully plan a new LoEn topic. Never launch it.

## Procedure

1. Derive or request a semantic lowercase kebab-case topic. Validate it against `^[a-z0-9](?:[a-z0-9]|-(?=[a-z0-9])){0,78}[a-z0-9]?$`; reject empty values, traversal, separators, uppercase, spaces, edge dashes, and repeated dashes.
2. Create or safely reuse `docs/loen/<topic>/`, its `evidence/` directory, and the standard files: `1_goal.md` through `7_result.md`, `loop.yaml`, `attempts.jsonl`, `handoff.md`, and `audit.html`. Never overwrite durable content without explicit confirmation.
3. Collect the user request, objective, observable outcome, success criteria, facts, constraints, mutable scope, protected scope, verifier, budget, rollback or recovery policy, and unresolved assumptions. Ask adaptive questions one at a time; ask only what prior answers leave unknown.
4. Resolve every unresolved assumption adaptively, one question at a time. `Unresolved Assumptions` must be explicitly empty before continuing; record `None.` rather than omitting the heading.
5. Write and present complete `1_goal.md` and `2_context.md` using the fixed template headings.
6. Obtain explicit confirmation of the complete goal and context. Ambiguous or negative responses do not confirm them. Hash the current confirmed `1_goal.md` and `2_context.md`, write the goal/context checkpoint, and append its confirmation event.
7. Ask the user to select `delivery` or `governance`; never infer mode or subtype. For governance, separately ask for `report-only`, `auto-fix`, or `merge-release`. Collect all selected mode policy fields, record the mode checkpoint, and append its confirmation event.
8. Write the integrated plan from the confirmed goal, context, mode, and subtype. Include preconditions, bounded steps, success-criterion mapping, exact checks and evidence paths, risks, rollback or recovery, and terminal condition.
9. Present the complete `3_plan.md`. Obtain separate explicit approval of the complete plan. Ambiguous or negative responses do not approve it. Hash the approved plan, write the plan checkpoint, and append its confirmation event.
10. Apply deterministic invalidation after every upstream artifact or decision change: reset every affected downstream checkpoint and hash before asking for confirmation again. For every transition, append checkpoint reset and confirmation events to `attempts.jsonl` with checkpoint, decision, hashes, mode, subtype, outcome, and timestamp.
11. Write `loop.yaml` with topic metadata, objective, scopes, quality gates, verifier, budget, stop and handoff conditions, rollback policy, run mode/subtype/state/pass limits, all checkpoint fields, and selected governance or release policy. Leave launch unconfirmed with empty hashes.
12. Keep `docs/TODO.md` as the only global registry. Durable topic artifacts, not chat history, are authoritative.

## Deterministic Invalidation

- INVALIDATE-GOAL-CONTEXT: Any content change to `1_goal.md` or `2_context.md` resets goal_context, mode, plan, and launch.
- INVALIDATE-MODE: Any mode or subtype change resets mode, plan, and launch.
- INVALIDATE-PLAN: Any content change to `3_plan.md` resets plan and launch.
- RESTORE-PLAN: Reapproval restores plan only; launch remains unconfirmed.
- INVALIDATE-FAILED-PREFLIGHT: Failed post-confirmation preflight resets launch only.
- RESET-AUDIT: Every reset appends one reset event; never infer confirmation or approval.

PROHIBITION: MUST NOT write `checkpoints.launch.confirmed: true`.

PROHIBITION: MUST NOT invoke `loen:loop-run`.

Never invoke `loen:loop-run` automatically. Never confirm launch in this skill.

## Output

Report topic, artifact directory, mode/subtype, goal/context confirmation, and plan approval. The continuation command is output only. End with exactly:

To continue, run `loen:loop-run <topic>`.

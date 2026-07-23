---
review:
  spec_hash: db66165851345baa
  last_run: 2026-07-23
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-07-23-loen-start-mode-gates-intent.md
---

# LoEn Start Mode Gates Design

## Purpose

Restore trust in the guided LoEn start flow by making topic development and execution authorization explicit, ordered, machine-enforced checkpoints. `loop-start` remains the user-facing orchestrator for initial planning. `loop-plan` remains available only for replanning an existing topic. `loop-run` becomes the only place where launch authorization can be granted.

The primary workflow is:

```text
loop-start
  -> develop and confirm goal/context
  -> select and confirm mode/subtype
  -> build and approve plan
  -> stop with exact loop-run command
loop-run <topic>
  -> summarize contract
  -> request launch confirmation
  -> persist launch checkpoint
  -> repeat full preflight
  -> execute or refuse
```

## Acceptance (from intent)

- `loop-start` requires separate confirmation of goal and context before generating a plan.
- The user explicitly selects the launch principle and, where applicable, its subtype before the plan can be approved.
- Plan approval and launch authorization are separate user decisions.
- `loop-run` cannot start unless all required confirmations are present and current.
- Missing, stale, contradictory, or legacy confirmation state produces a clear refusal and recovery path.
- Done when: negative scenarios prove `loop-run` cannot start without all four ordered checkpoints, positive scenarios start only after explicit launch authorization, and topic-quality tests verify required planning inputs.

## Requirements

### R1: Goal and Context Quality Gate

`loop-start` must collect an objective, observable outcome, success criteria, constraints, mutable scope, protected scope, verifier, budget, and rollback or recovery policy. It must ask adaptive follow-up questions for missing, ambiguous, or contradictory inputs. It must not generate `3_plan.md` while unresolved assumptions remain.

After topic development, `loop-start` must present the resulting goal and context as one reviewable summary and request an explicit confirmation. Confirmation persists the hashes of `1_goal.md` and `2_context.md` in the `goal_context` checkpoint.

Acceptance criteria:

- Every required topic field is present before planning starts.
- An unresolved assumption blocks plan generation and identifies the missing decision.
- Goal/context confirmation is a distinct user decision recorded with both artifact hashes.

### R2: Mode and Subtype Gate

After goal/context confirmation, `loop-start` must ask the user to select `delivery` or `governance`. Governance requires an explicit subtype: `report-only`, `auto-fix`, or `merge-release`. No mode or subtype may be inferred from defaults, task wording, or previous conversation.

Acceptance criteria:

- Mode selection cannot occur before current goal/context confirmation.
- Governance cannot proceed without an explicit supported subtype.
- The selected values are stored in the `mode` checkpoint.

### R3: Integrated Planning and Plan Approval

Initial planning is part of `loop-start`; users do not invoke `loop-plan` during the primary start flow. Planning consumes only confirmed goal/context and mode state. The generated plan must map actions to success criteria, scope, verifier evidence, budget, risks, and rollback or recovery behavior.

Plan approval is a separate checkpoint bound to the current `3_plan.md` hash. It does not authorize execution.

Acceptance criteria:

- `loop-start` generates a plan only after R1 and R2 pass.
- Plan approval records the current plan hash.
- Approval output does not imply or trigger launch authorization.

### R4: Explicit Handoff From Start to Run

`loop-start` must never invoke `loop-run` automatically and must not offer an immediate in-flow launch. After plan approval it must stop and show the exact instruction:

```text
To continue, run loen:loop-run <topic>.
```

User-facing localization may translate the surrounding sentence, but the command and resolved topic must remain exact.

Acceptance criteria:

- Every successful `loop-start` ends with the continuation command.
- No `loop-start` path writes launch confirmation or begins runner execution.

### R5: Launch Confirmation in `loop-run`

Invoking `loen:loop-run <topic>` is not launch confirmation. Before execution, `loop-run` must validate the first three checkpoints, present a final contract summary, and request an explicit human launch decision. The summary includes mode, subtype, mutable and protected scope, verifier, budget, rollback or recovery policy, and current goal, context, and plan hashes.

On explicit approval, `loop-run` writes the `launch` checkpoint and an audit event, then repeats the complete preflight. Execution begins only if the repeated preflight succeeds. A refusal or ambiguous response leaves execution blocked. A failed repeated preflight invalidates launch confirmation and records the failure.

Acceptance criteria:

- Command invocation alone never starts execution.
- Launch confirmation is written only by `loop-run` after an explicit answer.
- Execution begins only after the post-confirmation preflight passes.

### R6: Structured Checkpoints With Audit History

`loop.yaml` stores current executable checkpoint state. The existing audit trail stores append-only confirmation, reset, and refusal events. Audit history is evidence, not executable authority; preflight trusts only current checkpoints and matching hashes.

The contract shape is:

```yaml
checkpoints:
  goal_context:
    confirmed: true
    goal_hash: "<hash of 1_goal.md>"
    context_hash: "<hash of 2_context.md>"
  mode:
    confirmed: true
    mode: delivery
    subtype: null
  plan:
    approved: true
    plan_hash: "<hash of 3_plan.md>"
  launch:
    confirmed: false
    goal_hash: null
    context_hash: null
    plan_hash: null
```

Each audit event records timestamp, checkpoint name, decision type, relevant hashes, mode/subtype when applicable, and outcome. Existing audit artifact conventions determine the physical event file and rendering; this change must not create a second audit system.

Acceptance criteria:

- Current authority is readable from `checkpoints` without replaying audit history.
- Audit history shows every confirmation, invalidation, and refusal.
- Audit events cannot substitute for missing or stale checkpoint state.

### R7: Deterministic Invalidation

Checkpoint invalidation follows downstream dependency order:

| Change | Invalidated checkpoints |
|---|---|
| `1_goal.md` or `2_context.md` content changes | `goal_context`, `mode`, `plan`, `launch` |
| mode or subtype changes | `mode`, `plan`, `launch` |
| `3_plan.md` content changes | `plan`, `launch` |
| plan is re-approved | restores `plan` only |
| post-confirmation preflight fails | `launch` |

Any hash mismatch, missing checkpoint, contradictory value, or out-of-order state blocks execution. Legacy contracts without `checkpoints` are invalid and must direct the user back to `loop-start` for explicit renewal.

Acceptance criteria:

- Every upstream mutation invalidates all dependent downstream authority.
- Preflight reports the first failed checkpoint and a concrete recovery action.
- Legacy contracts never receive inferred or migrated approval.

### R8: Standalone Replanning

`loen:loop-plan` remains available for replanning an existing topic. It first validates current goal/context and mode checkpoints, regenerates or revises `3_plan.md`, invalidates plan and launch authority, and requests separate plan approval. It cannot confirm launch or execute the runner.

Acceptance criteria:

- Replanning cannot use stale goal/context or mode state.
- Any changed plan requires fresh plan approval and future launch confirmation.
- The primary `loop-start` flow does not require a separate `loop-plan` invocation.

### R9: Documentation Closeout

The final implementation step, after runtime behavior and focused tests are stable, must update these user-facing plugin documents:

- `plugins/loen/docs/architecture.md`;
- `plugins/loen/README.md`;
- `plugins/loen/README.ru.md`.

The updates must describe the integrated `loop-start` planning flow, standalone `loop-plan` replan role, four ordered checkpoints, deterministic invalidation, explicit `loop-run` launch confirmation, exact continuation command, and refusal of legacy contracts.

Acceptance criteria:

- All three documents describe the same checkpoint contract and user flow.
- Documentation updates occur after contract and test changes, so examples match the verified final behavior.
- Repository documentation and the bound `icodex` wiki contain no stale description of immediate launch or plan approval as execution authority.

## Components and Boundaries

### `loen:loop-start`

Owns initial topic development, goal/context confirmation, mode/subtype selection, integrated plan creation, plan approval, checkpoint persistence for the first three gates, and the final continuation instruction. It does not own launch confirmation or execution.

### `loen:loop-plan`

Owns standalone replan behavior for existing topics. It validates upstream checkpoints, updates the plan, resets downstream state, and obtains plan approval. It does not own initial start orchestration, launch confirmation, or execution.

### `loen:loop-run`

Owns launch confirmation, final contract presentation, repeated preflight, and execution. It consumes but does not infer the first three checkpoints.

### Runtime Contract Validation

The shared LoEn contract parser and preflight validator own checkpoint shape, hash matching, ordering, legacy refusal, and recovery diagnostics. Skills describe and drive the conversation; runtime validation supplies the hard enforcement boundary.

### Templates and Audit Rendering

Templates expose the new checkpoint shape with unconfirmed defaults. Audit rendering displays checkpoint decisions and invalidations using existing topic audit artifacts.

## Data Flow

1. `loop-start` creates or selects the topic and drafts `1_goal.md` and `2_context.md`.
2. Adaptive questioning resolves missing fields, ambiguity, and contradictions.
3. The user confirms the goal/context summary; hashes are stored and audited.
4. The user selects mode and subtype; selection is stored and audited.
5. Integrated planning creates `3_plan.md` from current confirmed inputs.
6. The user approves the plan; its hash is stored and audited.
7. `loop-start` stops with the exact `loen:loop-run <topic>` continuation instruction.
8. `loop-run` validates goal/context, mode, and plan checkpoints.
9. `loop-run` presents the final contract and asks for launch confirmation.
10. Explicit approval writes the launch checkpoint bound to all three artifact hashes and appends an audit event.
11. `loop-run` repeats full preflight. Success enters runner execution; failure resets launch and records refusal evidence.
12. Any later upstream mutation applies the R7 invalidation table before another run.

## Error Handling

Refusals must name the failed checkpoint, explain the mismatch, and give one concrete recovery action. Expected recovery routes are:

| Failure | Recovery |
|---|---|
| Goal/context missing, stale, or ambiguous | Resume `loop-start` and reconfirm goal/context. |
| Mode/subtype missing or contradictory | Resume `loop-start` and select mode/subtype. |
| Plan missing or stale | Resume `loop-start`, or use standalone `loop-plan` for replan. |
| Legacy contract | Resume `loop-start`; no automatic migration. |
| Launch declined or ambiguous | Leave launch unconfirmed and exit without execution. |
| Post-confirmation preflight failure | Reset launch, record failure, and report the failed prerequisite. |

No refusal path may perform action, check, reflect, merge, release, publication, or other runner work.

## Compatibility

This is an intentional breaking contract change for existing LoEn topics. Manual artifact reading remains possible, but `loop-run` refuses legacy `loop.yaml` files until the topic is explicitly renewed through `loop-start`. No compatibility flag, default approval, or automatic checkpoint migration is provided.

Existing scope, verifier, budget, rollback, plan-hash, governance-policy, worker/verifier separation, and protected-scope checks remain mandatory. The checkpoint layer adds authorization gates; it does not replace existing safety policy.

## Testing

Focused contract tests must verify behavior and state transitions rather than keyword presence:

- a complete four-checkpoint happy path reaches runner execution;
- each checkpoint missing independently blocks execution;
- out-of-order checkpoints block execution;
- goal, context, mode, subtype, and plan mutations invalidate the required downstream checkpoints;
- legacy contracts are refused with the `loop-start` recovery route;
- ambiguous and negative launch responses do not execute;
- launch confirmation is persisted before, and validated by, the repeated preflight;
- repeated-preflight failure resets launch and does not execute;
- standalone `loop-plan` invalidates and renews plan state correctly;
- confirm, reset, and refusal decisions appear in audit evidence;
- `loop-start` always emits the exact continuation command and never invokes `loop-run`;
- required topic fields and unresolved assumptions block planning;
- existing LoEn focused tests continue to pass after fixtures adopt the new contract.

Positive tests must include evidence that runner execution begins only after explicit launch confirmation. Negative tests must include evidence that no runner action occurred.

## Documentation Impact

Implementation must update runtime artifact documentation, relevant skill instructions, templates, and the bound `icodex` wiki pages as their source behavior changes. As the final implementation step, R9 updates `plugins/loen/docs/architecture.md`, `plugins/loen/README.md`, and `plugins/loen/README.ru.md` against the verified contract. Documentation must describe the primary integrated planning flow, standalone replan role, breaking legacy behavior, checkpoint invalidation, and separate launch confirmation.

## Out of Scope

- Automatic migration or grandfathering of legacy contracts.
- A second audit event store or global LoEn registry.
- New launch modes or governance subtypes.
- Automatic runner invocation from `loop-start`.
- Replacing existing scope, verifier, budget, rollback, or governance safety controls.

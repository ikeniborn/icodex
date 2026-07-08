---
review:
  spec_hash: 1dd42906540a618d
  last_run: 2026-07-08
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-07-08-loen-loop-run-intent.md
---
# LoEn loop run orchestration design

## Purpose

Extend LoEn so `loen:loop-start` becomes the single human planning checkpoint and a new `loen:loop-run <topic>` skill can execute an approved topic through a visible state machine.

The current LoEn workflow is intentionally durable but manual: after `loop-start`, the user invokes `loop-plan`, `loop-act`, `loop-check`, and `loop-reflect` one by one, or invokes `loop-governance` for governance topics. The new workflow keeps those manual skills available, but adds a guided path:

```text
loop-start -> approved plan and run policy -> loop-run <topic> -> 7_result.md or handoff.md
```

`loop-start` owns requirements collection, launch-mode choice, mode-specific parameters, and plan approval. `loop-run` owns automated execution after that approval.

## Acceptance (from intent)

- `loen:loop-start` asks the user for requirements, intent, success criteria, launch mode, and mode-specific parameters before execution starts.
- `loen:loop-start` offers at least `delivery` and `governance` mode selection, then collects the parameters required for the selected mode.
- `loen:loop-start` presents a plan for user approval before any automated run begins.
- After plan approval, `loen:loop-start` offers to invoke `loen:loop-run <topic>` immediately, while still allowing the user to run the same topic later.
- `loen:loop-run <topic>` reads approved topic artifacts and drives the selected mode without requiring manual calls to `loop-act`, `loop-check`, or `loop-reflect` on the happy path.
- A successful run leaves a complete LoEn artifact trail ending in `docs/loen/<topic>/7_result.md`, regenerated `audit.html`, and verifier evidence.
- A run that cannot safely continue leaves `docs/loen/<topic>/handoff.md` with the stop reason and the next human action.
- Governance runs record `governance:` policy in `loop.yaml`, append run records to `attempts.jsonl`, preserve evidence, and show automation state in `audit.html`.

## Architecture

Use one explicit runner state machine under a new `loen:loop-run` skill.

`loen:loop-start` creates or reuses `docs/loen/<topic>/`, collects requirements, asks the launch principle, collects the mode-specific policy, writes the approved plan, and records a machine-readable `run:` block in `loop.yaml`. It does not perform code changes, merge, release, destructive operations, or long-running execution.

`loen:loop-run <topic>` reads `loop.yaml`, `3_plan.md`, and current topic artifacts. It refuses to proceed unless the topic has an approved run contract. It then drives:

```text
prepare -> act -> check -> reflect -> retry/fix -> result | handoff
```

Delivery and governance share the same top-level state machine. Governance behavior is controlled by subtype-specific policy. This keeps audit, evidence, and stop behavior consistent while allowing stricter mode rules.

Manual skills remain valid. `loop-plan`, `loop-act`, `loop-check`, `loop-reflect`, `loop-governance`, and `loop-status` can still be used directly. Runner automation is an additional guided path over the same topic artifacts, not a replacement for manual operation.

## Launch Mode Selection

`loop-start` must ask the launch principle before it creates the final execution plan.

Supported launch modes:

| Mode | Meaning | Required next choice |
|---|---|---|
| `delivery` | One ordinary task or implementation loop. | No governance subtype. |
| `governance` | Policy-driven, recurring, scheduled, audit, release, or automation loop. | Governance subtype. |

Governance subtypes:

| Subtype | Default | Behavior |
|---|---|---|
| `report-only` | Yes | Run checks, collect evidence, write reports and attempts, no code edits. |
| `auto-fix` | No | May edit approved mutable scope when `auto_fix: true`, verifier, rollback, and budget are recorded. |
| `merge-release` | No | May perform real merge or release automation after start-time approval when target policy, verifier, evidence, scope, and recovery policy pass. |

`merge-release` does not require a second human approval immediately before merge or release. Approval at `loop-start` is sufficient when the recorded policy and evidence requirements pass.

## Run Contract

`loop.yaml` gains a `run:` block owned by `loop-start` and consumed by `loop-run`.

```yaml
run:
  mode: delivery
  subtype: null
  plan_approved: true
  plan_hash: "<hash of 3_plan.md>"
  state: prepare
  max_passes: 3
  current_pass: 0
  approval_source: loop-start
  approved_at: "2026-07-08T00:00:00Z"
```

For governance topics, `mode: governance` and `subtype` must be one of `report-only`, `auto-fix`, or `merge-release`.

Governance policy remains under `governance:` and is expanded only as needed:

```yaml
governance:
  automation_type: dependency-audit
  owner: maintainer
  schedule: "manual"
  auto_fix: false
  auto_merge: false
  report_only_on_no_findings: true
  alert_on:
    - protected_scope_attempt
    - verifier_failure
    - budget_exhausted
    - metric_regression
```

For `auto-fix`, `auto_fix: true` must be explicit and must be paired with mutable scope, verifier, budget, and rollback policy.

For `merge-release`, `auto_merge: true` may be explicit only with a release policy:

```yaml
release_policy:
  target_branch: master
  merge_strategy: pr
  verifier_required: true
  evidence_required: true
  recovery_policy: "Stop, record handoff, and leave branch state inspectable."
```

## Components

### `loen:loop-start`

Responsibilities:

- choose or validate a topic slug;
- scaffold or reuse `docs/loen/<topic>/`;
- collect objective, success criteria, constraints, mutable scope, protected scope, verifier, budget, and rollback policy;
- ask whether the run principle is `delivery` or `governance`;
- for governance, ask subtype and subtype parameters;
- write `1_goal.md`, `2_context.md`, `3_plan.md`, `loop.yaml`, and starter audit artifacts;
- present the plan for user approval;
- write `run.plan_approved: true` and `run.plan_hash` only after approval;
- offer to launch `loen:loop-run <topic>` immediately or leave the user with the exact command for later.

### `loen:loop-run`

Responsibilities:

- accept a topic argument;
- load `docs/loen/<topic>/loop.yaml` and `3_plan.md`;
- verify plan approval and plan hash;
- enforce mode/subtype policy before every state transition;
- write `4_act.md`, `5_check.md`, `6_reflect.md`, `7_result.md`, `handoff.md`, `attempts.jsonl`, evidence files, and regenerated `audit.html` as the run progresses;
- stop through `handoff.md` when policy or evidence is insufficient;
- avoid user prompts on the approved happy path.

### Existing Manual Skills

Manual skills keep their current identity and remain useful for step-by-step operation, debugging, repair, and partial handoff. They should read the same topic artifacts. If a topic has no `run:` block, manual skills continue normally. If `loop-run` is invoked without a valid `run:` block, it stops with a handoff explaining that no approved run contract exists.

## Data Flow

1. User invokes `loen:loop-start`.
2. `loop-start` creates or selects the topic directory.
3. `loop-start` collects objective, success criteria, and constraints.
4. `loop-start` asks the launch principle: `delivery` or `governance`.
5. If the launch principle is `governance`, `loop-start` asks the subtype: `report-only`, `auto-fix`, or `merge-release`.
6. `loop-start` collects mode-specific parameters:
   - delivery: mutable scope, verifier, budget, and rollback policy;
   - governance report-only: trigger or schedule, owner, verifier, evidence rules, and report rules;
   - governance auto-fix: report-only parameters plus mutable scope, rollback policy, fix budget, and explicit `auto_fix: true`;
   - governance merge-release: target branch or release target, merge strategy, verifier requirements, evidence requirements, scope limits, and recovery policy.
7. `loop-start` writes `1_goal.md`, `2_context.md`, `3_plan.md`, and `loop.yaml`.
8. User approves or revises the plan.
9. After approval, `loop-start` writes `run.plan_approved: true` and `run.plan_hash`.
10. `loop-start` offers immediate launch of `loen:loop-run <topic>` or a later manual launch.
11. `loop-run <topic>` validates topic, plan approval, plan hash, mode, subtype, scope, verifier, budget, and policy.
12. Runner executes state transitions until `7_result.md` or `handoff.md`.
13. Audit output and attempts reflect the complete path.

## Error Handling and Stop Rules

`loop-run` must stop through `handoff.md` instead of continuing on assumptions when:

- `run.plan_approved` is absent or false;
- `run.plan_hash` does not match the current `3_plan.md`;
- mode or subtype is missing, unknown, or contradictory;
- governance mode lacks a subtype;
- verifier command is missing or unavailable;
- planned action requires protected scope;
- planned action leaves mutable scope;
- budget or max passes are exhausted;
- checks fail and the next fix is not bounded;
- `LOEN_MODE`, hook policy, role/tool policy, evidence gate, or worker/verifier separation blocks progress;
- `auto-fix` lacks explicit `auto_fix: true` and required safety policy;
- `merge-release` lacks explicit start-time approval, target policy, verifier pass requirements, evidence requirements, scope limits, or recovery policy;
- a destructive, network publication, merge, release, or secret-affecting operation was not approved during `loop-start`.

Terminal states:

- `result`: `7_result.md` exists, verifier evidence exists, and `audit.html` reflects the completed run.
- `handoff`: `handoff.md` names the failed condition, evidence, and next recommended human action.

## Audit and Documentation Behavior

`audit.html` should show the runner path, selected mode, governance subtype, current state, pass count, evidence files, attempts, and terminal state. It should make plan approval visible so a reader can distinguish a runner-controlled topic from a manually operated topic.

`docs/TODO.md` remains the only global human-readable registry. LoEn must not add a second global runner index.

Repository docs and the `icodex` iwiki pages for LoEn must be updated when implementation changes user-facing workflow or architecture.

## Testing and Acceptance

Focused validation should prove:

- `loop-start` documentation and template contract include `delivery|governance` launch selection.
- Governance subtype is explicit: `report-only|auto-fix|merge-release`.
- `loop.yaml` template supports `run.mode`, `run.subtype`, `run.plan_approved`, `run.plan_hash`, `run.state`, `run.max_passes`, and `run.current_pass`.
- `loen:loop-run` exists and documents the state machine.
- `loop-run` refuses missing approval, hash mismatch, missing mode, missing subtype, and incomplete mode policy.
- Manual skills remain documented and usable.
- Governance report-only forbids code edits.
- Governance auto-fix requires explicit `auto_fix: true`, mutable scope, verifier, budget, and rollback policy.
- Governance merge-release requires explicit start approval, target policy, verifier pass, evidence, scope limits, and recovery policy.
- Audit output shows runner path and terminal state.
- Existing LoEn focused tests continue to pass.

Acceptance criteria:

- A user can complete `loen:loop-start`, approve a plan, and then run `loen:loop-run <topic>`.
- A delivery happy path can reach `7_result.md` without manual `loop-act`, `loop-check`, or `loop-reflect` calls.
- A blocked delivery path reaches `handoff.md`.
- Governance report-only, auto-fix, and merge-release modes follow their recorded policies to `7_result.md` or `handoff.md`.
- Existing manual LoEn skills and safety hooks remain compatible.

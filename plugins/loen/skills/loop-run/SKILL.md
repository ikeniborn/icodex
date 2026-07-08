---
name: loop-run
description: LoEn skill for running an approved topic contract to 7_result.md or handoff.md.
---

# LoEn Loop Run

Use this skill when a LoEn topic has an approved `3_plan.md` and needs one runner pass to terminal `7_result.md` or `handoff.md`.

## Required Input

Pass a topic slug:

```text
loen:loop-run sample-topic
```

Resolve artifacts under `docs/loen/<topic>/`.

## Preflight

1. Read `loop.yaml` and `3_plan.md`.
2. Verify `run.plan_approved: true`; on missing plan approval, write `handoff.md` and stop.
3. Verify `run.plan_hash` matches the current `3_plan.md` body hash; on mismatch, write `handoff.md` and stop.
4. Verify `run.mode` is `delivery` or `governance`.
5. For governance mode, verify `run.subtype` is `report-only`, `auto-fix`, or `merge-release`.
6. Verify scope, verifier, budget, and rollback or recovery policy are present and usable.
7. For governance `merge-release`, verify `governance.auto_merge: true` and a complete `release_policy:` block before acting.

Any preflight failure writes `handoff.md` with topic, failed check, evidence path when available, and required next human action, then stops.

## State Machine

`prepare -> act -> check -> reflect`

- `prepare`: complete preflight and select the next bounded plan step.
- `act`: perform only actions allowed by mode policy and scope.
- `check`: run the configured verifier and save evidence.
- `reflect`: decide terminal success, retry within budget, rollback/recover, or handoff.

## Mode Policy

### Delivery

- Execute plan steps only inside declared mutable scope.
- Run the configured verifier after each action.
- Write `7_result.md` when verifier passes and the plan outcome is complete.
- Write `handoff.md` on verifier failure that cannot be fixed within budget, protected scope, forbidden tool, or rollback need.

### Governance report-only

- Inspect, verify, and report only.
- Do not change product files except LoEn artifacts and evidence.
- Write `7_result.md` with findings and evidence when verifier/report generation completes.
- Write `handoff.md` when policy, verifier, or evidence is incomplete.

### Governance auto-fix

- Apply bounded fixes only inside mutable scope when `governance.auto_fix: true`.
- Never merge, release, or touch protected scope.
- Run verifier after each fix and record evidence.
- Write `7_result.md` on verified fix; write `handoff.md` when budget, verifier, protected scope, or policy blocks completion.

### Governance merge-release

- Proceed only when `governance.auto_merge: true` and `release_policy:` includes target, strategy, verifier/evidence requirements, scope limits, and recovery policy.
- No second LoEn-specific human approval is required if start-time approval and release policy pass preflight; external branch rules, host approval prompts, and repository safety gates still apply.
- Merge or release only according to `release_policy.target_branch`, `release_policy.merge_strategy`, verifier requirements, evidence requirements, scope limits, and recovery policy.
- Write `7_result.md` only after required verifier and evidence pass.
- Write `handoff.md` if merge-release policy is incomplete, recovery is required, protected scope is needed, or verifier evidence fails.

## Stop Rules

Stop and write `handoff.md` for:

- plan approval missing or false
- plan hash mismatch
- mode policy incomplete
- verifier failure that cannot be fixed within budget and policy
- protected scope required or touched
- budget exhaustion
- forbidden tool
- merge-release policy incomplete

## Output

Report:

- topic
- final state
- changed artifacts
- evidence path
- terminal `7_result.md` or `handoff.md`

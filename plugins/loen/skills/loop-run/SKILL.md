---
name: loop-run
description: Use when an existing LoEn topic has an approved plan and the user requests a runner pass.
---

# LoEn Loop Run

Invocation is not launch confirmation. Every mode and subtype uses the launch checkpoint.

## Required Input

Require one safe topic slug and resolve `docs/loen/<topic>/`. Reject unsafe or missing topics.

## Launch Gate

1. Run the complete contract validator with `require_launch=false`. Validate current goal/context hashes and confirmation, explicit mode/subtype, current plan hash and plan approval, mutable/protected scope, verifier, budget, stop/handoff conditions, rollback or recovery policy, and all mode-specific policy. Any failure writes `handoff.md` and stops.
2. Present the final contract fields: topic, objective and observable outcome, success criteria, mutable/protected scope, verifier, budget, rollback or recovery, mode/subtype, bounded plan, checks/evidence, risks, terminal condition, and current goal/context/plan hashes.
3. Ask exactly one explicit launch question. Ask whether to launch this exact contract now; do not combine it with another decision.
4. A refusal or ambiguous response does not authorize execution: append a `refused` launch event and stop. Do not modify action, check, result, or product files.
5. On explicit approval, write the current goal, context, and plan hashes into the launch checkpoint, set it confirmed, and append a confirmed launch event with timestamp, mode, subtype, and hashes.
6. Repeat the complete preflight with `require_launch=true`. If it fails, reset the launch checkpoint, append a reset event, and stop before the state machine. Write `handoff.md` with the failed check and required human action.

## State Machine

`prepare -> act -> check -> reflect`

- `prepare`: select the next bounded approved plan step after the successful launch preflight.
- `act`: perform only actions permitted by scope and mode policy.
- `check`: run the verifier and save evidence.
- `reflect`: decide verified success, bounded retry, rollback/recovery, or handoff.

## Mode Policy

### Delivery

- Execute approved plan steps only inside mutable scope.
- Verify each action. Write `7_result.md` only when outcome and verifier pass.
- Write `handoff.md` when policy, scope, budget, verifier, or rollback blocks completion.

### Governance report-only

- Inspect, verify, and report only; change no product files.
- Write result with evidence, or hand off when policy/verifier/evidence is incomplete.

### Governance auto-fix

- Require `governance.auto_fix: true`; fix only inside mutable scope.
- Never merge, release, or touch protected scope. Verify each fix.

### Governance merge-release

- The universal launch checkpoint is required for merge-release. Plan approval alone is insufficient.
- Require `governance.auto_merge: true` and complete release target, strategy, verifier/evidence requirements, scope limit, and recovery policy.
- Merge or release only under that policy and external repository safety gates. Write result only after required verification and evidence pass.

## Stop Rules

Stop with `handoff.md` for failed preflight, stale or missing approval/hash, incomplete mode policy, unfixable verifier failure, protected scope, exhausted budget, forbidden tool, or required recovery.

## Output

Report topic, final state, changed artifacts, evidence path, and terminal `7_result.md` or `handoff.md`.

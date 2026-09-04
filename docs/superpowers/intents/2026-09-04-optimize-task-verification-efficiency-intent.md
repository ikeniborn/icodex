---
review:
  intent_hash: 2d4edac7536ca612
  last_run: 2026-09-04
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
workflow:
  route: chain
  continuation: execute
---

# Intent: optimize-task-verification-efficiency

**Date:** 2026-09-04
**Status:** approved

## Objective

Reduce typical task duration from hours or days to a reasonable time by eliminating
verification that is repeated or disproportionate to the current risk, without reducing
the reliability of changes. The change is needed now because current rules can cause the
same evidence to be regenerated across implementation, result review, and branch
completion even when relevant code has not changed.

## Desired Outcomes

- The full test suite runs at most once for an unchanged code state.
- Read-only and documentation-only tasks do not run code tests.
- A successful verification is repeated only after a relevant input changes.

## Health Metrics

- Required focused and relevant regression checks continue to run.
- Security, migration, concurrency, and data-integrity changes retain enhanced review and
  verification.
- The rate of escaped regressions does not increase.
- Every final PASS remains attributable to a specific code state and declared verification
  scope.

## Strategic Context

- Interacts with: project agent instructions, verification and branch-finishing skills,
  `check-chain`, future implementation plans, task-ledger evidence, and the Bash test
  workflow.
- Priority trade-off: trust first; improve speed and cost only by removing checks that add
  no new evidence for the current state.

## Constraints

### Steering (behavioral guidance)

- Select the smallest verification set sufficient for the demonstrated risk and the claim
  being made.
- Preserve explicit evidence about command scope and the code state it verifies.
- Treat a verification budget as a strategy-change threshold, never as permission to skip
  a required check.

### Hard (architectural enforcement)

- Do not skip required checks for security, migration, concurrency, or data-integrity
  changes.
- Do not represent a focused test as evidence that the full suite passed.
- Do not repeat a successful check while its relevant inputs remain unchanged.
- Do not edit generated plugin-cache content as the permanent source of policy.

## Autonomy Zones

- Full autonomy (reversible, low risk): select focused and related tests from the changed
  files and the observable claim.
- Guarded (log + confidence threshold): decide whether the full suite is required and
  record the reason plus the verified code-state fingerprint.
- Proposal-first (needs approval): change mandatory security or data-integrity gates, or
  introduce parallel test execution before isolation is demonstrated.
- No autonomy (human only): accept known failing tests or lower the agreed trust
  guarantees.

> These zones OVERRIDE subagent-driven-development's "continuous execution,
> don't pause" default. Any task touching proposal-first / no-go decisions
> is marked HUMAN CHECKPOINT in the plan.

## Stop Rules

- Halt if: the relevant verification set cannot be determined, evidence cannot be tied to
  the current code state, or a required high-risk check would be omitted.
- Escalate if: two different diagnostic strategies fail to explain the same repeated
  failure.
- Done when: read-only and documentation-only scenarios run zero code tests; a successful
  check is reused while its relevant inputs remain unchanged; the full suite runs no more
  than once for one unchanged code state; focused regression coverage passes; and project
  documentation and iwiki describe the same policy.

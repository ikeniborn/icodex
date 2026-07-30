---
review:
  intent_hash: d00b465e7bbeced1
  last_run: 2026-07-30
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
result_check:
  verdict: OK
  source: intent
  intent_hash: d00b465e7bbeced1
  last_run: 2026-07-30
  reviewed: true
  docs_checked: true
---

# Intent: intent-profile-bootstrap

**Date:** 2026-07-30
**Status:** approved

## Objective

Ensure every approved IDD chain topic has a topic profile that governs intent review and profile selection before any routed implementation task can begin.

## Desired Outcomes

- Creating a chain topic and its intent results in a draft `docs/profiles/<topic>.yaml` for that same topic.
- The draft topic profile declares a task that covers intent review and route/profile selection.
- Routed implementation tasks cannot start until the topic profile is approved.
- Once approved, `--orchestrate <topic>` begins with the preparation task declared by the topic profile.

## Health Metrics

- Existing approved topic manifests continue to validate without changes.
- Existing `--run-task` and `--orchestrate` workflows continue to pass their focused test suites.
- Profile policy validation continues to reject unapproved manifests, registry hash mismatches, and malformed policy inputs.

## Strategic Context

- Interacts with: `fix-intent`, `check-chain`, `docs/profiles`, profile runner, profile policy, profile hook, and profile tests.
- Priority trade-off: trust over speed.

## Constraints

### Steering (behavioral guidance)

- Keep the workflow change limited to topic-profile bootstrap and its verification.
- Preserve the existing manifest layout and user-facing routed commands where compatible.

### Hard (architectural enforcement)

- Do not weaken `status: approved`, the shared registry hash pin, or fail-closed profile policy validation.
- Do not add portable session history or transfer routing state between machines.
- Update repository documentation, wiki documentation, and focused tests with the workflow change.

## Autonomy Zones

- Full autonomy (reversible, low risk): create the draft bootstrap manifest and focused tests.
- Guarded (log + confidence threshold): adjust skill and runner wiring while preserving existing approved-manifest behavior.
- Proposal-first (needs approval): change the profile manifest schema or profile policy validation contract.
- No autonomy (human only): weaken approval, registry pinning, or fail-closed routing behavior.

## Stop Rules

- Halt if: bootstrap cannot be added without weakening manifest approval or registry pinning.
- Escalate if: a schema or policy-validation change is required.
- Done when: a new chain topic has a draft profile containing an intent-review/profile-selection task, that profile gates routed implementation until approval, and existing focused profile tests pass.

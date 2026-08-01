---
review:
  intent_hash: 988e9ce0d7696de6
  last_run: 2026-08-01
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
workflow:
  route: chain
  continuation: full
---

# Intent: profile-full-chain-manifest

**Date:** 2026-08-01
**Status:** approved

## Objective

After a user chooses `direct` or `full`, generate the topic profile manifest for the
entire selected workflow instead of only its initial task. This lets the profile runner
orchestrate the approved workflow without manual manifest edits.

## Desired Outcomes

- A direct workflow manifest contains all tasks required by the direct workflow.
- A full workflow manifest contains intent, spec, plan, implementation, and result
  tasks, and the orchestrator accepts them without manual additions.

## Health Metrics

- Existing manifests and `--run-task` remain compatible.
- Direct-session binding, chain-gate behavior, and rejection of unapproved or invalid
  policy remain unchanged.

## Strategic Context

- Interacts with: `fix-intent`, continuation selection, the `direct-topic` hook,
  profile runner, profile policy documentation, and focused tests.
- Priority trade-off: trust > speed > cost.

## Constraints

### Steering (behavioral guidance)

- Generate full manifests deterministically from the selected workflow.
- Do not infer user-specific implementation task IDs.

### Hard (architectural enforcement)

- Direct work must not enter the App Server full-chain path.
- A full workflow receives tasks for its chain stages and implementation, and a manifest
  becomes approved only after review.
- Do not change the registry, runtime state, model selection, or chain verdict
  semantics.
- Existing manifests must remain valid.

## Autonomy Zones

- Full autonomy: implementation and test updates that preserve the approved policy.
- Guarded: deterministic manifest expansion with focused test evidence.
- Proposal-first: schema/profile-policy changes or discovered incompatibility with
  existing manifests.
- No autonomy: changing registry capacity values, runtime-state authority, model
  selection, or chain verdict semantics.

## Stop Rules

- Halt if the required workflow stages are ambiguous or the change weakens fail-closed
  policy validation.
- Escalate if compatibility requires a manifest schema change.
- Done when direct and full manifests are formed for their full workflows and focused
  plus full test suites pass.

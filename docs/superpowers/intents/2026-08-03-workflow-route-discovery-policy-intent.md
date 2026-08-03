---
review:
  intent_hash: e0b5de154f97f5ca
  last_run: 2026-08-03
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
  intent_hash: e0b5de154f97f5ca
  last_run: 2026-08-03
  reviewed: true
  docs_checked: true
---

# Intent: workflow-route-discovery-policy

**Date:** 2026-08-03
**Status:** approved

## Objective

Eliminate the workflow policy's tendency to recommend `chain` or `full` when evidence is incomplete. Require a bounded analysis of the request, relevant documentation, affected code, and available tests before route selection, while preserving safeguards for evidenced design and invariant risks.

## Desired Outcomes

- Ambiguous initial evidence selects bounded `direct discovery`, not `chain`.
- `direct`, `chain`, and `loen` are selected after a bounded routing analysis.
- A checked chain intent selects `execute` by default when implementation and verification are bounded.
- `full` requires both an enumerated design-risk category and a named unresolved design decision supported by repository evidence.
- AGENTS guidance, README, iwiki documentation, and regression tests describe the same route-selection contract.

## Health Metrics

- Bounded read-only requests, diagnosis, and local fixes create no unnecessary chain artifacts.
- Evidenced design, security, migration, concurrency, transaction, and data-invariant risks still block inappropriate direct execution.
- `full` remains unavailable before a validated intent.
- Existing LoEn isolation, profile hooks, and result reconciliation behavior remain unchanged.
- The Bash test suite continues to validate workflow boundaries.

## Strategic Context

- Interacts with: `.codex-isolated/AGENTS.md`, `check-chain`, `fix-intent`, workflow-boundary tests, README files, and the iwiki model-routing reference.
- Priority trade-off: trust > cost > speed. Unknown evidence is not proof of complexity.

## Constraints

### Steering (behavioral guidance)

- Keep documentation and code comments in English; keep user-facing discussion in Russian.
- Remove only policy redundancy or contradictions within this task's scope.
- Add semantic regression coverage rather than only checking for required phrases.
- Update repository documentation and iwiki because this changes the workflow contract.

### Hard (architectural enforcement)

- Do not change runtime hooks, profiles, launcher behavior, or model-selection mechanisms unless targeted analysis proves a direct requirement.
- Do not select `full` before an approved intent and intent-scoped repository analysis.
- Preserve the LoEn carve-out and intent-backed result reconciliation.

## Autonomy Zones

- Full autonomy: draft and validate the intent; inspect affected policy, tests, docs, and hooks; implement agreed policy, documentation, and test changes.
- Guarded: recommend `execute` or `full` only with file-level evidence after intent validation.
- Proposal-first: any runtime-hook, profile, model-routing, or scope expansion beyond policy, documentation, and tests.
- No autonomy: operate `/model` or `/status`, push changes, or open a pull request.

## Stop Rules

- Halt if targeted analysis shows that the policy change requires a runtime behavior change.
- Escalate if a new unresolved design choice affects routing semantics beyond the agreed scope.
- Done when route-table tests prove direct-discovery, default-execute, and full-trigger behavior, and AGENTS, README, and iwiki contain no contradictory route rules.

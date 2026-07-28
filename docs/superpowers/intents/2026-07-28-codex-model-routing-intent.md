---
workflow:
  route: chain
  continuation: execute
review:
  intent_hash: 4815fde7128019c2
  last_run: 2026-07-28
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
result_check:
  verdict: OK
  source: intent
  intent_hash: 4815fde7128019c2
  last_run: 2026-07-28
  reviewed: true
  docs_checked: true
---

# Intent: codex-model-routing

**Date:** 2026-07-28
**Status:** approved

## Objective

Reduce unnecessary Codex cost without weakening work that has evidenced complexity.
Add an instruction-only policy that recommends `direct`, `chain`, or `loen`. After an
approved chain intent, recommend either immediate execution or the full spec/plan path.
Reassess the model and reasoning effort before work and after relevant checks.

The policy produces a recommendation only. It must not edit TOML, install profiles,
change runtime configuration, create model-routing scripts, or claim that the active
interactive model changed. The user retains control of any switch through `/model`.

## Desired Outcomes

- Every transition after intent, spec, plan, task review, and result validation has a
  lowest normal model and reasoning baseline.
- Every task receives an objective `direct`, `chain`, or `loen` recommendation, while
  bounded direct work creates no chain artifacts.
- After intent validation, a chain records `execute` or `full`: `execute` skips spec and
  plan and reconciles result against intent; `full` preserves the complete chain.
- Every direct task still receives a model and reasoning recommendation before execution
  and is reassessed when checks, scope, or discovered invariants change its evidence.
- LoEn work receives the same evidence-based model recommendation at loop checkpoints
  without entering the IDD->SDD chain.
- Each recommendation names the workflow checkpoint, semantic execution route, current
  catalog resolution, observable evidence, decision, and switch requirement.
- Stable execution routes are `mechanical`, `engineering`, `synthesis`, `deep`,
  `escalation`, and `parallel-audit`; classification never depends on model branding.
- Exact model and effort pairs appear only in one current-catalog mapping table.
- Deep, escalation, and parallel-audit routes require explicit observable triggers and
  never carry forward automatically.
- A failed check or first failed attempt does not by itself increase model or effort.
- `parallel-audit` is recommended only as a separate independent audit, never inside
  active subagent orchestration.
- Critical migrations always receive a separate final integration review at `deep` or
  higher.

## Health Metrics

- The shared AGENTS policy contains deterministic stage baselines, classification rules,
  escalation rules, and one fixed recommendation format.
- The policy separates workflow routing from execution routing, so choosing direct or
  chain continuation `execute` never skips model/reasoning analysis.
- `check-chain result` closes a chain with continuation `execute` against its intent
  without inventing spec/plan, while preserving plan-backed result for `full`.
- Model catalog changes require updating only the current-catalog mapping, not workflow,
  classification, escalation, README, or wiki prose.
- Every expensive recommendation cites an artifact, finding, failure, invariant, or
  concrete risk.
- The policy explicitly chooses the lower route when evidence is absent or ambiguous.
- Existing Codex configuration, launcher behavior, profiles, and agent role files remain
  unchanged.
- Existing repository tests remain green.

## Strategic Context

- Interacts with: `.codex-isolated/AGENTS.md`, `check-chain`, Superpowers and LoEn
  boundaries, repository workflow docs, the interactive `/model` control, and user
  decisions.
- Priority trade-off: trust > cost > speed.

## Constraints

### Steering (behavioral guidance)

- Reassess only the next stage from current evidence.
- Prefer direct discovery for bounded work. Use chain when outcomes or constraints need
  a formal intent; after intent validation choose `execute` unless an enumerated design
  or planning trigger requires `full`.
- Treat keep and downgrade as normal outcomes; escalation is exceptional.
- Start from `mechanical` or `engineering` when the next task can be completed safely.
- Use concise recommendations rather than duplicating the checked artifact.
- Change strategy before retrying a failed attempt.

### Hard (architectural enforcement)

- Do not add or modify TOML profiles, runtime config mutation, launcher wiring, runtime
  model-routing scripts, or specialized role files for this task.
- Do not infer that any behavior change requires `fix-intent` or chain. Scoped
  Superpowers skills may run on direct tasks without creating chain artifacts.
- Route selection overrides generic brainstorming trigger wording for direct tasks; do
  not invoke chain-only Superpowers skills after choosing direct execution.
- Store `workflow.route: chain` and `workflow.continuation: execute|full` in intent
  frontmatter. Write execute-result state against the current intent hash; never claim
  plan-backed validation without a plan.
- Do not silently switch the active model or reasoning effort.
- Do not use `deep` because a stage is named plan or result, because a diff is large, or
  because one attempt failed.
- Treat two or more coupled subsystem boundaries as a `deep` trigger.
- Do not use `escalation` as a default or `parallel-audit` inside existing subagent
  orchestration.
- Do not continue after a declined escalation without explicit risk acceptance, and do
  not waive the final review of a critical migration.
- Do not let an implementer revise accepted upstream artifacts.

## Autonomy Zones

- Full autonomy: inspect accepted artifacts and checks, recommend keep or downgrade,
  and choose `mechanical` or `engineering` from complete evidence.
- Guarded: recommend `synthesis` or `deep` only with a cited classification trigger.
- Proposal-first: recommend `escalation`, a separate `parallel-audit`, or any model
  switch before the next stage.
- No autonomy: operate the user's `/model` control or claim a switch occurred.

## Stop Rules

- Halt before the next stage when a recommended switch requires user action.
- Refuse escalation without a concrete trigger.
- Return artifact drift to the earliest affected gate.
- Done when the policy separates direct, chain, and LoEn work; branches chain execution
  after intent; supports intent-backed and plan-backed results; centralizes current model
  mapping; rejects unjustified cost increases; keeps docs consistent; changes no runtime
  model-selection mechanism; and existing tests pass.

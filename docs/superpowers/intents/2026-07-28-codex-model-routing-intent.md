---
review:
  intent_hash: 71858e405689301d
  last_run: 2026-07-28
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
---

# Intent: codex-model-routing

**Date:** 2026-07-28
**Status:** approved

## Objective

Reduce unnecessary Codex cost without weakening work that has evidenced complexity.
Add an instruction-only policy to `.codex-isolated/AGENTS.md` that reassesses the model
and reasoning effort after each `check-chain` verdict and before the next workflow stage.

The policy produces a recommendation only. It must not edit TOML, install profiles,
change runtime configuration, create model-routing scripts, or claim that the active
interactive model changed. The user retains control of any switch through `/model`.

## Desired Outcomes

- Every transition after intent, spec, plan, task review, and result validation has a
  lowest normal model and reasoning baseline.
- Each recommendation names the completed checkpoint, next stage, current route,
  recommended route, decision, observable evidence, rejected higher mode, and whether
  the user must switch.
- Luna handles only completely determined mechanical work; Terra Medium remains the
  ordinary engineering default.
- Sol Medium is limited to non-trivial specification and planning synthesis.
- Sol High, Sol Max, and Ultra require explicit observable triggers and never carry
  forward automatically.
- Every named route resolves to one exact `gpt-5.6-*` model and effort pair; Ultra is
  always `gpt-5.6-sol / ultra`.
- A failed check or first failed attempt does not by itself increase model or effort.
- Ultra is recommended only as a separate independent audit, never inside active
  subagent orchestration.
- Critical migrations always receive a separate final integration review at Sol High
  or higher.

## Health Metrics

- The shared AGENTS policy contains deterministic stage baselines, classification rules,
  escalation rules, and one fixed recommendation format.
- The routing section stays at or below 600 words to limit its prompt overhead.
- Every expensive recommendation cites an artifact, finding, failure, invariant, or
  concrete risk.
- The policy explicitly chooses the lower route when evidence is absent or ambiguous.
- Existing Codex configuration, launcher behavior, profiles, and agent role files remain
  unchanged.
- Existing repository tests remain green.

## Strategic Context

- Interacts with: `.codex-isolated/AGENTS.md`, Superpowers chain boundaries,
  `check-chain` verdicts, the interactive `/model` control, and user decisions.
- Priority trade-off: trust > cost > speed.

## Constraints

### Steering (behavioral guidance)

- Reassess only the next stage from current evidence.
- Treat keep and downgrade as normal outcomes; escalation is exceptional.
- Start from Luna Medium or Terra Medium when the next task can be completed safely
  there.
- Use concise recommendations rather than duplicating the checked artifact.
- Change strategy before retrying a failed attempt.

### Hard (architectural enforcement)

- Do not add or modify TOML profiles, runtime config mutation, launcher wiring,
  validation scripts, or specialized role files for this task.
- Do not silently switch the active model or reasoning effort.
- Do not use Sol High because a stage is named plan or result, because a diff is large,
  or because one attempt failed.
- Treat two or more coupled subsystem boundaries as a Sol High trigger.
- Do not use Max as a default or Ultra inside existing subagent orchestration.
- Do not continue after a declined escalation without explicit risk acceptance, and do
  not waive the final review of a critical migration.
- Do not let an implementer revise accepted upstream artifacts.

## Autonomy Zones

- Full autonomy: inspect accepted artifacts and checks, recommend keep or downgrade,
  and choose Luna Medium or Terra Medium from complete evidence.
- Guarded: recommend Sol Medium or Sol High only with a cited classification trigger.
- Proposal-first: recommend Sol Max, a separate Ultra audit, or any model switch before
  the next stage.
- No autonomy: operate the user's `/model` control or claim a switch occurred.

## Stop Rules

- Halt before the next stage when a recommended switch requires user action.
- Refuse escalation without a concrete trigger.
- Return artifact drift to the earliest affected gate.
- Done when the AGENTS-only policy covers every chain boundary, rejects unjustified
  cost increases, makes switching advisory and visible, changes no runtime mechanism,
  and existing tests pass.

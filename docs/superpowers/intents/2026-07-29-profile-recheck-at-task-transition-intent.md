---
review:
  intent_hash: 083e52604fe6b830
  last_run: 2026-07-29
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

# Intent: profile-recheck-at-task-transition

**Date:** 2026-07-29
**Status:** approved

## Objective

Add an automatic model-transition check that evaluates the active Codex model before
protected task work continues. When a changed model satisfies the current task's
documented requirements, the hook permits work to continue without another manual
profile check. When evidence is missing or insufficient, it blocks protected work and
states the required user action.

This narrowly extends the earlier instruction-only model-routing policy with a runtime
guardrail; it does not let the wrapper or hook choose a model on the user's behalf.

## Desired Outcomes

- A hook detects an active model-slug change per Codex session before protected work.
- A local, versioned capacity registry evaluates capability, context-window, latency,
  cost, and throughput tiers without claiming live measurements.
- A task with an exact, sufficient requirement continues automatically after the model
  change.
- A missing registry entry, task requirement, reasoning-effort confirmation, or
  sufficient capacity blocks protected work with an actionable reason.
- The hook never changes the active model, invokes `/model`, or creates an automatic
  continuation loop.

## Health Metrics

- Existing secret guards, caveman, IDD, LoEn, and iwiki hook wiring remains enabled and
  idempotent.
- The hook uses documented hook payload fields and does not parse session transcripts.
- The default decision is safe: unknown state does not allow protected work.
- The hook performs no network requests and introduces no hidden usage cost.
- Existing tests remain green, and focused tests cover sufficient, insufficient, and
  unknown transition states.

## Strategic Context

- Interacts with: `icodex.sh`, `lib/idd/idd.sh`, per-project `hooks.json`,
  `.codex-isolated/hooks/`, `.codex-isolated/AGENTS.md`, the model-routing wiki page,
  and the user's interactive `/model` and `/status` controls.
- Priority trade-off: trust > speed > cost.
- Relationship: supersedes the runtime-hook exclusion in
  `2026-07-28-codex-model-routing-intent.md` only for this approved, scoped capability.

## Constraints

### Steering (behavioral guidance)

- Continue automatically only when the registry and recorded task requirement make the
  decision unambiguous.
- Keep capacity attributes qualitative tiers, not fabricated live metrics.
- Return a concise reason that names the missing or insufficient evidence.
- Preserve the existing policy's human control over model selection and risk waivers.

### Hard (architectural enforcement)

- Read only the documented `model` field from hook payloads; do not parse
  `transcript_path`.
- Treat active reasoning effort, remaining context capacity, and live latency, cost, and
  throughput as unknown unless separately confirmed through a supported source.
- Store state by `session_id` under `$CODEX_HOME/state/`.
- Do not issue `/model`, mutate model configuration, make network requests, or use a
  `Stop` hook to create a continuation loop.
- Preserve existing hook entries and register the new hook idempotently through the
  launcher wiring.
- Do not change `chain-gate.py` frontmatter, the Task Log schema, or chain verdict
  semantics.

## Autonomy Zones

- Full autonomy: detect a model-slug change, read the local registry and task state, and
  allow a clearly sufficient transition.
- Guarded: persist the decision and inject concise context about the detected transition.
- Proposal-first: change the capacity registry, hook wiring, blocking semantics, or
  model-routing policy.
- No autonomy: switch the user's model, accept a risk waiver, or invent capacity values.

## Stop Rules

- Halt if the registry, task requirement, or required supported confirmation is absent.
- Escalate if a requested automatic decision would rely on transcript parsing, live
  metrics, an undocumented payload field, or a change to existing chain semantics.
- Done when a model change with documented, sufficient capacity permits the first
  protected tool call, while insufficient or unknown state blocks it with a precise
  remediation; composition and focused tests pass without weakening existing hooks.

---
review:
  intent_hash: d295d68a68c99a8b
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

Add an automatic model-transition system that evaluates the active Codex model before
protected task work continues. Each topic declares a user-approved profile matrix. At a
task boundary, an orchestrator selects a sufficient approved profile and starts the next
Codex turn with it. The hook permits protected work only when the selected profile and
task requirement agree.

The hook is a runtime guardrail, not a model selector. The orchestrator may choose only
from the approved matrix; unknown requirements, new risks, or critical failures outside
that matrix require user clarification.

A profile is sufficient only when it meets or exceeds every required qualitative tier
recorded for the task in the capacity registry.

## Desired Outcomes

- Each topic has a user-approved matrix of model and reasoning-effort profiles with
  capacity tiers.
- A hook detects an active model-slug change per Codex session before protected work.
- A local, versioned capacity registry evaluates capability, context-window, latency,
  cost, and throughput tiers without claiming live measurements.
- At each task boundary, an orchestrator starts the next Codex turn with a sufficient
  profile from the approved matrix, without requiring a manual profile change.
- LoEn iterations continue without repeated profile evaluation while the topic,
  requirement, registry version, and selected profile remain unchanged.
- A missing registry entry, task requirement, approved profile, or sufficient capacity
  blocks protected work with an actionable reason.
- A newly discovered risk, increased complexity, or critical failure blocks automatic
  selection when it requires a profile outside the approved matrix.
- The hook never invokes `/model` or creates an automatic continuation loop.

## Health Metrics

- Existing secret guards, caveman, IDD, LoEn, and iwiki hook wiring remains enabled and
  idempotent.
- Existing interactive Codex launches remain available; orchestration is an explicit
  execution path rather than an implicit replacement.
- The hook uses documented hook payload fields and does not parse session transcripts.
- The default decision is safe: unknown state does not allow protected work.
- The hook performs no network requests and introduces no hidden usage cost.
- Existing tests remain green, and focused tests cover sufficient, insufficient, and
  unknown transition states.

## Strategic Context

- Interacts with: `icodex.sh`, `lib/idd/idd.sh`, per-project `hooks.json`,
  `.codex-isolated/hooks/`, `.codex-isolated/AGENTS.md`, the model-routing wiki page,
  the Codex App Server, and the user's interactive `/model` and `/status` controls.
- Priority trade-off: trust > speed > cost.
- Relationship: supersedes the runtime-hook exclusion in
  `2026-07-28-codex-model-routing-intent.md` only for this approved, scoped capability.

## Constraints

### Steering (behavioral guidance)

- Continue automatically only when the registry and recorded task requirement make the
  decision unambiguous.
- Select profiles automatically only from the topic's approved matrix.
- Re-evaluate a LoEn topic only when its selected profile, requirement, or registry
  version changes.
- Keep capacity attributes qualitative tiers, not fabricated live metrics.
- Return a concise reason that names the missing or insufficient evidence.
- Preserve the existing policy's human control over model selection and risk waivers.

### Hard (architectural enforcement)

- Read only the documented `model` field from hook payloads; do not parse
  `transcript_path`.
- Treat active reasoning effort, remaining context capacity, and live latency, cost, and
  throughput as unknown unless separately confirmed through a supported source.
- Store state by `session_id` under `$CODEX_HOME/state/`.
- Do not issue `/model`, mutate model configuration, make network requests from the
  hook, or use a `Stop` hook to create a continuation loop.
- Use App Server `turn/start` model and effort overrides only at task boundaries and
  only for a profile in the approved matrix.
- Preserve existing hook entries and register the new hook idempotently through the
  launcher wiring.
- Do not change `chain-gate.py` frontmatter, the Task Log schema, or chain verdict
  semantics.

## Autonomy Zones

- Full autonomy: detect a model-slug change, read the local registry and task state,
  choose a clearly sufficient profile from the approved matrix, and allow that
  transition.
- Guarded: persist the decision and inject concise context about the detected transition.
- Proposal-first: change the capacity registry, hook wiring, blocking semantics, or
  model-routing policy.
- No autonomy: choose a profile outside the approved matrix, accept a risk waiver, or
  invent capacity values.

## Stop Rules

- Halt if the registry, task requirement, approved profile, or required supported
  confirmation is absent.
- Escalate if a requested automatic decision would rely on transcript parsing, live
  metrics, an undocumented payload field, a profile outside the approved matrix, or a
  change to existing chain semantics.
- Done when a task boundary selects and starts an approved sufficient profile without a
  manual switch; LoEn avoids repeated checks for an unchanged selection; insufficient
  or unknown state blocks with a precise remediation; composition and focused tests pass
  without weakening existing hooks.

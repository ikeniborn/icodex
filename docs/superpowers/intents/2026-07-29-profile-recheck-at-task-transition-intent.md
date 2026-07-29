---
review:
  intent_hash: 63ec74acade51667
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
protected task work continues. One shared capacity registry must apply to every project
launched by this icodex installation. Each project retains its own authoritative manifest
under the target repository's `docs/profiles/` directory, and runtime reads it directly
from that repository. At a task boundary, an orchestrator selects a sufficient approved
profile and starts the next Codex turn with it. The hook permits protected work only when
the selected profile and task requirement agree.

The shared registry must be available through the shared `.codex-isolated/` store and a
per-home symlink. The per-project manifest requires a durable, reviewed, secret-free Git
source so the same approved policy can be reconstructed on another machine. Session
history remains machine-local runtime state.

The hook is a runtime guardrail, not a model selector. The orchestrator may choose only
from the approved matrix; unknown requirements, new risks, or critical failures outside
that matrix require user clarification.

A profile is sufficient only when it meets or exceeds every required qualitative tier
recorded for the task in the capacity registry.

## Desired Outcomes

- Every launched project home uses one shared, user-approved registry of model and
  reasoning-effort capacity tiers.
- Each project has a distinct authoritative manifest under its target repository's
  `docs/profiles/` directory; no home copy or manifest symlink is required.
- The manifest's approved source and hash survive cross-machine work through a reviewed,
  secret-free Git artifact.
- A hook detects an active model-slug change per Codex session before protected work.
- A shared, versioned capacity registry evaluates capability, context-window, latency,
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
- Project homes continue to isolate sessions, logs, and mutable runtime state from each
  other.
- A missing `state/profile-routing/` on another machine produces a safe cold start: policy
  is revalidated and no prior task progress is inferred.
- No auth material, caches, temporary files, SQLite state, raw session files, or other
  internal Codex state enters Git.
- Existing shared-asset symlink behavior and offline launch remain available.
- Existing interactive Codex launches remain available; orchestration is an explicit
  execution path rather than an implicit replacement.
- The hook uses documented hook payload fields and does not parse session transcripts.
- The default decision is safe: unknown state does not allow protected work.
- The hook performs no network requests and introduces no hidden usage cost.
- Existing tests remain green, and focused tests cover sufficient, insufficient, and
  unknown transition states.

## Strategic Context

- Interacts with: `icodex.sh`, `lib/config/isolated.sh`, `lib/idd/idd.sh`, per-project
  `hooks.json`, `.codex-isolated/`, `.codex-homes/`, `.codex-isolated/hooks/`,
  `.codex-isolated/AGENTS.md`, the model-routing wiki page, the Codex App Server, and
  the user's interactive `/model` and `/status` controls.
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
- Keep session history machine-local; do not add portable history export/import.

### Hard (architectural enforcement)

- Read only the documented `model` field from hook payloads; do not parse
  `transcript_path`.
- Treat active reasoning effort, remaining context capacity, and live latency, cost, and
  throughput as unknown unless separately confirmed through a supported source.
- Store mutable runtime state by `session_id` under `$CODEX_HOME/state/`; it is never
  a Git authority.
- Keep the shared registry under `.codex-isolated/` and link it into every per-project
  home; do not duplicate or independently edit it per project.
- Read the project manifest directly from the target repository's approved
  `docs/profiles/<topic>.yaml`; do not copy or symlink it into the project home.
- Keep handoffs, decisions, and orchestration progress under the per-project
  `$CODEX_HOME/state/profile-routing/`. Missing state starts a new local run and never
  implies cross-machine continuation.
- Never add a whole `.codex-homes/` tree, session history, or a session export to Git.
  Only approved project profile sources under `docs/profiles/` may be tracked.
- Do not issue `/model`, mutate model configuration, make network requests from the
  hook, or use a `Stop` hook to create a continuation loop.
- Use App Server `turn/start` model and effort overrides only at task boundaries and
  only for a profile in the approved matrix.
- Preserve existing hook entries and register the new hook idempotently through the
  launcher wiring.
- Do not change `chain-gate.py` frontmatter, the Task Log schema, or chain verdict
  semantics.

## Autonomy Zones

- Full autonomy: detect a model-slug change, read the shared registry and project
  manifest, choose a clearly sufficient profile from the approved matrix, and allow
  that transition.
- Guarded: persist the decision and inject concise context about the detected transition.
- Proposal-first: change the capacity registry, manifest source, registry-home symlink,
  hook wiring, blocking semantics, or model-routing policy.
- No autonomy: choose a profile outside the approved matrix, accept a risk waiver,
  invent capacity values, or track secrets, raw session state, or runtime-home contents.

## Stop Rules

- Halt if the shared registry, project manifest, approved source hash, task requirement,
  approved profile, or required supported confirmation is absent or mismatched.
- Escalate if a requested automatic decision would rely on transcript parsing, live
  metrics, an undocumented payload field, a profile outside the approved matrix, a
  change to existing chain semantics, or Git tracking of secrets/raw runtime state.
- Done when two project homes on different machines can use the same reviewed registry,
  validate and use the same approved project manifest from `docs/profiles/`, and
  select/start a sufficient profile without a manual switch while session history and
  routing state stay machine-local; missing state produces an explicit new cold start,
  unknown policy blocks with a precise remediation, and focused tests pass without
  weakening existing hooks.

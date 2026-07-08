---
review:
  intent_hash: a288eb7962e37707
  last_run: 2026-07-08
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
---
# Intent: LoEn loop run orchestration

**Date:** 2026-07-08
**Status:** approved

## Objective

Make LoEn start and execution feel like one guided workflow instead of a sequence of manual skill calls after planning.

Today, `loen:loop-start` creates or reuses a durable topic directory, then the user must manually invoke the next LoEn skills: `loop-plan`, `loop-act`, `loop-check`, `loop-reflect`, and for governance topics `loop-governance`. The target behavior is that `loen:loop-start` becomes the requirements, intent, mode selection, parameter collection, and plan approval step. After the plan is approved, it explicitly hands off to a new runner skill such as `loen:loop-run <topic>`. The user can confirm that run immediately at the end of `loop-start` or launch it later by naming the topic.

The runner must carry the chosen mode through to `7_result.md` or `handoff.md` without requiring the user to manually call `loop-act`, `loop-check`, or `loop-reflect` for every pass.

## Desired Outcomes

- `loen:loop-start` asks the user for requirements, intent, success criteria, launch mode, and mode-specific parameters before execution starts.
- `loen:loop-start` offers at least `delivery` and `governance` mode selection, then collects the parameters required for the selected mode.
- `loen:loop-start` presents a plan for user approval before any automated run begins.
- After plan approval, `loen:loop-start` offers to invoke `loen:loop-run <topic>` immediately, while still allowing the user to run the same topic later.
- `loen:loop-run <topic>` reads approved topic artifacts and drives the selected mode without requiring manual calls to `loop-act`, `loop-check`, or `loop-reflect` on the happy path.
- A successful run leaves a complete LoEn artifact trail ending in `docs/loen/<topic>/7_result.md`, regenerated `audit.html`, and verifier evidence.
- A run that cannot safely continue leaves `docs/loen/<topic>/handoff.md` with the stop reason and the next human action.
- Governance runs record `governance:` policy in `loop.yaml`, append run records to `attempts.jsonl`, preserve evidence, and show automation state in `audit.html`.

## Health Metrics

- Existing manual LoEn skills remain usable: `loop-plan`, `loop-act`, `loop-check`, `loop-reflect`, `loop-governance`, and `loop-status` still work as standalone steps.
- `docs/loen/<topic>/` remains the source of truth for loop state across context compaction, new threads, and runner handoff.
- `LOEN_MODE=off|advisory|enforce|strict` behavior must not be bypassed by the runner.
- Protected scope checks, evidence gates, role/tool policy, verifier requirements, and worker/verifier separation must not weaken.
- Governance defaults remain conservative unless the user explicitly chooses a stronger mode during `loop-start`.
- `docs/TODO.md` remains the only global human-readable task registry.

## Strategic Context

- Interacts with: `plugins/loen/skills/loop-start/SKILL.md`, a new runner skill such as `plugins/loen/skills/loop-run/SKILL.md`, `plugins/loen/skills/loop-plan/SKILL.md`, `plugins/loen/skills/loop-act/SKILL.md`, `plugins/loen/skills/loop-check/SKILL.md`, `plugins/loen/skills/loop-reflect/SKILL.md`, `plugins/loen/skills/loop-governance/SKILL.md`, `plugins/loen/hooks/*.py`, `plugins/loen/assets/templates/*`, `plugins/loen/README.md`, `plugins/loen/docs/architecture.md`, `docs/loen/<topic>/`, `docs/TODO.md`, and the `icodex` iwiki domain.
- Priority trade-off: trust first. The design should prefer explicit artifacts, approved plans, verifier evidence, safe stop rules, and auditability over a faster but opaque runner.

## Constraints

### Steering (behavioral guidance)

- Keep `loop-start` focused on intake, mode selection, parameter collection, scaffold/update of topic artifacts, and plan approval.
- Keep execution in a separate runner skill so a user can review or defer after `loop-start`.
- Prefer reusing the existing LoEn stage artifacts and skill responsibilities instead of inventing a second runtime state model.
- Preserve a visible approval point after planning and before execution.
- Treat governance modes as explicit choices made during `loop-start`, not as hidden defaults.
- For governance, default to report-only behavior unless the user explicitly chooses auto-fix or merge/release automation.
- Merge/release automation belongs in this design as a governance mode, but it must be policy-driven and evidence-backed rather than an implicit side effect.

### Hard (architectural enforcement)

- Do not make `loop-start` perform code changes, merge, release, or destructive operations.
- Add execution through a separate runner skill, named or equivalent to `loen:loop-run`.
- Do not require manual user calls to `loop-act`, `loop-check`, or `loop-reflect` during the approved runner happy path.
- Keep manual LoEn skills backward compatible.
- Do not bypass `LOEN_MODE`, protected scope, evidence gates, verifier commands, role/tool policy, or worker/verifier separation.
- Do not create a second global task registry; keep `docs/TODO.md` as the only global human-readable task index.
- Do not let governance auto-fix, merge, or release unless that mode was explicitly selected during `loop-start` and recorded in `loop.yaml`.
- For merge/release automation, approval at `loop-start` is sufficient; do not require a second final human approval gate if the approved policy, verifier, scope, and evidence requirements pass.

## Autonomy Zones

- Full autonomy (reversible, low risk): `loop-start` may scaffold or update LoEn topic artifacts, ask intake questions, write approved plan metadata, and offer the `loen:loop-run <topic>` handoff.
- Full autonomy (reversible, low risk): `loop-run` may drive delivery mode inside the approved `mutable_scope`, budget, verifier commands, and rollback policy until `7_result.md` or `handoff.md`.
- Full autonomy (reversible, low risk): `loop-run` may drive governance report-only mode by running checks, collecting evidence, appending `attempts.jsonl`, regenerating `audit.html`, and writing `7_result.md` or `handoff.md` without code changes.
- Guarded (log + confidence threshold): `loop-run` may perform governance auto-fix only when `loop-start` explicitly recorded `auto_fix: true`, mutable scope, verifier, budget, and rollback policy.
- Guarded (log + confidence threshold): `loop-run` may perform governance merge/release automation only when `loop-start` explicitly recorded the mode, target branch or release policy, verifier requirements, scope limits, budget, rollback or recovery policy, and completion criteria.
- Proposal-first (needs approval): change LoEn hook enforcement semantics, change `LOEN_MODE` meaning, weaken protected-scope or evidence gates, or change `docs/TODO.md` format.
- No autonomy (human only): silently enable auto-fix, merge, release, destructive operations, protected-scope edits, network publication, or secret-affecting changes without explicit start-time approval and recorded policy.

> These zones OVERRIDE subagent-driven-development's "continuous execution,
> don't pause" default. Any task touching proposal-first / no-go decisions
> is marked HUMAN CHECKPOINT in the plan.

## Stop Rules

- Halt if: a topic lacks an approved plan from `loop-start`.
- Halt if: the runner would need to edit protected scope, use a forbidden tool, bypass verifier evidence, or continue after budget exhaustion.
- Halt if: the selected governance mode is ambiguous or missing from `loop.yaml`.
- Halt if: merge/release automation lacks explicit start-time approval, target policy, verifier pass requirements, scope limits, or recovery policy.
- Escalate if: a verifier fails and the next fix is not bounded, a required command is unavailable, a merge/release policy is contradictory, or a governance run reaches an unmodeled risk.
- Done when: `loop-start` can collect intake, mode, parameters, and plan approval, then hand off to `loen:loop-run <topic>`.
- Done when: `loen:loop-run <topic>` can complete delivery mode to `7_result.md` with evidence and audit, or stop with `handoff.md`.
- Done when: `loen:loop-run <topic>` can complete governance report-only, auto-fix, and merge/release modes according to recorded policy, evidence, and stop rules, or stop with `handoff.md`.
- Done when: existing manual LoEn skills and safety hooks remain compatible and focused tests demonstrate both the manual path and runner path.

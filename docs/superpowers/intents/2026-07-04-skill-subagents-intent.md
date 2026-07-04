---
review:
  intent_hash: 2e674130990c6c60
  last_run: 2026-07-04
  phases:
    structure: { status: passed }
    completeness: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
    alignment: { status: passed }
  findings: []
---
# Intent: skill-subagents

**Date:** 2026-07-04
**Status:** approved

## Objective
Design and later implement both layers for subagent-aware skills: tracked custom subagents for the isolated icodex environment and updates to the existing skills so they can delegate suitable work while preserving a concise main context.

The target skills are:

- `.codex-isolated/skills/check-chain/SKILL.md`
- `.codex-isolated/skills/html-report/SKILL.md`
- `.codex-isolated/skills/mermaid-obsidian/SKILL.md`
- `.codex-isolated/skills/git-workflow/SKILL.md`
- `.codex-isolated/skills/context-awareness/SKILL.md`

## Desired Outcomes
- Each target skill has explicit guidance for when to use a subagent, when to stay in the main context, and what summary format returns to the main context.
- The repository contains tracked custom agent configuration for the isolated icodex environment.
- Each custom agent has a clear name, model choice, and reasoning effort with rationale tied to the work it performs.
- Smoke tests or checks demonstrate that every target skill either delegates to the intended agent pattern or explicitly remains in the main context.

## Health Metrics
- Accuracy and reliability of checks must not degrade.
- Subagent routing must not hide blocking findings, unsafe git actions, missing source data, or failed validation.
- The main agent must receive enough evidence to verify a result without pulling noisy intermediate logs into the main context.

## Strategic Context
- Interacts with: Codex custom agents, isolated icodex runtime files, target `SKILL.md` files, IDD/SDD chain artifacts, `docs/TODO.md`, iwiki documentation, and git-tracked repository state.
- Priority trade-off: trust first; speed and token cost are secondary and may be optimized only when they do not reduce accuracy or reliability.

## Constraints
### Steering (behavioral guidance)
- Prefer simple or lower-cost models only for read-heavy, template-like, or deterministic review tasks where quality risk is low.
- Use stronger reasoning for chain validation, git safety, and any task where missed findings can cause incorrect completion.
- Keep subagent outputs structured and concise: decision, evidence, uncertainty, and recommended next action.
- Keep changes narrow to the target skills and agent configuration unless a verification check proves a supporting tracked file must change.

### Hard (architectural enforcement)
- Add agents and skill changes to the isolated icodex environment, not only to a personal `~/.codex` location.
- Track all new agent configs and skill edits in git.
- Do not change runtime Bash code under `icodex.sh`, `lib/`, or `tests/` in the first implementation stage unless the approved plan later identifies an unavoidable wiring gap.
- Do not lower accuracy or reliability of `check-chain`, `html-report`, `mermaid-obsidian`, `git-workflow`, or `context-awareness`.
- Do not rely on undocumented `SKILL.md` frontmatter to auto-spawn subagents.

## Autonomy Zones
- Full autonomy (reversible, low risk): choose custom agent names, model choices, reasoning effort, and summary schemas when each choice is documented with rationale and checked by verification.
- Guarded (log + confidence threshold): choose lightweight model use for read-heavy or template-like work; proceed only with explicit rationale that explains why trust is not reduced.
- Proposal-first (needs approval): add new runtime wiring, change shell modules/tests, or move agent files outside the isolated icodex environment.
- No autonomy (human only): accept reduced validation accuracy, weaken git safety rules, skip required chain gates, or store agents only in an untracked personal Codex home.

> These zones OVERRIDE subagent-driven-development's "continuous execution,
> don't pause" default. Any task touching proposal-first / no-go decisions
> is marked HUMAN CHECKPOINT in the plan.

## Stop Rules
- Halt if: implementing the design requires runtime Bash changes before the skill/agent-only layer is proven insufficient.
- Halt if: a proposed simple model cannot be justified without reducing trust.
- Escalate if: documented Codex custom agent behavior conflicts with observed behavior in this environment.
- Escalate if: baseline tests fail in the new worktree before implementation changes.
- Done when: the branch contains tracked isolated icodex agent configs, updated target skills, rationale for each agent's name/model/reasoning effort, and verification output showing the full Bash suite plus focused smoke checks pass.

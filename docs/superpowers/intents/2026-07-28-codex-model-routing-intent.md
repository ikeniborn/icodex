---
review:
  intent_hash: ac8f4053fb1c3dc3
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

Reduce Codex token use and elapsed time across the icodex engineering workflow without weakening architectural decisions, implementation quality, or final integration checks. Replace ad hoc model and reasoning selection with documented profiles, specialized subagent roles, and evidence-based transition recommendations between `intent`, `spec`, `plan`, execution, and result validation.

Keep one interactive thread as the primary workflow. A selected TOML profile remains a startup preset, while `AGENTS.md` recommends whether to keep, downgrade, or escalate the active model and reasoning effort after each successful chain gate. The user performs any in-session switch through Codex model controls so the workflow preserves context and does not launch nested Codex processes.

## Desired Outcomes

- Every workflow stage has a documented default model, reasoning effort, and launch profile.
- After each `check-chain` gate, the user sees a concise next-stage recommendation that names the current and recommended modes, cites observable complexity evidence, and explicitly says whether to keep, downgrade, escalate, or use a separate run.
- Simple and fully determined work uses Luna or Terra; Sol is reserved for work that needs deeper design, debugging, integration, or risk analysis.
- High, Max, and Ultra are selected only when their documented entry conditions are met, and higher effort does not carry into the next stage without a fresh assessment.
- Specialized subagents receive bounded responsibilities, required input artifacts, output contracts, completion criteria, and escalation conditions.
- A specific subagent launch can override the normal role model or reasoning recommendation without inventing unsupported TOML fields.
- Ultra never becomes an inherited execute-worker mode and is used only for a separate, independently parallelizable audit.
- Operators can start any named profile with `--profile`, inspect the effective configuration, and restore the standard icodex configuration through a documented rollback procedure.

## Health Metrics

- Every configured model slug and reasoning effort exists in the bundled model catalog of the pinned Codex release.
- Every profile parses as TOML and loads from the active per-project `CODEX_HOME` without unknown configuration keys.
- The full Bash test suite remains green, including focused tests for profile distribution, role contracts, routing policy, and rollback behavior.
- Routine implementation does not use Sol High, Max, or Ultra unless the transition recommendation records a matching observable trigger.
- A higher mode selected for one stage is downgraded or retained only after the next checkpoint performs a fresh assessment.
- Existing sandbox, approval, permission, project-home isolation, plugin, hook, telemetry, and iwiki behavior remains unchanged unless explicitly required to distribute the new profiles.

## Strategic Context

- Interacts with: `.codex-isolated/config.toml`, per-project `CODEX_HOME` provisioning, `.codex-isolated/agents/`, `.codex-isolated/AGENTS.md`, Superpowers skills and `check-chain` gates, the Codex CLI model picker, profile loading, Bash tests, project documentation, and human operators.
- Priority trade-off: trust > cost > speed.

## Constraints

### Steering (behavioral guidance)

- Start every next-stage assessment from the lowest mode that can satisfy the accepted artifacts and observed risks.
- Treat keeping the current mode and downgrading as first-class recommendations; escalation is not the default outcome of a checkpoint.
- Base every escalation on paths, artifacts, failed checks, subsystem boundaries, contracts, data risks, or other observable evidence.
- Reassess complexity after every gate; do not inherit High, Max, or Ultra merely because an earlier stage used it.
- Change strategy before repeating a failed attempt.
- Keep recommendations concise enough to avoid duplicating the checked artifact.

### Hard (architectural enforcement)

- Use the exact supported model slugs `gpt-5.6-luna`, `gpt-5.6-terra`, and `gpt-5.6-sol`.
- Provide named startup profiles for `default`, `spec`, `plan`, `implement`, `simple`, `complex`, `review`, `final-review`, `escalation`, and `parallel-audit` as `$CODEX_HOME/<profile>.config.toml` layers selected through `--profile`.
- Keep the interactive workflow in one thread; do not start nested Codex processes to change a stage mode.
- Do not use Sol for mechanical work without a recorded trigger, Max as a standard mode, or Ultra inside `subagent-driven-development` or another active subagent orchestration.
- Do not allow an implementer to change approved intent, spec, or plan decisions; detected divergence returns to the earliest affected gate.
- Do not hide an escalation, repeat the same failed strategy, or execute a critical migration without a separate final integration review.
- Keep subagent role model and reasoning choices overridable for a specific spawn. Do not pin those fields in a custom-agent file if current Codex precedence would make the pin override explicit spawn parameters.
- Use only documented Codex configuration keys and model-catalog-supported values.
- Preserve existing user-owned runtime configuration outside the managed profile and routing surfaces.

## Autonomy Zones

- Full autonomy (reversible, low risk): inspect documentation and configuration, classify task complexity from evidence, recommend keeping or downgrading a mode, validate TOML and model-catalog compatibility, and prepare rollback instructions.
- Guarded (log + confidence threshold): recommend Sol High from documented complexity triggers, route bounded work to a specialized role, and provision managed profile links into a per-project `CODEX_HOME` without overwriting unrelated user files.
- Proposal-first (needs approval): change approved routing semantics, recommend Sol Max, recommend a separate Ultra audit, or resolve a conflict between deterministic role pinning and per-spawn override behavior.
- No autonomy (human only): operate the interactive `/model` control, accept a critical migration risk, waive a blocking chain finding, or authorize Ultra inside an existing execute orchestration.

> These zones override subagent-driven-development's continuous-execution default at model-transition and critical-risk checkpoints. The main agent owns the user-visible recommendation and waits when a model change or proposal-first decision is required.

## Stop Rules

- Halt if: the pinned Codex catalog does not support a configured model or reasoning effort, a profile contains an unknown key, or project configuration precedence prevents the requested effective mode without a disclosed override.
- Halt if: role configuration cannot simultaneously preserve the documented spawn precedence and the required per-run override behavior.
- Halt if: a requested escalation has no observable trigger, Ultra would create nested orchestration, or a critical migration lacks an independent final review path.
- Escalate if: two materially different Sol High strategies fail, reviewers return contradictory conclusions about the same invariant, an unexplained required test failure remains, or a migration presents a credible data-loss risk.
- Done when: all ten profiles load through `--profile`, all specialized roles expose complete behavioral contracts, checkpoint recommendations objectively select keep/downgrade/escalate decisions, explicit subagent spawn overrides remain possible, Ultra is isolated from execute orchestration, rollback restores the standard configuration, focused and full tests pass, and current Codex documentation plus the pinned model catalog support every shipped key and value.

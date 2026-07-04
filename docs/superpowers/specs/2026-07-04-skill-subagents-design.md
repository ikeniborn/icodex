# Design: trust-first subagents for isolated icodex skills

**Date:** 2026-07-04
**Status:** draft
**Topic:** skill-subagents

## Objective

Add trust-first subagent support for five existing icodex skills by implementing both required layers:

- tracked custom agent files inside the isolated icodex environment;
- explicit routing guidance inside the target `SKILL.md` files.

The target skills are:

- `.codex-isolated/skills/check-chain/SKILL.md`
- `.codex-isolated/skills/html-report/SKILL.md`
- `.codex-isolated/skills/mermaid-obsidian/SKILL.md`
- `.codex-isolated/skills/git-workflow/SKILL.md`
- `.codex-isolated/skills/context-awareness/SKILL.md`

Codex documentation supports custom agents through standalone TOML files under a Codex home agent directory. It does not document a `SKILL.md` frontmatter field that automatically forks a skill into a child context. Therefore this design uses custom agent files plus imperative skill instructions. Subagents analyze, draft, validate, and summarize; the main agent keeps final responsibility for user-facing decisions, writes, git mutations, and IDD/SDD gate transitions.

## Acceptance (from intent)

### Desired Outcomes

- Each target skill has explicit guidance for when to use a subagent, when to stay in the main context, and what summary format returns to the main context.
- The repository contains tracked custom agent configuration for the isolated icodex environment.
- Each custom agent has a clear name, model choice, and reasoning effort with rationale tied to the work it performs.
- Smoke tests or checks demonstrate that every target skill either delegates to the intended agent pattern or explicitly remains in the main context.

### Health Metrics

- Accuracy and reliability of checks must not degrade.
- Subagent routing must not hide blocking findings, unsafe git actions, missing source data, or failed validation.
- The main agent must receive enough evidence to verify a result without pulling noisy intermediate logs into the main context.

### Done When

- The branch contains tracked isolated icodex agent configs, isolated `CODEX_HOME` wiring for those agents, updated target skills, rationale for each agent's name/model/reasoning effort, and verification output showing the full Bash suite plus focused smoke checks pass.

## Non-Goals

- Do not add a private or undocumented `SKILL.md` frontmatter field for automatic subagent spawning.
- Do not rewrite the target skills beyond the routing sections required for this feature.
- Do not change skill semantics, phase checklists, git safety rules, Obsidian Mermaid constraints, HTML report constraints, or context-awareness detection priorities.
- Do not add runtime wiring beyond the approved `.codex-isolated/agents` shared-store path.
- Do not require every skill invocation to spawn a subagent. Small, low-noise tasks can stay in the main context.

## Architecture

### 1. Isolated Agent Runtime Wiring

`icodex` currently links shared assets from `.codex-isolated` into each per-project `CODEX_HOME` through `setup_codex_home`:

- `plugins`
- `hooks`
- `hooks.json`
- `auth.json`
- `skills`
- `rules`

This design adds `agents` to that list:

```text
.codex-isolated/agents  ->  $CODEX_HOME/agents
```

The implementation must:

- create `.codex-isolated/agents/` as the tracked source of project custom agents;
- add `.codex-isolated/agents/**` to the `.gitignore` whitelist;
- add `_link_shared agents` to `lib/config/isolated.sh`;
- extend `tests/test_isolated.sh` so a generated home has `CODEX_HOME/agents` symlinked to the shared store;
- extend `tests/test_gitignore.sh` so `.codex-isolated/agents/*.toml` is tracked-eligible.

This is the only runtime Bash wiring approved by the intent. The rest of the feature stays in tracked agent files, skill instructions, and tests.

### 2. Custom Agent Files

Add custom agent files under `.codex-isolated/agents/*.toml`. Every file must define:

- `name`
- `description`
- `developer_instructions`

Each file should also define:

- `model`
- `model_reasoning_effort`
- `sandbox_mode` when the agent should be constrained more tightly than the parent session.

The default project model is `gpt-5.5` with high reasoning. Agent overrides are chosen by risk:

- high-trust validation or git safety uses `gpt-5.5` and `high`;
- read-heavy or syntax/template checking uses `gpt-5.4-mini` and `medium`;
- shallow project scanning can use `gpt-5.4-mini` and `low` only when the main context performs the final synthesis.

### 3. Skill Routing Sections

Each target `SKILL.md` gets a compact `## Subagent Routing` section with the same structure:

- `Use subagent when:` noisy, read-heavy, parallelizable, or review-like work would pollute the main context.
- `Stay in main context when:` a user confirmation, file write, git mutation, final verdict, or gate transition is required.
- `Agent:` the custom agent name.
- `Return summary:` a structured summary with `decision`, `evidence`, `risks`, and `next_action`.
- `Stop rule:` what uncertainty or finding forces the main agent to halt or ask.

The language should say "spawn" or "delegate" only as an instruction to the current Codex agent. It must not imply that Codex automatically forks a skill because of frontmatter.

### 4. Trust Boundary

Subagents can do:

- read-heavy exploration;
- draft validation findings;
- draft report or diagram artifacts;
- summarize evidence;
- identify risks and uncertainties.

The main agent keeps:

- user confirmations;
- final file writes;
- frontmatter/report/TODO updates in the IDD chain;
- git branch, stage, commit, push, and PR operations;
- final user-facing result statements.

If a subagent returns uncertainty, missing evidence, an unsafe state, or any blocking finding, the main context treats that as a stop signal, not as a permission to continue.

## Agent Catalog

### `chain-auditor`

- File: `.codex-isolated/agents/chain-auditor.toml`
- Model: `gpt-5.5`
- Reasoning effort: `high`
- Primary skill: `check-chain`
- Rationale: `check-chain` is a gate in the IDD/SDD workflow. Missed CRITICAL findings, wrong hashes, or wrong result verdicts can mark incomplete work as valid. The agent therefore uses the strongest trust-first profile.
- Work delegated: phase scans, section/hash evidence, result diff reconciliation drafts, and report/TODO update checklist.
- Main-context ownership: confirmation prompts, verdict handling, frontmatter writes, HTML report merge, TODO row update, and downstream-chain stop/go decision.
- Required summary: stage, verdict draft, findings table, hash/state evidence, report/TODO checklist, uncertainty.

### `artifact-renderer`

- File: `.codex-isolated/agents/artifact-renderer.toml`
- Model: `gpt-5.4-mini`
- Reasoning effort: `medium`
- Primary skill: `html-report`
- Rationale: HTML report work is mostly structured recipe selection and checklist validation. `gpt-5.4-mini` is appropriate for read-heavy/template-heavy artifact review, while `medium` reasoning preserves enough rigor for zero-dependency and chain-tab checks.
- Work delegated: recipe selection, data-source coverage scan, chain-tab merge risk scan, and self-validation checklist.
- Main-context ownership: ambiguous source selection, final file write, and final user report.
- Required summary: selected recipe, source coverage, self-validation pass/fail, guarded warnings, missing data.

### `diagram-checker`

- File: `.codex-isolated/agents/diagram-checker.toml`
- Model: `gpt-5.4-mini`
- Reasoning effort: `medium`
- Primary skill: `mermaid-obsidian`
- Rationale: Mermaid/Obsidian work is rule-heavy syntax validation with bounded constraints. A smaller model is acceptable when the instructions require explicit rule evidence and the main context owns final delivery.
- Work delegated: syntax lint, Obsidian-specific constraint scan, corrected diagram draft, render-risk notes.
- Main-context ownership: resolving semantic ambiguity with the user and final answer/file edit.
- Required summary: corrected Mermaid, rule violations fixed, unresolved semantics, render-risk notes.

### `repo-safety-reviewer`

- File: `.codex-isolated/agents/repo-safety-reviewer.toml`
- Model: `gpt-5.5`
- Reasoning effort: `high`
- Primary skill: `git-workflow`
- Rationale: git workflow can lose work, commit unrelated changes, or push the wrong branch. Trust and review quality outrank token cost.
- Work delegated: branch/status/diff risk review, staged-file plan, conventional commit message draft, PR readiness scan.
- Main-context ownership: all mutating git commands and final decision to commit, push, or open a PR.
- Required summary: current branch, dirty files grouped by task relevance, risks, proposed staged files, commit message draft, readiness verdict.

### `project-explorer`

- File: `.codex-isolated/agents/project-explorer.toml`
- Model: `gpt-5.4-mini`
- Reasoning effort: `low`
- Primary skill: `context-awareness`
- Rationale: context-awareness is read-only and detection-oriented. A low-reasoning mini agent can scan file layout and docs cheaply, while the main context synthesizes final `project_context` and chooses verification commands.
- Work delegated: file/doc scan, project language/framework hints, iwiki status summary, candidate test/syntax command hints.
- Main-context ownership: final `project_context`, task-specific doc interpretation, and any deep wiki search decision.
- Required summary: detected signals, evidence paths, ambiguous signals, recommended syntax/test command, wiki status.

## Skill Routing Requirements

### R1. `check-chain`

`check-chain` must document `chain-auditor` as its analysis subagent.

It delegates:

- phase scans;
- section/hash evidence;
- result diff reconciliation drafts;
- report/TODO update checklist.

It stays in the main context for:

- "Буду проверять..." confirmations;
- final verdict handling;
- frontmatter writes;
- HTML report merge;
- TODO row update;
- downstream chain stop/go decisions.

Stop rule: any CRITICAL finding, hash mismatch uncertainty, missing artifact, or result reconciliation uncertainty halts downstream stages until the main context resolves it.

### R2. `html-report`

`html-report` must document `artifact-renderer` as its artifact-review subagent.

It delegates:

- recipe selection;
- named data-point coverage;
- chain-tab merge risk scan;
- self-validation checklist.

It stays in the main context for:

- ambiguous source selection;
- final file write;
- user-facing report of output path, file size, and guarded warnings.

Stop rule: missing source data, external resource need, non-self-contained output, or tab corruption uncertainty stops the write.

### R3. `mermaid-obsidian`

`mermaid-obsidian` must document `diagram-checker` as its syntax/review subagent.

It delegates:

- syntax lint;
- Obsidian 11.4.1 constraint scan;
- corrected diagram draft;
- render-risk notes.

It stays in the main context for:

- semantic questions;
- final answer or file edit.

Stop rule: if the user's intended graph semantics are ambiguous, ask instead of inventing structure.

### R4. `git-workflow`

`git-workflow` must document `repo-safety-reviewer` as its risk-review subagent.

It delegates:

- branch/status/diff risk review;
- staged-file plan;
- conventional commit message draft;
- PR readiness scan.

It stays in the main context for all mutating git commands:

- checkout;
- branch creation;
- add;
- commit;
- push;
- PR creation.

Stop rule: unrelated dirty files, wrong branch, untracked secrets, missing validation, or unclear base branch blocks mutation until resolved.

### R5. `context-awareness`

`context-awareness` must document `project-explorer` as its read-only scan subagent.

It delegates:

- file layout scan;
- docs skeleton scan;
- iwiki status summary;
- candidate syntax/test command hints.

It stays in the main context for:

- final `project_context` synthesis;
- task-specific doc interpretation;
- deep semantic wiki search decisions.

Stop rule: contradictory project signals are reported as ambiguity; the main context decides or asks.

## Data Flow

1. User invokes a task that triggers one of the target skills.
2. The main agent reads that skill through the normal progressive-disclosure flow.
3. The skill decides whether the current task crosses the routing threshold.
4. If delegation is useful and allowed, the main agent spawns the named custom agent with a bounded prompt.
5. The subagent returns only the structured summary.
6. The main agent validates the summary against the skill's stop rules.
7. The main agent performs any final write, git mutation, report merge, or user-facing response.

## Error Handling

- Missing `CODEX_HOME/agents` symlink: tests fail; do not rely on personal `~/.codex/agents`.
- Missing required TOML key: focused smoke check fails.
- Unknown or unavailable model: do not silently downgrade; report the mismatch and choose an approved fallback in the plan before implementation proceeds.
- Subagent summary missing `decision`, `evidence`, `risks`, or `next_action`: treat as incomplete and ask for a rerun or perform the analysis in the main context.
- Any subagent uncertainty on safety-critical tasks: main context halts mutation or downstream gate progression.

## Testing

Implementation must verify:

- `bash tests/test_isolated.sh` proves `CODEX_HOME/agents -> .codex-isolated/agents`.
- `bash tests/test_gitignore.sh` proves `.codex-isolated/agents/*.toml` is tracked-eligible.
- A focused smoke check parses `.codex-isolated/agents/*.toml` and verifies required keys: `name`, `description`, `developer_instructions`, `model`, and `model_reasoning_effort`.
- A focused text smoke check verifies each target `SKILL.md` contains `## Subagent Routing` and names its intended agent.
- The full suite passes:

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

## Documentation

This design is the source spec for the implementation plan. After implementation changes behavior, update the `icodex` iwiki domain before final response:

- document that isolated custom agents live under `.codex-isolated/agents`;
- document that `setup_codex_home` symlinks agents into per-project `CODEX_HOME`;
- document the five agent names and the trust boundary.

Run `wiki_lint` after updating the wiki.

# LoEn Plugin

LoEn is the Loop Engineering plugin source bundled with icodex. It provides
Codex skills, hooks, agents, and templates for durable work loops that keep task
state in repository files instead of chat history.

## What LoEn Adds

- Skills named `loen:loop-start`, `loen:loop-plan`, `loen:loop-act`,
  `loen:loop-check`, `loen:loop-reflect`, `loen:loop-status`,
  `loen:loop-repair`, `loen:loop-research`, `loen:loop-review`, and
  `loen:loop-governance`.
- Hook scripts that can enforce active loop state, mutable/protected scope,
  role/tool policy, shell/network policy, and final evidence requirements.
- Role agent definitions and context capsules for planner, worker, verifier,
  reviewer, and researcher flows.
- Templates for durable loop artifacts under `docs/loen/<topic>/`.

## Skill Responsibilities

| Skill | Use it when | Responsibility |
|---|---|---|
| `loen:loop-start` | Starting a new loop or selecting a durable topic. | Creates or reuses `docs/loen/<topic>/`, initializes `loop.yaml`, stage files, `attempts.jsonl`, `handoff.md`, topic-scoped `audit.html`, and `evidence/`. |
| `loen:loop-plan` | A goal exists and the loop needs one bounded pass. | Converts `1_goal.md`, `2_context.md`, and `loop.yaml` into `3_plan.md` with exact verification commands. |
| `loen:loop-act` | The active plan has one next action. | Executes one bounded action, then records changed files, commands, and observations in `4_act.md`. |
| `loen:loop-check` | Code, docs, or configuration changed. | Runs planned checks and records exit codes, output summaries, and evidence references in `5_check.md`. |
| `loen:loop-reflect` | Check evidence exists and the loop needs a decision. | Decides keep, fix, revert, or handoff; writes `6_reflect.md` and, when complete, `7_result.md`. |
| `loen:loop-status` | You need the current state of one or more topics. | Reads artifacts, reports current stage, latest evidence, open decisions, and next action. |
| `loen:loop-repair` | Evidence shows a failing test, CI failure, regression, or broken behavior. | Captures failure context, narrows the repair surface, and routes back to planning or action. |
| `loen:loop-research` | The task is an experiment with a measurable question. | Records metrics, baseline, experiment step, check commands, observed results, and decision threshold. |
| `loen:loop-review` | Reviewing a diff, branch, or pull request. | Records review scope, findings, evidence, and final review disposition inside the topic artifacts. |
| `loen:loop-governance` | A topic represents a recurring check, audit, CI triage, eval drift check, or cost/latency comparison. | Records recurrence policy, automation attempts, human-review requirements, verifier evidence, and audit updates. |

## Runtime Enablement in icodex

icodex wires LoEn into each isolated Codex home during normal launch. Install and
update commands stay binary-only and do not configure LoEn.

Control runtime behavior with `ICODEX_LOEN_MODE`:

| Mode | Behavior |
|---|---|
| `off` | Disable LoEn wiring and hooks. |
| `advisory` | Enable skills and non-blocking hook nudges. This is the default. |
| `enforce` | Block missing loop state, stage-order violations, protected paths, and missing evidence. |
| `strict` | Add role, tool, shell/network, and worker/verifier separation checks. |

Example:

```bash
ICODEX_LOEN_MODE=advisory ./icodex.sh
```

## Working With a Loop

Start with `loen:loop-start` to create a topic directory:

```text
docs/loen/<topic>/
```

Typical sequence:

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'background': '#1e1e2e', 'primaryColor': '#313244', 'primaryTextColor': '#cdd6f4', 'primaryBorderColor': '#89b4fa', 'lineColor': '#888888', 'secondaryColor': '#181825', 'tertiaryColor': '#45475a'}}}%%
sequenceDiagram
    participant User as User
    participant Start as loen:loop-start
    participant Plan as loen:loop-plan
    participant Act as loen:loop-act
    participant Check as loen:loop-check
    participant Reflect as loen:loop-reflect
    participant Status as loen:loop-status
    participant Files as docs/loen/topic

    User->>Start: create durable topic
    Start->>Files: write loop.yaml and stage files
    User->>Plan: request bounded plan
    Plan->>Files: update 3_plan.md
    User->>Act: execute one action
    Act->>Files: update 4_act.md
    User->>Check: run verifier commands
    Check->>Files: write 5_check.md and evidence
    User->>Reflect: decide keep, fix, revert, or handoff
    Reflect->>Files: update 6_reflect.md or 7_result.md
    User->>Status: inspect current state
    Status-->>User: stage, evidence, next action
```

## How a Loop Reaches a Solution

The normal delivery loop is driven by `loop-plan`, `loop-act`, `loop-check`, and
`loop-reflect`. Governance is not the step runner for ordinary work.

Each pass answers one question: did the last bounded action move the topic closer
to the objective with enough evidence to keep it?

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {'background': '#1e1e2e', 'primaryColor': '#313244', 'primaryTextColor': '#cdd6f4', 'primaryBorderColor': '#89b4fa', 'lineColor': '#888888', 'secondaryColor': '#181825', 'tertiaryColor': '#45475a'}}}%%
flowchart TD
    StartTopic["loen:loop-start creates docs/loen/<topic>/"] --> Branch{"Execution branch?"}

    subgraph delivery["Delivery pass"]
        PlanStep["loen:loop-plan writes 3_plan.md"]
        ActStep["loen:loop-act writes 4_act.md"]
        CheckStep["loen:loop-check writes 5_check.md and evidence/*"]
        ReflectStep{"loen:loop-reflect outcome"}
        ResultStep["7_result.md plus topic audit.html"]
        FixStep["Fix needs another bounded pass"]
        HandoffStep["handoff.md records human handoff"]
    end

    subgraph governance["Governance pass"]
        GovStep["loen:loop-governance"]
        GovPolicy["Required: loop.yaml governance owner, schedule, review rules"]
        GovAttempt["Required: attempts.jsonl automation record"]
        GovEvidence["Required: evidence/* verifier output"]
        GovAudit["Required: docs/loen/<topic>/audit.html"]
        GovReview{"Human review required?"}
        GovWait["Wait for owner review"]
    end

    Branch -- "ordinary task" --> PlanStep
    PlanStep --> ActStep
    ActStep --> CheckStep
    CheckStep --> ReflectStep
    ReflectStep -- "keep and objective met" --> ResultStep
    ReflectStep -- "fix" --> FixStep
    FixStep --> PlanStep
    ReflectStep -- "handoff" --> HandoffStep

    Branch -- "recurring or scheduled topic" --> GovStep
    GovStep --> GovPolicy
    GovPolicy --> GovAttempt
    GovAttempt --> GovEvidence
    GovEvidence --> GovAudit
    GovAudit --> GovReview
    GovReview -- "yes" --> GovWait
    GovReview -- "no" --> ReflectStep

    classDef decision fill:#f9e2af,color:#1e1e2e,stroke:#df8e1d
    classDef deliveryClass fill:#89b4fa,color:#1e1e2e,stroke:#74c7ec
    classDef governanceClass fill:#94e2d5,color:#1e1e2e,stroke:#179299
    classDef artifactClass fill:#a6e3a1,color:#1e1e2e,stroke:#40a02b
    class Branch,ReflectStep,GovReview decision
    class PlanStep,ActStep,CheckStep,FixStep,HandoffStep deliveryClass
    class GovStep,GovPolicy,GovAttempt,GovEvidence,GovAudit,GovWait governanceClass
    class ResultStep artifactClass
```

1. `loop-plan` narrows the goal to one verifiable action and writes checks into
   `3_plan.md`.
2. `loop-act` performs only that action and records what changed in `4_act.md`.
3. `loop-check` runs or inspects the planned checks and stores evidence in
   `5_check.md` plus `docs/loen/<topic>/evidence/`.
4. `loop-reflect` reads action and check evidence, then chooses one outcome:
   `keep`, `fix`, `revert`, or `handoff`.
5. If the outcome is `fix`, the next pass starts with a narrower plan based on
   the failed evidence.
6. If the outcome is `revert`, the next action restores the scoped change before
   another check.
7. If the outcome is `handoff`, the loop records why it cannot safely continue in
   `handoff.md`.
8. If the outcome is `keep` and the objective is satisfied, `loop-reflect` writes
   `7_result.md`; `audit.html` is regenerated for the topic.

The loop is complete only when the topic has a result and enough check evidence
to justify it. `loop-status` is read-only; it summarizes the current stage and
next action but does not advance the loop.

The topic directory stores:

| Artifact | Purpose |
|---|---|
| `1_goal.md` | User request, objective, and success criterion for the loop. |
| `2_context.md` | Facts, relevant files, constraints, and evidence summaries. |
| `3_plan.md` | Bounded plan and verification commands for one loop pass. |
| `4_act.md` | Action evidence: changed files, commands, and observations. |
| `5_check.md` | Check results, exit codes, and verifier evidence references. |
| `6_reflect.md` | Decision to keep, fix, revert, or hand off. |
| `7_result.md` | Final outcome when the loop is complete. |
| `loop.yaml` | Machine-readable contract: topic, mode, scope, verifier, budget, stop rules, and governance. |
| `attempts.jsonl` | Append-only run log for manual or automated attempts. |
| `evidence/` | Raw check output such as logs, JSON summaries, or verifier files. |
| `handoff.md` | Human handoff state when the loop cannot continue safely. |
| `audit.html` | Regenerated human-readable audit view for this topic at `docs/loen/<topic>/audit.html`. |

Use `loen:loop-status` to inspect current state. Continue with
`loen:loop-plan`, `loen:loop-act`, `loen:loop-check`, and
`loen:loop-reflect` for one bounded pass through the loop.

## Minimal Example

Request:

```text
Use LoEn to fix the failing proxy test.
```

Expected first pass:

```text
loen:loop-start creates docs/loen/fix-proxy-test/
loen:loop-plan writes a one-pass plan in 3_plan.md
loen:loop-act changes only the scoped files
loen:loop-check runs the configured test and stores evidence/latest-test.log
loen:loop-reflect records keep/fix/revert/handoff
```

If `ICODEX_LOEN_MODE=enforce`, edits outside the configured mutable scope or a
final answer without check evidence can be blocked by hooks.

## Automation Governance

Use `loen:loop-governance` for recurring or scheduled topics such as CI triage,
dependency audits, eval drift checks, and cost or latency comparisons. It adds
policy around a loop; it does not replace the normal plan, act, check, and
reflect pass.

Governance topics still write ordinary LoEn artifacts under
`docs/loen/<topic>/`, append automation attempts to `attempts.jsonl`, store
verifier output under `evidence/`, and regenerate
`docs/loen/<topic>/audit.html`.

The governance branch requires these artifacts before it can be treated as a
recorded run:

| Required artifact | Purpose |
|---|---|
| `loop.yaml` `governance:` | Owner, schedule, review rules, alert conditions, and safe automation defaults. |
| `attempts.jsonl` | Append-only automation run record with status, summary, evidence path, and review flags. |
| `evidence/` | Verifier output for the scheduled or recurring run. |
| `audit.html` | Topic-scoped audit regenerated at `docs/loen/<topic>/audit.html`. |

Automation is advisory in this plugin source. It must not auto-merge, perform
destructive operations, edit protected scope, or complete first runs without the
human-review requirements recorded in `loop.yaml`.

## Vendoring for Codex

Edit plugin source in this directory. To regenerate the committed Codex cache
used by icodex launch wiring, run:

```bash
./scripts/vendor-loen.sh
```

The script copies this source tree into:

```text
.codex-isolated/plugins/cache/icodex-local/loen/<version>/
```

It validates required assets and strips generated files such as `__pycache__`
and `*.pyc`.

## Boundaries

LoEn is self-contained and does not depend on other workflow plugins. It writes
loop state only under `docs/loen/<topic>/` and updates `docs/TODO.md` as the
global task index. It does not auto-merge, rewrite protected files, or bypass
`LOEN_MODE`.

Plugin internals are documented in `plugins/loen/docs/architecture.md`.

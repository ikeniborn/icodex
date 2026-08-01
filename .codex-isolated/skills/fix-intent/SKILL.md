---
name: fix-intent
description: 'Use BEFORE superpowers:brainstorming for any non-trivial work (new module, CLI flag, API change, arch decision). Triggers on "/fix-intent", "/idd", "capture intent", "intent doc". If brainstorming would start on non-trivial work without an approved intent doc in docs/superpowers/intents/, run IDD first. Brainstorm proceeds only when intent Status: approved.'
---

# IDD — Intent-Driven Design

## Overview

IDD captures *why* before *how*. Run before `superpowers:brainstorming` to anchor the spec to real objectives — preventing specs that are precisely wrong (right HOW, wrong WHAT/WHY).

IDD owns WHY / WHAT / Outcomes / Constraints. Brainstorm owns HOW (architecture, components, error handling, tests). Once an intent doc is approved, brainstorm treats the IDD answers as fixed inputs and does not re-ask them.

## When to use / When not to use

| Trigger | Action |
|---------|--------|
| New module / new CLI flag / API change / arch decision | Run IDD |
| Hotfix / typo / formatting change | Skip |
| Intent doc already exists in `docs/superpowers/intents/` | Validate its current review state, then honor or obtain its `execute|full` continuation |
| Bounded work with no durable intent decision | Use the project workflow classifier; `direct` may skip IDD |
| A durable intent decision is needed, even when implementation is familiar | Run IDD, then choose `execute|full` from evidence |

## Process

### Step 0: Load project context via iwiki (if available)

Before asking any questions, check the iwiki MCP server. If connected, `wiki_status`;
if a domain for this project exists, `wiki_bind(read=[<domain>], write=<domain>)` and load
context in parallel:

1. `wiki_search('<topic>')` — existing documentation for this topic

Store results as **wiki_context** for use in Steps 1–6 below.

Present to user:

```
Context from iwiki domain `<name>`:
[sections found, or "No documentation found for this topic"]
```

If the iwiki MCP server is unavailable, no project domain exists, or the search returns no
results — skip silently. Do not block or mention the absence.

---

### Steps 1–6: Six questions (one at a time)

Ask each question **one at a time**. Wait for the user's answer before proceeding. Do not batch.

For each question, if **wiki_context** contains relevant information — show it as a hint before asking. If wiki_context is empty — ask the plain question.

---

**Q1 — Objective:** What problem does this solve, and why now?

> *If wiki_context has relevant docs:*
> "From existing documentation on '[topic]': [brief summary — what is already documented, what decisions were made].
> What exactly needs to change or be added, and why now?"

---

**Q2 — Desired Outcomes:** What observable, user-facing states confirm success?

*(No wiki enrichment — outcomes are user-defined, not derivable from existing docs.)*

---

**Q3 — Health Metrics:** What must not degrade?

> *If wiki_context returned components:*
> "These components reference this area: [list from wiki_context].
> Which of them must not break? Which metrics must stay stable?"
>
> *(Goodhart's Law: name the metrics that stay stable even if the feature ships.)*

---

**Q4 — Strategic Context:** What systems, modules, or people interact with this? Priority trade-off: trust / speed / cost?

> *If wiki_context has architecture sections:*
> "From the architecture documentation: [relevant fragment].
> What else interacts with this area? What is the priority — trust / speed / cost?"

---

**Q5 — Constraints:** What steering constraints (behavioral guidance) apply? What hard constraints (architectural or forbidden) apply?

> *If wiki_context has decisions or constraints sections:*
> "Existing architectural decisions on this topic: [fragment from the iwiki domain].
> Which of them still hold? What is added as a new constraint?"

---

**Q6 — Autonomy & Stop Rules:** For each decision type, which autonomy zone applies: full / guarded / proposal-first / no-go? What conditions halt, escalate, or mark completion?

*(No wiki enrichment — autonomy policy is defined by the user per feature.)*

---

### After all six answers

**Validation checklist** — verify before presenting the doc:

1. All sections filled — no empty bullets?
2. Every constraint maps to steering OR hard (not both)?
3. Autonomy zones cover all decision types in this feature?
4. Stop Rules include at least one "Done when:" criterion, phrased as an observable result or measurable metric (not "implemented / code written")?

Fix any failures inline, then present.

**Write the intent doc** using the template below. Fill each section with the user's answers verbatim or lightly edited for clarity.

**File path:** `docs/superpowers/intents/YYYY-MM-DD-<topic>-intent.md`

**Topic profile bootstrap:** Create the draft topic profile before validation, after
writing the intent and before running `$check-chain intent`. Use the manifest helper;
do not write profile YAML inline:

```bash
topic="your-topic-slug"
intent_path="docs/superpowers/intents/$(date +%F)-${topic}-intent.md"
helper="$ICODEX_ROOT/lib/profile/manifest.py"
project_root="$(git rev-parse --show-toplevel)"
registry_path="$CODEX_HOME/profiles/registry.yaml"
python3 "$helper" bootstrap --project-root "$project_root" --registry "$registry_path" --topic "$topic" --intent "$intent_path" --status draft
```

The helper creates the single `intent-profile-selection` task for intent review and
selection of the routed profile. The manifest remains `status: draft`; the profile runner must not execute it
until the user has explicitly approved the checked intent and this manifest.

**Validation-first user review gate:**

1. Show a summary of the written document.
2. Run `$check-chain intent <path>` while the intent is still `Status: draft`.
   The check must update frontmatter and return `OK` before any approval request. If
   it returns `needs_work`, fix the markdown source first, rerun `$check-chain intent
   <path>`, and do not ask for approval yet.
3. Present the checked intent summary, markdown path, and draft topic profile for
   approval. Ask: "Review the checked intent and draft topic profile. Approve them or
   request changes."
4. On changes requested: edit the markdown source → rerun `$check-chain intent <path>`
   → update the draft topic profile when its context or routing selection changes →
   present the checked summary again → repeat.
5. On approval, set `Status: approved` and set the topic profile `status: approved`.
   Recommend `execute` or `full` from the checked
   intent and repository evidence:
   - `execute` when implementation and verification are bounded and no unresolved
     design/planning trigger remains;
   - `full` only for an evidenced architecture, public-contract, migration, security,
     concurrency/transaction/data-integrity, or coupled-subsystem design decision.
6. Ask the user to accept the continuation. An explicit earlier instruction to execute
   from intent or use continuation `full` counts as acceptance. Then write only
   frontmatter:

```yaml
workflow:
  route: chain
  continuation: execute | full
```

This records `workflow.route: chain` and the accepted
`workflow.continuation: execute|full` without changing the intent body hash.

7. For an accepted `full` continuation, after the approved manifest and
   `workflow.continuation: full` are recorded, expand it with the helper before any
   spec or plan work. This block can run in a fresh shell: replace
   `your-topic-slug` with the approved topic slug.

```bash
topic="your-topic-slug"
helper="$ICODEX_ROOT/lib/profile/manifest.py"
project_root="$(git rev-parse --show-toplevel)"
registry_path="$CODEX_HOME/profiles/registry.yaml"
python3 "$helper" expand --project-root "$project_root" --registry "$registry_path" --topic "$topic" --route full --authorization full
```

   This produces the canonical ordered tasks: `intent-profile-selection`, `spec-design`,
   `plan-writing`, `implementation`, and `result-reconciliation`. The helper must not add
   future spec or plan paths until those files exist. For `execute`, do not expand the
   manifest: it does not add spec or plan tasks.

8. Commit the approved intent, topic profile, and continuation once:

```bash
git add docs/superpowers/intents/ docs/profiles/
git commit -m "docs(idd): add intent profile for $topic"
```

9. For `execute`, hand off directly:

```text
Intent doc approved at <path> (Status: approved; continuation: execute).
Do not run brainstorming or writing-plans. Implement only from the approved
Desired Outcomes, Health Metrics, Hard Constraints, and Stop Rules, using scoped
implementation skills. Finish with $check-chain result <path>.
```

10. For `full`, hand off with this message:

```text
Intent doc approved at <path> (Status: approved).
Run superpowers:brainstorming. It MUST read this intent doc first and
treat Objective, Desired Outcomes, Health Metrics, and Hard Constraints
as FIXED inputs — do NOT re-ask Q1–Q5.
Carry Desired Outcomes + "Done when" verbatim into the design doc as an
"## Acceptance (from intent)" section so they reach writing-plans and
spec review.
```

## Intent doc template

```markdown
# Intent: <topic>

**Date:** YYYY-MM-DD
**Status:** draft

## Objective
[Answer to Q1]

## Desired Outcomes
- [observable state 1]
- [observable state 2]

## Health Metrics
- [metric that must not degrade]

## Strategic Context
- Interacts with: [modules / agents / humans]
- Priority trade-off: [trust | speed | cost]

## Constraints
### Steering (behavioral guidance)
- [guideline 1]
### Hard (architectural enforcement)
- [restriction 1]

## Autonomy Zones
- Full autonomy (reversible, low risk): [decision types]
- Guarded (log + confidence threshold): [decision types]
- Proposal-first (needs approval): [decision types]
- No autonomy (human only): [decision types]

> These zones OVERRIDE subagent-driven-development's "continuous execution,
> don't pause" default. Any task touching proposal-first / no-go decisions
> is marked HUMAN CHECKPOINT in the plan.

## Stop Rules
- Halt if: [condition]
- Escalate if: [condition]
- Done when: [completion criterion — observable result or measurable metric,
  not "implemented / code written"]
```

## Outcome Verification (run before result closure)

**Trigger:** during `$check-chain result` against the selected intent or plan source.

This is the IDD payoff superpowers does not provide: verify the RESULT against intent, not "tests green / code matches spec".

1. Re-read intent doc: Desired Outcomes + Health Metrics + "Done when".
2. Per Desired Outcome: run the real scenario, record the OBSERVABLE
   result. Green tests are NOT evidence of an outcome.
3. Per Health Metric: measure it, confirm no degradation.
4. Compare to intent. Mismatch = intent-compliance defect → return to
   spec/intent, do NOT patch code to mask it.
5. Done only when every Desired Outcome passes AND no Health Metric
   degraded. Passing tests on an unmet outcome = NOT done.

## Common mistakes

- **"It's a small change"** — A new CLI flag is a CLI API change. Still run IDD. Intent docs take 5 minutes and prevent hours of misaligned work.
- **"Let me ask one clarifying question and proceed"** — Asking scope is not capturing intent. Scope answers WHAT; intent captures WHY, outcomes, and stop conditions.
- **"iwiki not available"** — Skip Step 0 silently. Never block IDD or mention the absence of iwiki context. The process works without it.
- **"subagent-driven said not to stop"** — The intent doc's Autonomy Zones override continuous-execution. A no-go / proposal-first decision means halt and escalate.
- **"Tests are green, so it's done"** — Green tests are not a completed outcome. Done is determined by Outcome Verification against Desired Outcomes, not by a test run.
- **"Approved intent always means brainstorming"** — First recommend `execute|full`; only `full` enters brainstorming.
- **"Brainstorm already asked about the goal"** — If the intent doc is approved, brainstorm does not re-ask WHY/WHAT/Outcomes/Constraints. Duplicate questions mean the intent doc never reached brainstorm (see handoff).

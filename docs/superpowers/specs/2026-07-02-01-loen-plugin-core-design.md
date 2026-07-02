---
title: 01 LoEn plugin core design
date: 2026-07-02
status: draft
chain:
  intent: null
---

# 01 LoEn plugin core design

## Purpose

Define the editable LoEn plugin source tree under `plugins/loen/`. This layer
creates the plugin manifest, reusable skills, agent definitions, hook scripts,
and templates without wiring them into icodex runtime yet.

## Source Layout

```text
plugins/loen/
  .codex-plugin/
    plugin.json
  skills/
    loop-start/SKILL.md
    loop-plan/SKILL.md
    loop-act/SKILL.md
    loop-check/SKILL.md
    loop-reflect/SKILL.md
    loop-status/SKILL.md
    loop-repair/SKILL.md
    loop-research/SKILL.md
    loop-review/SKILL.md
    loop-governance/SKILL.md
  hooks/
    hooks.json
    loop-gate.py
    scope-guard.py
    tool-guard.py
    permission-guard.py
    evidence-gate.py
    audit-writer.py
  agents/
    loen-planner.toml
    loen-worker.toml
    loen-verifier.toml
    loen-reviewer.toml
    loen-researcher.toml
  assets/
    templates/
      loop.yaml
      1_goal.md
      2_context.md
      3_plan.md
      4_act.md
      5_check.md
      6_reflect.md
      7_result.md
      handoff.md
      audit.html
  docs/
    README.md
    architecture.md
```

## Manifest

The manifest identifies LoEn as a Codex plugin and points to the local plugin
subdirectories. It should not reference icodex internals, IDD, or Superpowers.

The manifest version is the single version used by the vendoring layer when it
copies the source into the installed cache path.

## Skills

The skills are the user-facing workflow surface:

| Skill | Responsibility |
|---|---|
| `loop-start` | Create or select a topic and write the goal and `loop.yaml`. |
| `loop-plan` | Convert goal and context into a bounded plan. |
| `loop-act` | Execute one bounded step within the active loop. |
| `loop-check` | Run configured checks and record evidence. |
| `loop-reflect` | Decide keep, fix, revert, or handoff based on evidence. |
| `loop-status` | Summarize current topic state from artifacts. |
| `loop-repair` | Specialize the loop for failing tests, CI, or regressions. |
| `loop-research` | Specialize the loop for metric-driven experiments. |
| `loop-review` | Specialize the loop for PR or diff review. |
| `loop-governance` | Specialize the loop for scheduled or recurring checks. |

Skills may use templates from `assets/templates/`, but active task artifacts are
written only under `docs/loen/<topic>/`.

## Hook Assets

Hook scripts are present in this layer but remain inert until the integration
layer installs and enables the plugin. Hook scripts must be deterministic and
must read LoEn task artifacts rather than infer state from chat history.

## Agent Assets

Agent definitions are role-specific. They are plugin assets that the isolation
layer will define in detail. The core layer only establishes names, files, and
the expectation that verifier/reviewer agents are read-only by default.

## Tests

This layer should add fixture tests that validate:

- `plugin.json` exists and contains the LoEn plugin name.
- Every skill directory has a `SKILL.md` with a unique name.
- Every hook listed in `hooks/hooks.json` has a corresponding script.
- Every agent TOML file parses as TOML.
- Template files exist for every runtime artifact required by the runtime layer.

## Acceptance

- `plugins/loen/` is a self-contained editable plugin source tree.
- No file in this layer depends on current IDD->SDD or Superpowers paths.
- Plugin source can be validated without installing it into Codex.

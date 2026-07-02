---
title: 02 LoEn runtime artifacts design
date: 2026-07-02
status: draft
chain:
  intent: null
---

# 02 LoEn runtime artifacts design

## Purpose

Define the repository artifacts LoEn writes for each task topic. These artifacts
make the loop durable across context compaction, new threads, subagents, review,
and later automation.

## Topic Layout

Each LoEn task is keyed by a unique topic slug and stored directly under
`docs/loen/`:

```text
docs/loen/
  <topic>/
    1_goal.md
    2_context.md
    3_plan.md
    4_act.md
    5_check.md
    6_reflect.md
    7_result.md
    loop.yaml
    attempts.jsonl
    evidence/
      <run-id>.json
      <run-id>.log
    handoff.md
    audit.html
```

The numeric prefixes keep the main loop stages sorted in reading order. Repeated
act/check/reflect cycles are logged in `attempts.jsonl` and `evidence/`, while
the numbered Markdown files hold the current human-readable state for each stage.

## Loop Contract

`loop.yaml` is the machine-readable contract used by skills and hooks.

Required fields:

```yaml
topic: example-topic
mode: delivery
objective: "Observable objective"
current_stage: goal
mutable_scope:
  - src/**
protected_scope:
  - secrets/**
quality_gates:
  - command: pytest tests/example
    evidence: evidence/latest-test.json
verifier:
  type: test|subagent|human|eval|ci
  command: pytest tests/example
budget:
  max_iterations: 3
stop_conditions:
  - quality gates pass
handoff_conditions:
  - schema change required
rollback_policy: "Revert unsafe changes"
```

Tool and permission policy fields are introduced by the enforcement layer.

## Audit Report

`audit.html` is scoped to one topic. It renders:

- current status and stage;
- loop contract summary;
- Goal, Context, Plan, Act, Check, Reflect, and Result summaries;
- attempts table;
- evidence links;
- verifier result;
- budget and stop/handoff state;
- protected-scope findings;
- final done or not-done verdict.

There is no LoEn global audit index. `docs/TODO.md` remains the global task
registry for all project work.

## TODO Tracking

Each LoEn layer and later each LoEn task topic is represented by one row in
`docs/TODO.md`. Manual rows are allowed before check-chain validation. The
initial LoEn design rows stay `in-progress` until their spec, plan, and result
checks pass through the existing project process.

## Tests

This layer should add tests that validate:

- a topic scaffold creates the exact required files;
- topic slug validation rejects path traversal and empty slugs;
- `loop.yaml` can be parsed and has required fields;
- `audit.html` is regenerated from artifacts without requiring chat context;
- `docs/TODO.md` is updated by topic without duplicate rows.

## Acceptance

- LoEn runtime state is stored under `docs/loen/<topic>/`.
- No `.agent-loop/` directory is required.
- Topic-level `audit.html` exists and no global LoEn audit index is created.
- `docs/TODO.md` remains the only global registry.

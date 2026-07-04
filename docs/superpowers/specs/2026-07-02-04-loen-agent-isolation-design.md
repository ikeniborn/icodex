---
title: 04 LoEn agent isolation design
date: 2026-07-02
status: draft
review:
  spec_hash: e3703a359aac2b1c
  last_run: 2026-07-04
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: null
---

# 04 LoEn agent isolation design

## Purpose

Define how LoEn separates planning, work, verification, review, and research.
The goal is to reduce context pollution and prevent the worker from being the
sole judge of its own output.

## Agent Roles

```text
plugins/loen/agents/
  loen-planner.toml
  loen-worker.toml
  loen-verifier.toml
  loen-reviewer.toml
  loen-researcher.toml
```

Responsibilities:

| Agent | Responsibility | Default access |
|---|---|---|
| `loen-planner` | Produce bounded plans from goal, context, and contract. | Read-only |
| `loen-worker` | Make scoped implementation changes. | Mutable scope only |
| `loen-verifier` | Run checks and validate evidence. | Read-only plus allowed checks |
| `loen-reviewer` | Review diff, risk, rollback, and scope. | Read-only |
| `loen-researcher` | Run bounded metric experiments. | Configured experiment scope |

## Context Capsules

LoEn should not pass the whole main-thread transcript to each role when a smaller
capsule is enough. A context capsule contains:

```text
Topic
Objective
Loop mode
Current stage
Mutable scope
Protected scope
Quality gates
Relevant files
Last evidence summary
Specific question or task for the agent
```

Capsules are generated from `docs/loen/<topic>/` artifacts and passed to custom
agents as task context. This gives context isolation, not a security boundary.

## Isolation Levels

LoEn uses a layered model:

| Level | Mechanism | Purpose |
|---|---|---|
| L0 | Same session | Simple advisory use. |
| L1 | Codex subagent with context capsule | Context isolation and role separation. |
| L2 | Separate `CODEX_HOME`, worktree, and Codex profile | Stronger local split for worker/verifier. |
| L3 | WASM executor for deterministic tools and evals | Lightweight execution isolation for verifiers. |
| L4 | External heavy adapter | Future container or microVM adapter for workloads WASM cannot cover. |

MicroVM and container execution are not part of the core LoEn plugin. They are
future external adapters if a workload needs full system isolation, browsers,
databases, native packages, or heavy ML/OCR pipelines.

## WASM-first Verifier

WASM is the preferred first strong verifier runtime because it is lightweight,
deterministic, and suitable for small policy checks and eval scripts. It does not
replace arbitrary shell execution.

The contract shape is:

```yaml
execution:
  isolation: codex-subagent|worktree|wasm|external
  executor: local|wasmtime
  network: off
  mounts:
    - path: .
      mode: read-only
    - path: /tmp/loen
      mode: write
```

## Tests

This layer should add tests that validate:

- context capsules include required fields and exclude unrelated transcript text;
- verifier/reviewer agent definitions are read-only by default;
- worker role is bound to mutable scope;
- WASM execution config rejects network-enabled verifier defaults;
- L4 external isolation is documented but not required by core tests.

## Acceptance

- Planner, worker, verifier, reviewer, and researcher roles are explicit.
- Context isolation is available through capsules and custom agents.
- Strong verifier execution starts with WASM, not microVM/container core code.

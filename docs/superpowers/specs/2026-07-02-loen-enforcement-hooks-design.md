---
title: LoEn enforcement hooks design
date: 2026-07-02
status: draft
chain:
  intent: null
---

# LoEn enforcement hooks design

## Purpose

Provide deterministic enforcement for the loop process without coupling to the
current IDD->SDD hooks. LoEn hooks inspect tool events, file paths, shell
commands, and topic artifacts. They do not judge whether a plan is good.

## Hook Files

```text
plugins/loen/hooks/
  hooks.json
  loop-gate.py
  scope-guard.py
  tool-guard.py
  permission-guard.py
  evidence-gate.py
  audit-writer.py
```

## Modes

```text
LOEN_MODE=off
LOEN_MODE=advisory
LOEN_MODE=enforce
LOEN_MODE=strict
```

Behavior:

| Mode | Behavior |
|---|---|
| `off` | Hooks are not registered or are stripped by icodex wiring. |
| `advisory` | Hooks emit nudges and audit updates but do not block. |
| `enforce` | Hooks block missing loop state, invalid stage transitions, and protected path edits. |
| `strict` | `enforce` plus tool permissions, shell/network restrictions, and verifier separation. |

## Contract Extensions

`loop.yaml` includes tool and permission policies:

```yaml
agents:
  planner:
    tools: [read, search]
    sandbox: read-only
  worker:
    tools: [read, search, edit, shell]
    sandbox: workspace-write
  verifier:
    tools: [read, search, shell]
    sandbox: read-only
    must_not_edit: true

tools:
  allowed:
    - read
    - search
    - apply_patch
    - shell
  denied:
    - network
    - secrets
    - destructive_git
    - external_write

permissions:
  filesystem:
    mutable_scope:
      - src/**
      - tests/**
    protected_scope:
      - migrations/**
      - secrets/**
  network:
    mode: off
    allowlist: []
  shell:
    allow:
      - pytest tests/auth
      - ruff check .
    deny_patterns:
      - rm -rf
      - git reset --hard
      - curl *|sh
```

## Hook Responsibilities

`loop-gate.py`:

- detects the active topic;
- blocks code edits when no active LoEn loop exists in `enforce` or `strict`;
- blocks stage transitions that skip required numbered artifacts;
- blocks final success claims without `7_result.md`.

`scope-guard.py`:

- extracts paths from `apply_patch`, `Write`, and `Edit`;
- allows `docs/loen/<topic>/` artifacts;
- allows only configured `mutable_scope`;
- blocks `protected_scope`.

`tool-guard.py`:

- maps Codex tool events to LoEn tool classes;
- checks the current stage and agent role against `loop.yaml`;
- blocks verifier/reviewer edits in `strict`.

`permission-guard.py`:

- checks shell commands against allow and deny rules;
- blocks configured destructive Git commands;
- blocks network-related commands unless allowed by policy.

`evidence-gate.py`:

- checks that `5_check.md`, evidence files, and verifier verdicts exist before
  a done verdict is accepted;
- requires worker and verifier separation in `strict`.

`audit-writer.py`:

- regenerates `docs/loen/<topic>/audit.html`;
- updates the matching row in `docs/TODO.md`;
- does not perform subjective review.

## Tests

This layer should add hook-level fixture tests for:

- no active loop behavior in each mode;
- mutable and protected scope path extraction;
- shell allow and deny patterns;
- verifier edit blocking;
- final success blocking without evidence;
- idempotent `audit.html` regeneration;
- no dependency on `chain-gate.py` or IDD frontmatter.

## Acceptance

- LoEn can enforce loop state without Superpowers or IDD.
- Hooks remain deterministic and testable with JSON fixtures.
- `strict` mode blocks missing evidence and verifier self-approval.

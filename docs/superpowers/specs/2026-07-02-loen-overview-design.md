---
title: LoEn loop engineering overview
date: 2026-07-02
status: draft
chain:
  intent: null
---

# LoEn loop engineering overview

## Purpose

LoEn is a standalone Codex plugin project for Loop Engineering. It provides a
portable process for agent-assisted development:

```text
Goal -> Context -> Plan -> Act -> Check -> Reflect/Fix -> Stop/Handoff
```

LoEn is not an extension of the current IDD->SDD chain and does not depend on
the Superpowers plugin. Existing icodex IDD, check-chain, and Superpowers assets
may coexist with LoEn, but they are not prerequisites for it.

## Design Goals

- Make the loop process enforceable, not only advisory.
- Keep plugin source separate from installed Codex cache artifacts.
- Store task state in reviewable repository documents, not only in chat context.
- Separate worker and verifier responsibilities.
- Support deterministic hooks for scope, tool, permission, and evidence checks.
- Provide role-specific agents with context capsules.
- Start with Codex-native isolation and add WASM-based deterministic verification
  before considering heavier external isolation adapters.
- Track each implementation layer as its own topic in `docs/TODO.md`.

## Layered Scope

LoEn is split into sequential layer specs:

| Order | Topic | Spec |
|---|---|---|
| 1 | `loen-plugin-core` | Plugin source tree, manifest, skills, templates |
| 2 | `loen-runtime-artifacts` | `docs/loen/<topic>/` artifacts and `audit.html` |
| 3 | `loen-enforcement-hooks` | Loop gates, scope guard, tool guard, permission guard, evidence gate |
| 4 | `loen-agent-isolation` | Agent roles, context capsules, Codex profile split, WASM verifier |
| 5 | `loen-icodex-integration` | Vendoring, launch-time wiring, config/cache integration |
| 6 | `loen-automation-governance` | Later L3 automations and governance loops |

The overview only defines shared boundaries and sequencing. Each layer owns its
own acceptance criteria and implementation plan.

## Repository Boundaries

The editable plugin source lives in:

```text
plugins/loen/
```

The installed plugin cache remains generated or vendored runtime material under:

```text
.codex-isolated/plugins/cache/<marketplace>/loen/<version>/
```

The task artifacts produced by LoEn live under:

```text
docs/loen/<topic>/
```

`docs/TODO.md` remains the only global human-readable task index. LoEn does not
create a second global registry.

## Modes

LoEn supports four runtime modes:

| Mode | Behavior |
|---|---|
| `off` | Plugin wiring and hooks are disabled. |
| `advisory` | Skills and nudges are active; hooks do not block edits. |
| `enforce` | Stage order, active loop state, scope, and evidence gates can block. |
| `strict` | `enforce` plus worker/verifier separation and tool/permission checks. |

The recommended initial icodex default is `advisory`, with `enforce` and
`strict` enabled after the layer tests and manual trial loops pass.

## Non-goals

- Do not replace IDD->SDD or Superpowers.
- Do not depend on `lib/plugin/iwiki.sh`; that path is legacy and excluded.
- Do not make microVM or container execution part of the core plugin.
- Do not use hooks for subjective reasoning. Hooks enforce deterministic state,
  scope, permissions, and evidence contracts only.

## Acceptance

- All layer specs exist and are linked from this overview.
- `docs/TODO.md` has one row for each LoEn layer topic.
- The design keeps LoEn independent from IDD->SDD and Superpowers.
- The design identifies which layer introduces each runtime behavior.

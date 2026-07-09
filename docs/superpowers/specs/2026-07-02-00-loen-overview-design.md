---
title: 00 LoEn loop engineering overview
date: 2026-07-02
status: draft
chain:
  intent: null
---

# 00 LoEn loop engineering overview

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

LoEn is split into sequential layer specs. Each linked layer owns its own
acceptance criteria and implementation plan.

| Order | Topic | Spec | Scope |
|---|---|---|---|
| 1 | [`01-loen-plugin-core`](2026-07-02-01-loen-plugin-core-design.md) | Plugin source tree, manifest, skills, templates | Editable source and inert assets |
| 2 | [`02-loen-runtime-artifacts`](2026-07-02-02-loen-runtime-artifacts-design.md) | `docs/loen/<topic>/` artifacts and `audit.html` | Durable task state |
| 3 | [`03-loen-enforcement-hooks`](2026-07-02-03-loen-enforcement-hooks-design.md) | Loop gates, scope guard, tool guard, permission guard, evidence gate | Deterministic enforcement |
| 4 | [`04-loen-agent-isolation`](2026-07-02-04-loen-agent-isolation-design.md) | Agent roles, context capsules, Codex profile split, WASM verifier | Worker/verifier separation |
| 5 | [`05-loen-icodex-integration`](2026-07-02-05-loen-icodex-integration-design.md) | Vendoring, launch-time wiring, config/cache integration | icodex adapter |
| 6 | [`06-loen-automation-governance`](2026-07-02-06-loen-automation-governance-design.md) | Later L3 automations and governance loops | Scheduled/background governance |

The overview only defines shared boundaries and sequencing. Each layer owns its
own acceptance criteria and implementation plan.

## Runtime Behavior Ownership

Each runtime behavior is introduced by one layer. Later layers may consume that
behavior, but should not redefine its contract.

| Runtime behavior | Owning layer |
|---|---|
| Editable plugin source, manifest, skills, templates, inert hook assets, and agent asset names | [`01-loen-plugin-core`](2026-07-02-01-loen-plugin-core-design.md) |
| Topic artifact contract, `loop.yaml`, per-topic `audit.html`, and TODO row rules | [`02-loen-runtime-artifacts`](2026-07-02-02-loen-runtime-artifacts-design.md) |
| Blocking/advisory loop gates, scope guard, tool guard, permission guard, evidence gate, and audit writer behavior | [`03-loen-enforcement-hooks`](2026-07-02-03-loen-enforcement-hooks-design.md) |
| Planner/worker/verifier/reviewer/researcher role separation, context capsules, Codex profile split, and WASM-first verifier model | [`04-loen-agent-isolation`](2026-07-02-04-loen-agent-isolation-design.md) |
| Vendoring, launch-time marketplace wiring, `ICODEX_LOEN_MODE`, and off/advisory/enforce/strict runtime enablement in icodex | [`05-loen-icodex-integration`](2026-07-02-05-loen-icodex-integration-design.md) |
| Scheduled/background loop governance, human-review counters, and no-auto-merge policy | [`06-loen-automation-governance`](2026-07-02-06-loen-automation-governance-design.md) |

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

The recommended icodex default is `off` so lifecycle hooks do not run during
ordinary work. Users opt in with `advisory`, with `enforce` and `strict` enabled
only after the layer tests and manual trial loops pass.

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

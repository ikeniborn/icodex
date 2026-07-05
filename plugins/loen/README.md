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
- Role agent definitions for planner, worker, verifier, reviewer, and
  researcher flows.
- Templates for durable loop artifacts under `docs/loen/<topic>/`.

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

The topic directory stores:

- numbered stage files from `1_goal.md` through `7_result.md`;
- `loop.yaml` with scope, mode, verifier, budget, stop rules, and governance;
- `attempts.jsonl` for run records;
- `evidence/` for check and verifier output;
- `handoff.md`;
- regenerated `audit.html`.

Use `loen:loop-status` to inspect current state. Continue with
`loen:loop-plan`, `loen:loop-act`, `loen:loop-check`, and
`loen:loop-reflect` for one bounded pass through the loop.

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

Plugin internals are documented in `docs/README.md` and
`docs/architecture.md`.

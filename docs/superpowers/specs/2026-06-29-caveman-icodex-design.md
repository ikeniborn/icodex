# Caveman integration for icodex — design

Date: 2026-06-29
Status: approved (pending spec review)
Branch: `dev-caveman-icodex`

## Problem

`iclaude` ships caveman (token-compression of model output) as four Claude Code JS
hooks. `icodex` — the isolated wrapper for the OpenAI Codex CLI — has no equivalent.
We want caveman-style terse output in Codex to save **output** tokens, while keeping
caveman's own **input**-token overhead near zero.

The two stated goals:

1. **Token efficiency** — terse model output (drop articles / filler / pleasantries),
   ~65–75% fewer output tokens on prose-heavy turns.
2. **Minimal self-overhead** — the caveman mechanism must add ≈0 input tokens per turn
   in the steady-state (default) mode.

## Success criteria

- With `ICODEX_CAVEMAN_MODE=full`, Codex output is terse (caveman style).
- In the baked-in default mode the per-turn hook injects **0 tokens** (all standing
  instruction lives in the prompt-cached `AGENTS.md`).
- `/caveman lite|full|ultra|off` (and `stop caveman` / `normal mode`) switches mode
  mid-session.
- The target project's files are never touched — caveman lives entirely in the
  icodex-owned, isolated `CODEX_HOME`.
- Disabled by default: caveman activates only when `ICODEX_CAVEMAN_MODE` is set.

## Background — what each side provides

### icodex extension points (verified)
- **`$CODEX_HOME/AGENTS.md`** — Codex reads a *global*-scope `AGENTS.md` from
  `CODEX_HOME` (defaults to `~/.codex`, follows `CODEX_HOME`). It is concatenated with
  the project's `AGENTS.md` (global first, leaf last) up to `project_doc_max_bytes`
  (32–64 KiB). icodex sets `CODEX_HOME` to a per-project home it fully owns, so writing
  a global `AGENTS.md` there never touches the user's project files.
- **Hooks** — Codex supports lifecycle hooks (`SessionStart`, `UserPromptSubmit`, …)
  configured **top-level** in `config.toml` (or a top-level `hooks = "…/hooks.json"`).
  A `UserPromptSubmit` command hook injects model-visible text via
  `hookSpecificOutput.additionalContext` (plain stdout is also accepted as
  `additionalContext` for `SessionStart` / `UserPromptSubmit`). Empty stdout = no-op.
  `bypass_hook_trust = true` (already in the icodex `config.toml` template) lets hooks
  fire non-interactively.
  - Known Codex bug: hooks declared in a **repo-local** `.codex/config.toml` do not fire
    in interactive sessions. icodex sidesteps this by writing hooks into the
    **home** `config.toml` (the authoritative config), which it already rewrites at launch.

### Decisions taken during brainstorming
- **Scope**: always-on default + in-session mode switch/off. No stats, no statusline.
- **Mechanism**: **hybrid** — cached `AGENTS.md` base carries the standing instruction
  (0 per-turn cost), a lightweight hook fires only on a `/caveman` switch or when the
  active mode deviates from the baked-in default.
- **Source**: **hybrid** — style rules vendored once from the upstream caveman
  `SKILL.md`; the hook is written native to icodex.
- **Default**: `off` (opt-in via `ICODEX_CAVEMAN_MODE`).
- **Hook count**: one hook (`UserPromptSubmit`), no `SessionStart` — mode state is
  lazy-initialised on the first turn.
- **Hook language**: `python3` (the shared store already provides `uv`/python).

## Architecture — two layers

### Layer 1 — `AGENTS.md` base block (static, cached, always-on)

icodex renders a caveman instruction block into `$CODEX_HOME/AGENTS.md` at launch when
`ICODEX_CAVEMAN_MODE` is set. The block contains:

- caveman persona + compression rules;
- the **full mode table** (lite / full / ultra) so the hook only needs to name a mode,
  not re-describe it;
- auto-clarity exceptions (security warnings, irreversible-action confirmations,
  multi-step sequences where omitted conjunctions risk misreading → write normally;
  code / commits / PRs → always normal);
- language rule (compress in the conversation language, never switch language to
  compress; docs / code comments / commits / PRs → English);
- the `/caveman` contract: "treat `/caveman <mode>` as a mode switch; the authoritative
  active mode is whatever the most recent injected `ACTIVE MODE` line states".

Write semantics:
- icodex manages `$CODEX_HOME/AGENTS.md` via a delimited region
  (`<!-- icodex:caveman:start -->` … `<!-- icodex:caveman:end -->`). The region is
  inserted or replaced in place; any non-caveman content in that file is preserved.
  When `ICODEX_CAVEMAN_MODE` is unset, the region is removed. Idempotent: rewritten
  only when changed.

Constraints:
- Keep the block **< 2 KiB**. Global scope is first in Codex's lookup order, so an
  oversized block could truncate the project's own `AGENTS.md` against
  `project_doc_max_bytes`.
- The default mode is substituted into the block at render time, so in the steady state
  the block alone fully specifies behaviour and the hook can stay silent.

Cost: counted once per session, prompt-cached → amortised ≈0 input tokens. This is the
core of goal 2.

### Layer 2 — `UserPromptSubmit` hook (dynamic, minimal, one python3 script)

Registered top-level in the per-project home `config.toml`. Per-turn logic:

1. Read stdin JSON (Codex schema: `prompt`, `session_id`, …).
2. Resolve the active mode from a per-session state file; lazy-init from
   `ICODEX_CAVEMAN_MODE` when the file is absent.
3. If `prompt` matches `/caveman <mode>` | `stop caveman` | `normal mode`:
   write the new mode to the state file and emit `additionalContext` =
   confirmation + one-line style for the new mode.
4. Else if active mode == baked-in default: emit **empty stdout** → 0 tokens injected
   (the common path).
5. Else (mode deviates from the default, e.g. switched earlier this session): emit a
   short `ACTIVE MODE: <mode>` reminder so the override stays salient at the tail of
   context.
6. `off` → emit "caveman disabled — respond normally" to override the `AGENTS.md` base
   (~10 tokens/turn while off; off is not the steady state).

No `SessionStart` hook: step 2's lazy-init removes the need, keeping the surface to one
script.

State file: keyed by `session_id` under `$CODEX_HOME/.caveman/` so concurrent sessions
do not clash.

## Data flow

```
icodex.sh launch
  └─ ensure_caveman_wiring  (only when ICODEX_CAVEMAN_MODE is set)
       ├─ render  $CODEX_HOME/AGENTS.md   ← .codex-isolated/caveman/agents-block.md (mode substituted)
       └─ register [hooks] in $CODEX_HOME/config.toml → .codex-isolated/caveman/hooks/caveman-hook.py

Codex turn
  └─ UserPromptSubmit → caveman-hook.py (stdin JSON) → additionalContext | empty
```

## Asset layout (tracked, shared)

```
.codex-isolated/caveman/
  agents-block.md           # caveman block (rules + mode table), curated from upstream SKILL.md
  hooks/caveman-hook.py     # native UserPromptSubmit hook (python3, stdlib only)
scripts/vendor-caveman.sh   # manual refresh of agents-block.md from upstream SKILL.md (mirrors vendor-superpowers.sh)
lib/caveman/caveman.sh      # ensure_caveman_wiring() + idempotent config.toml / AGENTS.md rewrite
```

The hook is python3 (stdlib only — no pip deps), matching icodex's dependency-light
ethos. Compression *rules* are vendored once from the upstream `SKILL.md` (hybrid
source); the hook *logic* is native.

## Config and wiring

- `ICODEX_CAVEMAN_MODE` in `.codex_config`: unset/`off` (default — disabled) |
  `lite` | `full` | `ultra`. Documented in `.codex_config.example`.
- `lib/caveman/caveman.sh::ensure_caveman_wiring` runs on the launch path next to
  `ensure_superpowers_wiring`. Idempotent: awk-based `[hooks]` rewrite + `AGENTS.md`
  rewrite only when content changed (`cmp -s`), preserving inode/permissions — same
  pattern as `lib/plugin/superpowers.sh`.
- `bypass_hook_trust = true` already present → hook fires non-interactively.
- No statusline / stats (explicitly out of scope).

## Token-overhead accounting (goal 2)

| State | AGENTS.md (cached, once) | Hook per-turn | Net |
|-------|--------------------------|---------------|-----|
| default mode | ~block size, cached | **0** | pure output savings |
| switched (non-default) | cached | ~10–20 tok | savings − tiny reminder |
| off | cached | ~10 tok (disable line) | ≈ neutral |

## Tests (`tests/test_*.sh`, sourcing `tests/helpers.sh`)

- `test_caveman_wiring.sh`
  - `ICODEX_CAVEMAN_MODE=full` → home `AGENTS.md` contains the block; home
    `config.toml` has a top-level `[hooks]` registration for the hook.
  - Re-run produces no diff (idempotent — `cmp -s` guard).
  - unset → no block, no hook registration.
- `test_caveman_hook.sh`
  - stdin JSON, default mode → empty stdout.
  - `/caveman lite` → state file updated + `additionalContext` emitted.
  - `off` → disable line emitted.
  - Tests avoid network; use temp dirs for state.

## Documentation (iwiki — mandatory per repo guidelines)

- New `docs/wiki/caveman.md` (modelled on the iclaude page, Codex-adapted).
- Update `docs/wiki/config.md` (`ICODEX_CAVEMAN_MODE`).
- Update `docs/wiki/architecture.md` / `docs/wiki/command.md` (launch-path step).
- Run `iwiki:iwiki-ingest` on changed sources + `/iwiki-lint`.

## Risks and mitigations

- **TUI noise** — Codex renders `additionalContext` as a visible `hook context:` line.
  Mitigated: the hook is silent in the default mode; noise appears only on a switch or
  while in a non-default/off mode.
- **`project_doc_max_bytes` starvation** — global block is first in lookup order.
  Mitigated: block kept < 2 KiB.
- **Repo-local hook bug** — hooks in `.codex/config.toml` don't fire interactively.
  Mitigated: hooks are written into the home `config.toml`.
- **Mode-file growth** — per-session state files accumulate. Minor; optional cleanup of
  stale files can be added later (out of scope for v1).

## Out of scope (v1)

- Stats / token-savings counter and statusline badge.
- `wenyan-*`, `commit`, `review`, `compress` modes from upstream.
- Porting the upstream Node JS hooks verbatim.
```

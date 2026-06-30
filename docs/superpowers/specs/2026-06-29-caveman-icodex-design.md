---
review:
  spec_hash: 12d0ef2ea1b81b29
  last_run: 2026-06-29
  phases:
    structure:   { status: passed }
    coverage:    { status: passed }
    clarity:     { status: passed }
    consistency: { status: passed }
  findings:
    - id: F-001
      phase: coverage
      severity: CRITICAL
      section: "Success criteria / Architecture (Layer 1 & 2)"
      section_hash: 711490f758fd2056
      fragment: "While the session's current mode equals the active launch mode, the per-turn hook injects 0 tokens ... current mode == active launch mode: emit empty stdout"
      text: >-
        Term overload on "default" creates an unverifiable requirement. The spec
        uses "default" for two different things: (a) the product default = off/disabled
        (SC5 line 30, Decisions line 58, Config line 150) and (b) a "baked-in default
        mode" substituted into the AGENTS.md block at render time, against which the hook
        compares to stay silent (Layer 1 lines 92-93, Layer 2 step 4 line 108). SC2 ("0
        tokens in the baked-in default mode") and the hook's silent-path branch cannot be
        verified because the spec never defines what value "baked-in default" holds. Since
        wiring only happens when ICODEX_CAVEMAN_MODE is set to lite|full|ultra, the
        "baked-in default" must be that launch value, but this is never stated.
      fix: >-
        Define "baked-in default mode" explicitly as the value of ICODEX_CAVEMAN_MODE at
        launch (one of lite|full|ultra), and disambiguate it from the product ship default
        (off). Rename one of the two concepts (e.g. "active launch mode" vs "ship default")
        so SC2 and Layer 2 step 4 reference a defined value.
      verdict: fixed
      verdict_at: 2026-06-29
      resolution: >-
        Resolved by the new "## Terminology" section (lines 22-32), which defines
        "Ship default" (off) vs "Active launch mode" (the value of ICODEX_CAVEMAN_MODE
        at launch, one of lite|full|ultra). The term "baked-in default" is fully removed
        from the body; SC2 (line 36) and Layer 2 step 4 now reference "active launch mode",
        a defined value, making the silent-path requirement verifiable.
    - id: F-002
      phase: clarity
      severity: WARNING
      section: "Decisions taken during brainstorming"
      section_hash: ccae8f11d7d96b4b
      fragment: "Scope: always-on once enabled + in-session mode switch/off ... Ship default: off (opt-in via ICODEX_CAVEMAN_MODE)"
      text: >-
        Inconsistent terms within the Decisions block: "always-on default" (line 52)
        vs "Default: off" (line 58). Reads as a contradiction unless the reader infers
        that "always-on" describes the standing AGENTS.md mechanism once enabled, while
        "Default: off" is the ship state. Same root overload as F-001.
      fix: >-
        Reword line 52 to "always-on once enabled" or similar, so "always-on" and
        "Default: off" no longer appear to collide.
      verdict: fixed
      verdict_at: 2026-06-29
      resolution: >-
        Resolved: the Decisions block now reads "always-on once enabled" (line 65) and
        "Ship default: off" (line 71). The two phrases no longer appear to collide, and
        the underlying overload is removed by the new "## Terminology" section.
chain:
  intent: null
---

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
   while the session runs in its **active launch mode** (defined below).

## Terminology

Two distinct concepts that must never be conflated:

- **Ship default** — the product default when `ICODEX_CAVEMAN_MODE` is unset: caveman is
  **off** (no `AGENTS.md` block, no hook registered). This is the out-of-the-box state.
- **Active launch mode** — once caveman is enabled, the value of `ICODEX_CAVEMAN_MODE`
  at launch (one of `lite` | `full` | `ultra`). This value is substituted into the
  `AGENTS.md` block at render time, so the block alone fully specifies behaviour and the
  hook can stay silent. The hook injects only when the session's *current* mode (after a
  `/caveman` switch) differs from the active launch mode.

## Success criteria

- With `ICODEX_CAVEMAN_MODE=full`, Codex output is terse (caveman style).
- While the session's current mode equals the active launch mode, the per-turn hook
  injects **0 tokens** (all standing instruction lives in the prompt-cached `AGENTS.md`).
- `/caveman lite|full|ultra|off` (and `stop caveman` / `normal mode`) switches mode
  mid-session.
- The target project's files are never touched — caveman lives entirely in the
  icodex-owned, isolated `CODEX_HOME`.
- Ship default is off: caveman activates only when `ICODEX_CAVEMAN_MODE` is set.

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
  - icodex already ships a shared `.codex-isolated/hooks.json` (PreToolUse secret
    guards) symlinked into each home and auto-discovered by Codex from
    `$CODEX_HOME/hooks.json`. The caveman hook plugs into this same file (see Layer 2).
  - Known Codex bug: hooks in a **repo-local** `.codex/config.toml` do not fire in
    interactive sessions — irrelevant here, since icodex uses the home `hooks.json`.

### Decisions taken during brainstorming
- **Scope**: always-on once enabled + in-session mode switch/off. No stats, no statusline.
- **Mechanism**: **hybrid** — cached `AGENTS.md` base carries the standing instruction
  (0 per-turn cost), a lightweight hook fires only on a `/caveman` switch or when the
  session's current mode deviates from the active launch mode.
- **Source**: **hybrid** — style rules vendored once from the upstream caveman
  `SKILL.md`; the hook is written native to icodex.
- **Ship default**: `off` (opt-in via `ICODEX_CAVEMAN_MODE`).
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
- The active launch mode is substituted into the block at render time, so in the steady
  state the block alone fully specifies behaviour and the hook can stay silent.

Cost: counted once per session, prompt-cached → amortised ≈0 input tokens. This is the
core of goal 2.

### Layer 2 — `UserPromptSubmit` hook (dynamic, minimal, one python3 script)

Registered via the per-project home `hooks.json` (auto-discovered by Codex from
`$CODEX_HOME/hooks.json`; wiring below). Per-turn logic:

1. Read stdin JSON (Codex schema: `prompt`, `session_id`, …).
2. Resolve the active mode from a per-session state file; lazy-init from
   `ICODEX_CAVEMAN_MODE` when the file is absent.
3. If `prompt` matches `/caveman <mode>` | `stop caveman` | `normal mode`:
   write the new mode to the state file and emit `additionalContext` =
   confirmation + one-line style for the new mode.
4. Else if current mode == active launch mode: emit **empty stdout** → 0 tokens injected
   (the common path).
5. Else (current mode deviates from the active launch mode, e.g. switched earlier this
   session): emit a short `ACTIVE MODE: <mode>` reminder so the override stays salient at
   the tail of context.
6. `off` → emit "caveman disabled — respond normally" to override the `AGENTS.md` base
   (~10 tokens/turn while off; off is not the steady state).

No `SessionStart` hook: step 2's lazy-init removes the need, keeping the surface to one
script.

State file: keyed by `session_id` under `$CODEX_HOME/.caveman/` so concurrent sessions
do not clash.

## Data flow

```
icodex.sh launch
  └─ ensure_caveman_wiring
       ├─ AGENTS.md region in $CODEX_HOME/AGENTS.md  ← .codex-isolated/caveman/agents-block.md
       │     mode set → insert/replace region (mode substituted);  off/unset → remove region
       └─ $CODEX_HOME/hooks.json
             mode set → real file = merge(shared secret-guards, caveman UserPromptSubmit
                        → python3 "$CODEX_HOME/hooks/caveman-hook.py")
             off/unset → symlink to shared hooks.json (caveman absent)

Codex turn
  └─ UserPromptSubmit → caveman-hook.py (stdin JSON) → additionalContext | empty
```

## Asset layout (tracked, shared)

```
.codex-isolated/
  hooks/caveman-hook.py     # native UserPromptSubmit hook (python3, stdlib only) — beside block-secrets.py
  caveman/agents-block.md   # caveman block (rules + mode table), curated from upstream SKILL.md
scripts/vendor-caveman.sh   # manual refresh of agents-block.md from upstream SKILL.md (mirrors vendor-superpowers.sh)
lib/caveman/caveman.sh      # ensure_caveman_wiring(): render AGENTS.md region + render/merge home hooks.json
```

The hook lives in `.codex-isolated/hooks/` (not under `caveman/`) because the registered
command is `python3 "$CODEX_HOME/hooks/caveman-hook.py"` and `setup_codex_home` symlinks
the shared `hooks/` dir into each home.

The hook is python3 (stdlib only — no pip deps), matching icodex's dependency-light
ethos. Compression *rules* are vendored once from the upstream `SKILL.md` (hybrid
source); the hook *logic* is native.

## Config and wiring

- `ICODEX_CAVEMAN_MODE` in `.codex_config`: unset/`off` (ship default — disabled) |
  `lite` | `full` | `ultra`. Documented in `.codex_config.example`.
- `lib/caveman/caveman.sh::ensure_caveman_wiring` runs on the launch path right after
  `ensure_superpowers_wiring`. Two idempotent actions (rewrite only when changed):
  1. **AGENTS.md region** — insert/replace the delimited caveman region in
     `$CODEX_HOME/AGENTS.md` (mode substituted), or remove it when off/unset.
  2. **home hooks.json** — mode set → replace the `$CODEX_HOME/hooks.json` symlink with a
     real file = the shared secret-guard hooks **plus** a `UserPromptSubmit` entry running
     `python3 "$CODEX_HOME/hooks/caveman-hook.py"` (merge in python3 — robust JSON, no
     TOML). off/unset → restore the symlink to the shared `hooks.json` (caveman absent).
  `setup_codex_home` runs first (`_link_shared hooks.json` establishes the symlink);
  `ensure_caveman_wiring` overrides it only when caveman is enabled.
- `bypass_hook_trust = true` already present → hook fires non-interactively.
- No statusline / stats (explicitly out of scope).

## Token-overhead accounting (goal 2)

| State | AGENTS.md (cached, once) | Hook per-turn | Net |
|-------|--------------------------|---------------|-----|
| current mode == active launch mode | ~block size, cached | **0** | pure output savings |
| switched (≠ launch mode) | cached | ~10–20 tok | savings − tiny reminder |
| off | cached | ~10 tok (disable line) | ≈ neutral |

## Tests (`tests/test_*.sh`, sourcing `tests/helpers.sh`)

- `test_caveman_wiring.sh`
  - `ICODEX_CAVEMAN_MODE=full` → home `AGENTS.md` contains the caveman region; home
    `hooks.json` is a real file containing **both** the secret-guard hooks and a
    `UserPromptSubmit` caveman entry.
  - Re-run produces no diff (idempotent — `cmp -s` guard).
  - unset → no caveman region in `AGENTS.md`; home `hooks.json` is the symlink to the
    shared file (no caveman entry).
- `test_caveman_hook.sh`
  - stdin JSON, current mode == active launch mode → empty stdout.
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
  Mitigated: the hook is silent while the current mode equals the active launch mode;
  noise appears only after a switch or while in an off mode.
- **`project_doc_max_bytes` starvation** — global block is first in lookup order.
  Mitigated: block kept < 2 KiB.
- **Repo-local hook bug** — hooks in a repo-local `.codex/config.toml` don't fire
  interactively. Avoided: caveman uses the home `hooks.json` (auto-discovered from
  `$CODEX_HOME`), the same mechanism as the existing secret-guard hooks.
- **Mode-file growth** — per-session state files accumulate. Minor; optional cleanup of
  stale files can be added later (out of scope for v1).

## Out of scope (v1)

- Stats / token-savings counter and statusline badge.
- `wenyan-*`, `commit`, `review`, `compress` modes from upstream.
- Porting the upstream Node JS hooks verbatim.
```

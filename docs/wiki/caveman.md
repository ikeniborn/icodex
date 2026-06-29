# Caveman

## Overview

The caveman layer adds output-token compression to icodex Codex sessions, targeting
~65–75% fewer output tokens on prose-heavy turns with ≈0 input-token overhead per turn
at steady state.

It is built from two cooperating layers: a cached `AGENTS.md` block that carries the
standing compression instruction (counted once per session, then prompt-cached), and a
lightweight `UserPromptSubmit` hook that fires only when the session's current mode
deviates from the active launch mode. See [[architecture#Default run path]] for where
these are wired, and [[config#Persistent user config]] for the controlling variable.

## Modes

`ICODEX_CAVEMAN_MODE` in `.codex_config` selects the compression level:

| Value | Behaviour |
|-------|-----------|
| unset / `off` | Caveman disabled — no `AGENTS.md` block, no hook registered (ship default). |
| `lite` | Drop filler words only; keep articles and full sentences. |
| `full` | Drop articles, filler, pleasantries; fragments OK; short synonyms. |
| `ultra` | Fragments + maximum abbreviation; technical terms exact. |

The value at launch is the **active launch mode**. It is substituted into the
`AGENTS.md` block at render time. When `ICODEX_CAVEMAN_MODE` is unset or `off`, icodex
restores normal operation — no block, hook symlinked back to the shared secret-guard
file. See [[config#ICODEX_CAVEMAN_MODE]].

## Layer 1 — `AGENTS.md` base block

`ensure_caveman_wiring` renders a delimited caveman region into
`$CODEX_HOME/AGENTS.md` from the template at
`.codex-isolated/caveman/agents-block.md`. The region is bounded by HTML comments
(`<!-- icodex:caveman:start -->` … `<!-- icodex:caveman:end -->`), so any
non-caveman content in that file is preserved.

The block contains:

- Caveman persona and compression rules;
- the full mode table (lite / full / ultra) with one-line style descriptions;
- auto-clarity exceptions (security warnings, irreversible-action confirmations,
  multi-step sequences, code, commits, PRs — always written normally);
- language rule (compress in the conversation language; docs, code comments, commits,
  PRs → English);
- the `/caveman` contract: the model treats `/caveman <mode>` as a mode switch and
  follows the most recent injected `ACTIVE MODE` line.

The active launch mode is substituted into the block once at render time, so in the
steady state the block alone fully specifies behaviour — the hook stays silent.

Cost: counted once per session and then prompt-cached, amortised ≈0 input tokens.
Block is kept below 2 KiB so it cannot crowd out the project's own `AGENTS.md`
against Codex's `project_doc_max_bytes` limit (global scope is first in lookup order).

Write semantics are idempotent: the file is only rewritten when the rendered content
changes (`cmp -s` guard).

## Layer 2 — `UserPromptSubmit` hook

`caveman-hook.py` (`.codex-isolated/hooks/caveman-hook.py`, python3, stdlib only) is
registered in the per-project home `hooks.json` when caveman is enabled. Per-turn
logic:

1. Read stdin JSON (Codex schema: `prompt`, `session_id`, …).
2. Resolve the active launch mode from `ICODEX_CAVEMAN_MODE`; resolve current mode from
   the per-session state file `$CODEX_HOME/.caveman/mode-<session_id>` (lazy-init from
   `ICODEX_CAVEMAN_MODE` when absent).
3. If `prompt` matches `/caveman <mode>` | `stop caveman` | `normal mode`: write new
   mode to state file, emit confirmation + one-line style.
4. Else if current mode == active launch mode: **emit empty stdout** → 0 tokens (common
   path; `AGENTS.md` block already carries the instruction).
5. Else (mode switched this session, differs from launch mode): emit a short
   `CAVEMAN ACTIVE MODE: <mode>` reminder.
6. `off` → emit "CAVEMAN DISABLED — respond normally" (~10 tokens/turn while off).

State files are keyed by `session_id` under `$CODEX_HOME/.caveman/` so concurrent
sessions do not clash. No `SessionStart` hook — lazy-init on first turn removes the
need.

## In-session mode switching

At any prompt, type one of:

```
/caveman lite
/caveman full
/caveman ultra
/caveman off
stop caveman
normal mode
```

The hook writes the new mode to the session state file and injects a confirmation plus
the new style line as `additionalContext`. All subsequent turns follow the new mode
until another switch or the session ends. The next session always starts from the
active launch mode (`ICODEX_CAVEMAN_MODE`).

## Token-overhead accounting

| State | `AGENTS.md` (cached, once) | Hook per-turn | Net |
|-------|---------------------------|---------------|-----|
| current mode == active launch mode | ~block size, cached | **0** | pure output savings |
| switched (≠ launch mode) | cached | ~10–20 tokens | savings − tiny reminder |
| `off` | cached | ~10 tokens | ≈ neutral |

## Launch-path wiring

`ensure_caveman_wiring` (defined in `lib/caveman/caveman.sh`) runs on the default run
path right after `ensure_superpowers_wiring`. It performs two idempotent actions:

1. **`AGENTS.md` region** — insert or replace the delimited caveman region in
   `$CODEX_HOME/AGENTS.md` (mode substituted), or remove it when off/unset.
2. **home `hooks.json`** — when enabled: replace the `$CODEX_HOME/hooks.json` symlink
   with a real file = shared secret-guard hooks merged with a `UserPromptSubmit` entry
   running `python3 "$CODEX_HOME/hooks/caveman-hook.py"` (python3 JSON merge —
   no TOML). When off/unset: restore the symlink to the shared `hooks.json`.

`setup_codex_home` runs before both wiring calls and establishes the initial symlink;
`ensure_caveman_wiring` overrides it only when caveman is enabled.
`bypass_hook_trust = true` is already present in the icodex `config.toml` template so
hooks fire non-interactively. See [[architecture#Default run path]] and
[[plugins#Superpowers wiring]].

## Asset layout

```
.codex-isolated/
  hooks/caveman-hook.py       # UserPromptSubmit hook (python3, stdlib only)
  caveman/agents-block.md     # block template (rules + mode table), curated from upstream SKILL.md
scripts/vendor-caveman.sh     # manual refresh of agents-block.md from upstream SKILL.md
lib/caveman/caveman.sh        # ensure_caveman_wiring(): render AGENTS.md region + home hooks.json
```

The hook lives in `.codex-isolated/hooks/` because `setup_codex_home` symlinks the
shared `hooks/` directory into each per-project home, making the hook available at
`$CODEX_HOME/hooks/caveman-hook.py` without copying it.

The compression rules are vendored once from the upstream caveman `SKILL.md` via
`scripts/vendor-caveman.sh`; the hook logic is native to icodex.

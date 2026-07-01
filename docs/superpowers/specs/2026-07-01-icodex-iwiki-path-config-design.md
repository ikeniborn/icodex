---
title: icodex iwiki path portability (command + base_dir) design
date: 2026-07-01
status: draft
chain:
  intent: null
review:
  spec_hash: 396a0cc2468aedc1
  last_run: 2026-07-01
  phases:
    structure:   { status: passed }
    coverage:    { status: passed }
    clarity:     { status: passed }
    consistency: { status: passed }
  findings: []
---

# icodex iwiki path portability — `command` + `IWIKI_BASE_DIR`

## Objective

Remove the two machine-specific absolute paths that `lib/iwiki/iwiki.sh` writes
literally into every Codex home `config.toml`, so an icodex checkout works on any
machine (different `$HOME`, different localized `Documents`/`Документы` folder)
without editing tracked source.

The two offending literals in `_iwiki_region_body`:

- `command = "/home/ikeniborn/.local/bin/iwiki-mcp"` — the iwiki-mcp binary.
- `IWIKI_BASE_DIR = "/home/ikeniborn/Documents/Project/iwiki-personal"` — the
  personal wiki content store.

Both are hardcoded to one user's home. On any other machine the username differs,
and the wiki store folder name is localized (observed: `Документы`, not
`Documents`), so a naive `$HOME/Documents/...` default would also break.

## Chosen approach — hybrid (auto-detect + `ICODEX_*` override)

Resolution happens inside `ensure_iwiki_wiring` at launch, using the existing
`.codex_config` → `ICODEX_*` allowlist (no parser change needed).

### `command` — auto-detect via PATH, optional override

```
cmd="${ICODEX_IWIKI_COMMAND:-$(command -v iwiki-mcp || true)}"
```

The iwiki-mcp binary is installed as a `uv tool`, which places a launcher on
`~/.local/bin` (on PATH) by convention. `command -v iwiki-mcp` therefore resolves
it with zero configuration on a correctly-installed machine (verified on the
current host: `/home/altuser/.local/bin/iwiki-mcp`). `ICODEX_IWIKI_COMMAND` is an
optional escape hatch for non-standard installs.

### `IWIKI_BASE_DIR` — required config var

```
base="${ICODEX_IWIKI_BASE_DIR:-}"
```

The wiki store location is genuinely a per-machine user choice (localized folder,
store lives outside any single project) and cannot be reliably auto-detected. It
is therefore **required**: `ICODEX_IWIKI_BASE_DIR` must be set in `.codex_config`.

### Guard — warn + skip (no half-broken block)

If either value is empty after resolution, `ensure_iwiki_wiring` logs a warning
and returns 0 without writing the iwiki region. Codex still starts; the iwiki MCP
server is simply not wired that launch. No silent wrong path, no hard failure.

```
if [[ -z "$cmd" || -z "$base" ]]; then
  log_warn "iwiki: command or base_dir unresolved, skipping iwiki wiring"
  return 0
fi
```

(Uses the existing logging helper in `lib/core/logging.sh`; exact function name
matched at implementation time.)

## Rationale — why hybrid over the two alternatives

- **Pure config-vars for both** (the initial proposal): correct but forces a
  manual `ICODEX_IWIKI_COMMAND` line on every machine for a value that is always
  the predictable uv/PATH location — needless per-machine toil.
- **Auto-detect for both**: rejected because `IWIKI_BASE_DIR` has no reliable
  automatic source (localized folder, user-chosen store outside the project).
- **Hybrid**: command self-ports via the install convention; base_dir stays under
  explicit user control where it must be. Matches the config header's stated
  precedence `built-in defaults < .codex_config < command-line flags`, and both
  values remain overridable via `ICODEX_*`, satisfying the original "extract into
  config" intent.

## Implementation surface

- **`lib/iwiki/iwiki.sh`** — `_iwiki_region_body` and `ensure_iwiki_wiring`:
  resolve `cmd`/`base` from `ICODEX_IWIKI_COMMAND` / `ICODEX_IWIKI_BASE_DIR` with
  the PATH fallback for command; add the empty-value guard; substitute the two
  values into the emitted block. The other three env values
  (`IWIKI_LLM_BASE_URL`, `IWIKI_EMBED_MODEL`, `IWIKI_EMBED_DIMENSIONS`) stay
  literal. The heredoc changes from fully-quoted `<<'EOF'` to a form that
  interpolates only `cmd`/`base` (built so the literal URL is not subject to
  unintended expansion).
- **`.codex_config.example`** — document both keys in the iwiki block:
  `ICODEX_IWIKI_COMMAND` (commented, optional, "auto-detected via PATH") and
  `ICODEX_IWIKI_BASE_DIR` (required for iwiki).
- **`.codex_config`** (local, git-ignored) — add
  `ICODEX_IWIKI_BASE_DIR=/home/altuser/Документы/Project/iwiki-personal`.
- **`tests/test_iwiki_wiring.sh`** — export the env vars in the test, assert the
  resolved values appear in the block, and add a case: unset base_dir ⇒ no iwiki
  region written, `ensure_iwiki_wiring` returns 0.
- **No change** to `lib/config/env.sh`: the `ICODEX_*` allowlist already admits
  both keys; `apply_iwiki_env` (secret `IWIKI_LLM_KEY` forwarding) is untouched.

## Non-goals

- No change to how the secret `IWIKI_LLM_KEY` is forwarded (`env_vars`).
- No change to `IWIKI_LLM_BASE_URL` / `IWIKI_EMBED_MODEL` /
  `IWIKI_EMBED_DIMENSIONS` (remain fixed literals).
- No change to `ensure_iwiki_binding` (`.iwiki.toml` seeding/symlink).

## Success criteria

- `grep -R "/home/ikeniborn" lib/ tests/` returns nothing (paths de-hardcoded).
- With `ICODEX_IWIKI_BASE_DIR` set and `iwiki-mcp` on PATH: the generated
  `[mcp_servers.iwiki]` block contains the resolved command and base_dir.
- With `ICODEX_IWIKI_BASE_DIR` unset: no iwiki region is written and launch does
  not fail.
- `tests/test_iwiki_wiring.sh` passes.

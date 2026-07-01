---
title: icodex iwiki full config externalization (all IWIKI_* server env) design
date: 2026-07-01
status: draft
chain:
  intent: null
review:
  spec_hash: c49c1770bb5cff4b
  last_run: 2026-07-01
  phases:
    structure:    { status: passed }
    coverage:     { status: passed }
    clarity:      { status: passed }
    consistency:  { status: passed }
  findings:
    - id: F-001
      phase: coverage
      severity: WARNING
      section: "Success criteria / Implementation surface"
      section_hash: 8819346ce2f3cb02
      fragment: 'grep -RIn "/home/ikeniborn" lib/ tests/ returns nothing (paths de-hardcoded).'
      text: >-
        Success criterion #1 greps lib/ AND tests/ for /home/ikeniborn and
        requires zero hits, and criterion #5 requires tests/test_iwiki_wiring.sh
        to pass; but that test currently hardcodes
        /home/ikeniborn/.local/bin/iwiki-mcp (lines 22, 47) and asserts literal
        command/IWIKI_BASE_DIR values the change removes. The Implementation
        surface file list omits tests/test_iwiki_wiring.sh, so the two criteria
        cannot both be met as scoped.
      fix: >-
        Add tests/test_iwiki_wiring.sh to the Implementation surface (update its
        assertions to config-driven/synthetic values), or narrow success
        criterion #1 to lib/ only and explicitly list the test-file rewrite.
      verdict: fixed
      verdict_at: 2026-07-01
---

# icodex iwiki full config externalization — all `IWIKI_*` server env

## Objective

Make the entire `IWIKI_*` environment surface of the iwiki MCP server configurable
from the user's git-ignored `.codex_config` via the existing `ICODEX_IWIKI_*`
convention, and remove the machine-specific literals currently baked into
`lib/iwiki/iwiki.sh`. Today `_iwiki_region_body` writes a fixed `[mcp_servers.iwiki]`
block into every Codex home `config.toml`, with two paths hardcoded to one user's
home and a fixed subset of env values. After this change the block is assembled at
launch: required values come from config (missing ⇒ iwiki is skipped), and every
optional tuning value is forwarded only when set (otherwise the server applies its
own default).

## The full `IWIKI_*` surface

Authoritative source: iwiki-mcp `src/iwiki_mcp/engine/config.py` + `base.py` and the
project README "Env reference". Each server var maps to `ICODEX_IWIKI_<NAME>`.

| Server env | Server default | icodex tier |
|---|---|---|
| `IWIKI_LLM_BASE_URL` | none | **required** |
| `IWIKI_LLM_KEY` | none | **required, secret** (forwarded via `env_vars`) |
| `IWIKI_BASE_DIR` | none | **required** |
| `IWIKI_EMBED_MODEL` | `text-embedding-3-small` | optional passthrough |
| `IWIKI_EMBED_DIMENSIONS` | `1536` | optional passthrough |
| `IWIKI_TOP_K` | `8` | optional passthrough |
| `IWIKI_SCORE_THRESHOLD` | `0.2` | optional passthrough |
| `IWIKI_GRAPH_DEPTH` | `2` | optional passthrough |
| `IWIKI_CHUNK_SIZE` | `512` | optional passthrough |
| `IWIKI_CHUNK_OVERLAP` | `64` | optional passthrough |
| `IWIKI_SUMMARY_MAX_CHARS` | `400` | optional passthrough |
| `IWIKI_PROJECT_DIR` | process cwd | **out of scope** (see below) |

`command` (the binary path, not an env var) is resolved separately:
`ICODEX_IWIKI_COMMAND`, else auto-detect via `command -v iwiki-mcp`.

`IWIKI_PROJECT_DIR` is deliberately never set: icodex resolves per-project binding
by symlinking the project `.iwiki.toml` into the Codex home so the server picks it
up from its cwd (`ensure_iwiki_binding`, unchanged). Setting `IWIKI_PROJECT_DIR`
would override that mechanism.

## Chosen approach — tiered resolution in `ensure_iwiki_wiring`

Resolution runs at launch using the existing `.codex_config` → `ICODEX_*` allowlist
(`lib/config/env.sh`; `ICODEX_IWIKI_*` already passes `_config_key_allowed`, so no
parser change).

### `command` — auto-detect via PATH, optional override

```
cmd="${ICODEX_IWIKI_COMMAND:-$(command -v iwiki-mcp || true)}"
```

The uv-tool install puts an `iwiki-mcp` launcher on `~/.local/bin` (on PATH), so
auto-detect works with zero config on a correctly-installed host (verified:
`/home/altuser/.local/bin/iwiki-mcp`). `ICODEX_IWIKI_COMMAND` overrides.

### Required tier — guarded

```
base="${ICODEX_IWIKI_BASE_DIR:-}"
url="${ICODEX_IWIKI_LLM_BASE_URL:-}"
key="${ICODEX_IWIKI_LLM_KEY:-${IWIKI_LLM_KEY:-}}"
```

`IWIKI_BASE_DIR`, `IWIKI_LLM_BASE_URL`, and the secret `IWIKI_LLM_KEY` are each
required for the server to function. `command` must also resolve. If any of
`cmd`/`base`/`url`/`key` is empty, `ensure_iwiki_wiring` logs a warning and returns
0 without writing the iwiki region — Codex still starts, iwiki is simply not wired
that launch. No partial block, no silent wrong path, no hard failure.

```
if [[ -z "$cmd" || -z "$base" || -z "$url" || -z "$key" ]]; then
  log_warn "iwiki: required setting (command/base_dir/llm_base_url/llm_key) unresolved, skipping iwiki wiring"
  return 0
fi
```

`base` and `url` are written literally into the `[mcp_servers.iwiki.env]` block;
`key` is **not** written literally — it stays forwarded through
`env_vars = ["IWIKI_LLM_KEY"]` (mapped from `ICODEX_IWIKI_LLM_KEY` by
`apply_iwiki_env`, unchanged). The guard only *checks* the key's presence.

### Optional passthrough tier — emit only when set

The eight optional vars are written into the block **only when the corresponding
`ICODEX_IWIKI_*` is non-empty**; otherwise the line is omitted and the server uses
its documented default. This is implemented with one loop over the var-name list,
using bash indirect expansion — no per-var branch, and new server vars are added by
extending the list:

```
for name in EMBED_MODEL EMBED_DIMENSIONS TOP_K SCORE_THRESHOLD GRAPH_DEPTH \
            CHUNK_SIZE CHUNK_OVERLAP SUMMARY_MAX_CHARS; do
  cfg="ICODEX_IWIKI_${name}"; val="${!cfg:-}"
  [[ -n "$val" ]] && printf 'IWIKI_%s = "%s"\n' "$name" "$val"
done
```

### Block structure

`_iwiki_region_body` receives the resolved `cmd`/`base`/`url` and emits (via
`printf`, so no heredoc-expansion concerns):

```
[mcp_servers.iwiki]
command = "<cmd>"
env_vars = ["IWIKI_LLM_KEY"]
[mcp_servers.iwiki.env]
IWIKI_BASE_DIR = "<base>"
IWIKI_LLM_BASE_URL = "<url>"
<optional IWIKI_* lines for each set var>
```

## Rationale

- The user asked for the whole `IWIKI_*` server surface to be configurable from
  `.codex_config`. The authoritative surface is 12 vars; 8 have sensible server
  defaults, so forcing them all to be set would be poor UX.
- Tiering keeps the mandatory footprint minimal (three required + a resolvable
  command) while making every tuning knob overridable — and the emit-if-set loop
  means the block never pins a value the user did not choose, so server-side default
  changes still take effect.
- The two path literals are broken across machines (different `$HOME`; the store
  folder is localized — observed `Документы`, not `Documents`), so they must be
  externalized regardless.
- The secret stays on its `env_vars` path (never written literally); the guard adds
  only a presence check so iwiki is not wired without a usable key.
- `IWIKI_PROJECT_DIR` is excluded because icodex's binding mechanism owns it.

## Implementation surface

- **`lib/iwiki/iwiki.sh`**
  - `_iwiki_region_body` takes `command`, `base_dir`, `llm_base_url`, emits the
    fixed lines with `printf`, then loops the eight optional var names emitting a
    line per set `ICODEX_IWIKI_*` (indirect expansion). Structural lines
    (`[mcp_servers.iwiki]`, `env_vars = ["IWIKI_LLM_KEY"]`, `[mcp_servers.iwiki.env]`)
    stay literal.
  - `ensure_iwiki_wiring` resolves `cmd` (with PATH fallback), `base`, `url`, `key`;
    applies the required-tier guard; passes `cmd`/`base`/`url` to `_iwiki_region_body`.
  - Update the module header comment.
- **`.codex_config.example`** — document the full key set: `ICODEX_IWIKI_COMMAND`
  (optional/auto), the three required keys, the eight optional passthrough keys
  (each noting its server default), and the secret `ICODEX_IWIKI_LLM_KEY`.
- **`.codex_config`** (local, git-ignored) — set this machine's required keys
  (`ICODEX_IWIKI_BASE_DIR`, `ICODEX_IWIKI_LLM_BASE_URL`) and the two embedding
  overrides this deployment already uses (`ICODEX_IWIKI_EMBED_MODEL=ollama-bge-m3`,
  `ICODEX_IWIKI_EMBED_DIMENSIONS=1024`), copied from the current source literals.
  The secret `ICODEX_IWIKI_LLM_KEY` is already present. Tuning vars are left unset
  (server defaults), preserving today's runtime behavior exactly.
- **`tests/test_iwiki_wiring.sh`** — rewrite the assertions from the removed
  hardcoded literals to config-driven / synthetic values: drive `ICODEX_IWIKI_*`
  in the test env, assert the resolved `command` / `IWIKI_BASE_DIR` /
  `IWIKI_LLM_BASE_URL` lines, assert set optional vars emit a line while unset ones
  are absent, and add a required-missing ⇒ no-region case.
- **No change** to `lib/config/env.sh` (allowlist admits all `ICODEX_IWIKI_*`;
  `apply_iwiki_env` untouched) or `ensure_iwiki_binding`.

## Non-goals

- No change to how the secret `IWIKI_LLM_KEY` is forwarded (`env_vars`).
- `IWIKI_PROJECT_DIR` is not exposed (binding is owned by `ensure_iwiki_binding`).
- No config-file parser changes (existing `ICODEX_*` allowlist reused).

## Success criteria

- `grep -RIn "/home/ikeniborn" lib/ tests/` returns nothing (paths de-hardcoded).
- `grep -n 'ollama-bge-m3\|IWIKI_EMBED_DIMENSIONS = "1024"\|IWIKI_LLM_BASE_URL = "http' lib/iwiki/iwiki.sh`
  returns nothing — the machine/deployment value literals no longer live in source
  (the template lines `IWIKI_* = "$var"` are intentionally not matched).
- With `cmd`/`base`/`url`/`key` all resolvable: the generated block contains
  `command`, `IWIKI_BASE_DIR`, `IWIKI_LLM_BASE_URL`, and `env_vars`; and for each set
  optional `ICODEX_IWIKI_*`, exactly one `IWIKI_<NAME>` line, with unset optionals
  absent.
- With any required value (`base`/`url`/`key`) unset: no iwiki region is written and
  launch returns 0.
- `tests/test_iwiki_wiring.sh` passes and the full `tests/test_*.sh` suite stays
  green.

---
title: icodex iwiki-mcp server integration design
date: 2026-06-30
status: draft
review:
  spec_hash: 0bfd265e61f4ecd6
  last_run: 2026-06-30
  phases:
    structure:    { status: passed }
    coverage:     { status: passed }
    clarity:      { status: passed }
    consistency:  { status: passed }
  findings: []
chain:
  intent: null
---

# icodex iwiki-mcp server integration

## Objective

Make the `iwiki-mcp` stdio MCP server (sibling project `iwiki-mcp`, see its
`README.md`) a built-in part of the isolated Codex environment that icodex
provisions. Today the server
is reachable only because it was registered by hand in a Claude Code runtime file
(`.claude.json`); icodex itself wires no MCP server, so the registration is lost
on any rebuild and never reaches Codex at all. After this change every Codex home
icodex launches has the `iwiki` MCP server registered, always on, with its
settings fixed in the server block and the one secret kept out of git.

Scope decisions (confirmed with the user):

- **Target: Codex only (icodex).** Not iclaude. The Claude-side engine plugin is
  untouched; icodex has no prior iwiki integration, so this adds the MCP server
  from scratch.
- **Always on.** No enable/disable gate — the server is wired on every launch.
- **System binary (hardcoded path).** Use the already-installed
  `/home/ikeniborn/.local/bin/iwiki-mcp` (a `uv tool`, v0.1.0) directly. No
  isolated install, no PATH resolution.
- **Settings fixed in the server block.** Non-secret env (`IWIKI_BASE_DIR`,
  `IWIKI_LLM_BASE_URL`, `IWIKI_EMBED_MODEL`, `IWIKI_EMBED_DIMENSIONS`) is written
  literally into the `[mcp_servers.iwiki]` block. Only the secret
  (`IWIKI_LLM_KEY`) is kept out of the block.
- **No per-project binding.** `.iwiki.toml` / `IWIKI_PROJECT_DIR` are not used —
  every project can already reach any domain via `scope="all"`, an explicit
  `domains` list, or `wiki_bind` in-session. The block is fully static.
- **Base:** `/home/ikeniborn/Documents/Project/iwiki-personal`.

## Background — how Codex passes env to an MCP server

Codex does **not** hand the full parent environment to a spawned stdio MCP
server. Two distinct keys control its env (Codex config reference / MCP docs):

- `env = { KEY = "value" }` — literal values written into the config.
- `env_vars = ["NAME"]` — an allowlist of parent-process env vars to forward by
  the same name. There is **no** shell-style expansion (`"$TOKEN"` is literal).

This is the hinge of the design: literal non-secret settings go in `env`; the
secret is forwarded by name via `env_vars`, so it never appears in the config
file.

### Git-tracking facts that force the secret out of the block

| Path | Tracked in git? | Consequence |
|------|-----------------|-------------|
| `.codex-isolated/config.toml` (shared template) | **yes** (whitelisted) | no secret may be written here |
| `.codex-homes/*/config.toml` (per-project home) | no (`.codex-homes/` ignored) | per-home config may hold a secret, but it is generated, not authored |
| `.codex_config` | no (ignored, chmod 600) | the place for the secret |
| `lib/**` | yes | region text authored here must contain no secret |

The non-secret server settings are not secrets, so hardcoding them in tracked
code is acceptable (the repo already hardcodes the user's absolute paths, e.g.
the marketplace `source` line). The secret must live only in `.codex_config` and
reach the server through the environment.

## Architecture

icodex already exports `ICODEX_*` config into the launch environment
(`lib/config/env.sh` `load_config`) and applies per-home wiring steps at launch
(`ensure_caveman_wiring`, `ensure_idd_wiring`) that edit the per-home
`config.toml` / `hooks.json`. This change follows that exact shape: an env mapping
for the secret plus a per-launch wiring step that maintains a delimited region in
the per-home `config.toml`.

```
.codex_config                      # ICODEX_IWIKI_LLM_KEY=<secret> (git-ignored)
.codex_config.example              # commented #ICODEX_IWIKI_LLM_KEY=... + docs
lib/config/env.sh                  # allow ICODEX_IWIKI_*; apply_iwiki_env de-prefix
lib/iwiki/iwiki.sh                 # ensure_iwiki_wiring — region resync (new)
icodex.sh                          # source iwiki/iwiki + call after ensure_idd_wiring
```

Data flow at launch:

1. `load_config` exports `ICODEX_IWIKI_LLM_KEY` into the environment.
2. `apply_iwiki_env` re-exports it as `IWIKI_LLM_KEY` (the name the server and
   `env_vars` expect).
3. `ensure_iwiki_wiring` writes the static `# icodex:iwiki:*` region into the
   per-home `config.toml`.
4. Codex launches, spawns `iwiki-mcp`, forwards `IWIKI_LLM_KEY` from the env per
   `env_vars`, and passes the literal `env` block.

## Component 1 — the server block (static region)

A delimited region appended to the per-home `config.toml`:

```toml
# icodex:iwiki:start
[mcp_servers.iwiki]
command = "/home/ikeniborn/.local/bin/iwiki-mcp"
env_vars = ["IWIKI_LLM_KEY"]
[mcp_servers.iwiki.env]
IWIKI_BASE_DIR = "/home/ikeniborn/Documents/Project/iwiki-personal"
IWIKI_LLM_BASE_URL = "https://litellm.ikeniborn.ru/v1"
IWIKI_EMBED_MODEL = "ollama-bge-m3"
IWIKI_EMBED_DIMENSIONS = "1024"
# icodex:iwiki:end
```

TOML notes: `command` / `env_vars` must precede the `[mcp_servers.iwiki.env]`
subtable header (keys after a subtable header bind to the subtable). The region
is **appended at the end of the file** — `[mcp_servers.iwiki]` and its `.env`
subtable are the trailing tables, so no later bare top-level key can be captured
by them. icodex's other launch edits (`apply_mode`) rewrite existing fields in
place and never append top-level keys after this region, so the ordering holds.

## Component 2 — `.codex_config` / `.codex_config.example`

- `.codex_config` (the live, git-ignored file): add `ICODEX_IWIKI_LLM_KEY=<secret>`.
- `.codex_config.example`: add a commented `#ICODEX_IWIKI_LLM_KEY=sk-...` with a
  one-line explanation that it is the only iwiki key needed (everything else is
  fixed in the server block), mirroring the existing example's comment style. No
  secret value in the example.

## Component 3 — `lib/config/env.sh`

Two edits, both following existing patterns:

1. **Unblock the wrapper key.** `_config_key_allowed` currently rejects
   `ICODEX_IWIKI_*|IWIKI_[A-Z0-9_]*`. Change it to allow `ICODEX_IWIKI_*`
   (so `load_config` exports it) while keeping the raw `IWIKI_*` prefix rejected
   (a raw `IWIKI_LLM_KEY` in `.codex_config` stays disallowed; it must go through
   the `ICODEX_` wrapper).
2. **De-prefix mapping.** Add `apply_iwiki_env()` mirroring `apply_api_key`:
   `ICODEX_IWIKI_LLM_KEY` → `export IWIKI_LLM_KEY` (only when set; do not clobber
   an `IWIKI_LLM_KEY` already in the environment). Call it from `icodex.sh`
   `main()` right after `apply_api_key`.

Only `IWIKI_LLM_KEY` is mapped — it is the only var the server needs from the
environment (everything else is literal in the block).

## Component 4 — `lib/iwiki/iwiki.sh` (new)

A small launch-path module mirroring the region mechanism in
`lib/config/isolated.sh` (`_sync_agents_base_region`). One function,
`ensure_iwiki_wiring`:

- Operates on `$ICODEX_HOME_DIR/config.toml` (a real copied file, not a symlink,
  per `setup_codex_home`), so in-place editing is safe.
- Strips any existing `# icodex:iwiki:start` … `# icodex:iwiki:end` region, then
  appends the current static region at the end of the file.
- Idempotent: writes only when the result differs (the `cmp -s` guard the other
  region helpers use).
- Always on — no gate, no opt-out branch. (Stripping is only the
  remove-then-reappend step, not a disable path.)

Because the region is resynced from the module on every launch, it lands in both
existing homes (which were copied before this feature) and new ones.

## Component 5 — `icodex.sh`

- Add `iwiki/iwiki` to the module `source` list.
- Call `ensure_iwiki_wiring` in `main()` after `ensure_idd_wiring` (alongside the
  other per-home wiring steps, after `setup_codex_home` has created the home).
- Call `apply_iwiki_env` after `apply_api_key`.

No `.gitignore` change is needed: the new file is under `lib/` (already tracked)
and the region is written only into git-ignored per-home configs.

## Error handling

- **Missing secret.** If `ICODEX_IWIKI_LLM_KEY` is unset, the region is still
  written; the server starts but its embeddings calls fail at runtime. The
  `.codex_config.example` documents the key; no launch-time hard failure is
  introduced (consistent with how icodex treats other optional config).
- **Missing binary.** The hardcoded `command` path may not exist on a given host;
  Codex reports the MCP server as failed to start. Acceptable for a personal
  tool with a fixed install location; surfaced in the spec, not guarded in code.
- **Region write.** `ensure_iwiki_wiring` follows the existing region helpers'
  failure posture (temp file + compare + replace); a write failure leaves the
  prior config intact.

## Testing

Standalone `tests/test_iwiki_*.sh` (sourcing `tests/helpers.sh`, no network,
temp-dir filesystem side effects):

- `test_iwiki_wiring.sh` — `ensure_iwiki_wiring` on a fresh temp `config.toml`
  inserts exactly one `# icodex:iwiki:*` region containing the `[mcp_servers.iwiki]`
  block; a second run is a no-op (idempotent, byte-identical); a pre-existing
  stale region is replaced, not duplicated; the region is the trailing content of
  the file.
- `test_iwiki_env.sh` — `apply_iwiki_env` exports `IWIKI_LLM_KEY` from
  `ICODEX_IWIKI_LLM_KEY`; does not clobber a pre-set `IWIKI_LLM_KEY`; is a no-op
  when the source is unset. `_config_key_allowed` accepts `ICODEX_IWIKI_LLM_KEY`
  and still rejects a raw `IWIKI_LLM_KEY`.

## Out of scope

- iclaude / Claude Code wiring (the Claude-side engine plugin is untouched).
- Isolated install of the `iwiki-mcp` binary (system binary by decision).
- Per-project `.iwiki.toml` binding / `IWIKI_PROJECT_DIR` (dropped by decision).
- An enable/disable gate (always on by decision).
- Making the non-secret settings configurable via `ICODEX_IWIKI_*` (fixed in the
  block by decision; can be revisited if a second base/model is ever needed).

# Config

## Overview

The `lib/config/` modules manage per-project isolation and Codex runtime config.

`isolated.sh` resolves a per-project `CODEX_HOME` backed by a shared asset store,
`sandbox.sh` resolves an `ICODEX_MODE` run profile and writes its `sandbox_mode` /
`approval_policy` / `default_permissions` triple, `permissions.sh` grants filesystem
access (including `.git` write) and trusts the launched project, and `env.sh` parses
the git-ignored `.codex_config`. See [[architecture#Two-config model]].

## CODEX_HOME isolation

`setup_codex_home` builds a per-project home under `ICODEX_HOMES_DIR` and exports `CODEX_HOME`.

Expensive, stable assets — the codex binary, `uv`, the vendored plugin cache,
standalone skills, and `auth.json` — live once in the shared store
`ICODEX_SHARED_DIR` (`.codex-isolated`).
Per-project state lives in a home `ICODEX_HOMES_DIR/<basename>-<short-sha256>`
(`.codex-homes/<id>`), keyed by the target project root via `resolve_project_root`
(the git toplevel of the CWD, else `pwd -P`). `setup_codex_home` symlinks `plugins`,
`hooks`, `hooks.json`, `auth.json`, `skills`, and `rules` back to the shared store
with the idempotent `_link_shared` — so the vendored user skills and the
`rules/default.rules` execution policy (read by codex from `$CODEX_HOME/rules` at
startup) are live in each home, not stranded in the shared store. It copies the
template `config.toml` once when absent, syncs the `AGENTS.md` base region with
`_sync_agents_base_region`, and exports `CODEX_HOME` — so each project gets isolated
sessions and logs while sharing the heavy assets. The `install`/`update` paths
instead call `setup_shared_dirs`, which only creates the shared `bin` dir. The
`.codex-homes/` tree is git-ignored runtime state.

`_sync_agents_base_region` keeps the global guidance current in every home without a
symlink (which caveman would mutate into the tracked source). It maintains a
delimited `<!-- icodex:base:start -->`…`<!-- icodex:base:end -->` region in
`$CODEX_HOME/AGENTS.md`, re-synced from the shared `.codex-isolated/AGENTS.md` on
every launch so edits propagate to existing homes. It strips and re-appends only its
own region, leaving the caveman region and any free text intact — mirroring the
region mechanism in [[caveman]].

## Sandbox mode

`sandbox.sh` resolves a complete run profile from `ICODEX_MODE` and writes it idempotently into the per-project `config.toml`.

`resolve_mode` maps the `ICODEX_MODE` preset — `ro`, `safe`, `full-ask` (the
default), or `full-auto` — to the effective `sandbox approval permissions` triple.
Precedence runs preset `< ICODEX_MODE <` the granular `ICODEX_SANDBOX` /
`ICODEX_APPROVAL` / `ICODEX_PERMISSIONS` overrides; `--full-access` /
`ICODEX_FULL_ACCESS` still forces the sandbox field to `danger-full-access` (it
reuses `resolve_sandbox_mode`). Any invalid preset or value is rejected with
`log_error` and a non-zero return. `apply_mode` upserts `sandbox_mode` and
`approval_policy` as top-level keys via `_upsert_toml_toplevel`, then manages the
permission layer: for a real profile it
upserts `default_permissions` and calls `ensure_git_writable`; for the `none`
sentinel it drops `default_permissions` with `_remove_toml_toplevel`, turning the
managed layer off. It emits a `log_warn` for `danger-full-access` (full filesystem
access) and for `none` (managed permission layer off; `approval_policy` is set
separately). All writes are
idempotent upserts that leave an unchanged file byte-identical. See
[[command#Flag parsing]].

## Project trust

`ensure_project_trust` marks the launched project trusted in its per-project config.

It idempotently appends a `[projects."<root>"]` block with `trust_level = "trusted"`
for `ICODEX_PROJECT_ROOT`, escaping the path with `_toml_basic_string_escape` and
skipping the write when the block already exists. It governs trust only and never
changes `approval_policy`.

## Persistent user config

`load_config` reads `.codex_config` line by line.

It tolerates CRLF, ignores comments and blank lines, and exports only allowed
keys. The file is parsed, never sourced, so values can never execute code.
Precedence is built-in defaults < `.codex_config` < CLI flags. Missing file is a
no-op.

## Allowed keys

`_config_key_allowed` permits `ICODEX_*` keys and exports each verbatim.

The `ICODEX_IWIKI_*`/`IWIKI_*` namespace reserved for the iwiki plugin is
explicitly denied; everything else non-`ICODEX_` is ignored. `uv` is not
configurable here — its path is fixed at `.codex-isolated/bin/uv`, exported as
`UV_BIN` by [[binary#uv dependency]].

## ICODEX_CAVEMAN_MODE

`ICODEX_CAVEMAN_MODE` selects the caveman output-compression level for the session.

Values: unset / `off` (ship default — caveman disabled) | `lite` | `full` | `ultra`.
When set to `lite`, `full`, or `ultra`, `ensure_caveman_wiring` renders the caveman
instruction block into `$CODEX_HOME/AGENTS.md` and registers the `UserPromptSubmit`
hook by writing a real `$CODEX_HOME/hooks.json` = shared secret-guard hooks merged
with the caveman entry. When unset or `off`, the block is removed and the symlink to
the shared `hooks.json` is restored. The value at launch becomes the **active launch
mode**; in-session `/caveman` switches can override it for the remainder of the
session. See [[caveman]] for full details.

## ICODEX_IDD

`ICODEX_IDD` controls the IDD->SDD gate and nudge hooks.

IDD is enabled by default. Set `ICODEX_IDD=off` to strip the `chain-gate.py` gate
and nudge hook entries from the per-project `hooks.json`. When stripping leaves
the home hook config identical to the shared base, the wrapper restores the home
`hooks.json` symlink. See [[idd#Opt-out]].

## API key mapping

`apply_api_key` maps `ICODEX_API_KEY` to `OPENAI_API_KEY` for codex.

An `OPENAI_API_KEY` already present in the environment wins, so an ambient key is
never overridden. This keeps the secret out of git while still supporting
`codex login` or a directly-exported key.

## Config upsert

`_config_set` upserts a `KEY=value` line while preserving other lines.

It greps out the existing key, appends the new value, and rewrites the file with a
`177` umask plus explicit `chmod 600`, so credentials stay private from the first
write. Used by [[launch#Proxy persist and apply]].

## Sandbox permission wiring

`permissions.sh` injects the filesystem grants codex needs into the managed permission profiles of `config.toml`.

The managed layer is the second half of the two-layer model: `sandbox_mode` sets the
broad sandbox, while a named `[permissions.<profile>]` profile (selected by
`default_permissions`) sets fine-grained filesystem and network rules.
`_ensure_filesystem_permission_entry` upserts a quoted path key idempotently under
`[permissions.dev-safe.filesystem]`, and `ensure_launcher_binary_permission` grants
`read` on `ICODEX_BIN` so the launcher binary stays reachable from any workspace.
`ensure_git_writable <config> <profile>` grants `".git/" = "write"` under the
profile's `:workspace_roots` table — parameterized for both `dev-safe` and
`ssh-on-request` — overriding codex's read-only re-mount of `.git` so commits work in
every writable mode. `apply_mode` calls it for the active profile on each run. The grant
is verifiable in isolation: under a `workspace-write` sandbox a write to `.git/` run via
`codex sandbox -P <profile> --include-managed-config` succeeds only while the
`".git/" = "write"` line is present and fails once it is removed; under
`danger-full-access` `.git` is writable through the sandbox regardless, and under
`read-only` nothing is writable.

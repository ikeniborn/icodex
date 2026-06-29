# Config

## Overview

The `lib/config/` modules manage per-project isolation and Codex runtime config.

`isolated.sh` resolves a per-project `CODEX_HOME` backed by a shared asset store,
`sandbox.sh` resolves and writes the effective `sandbox_mode`, `permissions.sh`
grants filesystem access and trusts the launched project, and `env.sh` parses the
git-ignored `.codex_config` and maps the API key. See [[architecture#Two-config model]].

## CODEX_HOME isolation

`setup_codex_home` builds a per-project home under `ICODEX_HOMES_DIR` and exports `CODEX_HOME`.

Expensive, stable assets — the codex binary, `uv`, the vendored plugin cache, and
`auth.json` — live once in the shared store `ICODEX_SHARED_DIR` (`.codex-isolated`).
Per-project state lives in a home `ICODEX_HOMES_DIR/<basename>-<short-sha256>`
(`.codex-homes/<id>`), keyed by the target project root via `resolve_project_root`
(the git toplevel of the CWD, else `pwd -P`). `setup_codex_home` symlinks `plugins`
and `auth.json` back to the shared store with the idempotent `_link_shared`, copies
the template `config.toml` once when absent, and exports `CODEX_HOME` — so each
project gets isolated sessions and logs while sharing the heavy assets. The
`install`/`update` paths instead call `setup_shared_dirs`, which only creates the
shared `bin` dir. The `.codex-homes/` tree is git-ignored runtime state.

## Sandbox mode

`sandbox.sh` makes the filesystem sandbox safe by default and makes escalation explicit.

`resolve_sandbox_mode` echoes the effective mode with precedence
`workspace-write` (the default) < `ICODEX_SANDBOX` < `--full-access` /
`ICODEX_FULL_ACCESS`; an `ICODEX_SANDBOX` outside `read-only`, `workspace-write`,
`danger-full-access` is rejected with `log_error` and a non-zero return.
`apply_sandbox_mode` writes the resolved value into the per-project `config.toml`
through `_upsert_toml_toplevel` — an idempotent `awk` upsert of a top-level
`sandbox_mode = "..."` line that leaves an unchanged file byte-identical. Escalating
to `danger-full-access` emits a `log_warn` that full filesystem access is enabled.
`approval_policy` is never touched. See [[command#Flag parsing]].

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

## Allowed keys and mapping

`_config_key_allowed` permits `ICODEX_*`, `CODEX_UV_BIN`, and `UV_BIN`.

`_config_export_mapped` exports each key as written and also maps
`ICODEX_UV_BIN`/`CODEX_UV_BIN` to `UV_BIN`.

## API key mapping

`apply_api_key` maps `ICODEX_API_KEY` to `OPENAI_API_KEY` for codex.

An `OPENAI_API_KEY` already present in the environment wins, so an ambient key is
never overridden. This keeps the secret out of git while still supporting
`codex login` or a directly-exported key.

## Config upsert

`_config_set` upserts a `KEY=value` line while preserving other lines.

It greps out the existing key, appends the new value, and rewrites the file with a
`177` umask plus explicit `chmod 600`, so credentials stay private from the first
write. Used by [[launch#Proxy persist and apply]] and [[binary#uv dependency]].

## Sandbox permission wiring

`permissions.sh` injects filesystem grants into the `dev-safe` profile of `config.toml`.

This lets codex reach paths icodex needs even when the workspace is another repo.
`_ensure_filesystem_permission_entry` uses an awk pass to upsert a quoted path key
idempotently under `[permissions.dev-safe.filesystem]`; `ensure_launcher_binary_permission`
grants `read` on `ICODEX_BIN`.

# Config

## Overview

The `lib/config/` modules manage isolation and configuration.

`isolated.sh` redirects codex state into the project via `CODEX_HOME`, `env.sh`
parses the git-ignored `.codex_config` and maps the API key, and `permissions.sh`
injects sandbox filesystem grants into `config.toml`. See
[[architecture#Two-config model]] and [[binary#uv dependency]].

## CODEX_HOME isolation

`setup_codex_home` creates `.codex-isolated/bin` and exports `CODEX_HOME`.

It points `CODEX_HOME` at `ICODEX_HOME_DIR`. This single redirect makes codex keep
all of its state — config, sessions, logs, sqlite, plugin caches — inside the
project rather than the user's home, the foundation of icodex's isolation.

## Persistent user config

`load_config` reads `.codex_config` line by line.

It tolerates CRLF, ignores comments and blank lines, and exports only allowed
keys. The file is parsed, never sourced, so values can never execute code.
Precedence is built-in defaults < `.codex_config` < CLI flags. Missing file is a
no-op.

## Allowed keys and mapping

`_config_key_allowed` permits `ICODEX_*`, `CODEX_UV_BIN`, `IWIKI_*`, and `UV_BIN`.

`_config_export_mapped` exports each key as written and also under a runtime
alias: `ICODEX_IWIKI_*` is re-exported as `IWIKI_*` (the names iwiki tools
expect), and `ICODEX_UV_BIN`/`CODEX_UV_BIN` as `UV_BIN`. See [[plugins#iwiki wiring]].

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

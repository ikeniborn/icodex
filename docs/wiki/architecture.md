# Architecture

## Overview

icodex is an isolated bash wrapper around the OpenAI Codex CLI.

The `icodex.sh` entrypoint sources every module under `lib/`, then `main()`
loads config, parses flags, and dispatches to install, update, or the default
run path. State is kept in-project via `CODEX_HOME`; only the pinned binary is
fetched on demand. See [[core#Global paths and identity]], [[command#Flag parsing]],
[[binary#Install and update]].

## Entrypoint and symlink resolution

`icodex.sh` resolves its own real path even when invoked through a symlink.

It walks `readlink` until it reaches the repo, so modules are always sourced from
the repo rather than the link directory (e.g. `~/.local/bin/icodex`). The resolved
directory becomes `ICODEX_ROOT` and is exported.

## Module load order

The entrypoint sources modules in a fixed order before running `main()`.

The order is `core/logging`, `core/init`, `core/validation`, `command/args`, the
`binary/*` trio, `config/*`, `proxy`, `symlink`, the `plugin/*` pair, and finally
`launcher/launch`. Each is a flat bash file defining functions only — see
[[core#Logging helpers]] for the first loaded.

## Command dispatch

`main()` runs `load_config`, `apply_api_key`, then `parse_args`.

Early commands (`help`, `clear`, `version`) return before any tool checks. After
`require_tools`, a `--proxy` value is persisted, then `install`/`update` run and
exit, or the default run path proceeds. Flags map to `ICODEX_CMD` in
[[command#Flag parsing]].

## Default run path

The default `run` case wires up the isolated environment, then execs codex.

It calls `setup_codex_home`, wires launcher binary permissions, wires the
Superpowers and iwiki plugins, ensures the binary and uv are present, optionally
applies the proxy, then `exec`s codex. See [[config#CODEX_HOME isolation]],
[[plugins#Superpowers wiring]], [[launch#Final exec]].

## Two-config model

icodex separates wrapper settings from Codex runtime settings.

`.codex_config` (git-ignored, `chmod 600`) holds `ICODEX_*` keys: API key, proxy,
repo, symlink dir. `.codex-isolated/config.toml` (tracked) holds Codex runtime:
model, sandbox, approvals, permissions, plugins. See [[config#Persistent user config]].

## What lives in git

Only the codex binary is fetched on demand; everything else ships in the repo.

The binary is pinned by version + sha256 in the committed `.codex-lockfile.json`.
The curated `CODEX_HOME` config and the pre-vendored Superpowers/iwiki plugin
caches are committed. Binary, secrets, and runtime state are git-ignored via an
allowlist. See [[binary#Lockfile pinning]] and [[tooling#Plugin vendoring]].

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

## Launcher symlink and PATH

`install_symlink` and `ensure_path_entry` (in `lib/symlink/symlink.sh`) make
`icodex` runnable as a bare command after `--install`/`--update`.

`install_symlink` points `$ICODEX_LINK_DIR/icodex` (default `~/.local/bin/icodex`)
at the repo's `icodex.sh`, repairing a stale link and never clobbering a real file.
`ensure_path_entry` then guarantees that dir is on `PATH`: if it is already present
it does nothing; otherwise it appends an `export` (bash `~/.bashrc`, zsh `~/.zshrc`)
or `fish_add_path` (`~/.config/fish/config.fish`) chosen from `$SHELL`. It is
idempotent — skipped when the dir is already referenced in the profile (marker,
prior run, or manual edit) — and only ever appends, so a hand-managed profile stays
intact. An unknown shell gets a manual hint instead of an edit. Both run on
`--install` and `--update`. See [[binary#Install and update]].

## Module load order

The entrypoint sources modules in a fixed order before running `main()`.

The order is `core/logging`, `core/init`, `core/validation`, `command/args`, the
`binary/*` trio, `config/*`, `proxy`, `symlink`, the plugin module, and finally
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

It calls `setup_codex_home` to build the per-project `CODEX_HOME`, `apply_mode`
to write the resolved `ICODEX_MODE` run profile (`sandbox_mode`, `approval_policy`,
managed permissions), and `ensure_project_trust` to trust the
launched project, then wires launcher binary permissions and the Superpowers plugin,
runs `ensure_caveman_wiring` (gated on `ICODEX_CAVEMAN_MODE`) to render the caveman
`AGENTS.md` block and merge the `UserPromptSubmit` hook into the home `hooks.json`,
ensures the binary and `uv` are present, optionally applies the proxy, and finally
`exec`s codex. The `install`/`update` paths instead call `setup_shared_dirs` and
create no per-project home. See [[config#CODEX_HOME isolation]], [[config#Sandbox mode]],
[[plugins#Superpowers wiring]], [[caveman#Launch-path wiring]], [[launch#Final exec]].

## Two-config model

icodex separates wrapper settings from Codex runtime settings.

`.codex_config` (git-ignored, `chmod 600`) holds `ICODEX_*` keys: API key, proxy,
repo, symlink dir. The tracked `.codex-isolated/config.toml` is the template Codex
runtime config (model, sandbox, approvals, permissions, plugins); it is copied into
each per-project `CODEX_HOME` on first run, where `sandbox_mode` and project trust
are then managed. See [[config#Persistent user config]], [[config#Sandbox mode]].

## What lives in git

Only the codex binary is fetched on demand; everything else ships in the repo.

The binary is pinned by version + sha256 in the committed `.codex-lockfile.json`.
The curated `CODEX_HOME` config and the pre-vendored Superpowers plugin cache
are committed. Binary, secrets, and runtime state are git-ignored via an
allowlist. See [[binary#Lockfile pinning]] and [[tooling#Plugin vendoring]].

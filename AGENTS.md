# Repository Guidelines

## Project Structure & Module Organization

`icodex.sh` is the main Bash entrypoint. Runtime modules live under `lib/`, grouped by responsibility: `core/`, `command/`, `binary/`, `config/`, `proxy/`, `plugin/`, `launcher/`, and `symlink/`. Maintenance scripts live in `scripts/`. Tests are standalone Bash files in `tests/`, with shared assertions in `tests/helpers.sh`. Project documentation and design notes are under `docs/superpowers/`. The isolated Codex home template is tracked selectively in `.codex-isolated/`; do not add secrets or runtime state there.

## Build, Test, and Development Commands

- `./icodex.sh --help` prints supported wrapper commands and options.
- `./icodex.sh --install` fetches the pinned Codex binary and creates the local symlink.
- `./icodex.sh --version` prints the wrapper version and installed Codex version, if present.
- `bash tests/test_smoke.sh` runs the smoke test.
- `for t in tests/test_*.sh; do bash "$t" || exit 1; done` runs the full Bash test suite.

There is no package manager or Makefile in this repository; keep new commands dependency-free unless the project explicitly adopts a tool.

## Coding Style & Naming Conventions

Use Bash with `#!/usr/bin/env bash`. Prefer `set -euo pipefail` for executable paths and `set -uo pipefail` in tests that intentionally inspect failures. Use two-space indentation inside functions and conditionals, matching existing files. Keep module functions focused and name them with lowercase words separated by underscores, for example `install_ensure` or `ensure_iwiki_wiring`. Environment variables should use the `ICODEX_` prefix for wrapper configuration.

## Testing Guidelines

Add or update a focused `tests/test_*.sh` file for behavior changes. Source `tests/helpers.sh` and use `assert_eq`, `assert_exit`, and `assert_contains` for readable checks. Tests should avoid network access where possible and use temporary directories for filesystem side effects.

## Commit & Pull Request Guidelines

Git history mostly follows Conventional Commits, such as `feat(plugin): ...`, `fix(vendor): ...`, `docs(spec): ...`, and `chore: ...`. Keep commits scoped to one change. For pull requests, include a short summary, test commands run, and any user-visible behavior or configuration changes. Link related design docs or issues when applicable.

## Security & Configuration Tips

Keep secrets in `.codex_config` or Codex auth files, never in tracked docs or scripts. Do not commit downloaded binaries, SQLite runtime state, logs, tokens, or local credentials. When editing `.codex-isolated/`, respect the existing whitelist-style tracking model.

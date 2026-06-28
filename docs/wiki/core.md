# Core

## Overview

The `lib/core/` modules provide foundations every other module relies on.

They give stderr-only logging helpers, global path and identity variables derived
from `ICODEX_ROOT`, a portable sha256 helper, and a precondition check for
required external tools. They are sourced first by the entrypoint. See
[[architecture#Module load order]] and [[binary#Install and update]].

## Logging helpers

`core/logging.sh` defines `log_info`, `log_warn`, and `log_error`.

All three print to stderr (with ANSI color prefixes) so stdout stays clean for
data such as the `version` output. Every module emits diagnostics through these
helpers rather than raw `echo`.

## Global paths and identity

`core/init.sh` derives `ICODEX_ROOT` if absent, then sets the canonical paths.

These are `ICODEX_HOME_DIR` (`.codex-isolated`), `ICODEX_BIN`, the version stamp
`ICODEX_STAMP`, `ICODEX_LOCKFILE`, `ICODEX_CONFIG`, `ICODEX_PROJECT_ID`, and the
default `ICODEX_REPO` (`openai/codex`). They are used throughout, including
[[binary#Install and update]] and [[config#CODEX_HOME isolation]].

## Portable sha256

`core/init.sh` also defines `_sha256`, reading stdin and printing only the digest.

It prefers `sha256sum` and falls back to `shasum -a 256`, making the binary
integrity check in [[binary#Tamper guard]] portable across Linux and macOS.

## Tool preconditions

`core/validation.sh` provides `require_tools`, checking required tools are on PATH.

It verifies `curl`, `tar`, and one of `sha256sum`/`shasum`. Missing tools are
collected and reported via `log_error`, returning non-zero so `main()` aborts
before any download. The `help`/`clear`/`version` commands run before this check.

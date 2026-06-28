# icodex External Workspace Sandbox Access Design

**Date:** 2026-06-28
**Intent:** `docs/superpowers/intents/2026-06-28-icodex-external-workspace-sandbox-intent.md`

## Acceptance From Intent
- Running Codex through `icodex` from an external workspace no longer fails with
  `bwrap: execvp .../.codex-isolated/bin/codex: No such file or directory`.
- Normal tool commands inside Codex, such as `git status`, `pwd`, and workspace
  file reads, can start.
- Access to `.codex-isolated/bin/codex` is granted as read-only, without write
  access to `.codex-isolated/bin`.
- Existing `dev-safe` deny rules for secrets, environment files, and tokens are
  not weakened.

## Root Cause
`icodex` stores and executes the Codex binary from
`$ICODEX_ROOT/.codex-isolated/bin/codex`. When `icodex` is used as a shared
wrapper for another workspace, that binary path can sit outside the active
workspace root. Codex's Bubblewrap sandbox then attempts to `execvp` the launcher
binary path before the command shell starts, but the path is not mounted in the
sandbox, causing `No such file or directory`.

## Chosen Approach
On the default launch path, `icodex` rewrites the live
`.codex-isolated/config.toml` to include a literal read-only filesystem entry for
`$ICODEX_BIN`:

```toml
"/abs/path/to/.codex-isolated/bin/codex" = "read"
```

The entry is inserted into `[permissions.dev-safe.filesystem]`. The helper is
idempotent: if the entry already exists with `read`, it leaves the file unchanged;
if the same key exists with another value, it replaces it with `read`.

## Rejected Approaches
- `--add-dir .codex-isolated/bin`: too broad for the `trust` priority because it
  treats the directory as an additional workspace root.
- Per-workspace Codex binary installation: duplicates state and contradicts the
  shared-wrapper objective.
- Global `~/.codex`: weakens the per-wrapper isolation model.

## Data Flow
1. `icodex.sh` resolves `ICODEX_ROOT`.
2. `setup_codex_home` sets `CODEX_HOME` to `$ICODEX_ROOT/.codex-isolated`.
3. `ensure_launcher_binary_permission` adds or corrects the read-only binary
   permission in live `config.toml`.
4. Existing Superpowers marketplace wiring runs.
5. Codex binary install/check runs.
6. `launch_codex` execs `$ICODEX_BIN`.

## Tests
- `tests/test_plugin.sh` verifies the live config gets the read-only binary
  entry, remains idempotent, and preserves existing Superpowers source rewriting.
- `tests/test_smoke.sh` verifies the default launch path calls the new permission
  wiring and that install/update paths remain binary-only.
- `bash -n` validates changed shell files.

# Intent: icodex external workspace sandbox access

**Date:** 2026-06-28
**Status:** approved

## Objective
`icodex` must work reliably as a shared wrapper for external workspaces, such as
`personal-ai-wiki`, even when the wrapper repository and its isolated Codex
binary live outside the active workspace root.

## Desired Outcomes
- Running Codex through `icodex` from an external workspace no longer fails with
  `bwrap: execvp .../.codex-isolated/bin/codex: No such file or directory`.
- Normal tool commands inside Codex, such as `git status`, `pwd`, and workspace
  file reads, can start.
- Access to `.codex-isolated/bin/codex` is granted as read-only, without write
  access to `.codex-isolated/bin`.

## Health Metrics
- The sandbox does not gain write access to `icodex/.codex-isolated/bin` or the
  whole `icodex` repository.
- Existing `dev-safe` deny rules for secrets, environment files, and tokens are
  not weakened.
- `icodex --install`, `--update`, and `--version` remain binary-only paths and do
  not require external workspace context.
- Existing Superpowers plugin wiring remains idempotent.

## Strategic Context
- Interacts with: `icodex.sh`, launcher/config wiring, Codex managed filesystem
  permissions, Bubblewrap sandbox startup, external project workspaces.
- Priority trade-off: trust.

## Constraints
### Steering
- Prefer a narrowly scoped config change over broader sandbox access.
- Keep the fix small, testable, and aligned with existing launch-time config
  rewriting patterns.

### Hard
- Do not use `--add-dir` as the primary fix.
- Do not copy or install the Codex binary into each target workspace.
- Do not move `CODEX_HOME` back to global `~/.codex`.
- Do not read auth, token, credential, secret, or denied environment files.
- Do not weaken `dev-safe` deny rules.

## Autonomy Zones
- Full autonomy: bash helpers, tests, launcher/config wiring, and docs/spec
  updates.
- Guarded: changing live `.codex-isolated/config.toml`, only through an
  idempotent and scoped permission entry.
- Proposal-first: changing strategy if Codex CLI does not support a literal
  read-only path entry in managed filesystem permissions.
- No autonomy: widening access to the whole `icodex` repository or disabling the
  sandbox.

> These zones OVERRIDE subagent-driven-development's "continuous execution,
> don't pause" default. Any task touching proposal-first / no-go decisions is
> marked HUMAN CHECKPOINT in the plan.

## Stop Rules
- Halt if the only working option requires broad write access or disabling the
  sandbox.
- Escalate if Codex managed permissions cannot represent read-only access to the
  launcher binary path.
- Done when: a test first reproduces the missing read permission for
  `$ICODEX_BIN`, then passes after the fix; existing shell tests pass; live config
  contains a read-only entry for `$ICODEX_BIN`; and the external-workspace launch
  path no longer shows the `bwrap execvp` failure as far as local verification can
  exercise it.

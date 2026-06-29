# icodex Run Profiles (ICODEX_MODE) + `.git` Writability — Design

**Date:** 2026-06-29
**Status:** approved (brainstorming)
**Branch:** `dev-icodex-run-profiles` (off `main` @ 2054663)

## Goal

icodex must let the user pick a complete run profile — not just the filesystem
sandbox — with two headline modes: **run-with-prompts** and **full no-stop**. A
single `ICODEX_MODE` preset sets `sandbox_mode`, `approval_policy`, and the managed
permission profile together. In addition, codex must be able to write `.git` (create
branches, commit) in every writable mode, which it currently cannot.

## Problem

Two distinct gaps, both rooted in the same place — icodex manages only `sandbox_mode`:

1. **approval / permissions are unmanaged.** `apply_sandbox_mode` (`lib/config/sandbox.sh`)
   writes only `sandbox_mode`; `approval_policy` and `default_permissions` are baked
   into the template `.codex-isolated/config.toml` (`approval_policy = "on-request"`,
   `default_permissions = "ssh-on-request"`) and copied once into each per-project home.
   So setting `ICODEX_SANDBOX=danger-full-access` still leaves codex asking for approval
   and pinned to the SSH-prompting profile — there is no way to get "full, no-stop".

2. **`.git` is read-only.** Codex always re-mounts protected paths (`.git`, `.codex`,
   `.agents`, resolved `gitdir:`) read-only inside writable roots whenever a managed
   permission profile is active — independent of `sandbox_mode`, even at
   `danger-full-access`. The agent then fails git writes with
   `cannot lock ref ... .git/...lock: Read-only file system`. The fix is to either grant
   `.git/` write explicitly in the profile, or disable the managed layer entirely.

References: [Codex Permissions](https://developers.openai.com/codex/permissions),
[Config Reference](https://developers.openai.com/codex/config-reference),
[Issue #15505 `.git` read-only](https://github.com/openai/codex/issues/15505),
[Permission profiles & the two-layer model](https://codex.danielvaughan.com/2026/05/08/codex-cli-permission-profiles-sandbox-modes-security-layers/).

## Background: codex's two-layer model

Codex enforces two layers, the stricter wins:

- **Sandbox layer** — `sandbox_mode` ∈ `read-only | workspace-write | danger-full-access`
  (the OS sandbox over model-run commands).
- **Managed-permission layer** — `default_permissions = "<profile>"` selects a named
  `[permissions.<name>]` profile with filesystem/network rules. When active, protected
  paths (`.git`, …) are forced read-only unless re-granted, e.g.
  `".git/" = "write"` under `[permissions.<name>.filesystem.":workspace_roots"]`.
  When `default_permissions` is absent, the managed layer is off and only the sandbox
  layer applies — so `danger-full-access` + `approval_policy = "never"` with no managed
  profile is the documented equivalent of `--dangerously-bypass-approvals-and-sandbox`.

`approval_policy` ∈ `untrusted | on-failure | on-request | never` governs when codex
asks the human before running a command (orthogonal to both layers above).

## Decisions

Resolved during brainstorming:

- **Control model:** one `ICODEX_MODE` preset bundles the three settings; granular env
  keys override individual fields. No new CLI flags.
- **Presets (4):**

  | `ICODEX_MODE` | `sandbox_mode`     | `approval_policy` | `default_permissions` | `.git` writable |
  |---------------|--------------------|-------------------|-----------------------|-----------------|
  | `ro`          | read-only          | on-request        | dev-safe              | no (sandbox blocks all writes) |
  | `safe`        | workspace-write    | on-request        | dev-safe              | yes (profile grants `.git/`) |
  | `full-ask`    | danger-full-access | on-request        | ssh-on-request        | yes (profile grants `.git/`) |
  | `full-auto`   | danger-full-access | never             | *(removed)*           | yes (managed layer off) |

- **Default mode:** `full-ask` — reproduces the literal shipped template
  (danger-full-access + on-request + ssh-on-request), now additionally `.git`-writable.
  Note this differs from today's *resolved* default: `resolve_sandbox_mode` currently
  defaults the sandbox field to `workspace-write` when `ICODEX_SANDBOX` is unset, which
  overwrites the template's `danger-full-access`. Under `full-ask` the unset-env default
  becomes `danger-full-access`, matching the template literal.
- **`full-auto` = full no-stop:** removes `default_permissions` so the managed layer is
  off → no prompts at all (including SSH), `.git` writable. Equivalent to
  `--dangerously-bypass-approvals-and-sandbox`. Emits a `log_warn`.
- **`.git` fix:** add `".git/" = "write"` under `:workspace_roots` to the `dev-safe`
  and `ssh-on-request` profiles. Applied **idempotently every run** so existing
  per-project homes (copied from the old template) migrate too — not just a fresh template.
- **Precedence:**
  `defaults (full-ask) < ICODEX_MODE < granular (ICODEX_SANDBOX | ICODEX_APPROVAL | ICODEX_PERMISSIONS)`.
  No CLI-flag layer is added; the existing `--full-access` flag keeps forcing
  `sandbox_mode = danger-full-access` only (sandbox field), unchanged.
- **Granular values:**
  - `ICODEX_SANDBOX` ∈ `read-only | workspace-write | danger-full-access` (existing).
  - `ICODEX_APPROVAL` ∈ `untrusted | on-failure | on-request | never`.
  - `ICODEX_PERMISSIONS` ∈ `dev-safe | ssh-on-request | none` (`none` removes the
    managed layer, like `full-auto`).
- **Validation:** an invalid `ICODEX_MODE` or any invalid granular value → `log_error`
  + non-zero return, mirroring today's `resolve_sandbox_mode`.

## Architecture

Changes are localized to `lib/config/sandbox.sh` (generalized into the run-mode
resolver/applier), `lib/config/permissions.sh` (the `.git` grant), one line in
`icodex.sh`, the template `config.toml`, and tests. CODEX_HOME isolation and proxy
logic are untouched.

Units (each one purpose, independently testable):

- **`resolve_mode`** — pure resolver. Echoes the effective triple
  `sandbox approval permissions` (space-separated). Starts from the `ICODEX_MODE`
  preset (default `full-ask`), then overrides each field from `ICODEX_SANDBOX` /
  `ICODEX_APPROVAL` / `ICODEX_PERMISSIONS` when set. The existing `--full-access`
  (`ICODEX_FULL_ACCESS`) still forces the sandbox field to `danger-full-access`.
  `permissions` may be the sentinel `none`. Invalid preset/value → `log_error` + return 1.
- **`_upsert_toml_toplevel <config> <key> <value>`** — unchanged (existing idempotent
  top-level upsert).
- **`_remove_toml_toplevel <config> <key>`** — new sibling. Removes a top-level
  `key = ...` line (before the first `[section]`) idempotently; byte-identical when
  absent. Used to drop `default_permissions` for `none`/`full-auto`.
- **`apply_mode`** — orchestrator (replaces `apply_sandbox_mode` on the run path):
  1. `read sandbox approval permissions <<< "$(resolve_mode)"` (return 1 on failure).
  2. `_upsert_toml_toplevel "$config" sandbox_mode "$sandbox"`.
  3. `_upsert_toml_toplevel "$config" approval_policy "$approval"`.
  4. If `permissions == none`: `_remove_toml_toplevel "$config" default_permissions`;
     else `_upsert_toml_toplevel "$config" default_permissions "$permissions"` and
     `ensure_git_writable "$config" "$permissions"`.
  5. `log_warn` when `sandbox == danger-full-access` (full filesystem access) and an
     additional `log_warn` when `permissions == none` (no managed permissions / no prompts).
- **`ensure_git_writable <config> <profile>`** (in `permissions.sh`) — idempotently
  upserts `".git/" = "write"` under `[permissions.<profile>.filesystem.":workspace_roots"]`,
  reusing the existing awk-upsert approach (`_ensure_filesystem_permission_entry`
  generalized to accept the section + key, or a thin dedicated function). Byte-identical
  when the rule is already present.

Run-path change in `icodex.sh`: `apply_sandbox_mode || exit 1` becomes
`apply_mode || exit 1`. Order relative to `ensure_project_trust` /
`ensure_launcher_binary_permission` is unchanged.

Template `.codex-isolated/config.toml`: keep `approval_policy` and `default_permissions`
(the `full-ask` default); add `".git/" = "write"` to the `:workspace_roots` table of
both `dev-safe` and `ssh-on-request`; refresh the "Launch safety modes" / "Permission
profiles" comments to describe `ICODEX_MODE`.

## Error handling

- Invalid `ICODEX_MODE` / granular value → `log_error` + return 1; `icodex.sh` exits 1
  before launching codex (no partial config write that changes behavior silently).
- `_remove_toml_toplevel` on a file lacking the key → no-op, byte-identical (safe under
  `set -euo pipefail`).
- `ensure_git_writable` when the named profile section is absent → creates the
  `:workspace_roots` table (same fallback the existing awk upsert already has).
- Re-running any mode is idempotent: all writes are upserts/removes that converge.

## Testing (`tests/`, new `test_mode.sh` + extend `test_install.sh`)

- `resolve_mode`: each preset → exact triple; default (unset) → `full-ask`;
  per-field overrides (`ICODEX_APPROVAL=never` on `safe` → `... never dev-safe`);
  `ICODEX_PERMISSIONS=none` → sentinel; `ICODEX_FULL_ACCESS=1` forces sandbox;
  invalid `ICODEX_MODE` and invalid each-field → return 1 + `log_error`.
- `apply_mode`: seed a config; assert `sandbox_mode` / `approval_policy` lines written;
  `full-auto` removes `default_permissions`; non-`none` modes write it; warnings emitted
  for danger / none; second run is byte-identical (idempotent).
- `_remove_toml_toplevel`: removes present key; no-op when absent; leaves `[sections]`
  intact.
- `ensure_git_writable`: adds `".git/" = "write"` under the right profile's
  `:workspace_roots`; idempotent on re-run; works for both `dev-safe` and
  `ssh-on-request`.

## Documentation

- `.codex_config.example`: new `ICODEX_MODE` block documenting the 4 presets and the
  default; annotate `ICODEX_SANDBOX` as a granular override and add commented
  `ICODEX_APPROVAL` / `ICODEX_PERMISSIONS`.
- `docs/wiki/config.md`: replace the "Sandbox mode" section with a "Run mode" section
  (presets, precedence, `.git` writability, two-layer model); re-run iwiki ingest + lint.
- `README.md` and `print_help` (`lib/command/args.sh`): mention `ICODEX_MODE`.

## Global constraints

- `#!/usr/bin/env bash`; `set -euo pipefail` in `lib/`, `set -uo pipefail` in tests.
- Two-space indent; functions `lowercase_with_underscores`; env vars `ICODEX_` prefix.
- Dependency-light: bash + awk + existing helpers; no new tools.
- CODEX_HOME isolation, proxy, binary install, and trust logic untouched.

## Out of scope (YAGNI)

- New CLI flags (`--mode`, `--full-auto`) — `.codex_config` only.
- A custom no-prompt permission profile that still guards secrets — `full-auto` drops
  the managed layer wholesale (documented, warned).
- Per-project `ICODEX_MODE` overrides beyond the single `.codex_config`.
- Granting write to other protected paths (`.codex`, `.agents`) — only `.git`.
- Migrating/rewriting historical per-project homes beyond the idempotent per-run upsert.

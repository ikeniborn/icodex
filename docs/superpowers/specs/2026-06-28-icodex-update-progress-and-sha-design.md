# icodex Update Progress and SHA Handling Design

> Date: 2026-06-28
> Status: Approved
> Scope: Make `icodex --update` visible while it runs and fix false SHA mismatch failures.

## Problem

`icodex --update` can appear stuck because the network steps are quiet. It can
also fail with a false tamper-guard error: update resolves a new latest Codex
release, downloads it, then compares the new tarball SHA against the previous
lockfile SHA.

For update, a different SHA is expected. The new SHA should be recorded in
`.codex-lockfile.json` after the downloaded archive is installed.

## Design

- Keep normal launch/install behavior quiet.
- Make only `install_ensure --update` print progress stage messages.
- Use curl's progress bar for the update tarball download.
- Keep the pinned SHA tamper guard for normal install.
- Skip the old pinned SHA comparison during update, then write the new SHA to
  the lockfile.

## Verification

- Add a test where the lockfile contains an old SHA, `--update` resolves a new
  version, and the update succeeds while rewriting the lockfile SHA.
- Add a test that `--update` emits key progress stage messages.
- Preserve the existing normal-install SHA mismatch test.

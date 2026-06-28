# Launch

## Overview

This page covers the thin launch- and install-time modules.

`lib/proxy/proxy.sh` persists and applies the proxy, `lib/symlink/symlink.sh`
creates the user-space `icodex` symlink, and `lib/launcher/launch.sh` performs the
final transparent exec of the codex binary. See [[architecture#Default run path]]
and [[command#Passthrough collection]].

## Proxy persist and apply

`proxy_save` upserts `ICODEX_PROXY`; `proxy_clear` removes the config file; `proxy_apply` exports the vars.

Persistence goes through [[config#Config upsert]]. `proxy_apply` exports the
standard `HTTPS_PROXY`/`HTTP_PROXY` (upper and lower case) from `ICODEX_PROXY`,
and `NO_PROXY` from the `ICODEX_NO_PROXY` host bypass list, which Codex's Rust
reqwest stack honors. `--no-proxy` skips application for one run.

## Symlink creation

`install_symlink` creates an `icodex` symlink in `ICODEX_LINK_DIR`.

The default is `~/.local/bin`, with leading `~/` expanded since config values are
not sourced, pointing at `icodex.sh`. An existing icodex symlink is repaired if
stale; a real non-symlink file is never clobbered. It warns when the target dir
is not on PATH.

## Final exec

`launch_codex` is the last step of the run path.

It checks that `ICODEX_BIN` is executable — erroring with an install hint if not —
then `exec`s the binary with all forwarded arguments, replacing the wrapper
process. The passthrough array from [[command#Passthrough collection]] is expanded
here verbatim.

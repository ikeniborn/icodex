# Launch

## Overview

This page covers the thin launch- and install-time modules.

`lib/proxy/proxy.sh` persists and applies the proxy, `lib/symlink/symlink.sh`
creates the user-space `icodex` symlink, and `lib/launcher/launch.sh` performs the
final transparent exec of the codex binary. See [[architecture#Default run path]]
and [[command#Passthrough collection]].

## Proxy persist and apply

`proxy_save` upserts `ICODEX_PROXY`; `proxy_clear` removes the config file; `proxy_apply` exports the vars. `proxy_ensure` is the run-path entry point that probes the proxy before applying it.

Persistence goes through [[config#Config upsert]]. `proxy_apply` exports the
standard `HTTPS_PROXY`/`HTTP_PROXY` (upper and lower case) from `ICODEX_PROXY`,
and `NO_PROXY` from the `ICODEX_NO_PROXY` host bypass list, which Codex's Rust
reqwest stack honors. `--no-proxy` skips application for one run.

## Reachability probe (`proxy_ensure`)

`proxy_ensure` is called on every run before codex is exec'd. If `ICODEX_PROXY` is
unset, it returns immediately (no-op). Otherwise:

1. `_proxy_host_port` strips scheme, userinfo, and path from the URL and returns
   `host port`; the port defaults by scheme (https→443, socks\*→1080, else 80).
2. `proxy_reachable` opens a `/dev/tcp` connection (via `timeout`, 3 s) to that
   host:port. Exit 0 means reachable.
3. **Reachable** → `proxy_apply` is called; the run continues normally.
4. **Unreachable** → a warning is emitted, then:
   - **Interactive TTY**: the user is prompted "Continue without proxy? [Y/n]".
     Answering `n`/`N` triggers `exit 1`; any other reply (Enter, `y`/`Y`, EOF)
     continues without the proxy.
   - **No TTY** (CI, script): warns and continues without the proxy — no prompt,
     no exit.

`_proxy_unreachable_action <tty> <reply>` encodes that decision and returns
`"continue"` or `"exit"`, making the logic unit-testable in isolation.

When `--no-proxy` is active, `proxy_ensure` is not called at all — the guard is at
the call site in `icodex.sh`, so the probe is skipped entirely.

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

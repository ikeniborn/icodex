# icodex Proxy Reachability — Design

**Date:** 2026-06-29
**Status:** approved (brainstorming)
**Branch:** `dev-icodex-proxy-reachability` (off `main` @ 5898a52)

## Goal

When `ICODEX_PROXY` is set but the proxy is unreachable, icodex must not let codex
hang on the network. It probes the proxy before launch and, if unreachable, either
asks the user (interactive) or continues without the proxy (non-interactive) — never
silently hanging.

## Problem

`proxy_apply` (`lib/proxy/proxy.sh`) only exports the `*_PROXY` / `NO_PROXY`
environment variables when `ICODEX_PROXY` is set. It performs no reachability check.
If the proxy host is down or misconfigured, codex inherits the proxy vars and stalls
on its first network call with no actionable feedback. The run path calls it as
`(( ICODEX_DISABLE_PROXY )) || proxy_apply`.

## Decisions

Resolved during brainstorming:

- **Detection method:** TCP connect to the proxy's own `host:port`, using bash
  `/dev/tcp` wrapped in `timeout` — dependency-free (no `curl`/`nc`). It verifies the
  proxy port is reachable, not that it is a fully working proxy; that is the common
  failure mode and keeps the probe fast and dependency-light.
- **Probe timeout:** 3 seconds.
- **Unreachable + interactive (stdin is a TTY):** prompt
  `Proxy <url> unreachable. Continue without proxy? [Y/n]`. `n`/`N` → error + exit 1.
  Empty (Enter), `y`/`Y`, or EOF → continue **without** applying the proxy.
- **Unreachable + non-interactive (no TTY):** print a warning and continue without
  the proxy (fail-open). No prompt.
- **Reachable:** apply the proxy exactly as today.
- **`ICODEX_PROXY` unset, or `--no-proxy`:** unchanged — no probe, no-op.

Behavior matrix:

| `ICODEX_PROXY` | Reachable | TTY | Reply | Result |
|----------------|-----------|-----|-------|--------|
| unset | — | — | — | no-op (no proxy) |
| set | yes | — | — | `proxy_apply` (proxy used) |
| set | no | yes | `n`/`N` | `log_error` + `exit 1` |
| set | no | yes | empty / `y` / EOF | warn + continue, no proxy |
| set | no | no | — | warn + continue, no proxy |

## Architecture

All changes are in `lib/proxy/proxy.sh`, plus one line in `icodex.sh` and tests in
`tests/test_proxy.sh`. `approval_policy`, sandbox, and isolation logic are untouched.

Units (each independently testable, one clear purpose):

- **`_proxy_host_port <url>`** — pure parser. Echoes `host port`. Strips the scheme
  (`http://`, `https://`, `socks5://`, …) and any `user:pass@` userinfo, drops a
  trailing `/path`, and splits `host:port`. Default port by scheme: `http` → 80,
  `https` → 443, `socks5`/`socks5h`/`socks4` → 1080, otherwise 80. No side effects.
- **`proxy_reachable <host> <port> [timeout=3]`** — TCP probe. Returns 0 if a
  connection opens within the timeout, else 1. Implemented as
  `timeout "$t" bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null`. No output.
- **`_proxy_unreachable_action <tty> <reply>`** — pure decision. Given whether stdin
  is a TTY (`1`/`0`) and the captured reply, echoes `continue` or `exit`. Encodes the
  prompt-default rule. Unit-testable without any terminal.
- **`proxy_ensure`** — thin orchestrator (replaces the direct `proxy_apply` call on
  the run path):
  1. `[[ -n "${ICODEX_PROXY:-}" ]]` else return 0.
  2. Parse `host port` via `_proxy_host_port`.
  3. `proxy_reachable "$host" "$port"` → on success, `proxy_apply`; return.
  4. On failure: `log_warn` that the proxy is unreachable. If `[[ -t 0 ]]`, prompt and
     `read -r reply`; else `reply=""` and treat as non-TTY. Feed (`tty`, `reply`) to
     `_proxy_unreachable_action`. `exit` → `log_error` + `exit 1`; `continue` →
     return 0 without `proxy_apply` (codex launches with no proxy vars).
- **`proxy_apply`** — unchanged (pure exporter).

Run-path change in `icodex.sh`: `(( ICODEX_DISABLE_PROXY )) || proxy_apply` becomes
`(( ICODEX_DISABLE_PROXY )) || proxy_ensure`.

Constant: `ICODEX_PROXY_PROBE_TIMEOUT=3` (local default in `proxy_reachable`'s signature).

## Error handling

- A malformed `ICODEX_PROXY` that yields an empty host → treat as unreachable (the
  probe fails), then follow the unreachable branch. No crash under `set -euo pipefail`.
- `proxy_reachable` swallows connection errors (`2>/dev/null`) and maps them to a
  non-zero return; `timeout` bounds a hung connect.
- `read -r` returning non-zero (EOF / closed stdin) is treated as the default
  (`continue`) — never an unhandled failure under `set -e`.

## Testing (`tests/test_proxy.sh`, extend)

- `_proxy_host_port`: `http://h:8080` → `h 8080`; `http://h` → `h 80`;
  `https://h` → `h 443`; `socks5://h` → `h 1080`; `http://u:p@h:3128/x` → `h 3128`;
  bare `h:9` → `h 9`.
- `proxy_reachable` against a known-closed port (e.g. `127.0.0.1` high port) → returns 1
  within the timeout.
- `_proxy_unreachable_action`: `(tty=1, reply="n")` → `exit`; `(1,"N")` → `exit`;
  `(1,"")` → `continue`; `(1,"y")` → `continue`; `(0,"")` → `continue`.
- `proxy_apply` still exports the vars (existing assertions unchanged).

The interactive prompt and TTY detection inside `proxy_ensure` are a thin shell over
the pure `_proxy_unreachable_action`; the decision logic is fully covered without a
live terminal. The reachable→`proxy_apply` path is covered by the existing exporter
tests plus the `proxy_reachable` probe test.

## Global constraints

- `#!/usr/bin/env bash`; `set -euo pipefail` in `lib/`, `set -uo pipefail` in tests.
- Dependency-light: only bash (`/dev/tcp`), `timeout`, awk, existing helpers. No new tools.
- Two-space indent; functions `lowercase_with_underscores`; env vars `ICODEX_` prefix.
- `proxy_apply` semantics unchanged; `approval_policy` / sandbox / isolation untouched.

## Out of scope (YAGNI)

- End-to-end proxy validation (an actual request through the proxy to a target).
- Retries / backoff.
- Configurable probe timeout via env or flag.
- Caching the probe result across runs.
- Probing per `NO_PROXY` bypass host.

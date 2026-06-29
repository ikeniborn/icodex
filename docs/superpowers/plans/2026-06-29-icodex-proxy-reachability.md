# icodex Proxy Reachability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Probe `ICODEX_PROXY` before launching codex; if the proxy is unreachable, prompt to continue-without-proxy or exit (interactive) or fail-open with a warning (non-interactive) — never let codex hang on a dead proxy.

**Architecture:** All new logic lives in `lib/proxy/proxy.sh` as small, independently testable functions (`_proxy_host_port` parser, `proxy_reachable` TCP probe, `_proxy_unreachable_action` pure decision, `proxy_ensure` orchestrator). `proxy_apply` is unchanged. The run path in `icodex.sh` calls `proxy_ensure` instead of `proxy_apply`.

**Tech Stack:** Bash (`set -euo pipefail`), `timeout`, bash `/dev/tcp`. No new dependencies. Standalone bash tests sourcing `tests/helpers.sh`.

## Global Constraints

- Bash with `#!/usr/bin/env bash`; `set -euo pipefail` in `lib/`, `set -uo pipefail` in tests. (verbatim from spec / AGENTS.md)
- Dependency-light: only bash (`/dev/tcp`), `timeout`, awk, and existing helpers. No new tools.
- Two-space indent inside functions; functions `lowercase_with_underscores`; wrapper env vars use the `ICODEX_` prefix.
- `proxy_apply` semantics are unchanged; `approval_policy`, sandbox, and isolation logic are NOT touched.
- Probe timeout default: `3` seconds.
- Unreachable behavior is fail-open: interactive prompt defaults to continue (Enter / `y` / EOF); only `n`/`N` exits. No TTY → continue with a warning.
- Run the full suite with: `for t in tests/test_*.sh; do bash "$t" || exit 1; done`.

---

### Task 1: Proxy URL parser

**Files:**
- Modify: `lib/proxy/proxy.sh` (append `_proxy_host_port` after `proxy_apply`, which ends at line 20)
- Test: `tests/test_proxy.sh` (extend)

**Interfaces:**
- Produces: `_proxy_host_port <url>` → echoes `host port` (single space). Strips the scheme and any `user:pass@` userinfo, drops a trailing `/path`, splits `host:port`. Default port by scheme: `https`→443, `socks5`/`socks5h`/`socks4`→1080, else 80. A URL with no host yields an empty host field.

- [ ] **Step 1: Write the failing test** — in `tests/test_proxy.sh`, insert this block immediately BEFORE the `rm -rf "$tmp"` line near the end:

```bash
# --- _proxy_host_port: parse host+port from a proxy URL (Task 1) ---
assert_eq "host:port explicit"      "h 8080" "$(_proxy_host_port http://h:8080)"
assert_eq "http default port"       "h 80"   "$(_proxy_host_port http://h)"
assert_eq "https default port"      "h 443"  "$(_proxy_host_port https://h)"
assert_eq "socks5 default port"     "h 1080" "$(_proxy_host_port socks5://h)"
assert_eq "userinfo and path strip" "h 3128" "$(_proxy_host_port http://MASKING@h:3128/x)"
assert_eq "schemeless host:port"    "h 9"    "$(_proxy_host_port h:9)"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_proxy.sh`
Expected: FAIL — `_proxy_host_port: command not found` (function not defined).

- [ ] **Step 3: Append `_proxy_host_port` to `lib/proxy/proxy.sh`** (after the closing `}` of `proxy_apply`):

```bash

# Echo "host port" parsed from a proxy URL. Strips scheme, userinfo, and path;
# defaults the port by scheme (https=443, socks*=1080, otherwise 80).
_proxy_host_port() { # <url>
  local url="$1" scheme rest host port
  if [[ "$url" == *"://"* ]]; then
    scheme="${url%%://*}"
    rest="${url#*://}"
  else
    scheme=""
    rest="$url"
  fi
  rest="${rest##*@}"      # strip user:pass@ userinfo
  rest="${rest%%/*}"      # strip /path
  host="${rest%%:*}"
  if [[ "$rest" == *:* ]]; then
    port="${rest##*:}"
  else
    case "$scheme" in
      https) port=443 ;;
      socks5|socks5h|socks4) port=1080 ;;
      *) port=80 ;;
    esac
  fi
  printf '%s %s\n' "$host" "$port"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_proxy.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/proxy/proxy.sh tests/test_proxy.sh
git commit -m "feat(proxy): parse host and port from the proxy URL"
```

---

### Task 2: Reachability probe and unreachable-decision

**Files:**
- Modify: `lib/proxy/proxy.sh` (append `proxy_reachable` and `_proxy_unreachable_action`)
- Test: `tests/test_proxy.sh` (extend)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces:
  - `proxy_reachable <host> <port> [timeout=3]` → returns 0 if a TCP connection opens within the timeout, else non-zero (1). No stdout.
  - `_proxy_unreachable_action <tty:0|1> <reply>` → echoes `continue` or `exit`. `tty=1` AND reply matching `^[Nn]$` → `exit`; everything else (including no TTY) → `continue`.

- [ ] **Step 1: Write the failing test** — in `tests/test_proxy.sh`, insert this block immediately BEFORE the `rm -rf "$tmp"` line:

```bash
# --- proxy_reachable: closed port is unreachable (Task 2) ---
assert_exit "closed port unreachable" 1 proxy_reachable 127.0.0.1 65000 2

# --- _proxy_unreachable_action: decision logic (Task 2) ---
assert_eq "tty + n -> exit"        "exit"     "$(_proxy_unreachable_action 1 n)"
assert_eq "tty + N -> exit"        "exit"     "$(_proxy_unreachable_action 1 N)"
assert_eq "tty + empty -> continue" "continue" "$(_proxy_unreachable_action 1 '')"
assert_eq "tty + y -> continue"     "continue" "$(_proxy_unreachable_action 1 y)"
assert_eq "no tty -> continue"      "continue" "$(_proxy_unreachable_action 0 '')"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_proxy.sh`
Expected: FAIL — `proxy_reachable` / `_proxy_unreachable_action` not defined.

- [ ] **Step 3: Append both functions to `lib/proxy/proxy.sh`** (after `_proxy_host_port`):

```bash

# Return 0 if a TCP connection to host:port opens within <timeout> seconds, else 1.
# host/port are passed as positional args to the inner shell (no path injection).
proxy_reachable() { # <host> <port> [timeout=3]
  local host="$1" port="$2" t="${3:-3}"
  timeout "$t" bash -c 'exec 3<>/dev/tcp/"$0"/"$1"' "$host" "$port" 2>/dev/null
}

# Echo "continue" or "exit" for the proxy-unreachable case. Only an explicit n/N
# at an interactive prompt exits; an empty reply, y/Y, EOF, or no TTY continues.
_proxy_unreachable_action() { # <tty:0|1> <reply>
  local tty="$1" reply="$2"
  if [[ "$tty" == 1 && "$reply" =~ ^[Nn]$ ]]; then
    printf 'exit\n'
  else
    printf 'continue\n'
  fi
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_proxy.sh`
Expected: PASS. (The `proxy_reachable` probe to `127.0.0.1:65000` is refused immediately and returns 1 well within the 2s timeout.)

- [ ] **Step 5: Commit**

```bash
git add lib/proxy/proxy.sh tests/test_proxy.sh
git commit -m "feat(proxy): TCP reachability probe and unreachable-decision helper"
```

---

### Task 3: proxy_ensure orchestrator and run-path wiring

**Files:**
- Modify: `lib/proxy/proxy.sh` (append `proxy_ensure`)
- Modify: `icodex.sh:61` (`proxy_apply` → `proxy_ensure` on the run path)
- Test: `tests/test_proxy.sh` (extend), `tests/test_smoke.sh` (update the launch-order awk)

**Interfaces:**
- Consumes: `_proxy_host_port`, `proxy_reachable`, `_proxy_unreachable_action` (Tasks 1-2), `proxy_apply` (existing), `log_warn`/`log_error` (logging.sh).
- Produces: `proxy_ensure` → on the run path, applies the proxy when reachable; on unreachable, prompts (TTY) or warns-and-skips (no TTY); `exit 1` on an interactive `n`. No-op when `ICODEX_PROXY` is unset.

- [ ] **Step 1: Write the failing test** — in `tests/test_proxy.sh`, insert this block immediately BEFORE the `rm -rf "$tmp"` line. It stubs `proxy_reachable` to exercise the reachable branch, then re-sources `proxy.sh` to restore the real function:

```bash
# --- proxy_ensure: orchestration (Task 3) ---
# no proxy set -> no-op (nothing exported)
unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy ICODEX_PROXY
proxy_ensure </dev/null
assert_eq "no proxy -> noop" "" "${HTTPS_PROXY:-}"

# unreachable + no TTY (stdin from /dev/null) -> continue, proxy NOT applied
unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy
ICODEX_PROXY="http://127.0.0.1:65000" proxy_ensure </dev/null
assert_eq "unreachable continues (exit 0)" "0" "$?"
assert_eq "unreachable -> proxy not applied" "" "${HTTPS_PROXY:-}"

# reachable (stub) -> proxy applied
unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy
proxy_reachable() { return 0; }                # stub: force reachable
ICODEX_PROXY="http://p:8080" proxy_ensure </dev/null
assert_eq "reachable -> proxy applied" "http://p:8080" "${HTTPS_PROXY:-}"
source "$ROOT/lib/proxy/proxy.sh"              # restore the real proxy_reachable
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_proxy.sh`
Expected: FAIL — `proxy_ensure: command not found`.

- [ ] **Step 3: Append `proxy_ensure` to `lib/proxy/proxy.sh`** (after `_proxy_unreachable_action`):

```bash

# Probe ICODEX_PROXY before launch; apply it if reachable, else prompt (TTY) or
# warn-and-skip (no TTY). Never lets codex hang on a dead proxy. exit 1 only when
# an interactive user answers n/N.
proxy_ensure() {
  [[ -n "${ICODEX_PROXY:-}" ]] || return 0
  local host port
  read -r host port < <(_proxy_host_port "$ICODEX_PROXY")
  if proxy_reachable "$host" "$port"; then
    proxy_apply
    return 0
  fi
  log_warn "proxy $ICODEX_PROXY unreachable"
  local tty=0 reply=""
  if [[ -t 0 ]]; then
    tty=1
    printf '[icodex] Continue without proxy? [Y/n] ' >&2
    read -r reply || reply=""
  fi
  if [[ "$(_proxy_unreachable_action "$tty" "$reply")" == exit ]]; then
    log_error "aborted: proxy $ICODEX_PROXY unreachable"
    exit 1
  fi
  log_warn "continuing without proxy"
  return 0
}
```

- [ ] **Step 4: Wire the run path** — in `icodex.sh`, change the proxy line (currently line 61):

```bash
  (( ICODEX_DISABLE_PROXY )) || proxy_ensure
```

(only `proxy_apply` → `proxy_ensure`; leave the `(( ICODEX_DISABLE_PROXY )) ||` guard intact.)

- [ ] **Step 5: Update the smoke launch-order awk** — in `tests/test_smoke.sh`, the proxy step (currently line 60) matches `proxy_apply`; change that one token to `proxy_ensure`:

```bash
  inblock && /^[[:space:]]*\(\([[:space:]]*ICODEX_DISABLE_PROXY[[:space:]]*\)\)[[:space:]]*\|\|[[:space:]]*proxy_ensure[[:space:]]*$/ && step == 7 { step = 8; next }
```

- [ ] **Step 6: Run the proxy + smoke tests to verify they pass**

Run: `bash tests/test_proxy.sh && bash tests/test_smoke.sh`
Expected: PASS for both. (The unreachable-non-TTY test probes `127.0.0.1:65000` — refused immediately; the smoke awk now matches the rewired `proxy_ensure` line.)

- [ ] **Step 7: Commit**

```bash
git add lib/proxy/proxy.sh icodex.sh tests/test_proxy.sh tests/test_smoke.sh
git commit -m "feat(proxy): probe proxy reachability on the run path with prompt or fail-open"
```

---

### Task 4: Full suite + docs

**Files:**
- Verify: all `tests/test_*.sh`
- Modify (docs): regenerate `docs/wiki/launch.md` (proxy section) via iwiki; refresh README proxy note.

**Interfaces:** none (verification + docs).

- [ ] **Step 1: Run the whole suite**

Run: `for t in tests/test_*.sh; do echo "== $t =="; bash "$t" || { echo "FAILED: $t"; break; }; done`
Expected: every file ends `PASS=… FAIL=0`.

- [ ] **Step 2: Regenerate the affected wiki page** — per the repo's iwiki workflow:

Run: `iwiki:iwiki-ingest lib/proxy/proxy.sh`, then `/iwiki-lint`.
Expected: `launch.md` (Proxy persist and apply) documents the reachability probe + prompt/fail-open behavior; lint reports no broken `[[refs]]`, no orphans, no stale pages.

- [ ] **Step 3: Add a README proxy note** — in `README.md`, append to the `ICODEX_NO_PROXY`/`--no-proxy` paragraph (the one after the configuration-variables table):

```markdown
If `ICODEX_PROXY` is set but the proxy is unreachable, icodex warns and — when run
interactively — asks whether to continue without the proxy (default yes) or exit;
without a TTY it continues without the proxy. Use `--no-proxy` to skip the proxy (and
the probe) entirely.
```

- [ ] **Step 4: Commit docs**

```bash
git add docs/wiki/ README.md
git commit -m "docs: proxy reachability probe behavior"
```

---

## Self-Review

**Spec coverage:**
- Detection (bash `/dev/tcp` + `timeout`, 3s) → Task 2 `proxy_reachable`. ✓
- URL parse with scheme/userinfo/path strip + default ports → Task 1 `_proxy_host_port`. ✓
- Unreachable + TTY prompt (`n`→exit 1; Enter/`y`/EOF→continue) → Task 2 `_proxy_unreachable_action` + Task 3 `proxy_ensure`. ✓
- Unreachable + no TTY → warn + continue → Task 3 `proxy_ensure` (`tty=0`). ✓
- Reachable → `proxy_apply` unchanged → Task 3 + existing exporter tests. ✓
- `ICODEX_PROXY` unset / `--no-proxy` → no-op → Task 3 (early return) + the `(( ICODEX_DISABLE_PROXY )) ||` guard kept in icodex.sh. ✓
- Run-path wiring `proxy_apply`→`proxy_ensure` → Task 3 Step 4; smoke awk updated Step 5. ✓
- Behavior matrix rows → covered by `_proxy_unreachable_action` unit cases + `proxy_ensure` no-op/unreachable/reachable(stub) tests. The interactive `exit` path (TTY + `n`) is covered at the decision level by `_proxy_unreachable_action 1 n` → `exit`; the live pty exit is not unit-tested (documented). ✓

**Placeholder scan:** No TBD/TODO; every code and test step shows full content. ✓

**Type/name consistency:** `_proxy_host_port`, `proxy_reachable`, `_proxy_unreachable_action`, `proxy_ensure`, `proxy_apply` — used identically across Tasks 1-3 and the run-path block. The smoke awk matches the exact wired token `proxy_ensure`. ✓

**Out of scope (per spec, unchanged):** end-to-end proxy validation, retries, env-configurable timeout, probe-result caching, per-`NO_PROXY` host probing.

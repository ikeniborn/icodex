---
review:
  plan_hash: ab4ff975845dbd10
  spec_hash: c474263773319527
  last_run: 2026-06-25
  phases:
    structure:     { status: passed }
    coverage:      { status: passed }
    dependencies:  { status: passed }
    verifiability: { status: passed }
    consistency:   { status: passed }
  findings:
    - id: F-001
      phase: verifiability
      severity: WARNING
      section: "Task 1 (representative; also VERSION/README/helpers create-steps)"
      section_hash: c44e4d9227754737
      fragment: "Step 1: Create `.gitignore`"
      text: "Pure file-creation steps (.gitignore, VERSION, tests/helpers.sh, README.md) carry no inline verification command / expected output of their own."
      fix: "Acceptable: their DoD is the task's subsequent test-run step which sources/uses the created files. Optionally add a quick `test -f`/`cat` check to each create-step."
      verdict: open
      verdict_at: null
chain:
  intent: null
  spec: docs/superpowers/specs/2026-06-25-icodex-mvp-wrapper-design.md
result_check:
  verdict: OK
  plan_hash: ab4ff975845dbd10
  last_run: 2026-06-25
---

# icodex MVP Wrapper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `icodex` — a dependency-free bash wrapper that installs a pinned OpenAI Codex CLI binary into the project, isolates its state via `CODEX_HOME`, optionally routes it through a proxy, and launches it transparently.

**Architecture:** Standalone mirror of the `iclaude` module pattern. `icodex.sh` only sources `lib/*` modules and orchestrates; every module is a single-responsibility bash file with pure functions and injectable seams (uname, download, latest-tag) so they unit-test without network. The codex binary is the prebuilt static `x86_64-unknown-linux-musl` (and aarch64 / apple-darwin) release artifact, pinned by version + sha256 in a committed lockfile.

**Tech Stack:** Bash 4+, `curl`, `tar`, `sha256sum`/`shasum`. No Node, no jq, no bats. Tests are dependency-free bash scripts following the `iclaude` `tests/` pattern.

## Global Constraints

- Pure bash; **no Node, no jq, no bats**. Allowed external tools: `curl`, `tar`, and a sha256 tool (`sha256sum` on Linux, `shasum -a 256` on macOS).
- All logic lives under `lib/`; `icodex.sh` only sources modules and orchestrates.
- Codex binary source: GitHub Releases `openai/codex`, asset `codex-<arch>-<os>.tar.gz` (e.g. `codex-x86_64-unknown-linux-musl.tar.gz`). Release tags have the form `rust-v<semver>`.
- Isolation paths (all relative to the repo root): `CODEX_HOME = .codex-isolated/`; binary at `.codex-isolated/bin/codex`; install stamp at `.codex-isolated/bin/.codex-version`; pin file `.codex-lockfile.json` (committed); proxy creds `.codex_config` (chmod 600, gitignored).
- `.codex-isolated/` and `.codex_config` are git-ignored. `.codex-lockfile.json` is committed.
- Tamper guard: if the lockfile pins a sha256 and the downloaded tarball's sha differs, **stop** — never install or launch.
- Auth is passthrough only: the wrapper never reads, stores, or injects credentials. `codex login` / `OPENAI_API_KEY` write into the isolated `CODEX_HOME` themselves.
- Unknown arguments (the first non-icodex token onward, or everything after `--`) are forwarded verbatim to `codex`.
- Every module function logs errors via `log_error` and returns non-zero on failure (no `exit` inside library functions except the final `exec`).

---

### Task 1: Scaffold + test harness + logging

**Files:**
- Create: `.gitignore`
- Create: `VERSION`
- Create: `tests/helpers.sh`
- Create: `lib/core/logging.sh`
- Test: `tests/test_logging.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `tests/helpers.sh` exposing `assert_eq <desc> <expected> <actual>`, `assert_exit <desc> <expected_code> <cmd...>`, `assert_contains <desc> <haystack> <needle>`, `finish` (prints `PASS=n FAIL=n`, returns non-zero if any FAIL). `lib/core/logging.sh` exposing `log_info`, `log_warn`, `log_error` (all write to **stderr**, return 0).

- [ ] **Step 1: Create `.gitignore`**

```gitignore
# icodex runtime state — never commit
.codex-isolated/
.codex_config

# OS / editor noise
.DS_Store
*.swp
```

- [ ] **Step 2: Create `VERSION`**

```
0.1.0
```

- [ ] **Step 3: Create the shared test harness `tests/helpers.sh`**

```bash
#!/usr/bin/env bash
# Dependency-free test helpers for icodex (mirrors the iclaude tests/ pattern).
set -uo pipefail

PASS=0
FAIL=0

assert_eq() { # <desc> <expected> <actual>
  local desc="$1" exp="$2" act="$3"
  if [[ "$exp" == "$act" ]]; then
    echo "PASS [$desc]"; PASS=$((PASS+1))
  else
    echo "FAIL [$desc]: expected '$exp' got '$act'"; FAIL=$((FAIL+1))
  fi
}

assert_exit() { # <desc> <expected_code> <cmd...>
  local desc="$1" exp="$2"; shift 2
  local code=0
  "$@" >/dev/null 2>&1 || code=$?
  if [[ "$code" == "$exp" ]]; then
    echo "PASS [$desc]"; PASS=$((PASS+1))
  else
    echo "FAIL [$desc]: exit $code want $exp"; FAIL=$((FAIL+1))
  fi
}

assert_contains() { # <desc> <haystack> <needle>
  local desc="$1" hay="$2" need="$3"
  if grep -qF -- "$need" <<<"$hay"; then
    echo "PASS [$desc]"; PASS=$((PASS+1))
  else
    echo "FAIL [$desc]: '$need' not found"; FAIL=$((FAIL+1))
  fi
}

finish() {
  echo "---"
  echo "PASS=$PASS FAIL=$FAIL"
  [[ "$FAIL" -eq 0 ]]
}
```

- [ ] **Step 4: Write the failing test `tests/test_logging.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"

# log_error writes to stderr and includes the message
err="$(log_error "boom" 2>&1 >/dev/null)"
assert_contains "log_error to stderr" "$err" "boom"

# log_info returns 0
log_info "hi" 2>/dev/null
assert_eq "log_info returns 0" "0" "$?"

finish
```

- [ ] **Step 5: Run test to verify it fails**

Run: `bash tests/test_logging.sh`
Expected: FAIL — `lib/core/logging.sh` does not exist yet (source error / function not found).

- [ ] **Step 6: Implement `lib/core/logging.sh`**

```bash
#!/usr/bin/env bash
# Logging helpers. All output to stderr so stdout stays clean for data.
log_info()  { printf '\033[0;34m[icodex]\033[0m %s\n'       "$*" >&2; }
log_warn()  { printf '\033[0;33m[icodex] WARN:\033[0m %s\n'  "$*" >&2; }
log_error() { printf '\033[0;31m[icodex] ERROR:\033[0m %s\n' "$*" >&2; }
```

- [ ] **Step 7: Run test to verify it passes**

Run: `bash tests/test_logging.sh`
Expected: `PASS=2 FAIL=0`, exit 0.

- [ ] **Step 8: Commit**

```bash
git add .gitignore VERSION tests/helpers.sh tests/test_logging.sh lib/core/logging.sh
git commit -m "feat(core): scaffold project, test harness, logging"
```

---

### Task 2: Core paths & identity (`core/init`)

**Files:**
- Create: `lib/core/init.sh`
- Test: `tests/test_init.sh`

**Interfaces:**
- Consumes: `ICODEX_ROOT` (set by the entrypoint; init derives it if unset).
- Produces: global vars `ICODEX_ROOT`, `ICODEX_HOME_DIR`, `ICODEX_BIN`, `ICODEX_STAMP`, `ICODEX_LOCKFILE`, `ICODEX_CONFIG`, `ICODEX_PROJECT_ID`, `ICODEX_REPO`; and function `_sha256` (reads stdin, prints lowercase hex digest, picks `sha256sum` or `shasum -a 256`).

- [ ] **Step 1: Write the failing test `tests/test_init.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

tmp="$(mktemp -d)"
ICODEX_ROOT="$tmp"
source "$ROOT/lib/core/init.sh"

assert_eq "home dir"   "$tmp/.codex-isolated"          "$ICODEX_HOME_DIR"
assert_eq "bin path"   "$tmp/.codex-isolated/bin/codex" "$ICODEX_BIN"
assert_eq "stamp path" "$tmp/.codex-isolated/bin/.codex-version" "$ICODEX_STAMP"
assert_eq "lockfile"   "$tmp/.codex-lockfile.json"     "$ICODEX_LOCKFILE"
assert_eq "config"     "$tmp/.codex_config"            "$ICODEX_CONFIG"
assert_eq "repo"       "openai/codex"                  "$ICODEX_REPO"

# _sha256 of the empty string is the well-known constant
digest="$(printf '' | _sha256)"
assert_eq "_sha256 empty" "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" "$digest"

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_init.sh`
Expected: FAIL — `lib/core/init.sh` missing.

- [ ] **Step 3: Implement `lib/core/init.sh`**

```bash
#!/usr/bin/env bash
# Global paths & identity. ICODEX_ROOT is set by the entrypoint; derive if absent.
: "${ICODEX_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

ICODEX_HOME_DIR="$ICODEX_ROOT/.codex-isolated"
ICODEX_BIN="$ICODEX_HOME_DIR/bin/codex"
ICODEX_STAMP="$ICODEX_HOME_DIR/bin/.codex-version"
ICODEX_LOCKFILE="$ICODEX_ROOT/.codex-lockfile.json"
ICODEX_CONFIG="$ICODEX_ROOT/.codex_config"
ICODEX_PROJECT_ID="$(basename "$ICODEX_ROOT")"
ICODEX_REPO="openai/codex"

# Portable sha256 of stdin → lowercase hex digest only.
_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_init.sh`
Expected: `PASS=7 FAIL=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add lib/core/init.sh tests/test_init.sh
git commit -m "feat(core): paths, identity, portable _sha256"
```

---

### Task 3: Precondition checks (`core/validation`)

**Files:**
- Create: `lib/core/validation.sh`
- Test: `tests/test_validation.sh`

**Interfaces:**
- Consumes: `log_error` (Task 1).
- Produces: `require_tools` — returns 0 if `curl`, `tar`, and a sha256 tool are present; else logs the missing tools and returns 1. Internal seam `_has <cmd>` (wraps `command -v`) is overridable in tests.

- [ ] **Step 1: Write the failing test `tests/test_validation.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/core/validation.sh"

# All tools present (real environment) → 0
assert_exit "tools present" 0 require_tools

# Simulate a missing tool by overriding the seam
_has() { [[ "$1" != "tar" ]]; }   # pretend tar is absent
assert_exit "missing tar -> 1" 1 require_tools

finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_validation.sh`
Expected: FAIL — `lib/core/validation.sh` missing.

- [ ] **Step 3: Implement `lib/core/validation.sh`**

```bash
#!/usr/bin/env bash
# Preconditions: required external tools must be on PATH.
_has() { command -v "$1" >/dev/null 2>&1; }

require_tools() {
  local missing=()
  _has curl || missing+=("curl")
  _has tar  || missing+=("tar")
  if ! _has sha256sum && ! _has shasum; then
    missing+=("sha256sum|shasum")
  fi
  if (( ${#missing[@]} )); then
    log_error "missing required tools: ${missing[*]}"
    return 1
  fi
  return 0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_validation.sh`
Expected: `PASS=2 FAIL=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add lib/core/validation.sh tests/test_validation.sh
git commit -m "feat(core): require_tools precondition check"
```

---

### Task 4: Platform detection (`binary/detect`)

**Files:**
- Create: `lib/binary/detect.sh`
- Test: `tests/test_detect.sh`

**Interfaces:**
- Consumes: `log_error` (Task 1). Reads `ICODEX_UNAME_S` / `ICODEX_UNAME_M` env overrides if set, else `uname -s` / `uname -m`.
- Produces: `detect_asset` — prints the release asset filename `codex-<arch>-<os>.tar.gz` to stdout and returns 0; on unsupported OS/arch logs an error and returns 1.

- [ ] **Step 1: Write the failing test `tests/test_detect.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/binary/detect.sh"

ICODEX_UNAME_S="Linux"  ICODEX_UNAME_M="x86_64"
assert_eq "linux x86_64" "codex-x86_64-unknown-linux-musl.tar.gz" "$(detect_asset)"

ICODEX_UNAME_S="Linux"  ICODEX_UNAME_M="aarch64"
assert_eq "linux aarch64" "codex-aarch64-unknown-linux-musl.tar.gz" "$(detect_asset)"

ICODEX_UNAME_S="Darwin" ICODEX_UNAME_M="arm64"
assert_eq "darwin arm64" "codex-aarch64-apple-darwin.tar.gz" "$(detect_asset)"

ICODEX_UNAME_S="Darwin" ICODEX_UNAME_M="x86_64"
assert_eq "darwin x86_64" "codex-x86_64-apple-darwin.tar.gz" "$(detect_asset)"

ICODEX_UNAME_S="Plan9" ICODEX_UNAME_M="x86_64"
assert_exit "unsupported OS -> 1" 1 detect_asset

finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_detect.sh`
Expected: FAIL — `lib/binary/detect.sh` missing.

- [ ] **Step 3: Implement `lib/binary/detect.sh`**

```bash
#!/usr/bin/env bash
# Map host OS/arch -> GitHub release asset name. Env overrides aid testing.
detect_asset() {
  local s="${ICODEX_UNAME_S:-$(uname -s)}"
  local m="${ICODEX_UNAME_M:-$(uname -m)}"
  local os arch
  case "$s" in
    Linux)  os="unknown-linux-musl" ;;
    Darwin) os="apple-darwin" ;;
    *) log_error "unsupported OS: $s (supported: Linux, Darwin)"; return 1 ;;
  esac
  case "$m" in
    x86_64|amd64)  arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) log_error "unsupported arch: $m (supported: x86_64, aarch64)"; return 1 ;;
  esac
  printf 'codex-%s-%s.tar.gz\n' "$arch" "$os"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_detect.sh`
Expected: `PASS=5 FAIL=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add lib/binary/detect.sh tests/test_detect.sh
git commit -m "feat(binary): detect_asset for OS/arch -> release asset"
```

---

### Task 5: Lockfile read/write (`binary/lockfile`)

**Files:**
- Create: `lib/binary/lockfile.sh`
- Test: `tests/test_lockfile.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `lockfile_get <file> <key>` — prints the string value for `version`|`asset`|`sha256` from the flat JSON; returns 1 if the file is absent. `lockfile_write <file> <version> <asset> <sha256>` — writes the canonical flat JSON.

- [ ] **Step 1: Write the failing test `tests/test_lockfile.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/binary/lockfile.sh"

tmp="$(mktemp -d)"; lf="$tmp/lock.json"

lockfile_write "$lf" "rust-v0.142.2" "codex-x86_64-unknown-linux-musl.tar.gz" "abc123"
assert_eq "version round-trip" "rust-v0.142.2"                              "$(lockfile_get "$lf" version)"
assert_eq "asset round-trip"   "codex-x86_64-unknown-linux-musl.tar.gz"     "$(lockfile_get "$lf" asset)"
assert_eq "sha round-trip"     "abc123"                                     "$(lockfile_get "$lf" sha256)"

assert_exit "missing file -> 1" 1 lockfile_get "$tmp/nope.json" version

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_lockfile.sh`
Expected: FAIL — `lib/binary/lockfile.sh` missing.

- [ ] **Step 3: Implement `lib/binary/lockfile.sh`**

```bash
#!/usr/bin/env bash
# Read/write the flat, self-controlled pin file .codex-lockfile.json.
lockfile_get() { # <file> <key>
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 1
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$file" | head -1
}

lockfile_write() { # <file> <version> <asset> <sha256>
  local file="$1" version="$2" asset="$3" sha="$4"
  cat >"$file" <<EOF
{
  "version": "$version",
  "asset": "$asset",
  "sha256": "$sha"
}
EOF
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_lockfile.sh`
Expected: `PASS=4 FAIL=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add lib/binary/lockfile.sh tests/test_lockfile.sh
git commit -m "feat(binary): lockfile get/write for the version+sha pin"
```

---

### Task 6: Config isolation (`config/isolated`)

**Files:**
- Create: `lib/config/isolated.sh`
- Test: `tests/test_isolated.sh`

**Interfaces:**
- Consumes: `ICODEX_HOME_DIR` (Task 2).
- Produces: `setup_codex_home` — creates `$ICODEX_HOME_DIR/bin` and `export CODEX_HOME="$ICODEX_HOME_DIR"`.

- [ ] **Step 1: Write the failing test `tests/test_isolated.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/config/isolated.sh"

tmp="$(mktemp -d)"
ICODEX_HOME_DIR="$tmp/.codex-isolated"
unset CODEX_HOME

setup_codex_home
assert_eq  "CODEX_HOME exported" "$ICODEX_HOME_DIR" "${CODEX_HOME:-}"
assert_exit "bin dir created" 0 test -d "$ICODEX_HOME_DIR/bin"

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_isolated.sh`
Expected: FAIL — `lib/config/isolated.sh` missing.

- [ ] **Step 3: Implement `lib/config/isolated.sh`**

```bash
#!/usr/bin/env bash
# Redirect all codex state into the project via CODEX_HOME.
setup_codex_home() {
  mkdir -p "$ICODEX_HOME_DIR/bin"
  export CODEX_HOME="$ICODEX_HOME_DIR"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_isolated.sh`
Expected: `PASS=2 FAIL=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add lib/config/isolated.sh tests/test_isolated.sh
git commit -m "feat(config): isolate codex state via CODEX_HOME"
```

---

### Task 7: Proxy passthrough (`proxy/proxy`)

**Files:**
- Create: `lib/proxy/proxy.sh`
- Test: `tests/test_proxy.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `proxy_save <config_file> <url>` (writes `PROXY_URL=<url>`, chmod 600); `proxy_clear <config_file>` (removes the file); `proxy_apply <config_file>` (if the file holds a URL, exports `HTTPS_PROXY HTTP_PROXY https_proxy http_proxy`; no-op when absent, returns 0).

- [ ] **Step 1: Write the failing test `tests/test_proxy.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/proxy/proxy.sh"

tmp="$(mktemp -d)"; cfg="$tmp/.codex_config"

proxy_save "$cfg" "http://proxy.local:8080"
assert_exit "config written" 0 test -f "$cfg"
perm="$(stat -c '%a' "$cfg" 2>/dev/null || stat -f '%Lp' "$cfg")"
assert_eq "config is 600" "600" "$perm"

unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy
proxy_apply "$cfg"
assert_eq "HTTPS_PROXY exported" "http://proxy.local:8080" "${HTTPS_PROXY:-}"
assert_eq "http_proxy exported"  "http://proxy.local:8080" "${http_proxy:-}"

unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy
proxy_apply "$tmp/absent"
assert_eq "no export when absent" "" "${HTTPS_PROXY:-}"

proxy_clear "$cfg"
assert_exit "config cleared" 1 test -f "$cfg"

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_proxy.sh`
Expected: FAIL — `lib/proxy/proxy.sh` missing.

- [ ] **Step 3: Implement `lib/proxy/proxy.sh`**

```bash
#!/usr/bin/env bash
# Persist and apply proxy env vars for codex (Rust reqwest honors them natively).
proxy_save() { # <config_file> <url>
  printf 'PROXY_URL=%s\n' "$2" > "$1"
  chmod 600 "$1"
}

proxy_clear() { # <config_file>
  rm -f "$1"
}

proxy_apply() { # <config_file>
  local file="$1" url
  [[ -f "$file" ]] || return 0
  url="$(sed -n 's/^PROXY_URL=//p' "$file" | head -1)"
  [[ -n "$url" ]] || return 0
  export HTTPS_PROXY="$url" HTTP_PROXY="$url" https_proxy="$url" http_proxy="$url"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_proxy.sh`
Expected: `PASS=6 FAIL=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add lib/proxy/proxy.sh tests/test_proxy.sh
git commit -m "feat(proxy): save/apply/clear proxy env passthrough"
```

---

### Task 8: Binary install with tamper guard (`binary/install`)

This task implements the install core and **resolves finding F-001** from the spec review: idempotency is defined by an explicit stamp file (`.codex-isolated/bin/.codex-version`) holding the installed tag, compared against the lockfile version — not by re-hashing the extracted binary.

**Files:**
- Create: `lib/binary/install.sh`
- Test: `tests/test_install.sh`

**Interfaces:**
- Consumes: `detect_asset` (Task 4); `lockfile_get`/`lockfile_write` (Task 5); `_sha256`, `ICODEX_REPO`, `ICODEX_HOME_DIR`, `ICODEX_BIN`, `ICODEX_STAMP`, `ICODEX_LOCKFILE` (Task 2); `log_info`/`log_error` (Task 1).
- Produces: seams `_download <url> <dest>` (default `curl -fsSL`), `_resolve_latest` (default GitHub API → `tag_name`), `_release_url <tag> <asset>`, `_extract_codex <tarball>`; and `install_ensure [--update]` — ensures the pinned binary is present & verified, returns 0 on success, non-zero on any failure (download error, sha mismatch, extraction failure).

- [ ] **Step 1: Write the failing test `tests/test_install.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/binary/detect.sh"
source "$ROOT/lib/binary/lockfile.sh"

ICODEX_UNAME_S="Linux"; ICODEX_UNAME_M="x86_64"

setup_case() {
  tmp="$(mktemp -d)"
  ICODEX_ROOT="$tmp"
  ICODEX_HOME_DIR="$tmp/.codex-isolated"
  ICODEX_BIN="$ICODEX_HOME_DIR/bin/codex"
  ICODEX_STAMP="$ICODEX_HOME_DIR/bin/.codex-version"
  ICODEX_LOCKFILE="$tmp/.codex-lockfile.json"
  ICODEX_REPO="openai/codex"
  mkdir -p "$ICODEX_HOME_DIR/bin"
  _sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum|awk '{print $1}'; else shasum -a 256|awk '{print $1}'; fi; }
  # Build a fixture tarball containing an executable `codex`
  local stage="$tmp/stage"; mkdir -p "$stage"
  printf '#!/bin/sh\necho codex-fixture 0.0.0\n' > "$stage/codex"; chmod +x "$stage/codex"
  FIXTURE_TAR="$tmp/fixture.tar.gz"
  tar -czf "$FIXTURE_TAR" -C "$stage" codex
  FIXTURE_SHA="$(_sha256 < "$FIXTURE_TAR")"
  DL_CALLS=0
}

source "$ROOT/lib/binary/install.sh"

# --- Case A: clean install with matching pinned sha succeeds ---
setup_case
_download() { DL_CALLS=$((DL_CALLS+1)); cp "$FIXTURE_TAR" "$2"; }   # offline seam
lockfile_write "$ICODEX_LOCKFILE" "rust-v9.9.9" "codex-x86_64-unknown-linux-musl.tar.gz" "$FIXTURE_SHA"
assert_exit "install succeeds" 0 install_ensure
assert_exit "binary installed & executable" 0 test -x "$ICODEX_BIN"
assert_eq   "stamp == pinned tag" "rust-v9.9.9" "$(cat "$ICODEX_STAMP")"
rm -rf "$tmp"

# --- Case B: idempotent — second call does not re-download ---
setup_case
_download() { DL_CALLS=$((DL_CALLS+1)); cp "$FIXTURE_TAR" "$2"; }
lockfile_write "$ICODEX_LOCKFILE" "rust-v9.9.9" "codex-x86_64-unknown-linux-musl.tar.gz" "$FIXTURE_SHA"
install_ensure >/dev/null 2>&1
before="$DL_CALLS"
install_ensure >/dev/null 2>&1
assert_eq "no second download" "$before" "$DL_CALLS"
rm -rf "$tmp"

# --- Case C: sha mismatch stops install (tamper guard) ---
setup_case
_download() { DL_CALLS=$((DL_CALLS+1)); cp "$FIXTURE_TAR" "$2"; }
lockfile_write "$ICODEX_LOCKFILE" "rust-v9.9.9" "codex-x86_64-unknown-linux-musl.tar.gz" "deadbeef_wrong_sha"
assert_exit "mismatch -> non-zero" 1 install_ensure
assert_exit "binary NOT installed" 1 test -x "$ICODEX_BIN"
rm -rf "$tmp"

finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_install.sh`
Expected: FAIL — `lib/binary/install.sh` missing.

- [ ] **Step 3: Implement `lib/binary/install.sh`**

```bash
#!/usr/bin/env bash
# Ensure the pinned codex binary is present & verified.
# Idempotency (resolves F-001): a stamp file holds the installed tag; if it
# matches the lockfile version and the binary is executable, skip the download.

# --- Seams (overridable in tests) ---
_download() { # <url> <dest>
  curl -fsSL "$1" -o "$2"
}

_resolve_latest() {
  curl -fsSL "https://api.github.com/repos/$ICODEX_REPO/releases/latest" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

_release_url() { # <tag> <asset>
  printf 'https://github.com/%s/releases/download/%s/%s\n' "$ICODEX_REPO" "$1" "$2"
}

_extract_codex() { # <tarball> -> installs $ICODEX_BIN
  local tarball="$1" tmpd found
  tmpd="$(mktemp -d)"
  if ! tar -xzf "$tarball" -C "$tmpd"; then
    log_error "failed to extract $tarball"; rm -rf "$tmpd"; return 1
  fi
  found="$(find "$tmpd" -type f -name 'codex*' ! -name '*.tar*' ! -name '*.sigstore' | head -1)"
  if [[ -z "$found" ]]; then
    log_error "codex binary not found inside archive"; rm -rf "$tmpd"; return 1
  fi
  mkdir -p "$ICODEX_HOME_DIR/bin"
  cp "$found" "$ICODEX_BIN"
  chmod +x "$ICODEX_BIN"
  rm -rf "$tmpd"
}

# install_ensure [--update]
install_ensure() {
  local update=0
  [[ "${1:-}" == "--update" ]] && update=1

  local asset; asset="$(detect_asset)" || return 1
  local want_version want_sha
  want_version="$(lockfile_get "$ICODEX_LOCKFILE" version 2>/dev/null || true)"
  want_sha="$(lockfile_get "$ICODEX_LOCKFILE" sha256 2>/dev/null || true)"

  # Idempotency: stamp matches pinned tag and binary present -> done.
  if (( ! update )) && [[ -x "$ICODEX_BIN" && -f "$ICODEX_STAMP" && -n "$want_version" ]]; then
    if [[ "$(cat "$ICODEX_STAMP")" == "$want_version" ]]; then
      return 0
    fi
  fi

  local tag="$want_version"
  if (( update )) || [[ -z "$tag" ]]; then
    tag="$(_resolve_latest)" || { log_error "cannot resolve latest codex release"; return 1; }
  fi
  [[ -n "$tag" ]] || { log_error "no codex version pinned and latest unresolved"; return 1; }

  local url tarball sha
  url="$(_release_url "$tag" "$asset")"
  tarball="$(mktemp)"
  if ! _download "$url" "$tarball"; then
    log_error "download failed: $url"
    log_error "manual: fetch $asset from https://github.com/$ICODEX_REPO/releases/tag/$tag"
    rm -f "$tarball"; return 1
  fi
  sha="$(_sha256 < "$tarball")"

  if [[ -n "$want_sha" && "$want_sha" != "$sha" ]]; then
    log_error "sha256 mismatch (tamper guard): pinned '$want_sha' got '$sha'"
    rm -f "$tarball"; return 1
  fi

  if ! _extract_codex "$tarball"; then
    rm -f "$tarball"; return 1
  fi
  printf '%s\n' "$tag" > "$ICODEX_STAMP"
  rm -f "$tarball"

  if (( update )); then
    lockfile_write "$ICODEX_LOCKFILE" "$tag" "$asset" "$sha"
    log_info "pinned codex $tag (sha256 $sha)"
  fi
  return 0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_install.sh`
Expected: `PASS=6 FAIL=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add lib/binary/install.sh tests/test_install.sh
git commit -m "feat(binary): install_ensure with sha tamper guard and stamp idempotency"
```

---

### Task 9: Argument parsing (`command/args`)

**Files:**
- Create: `lib/command/args.sh`
- Test: `tests/test_args.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: globals `ICODEX_CMD` (`run`|`clear`|`update`|`install`|`version`|`help`), `ICODEX_NO_PROXY` (0/1), `ICODEX_SET_PROXY` (string), `ICODEX_PASSTHROUGH` (array); functions `parse_args "$@"` and `print_help`. The first non-icodex token (or everything after `--`) begins passthrough.

- [ ] **Step 1: Write the failing test `tests/test_args.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/command/args.sh"

reset() { ICODEX_CMD="run"; ICODEX_NO_PROXY=0; ICODEX_SET_PROXY=""; ICODEX_PASSTHROUGH=(); }

reset; parse_args --proxy "http://p:8080"
assert_eq "proxy url captured" "http://p:8080" "$ICODEX_SET_PROXY"
assert_eq "cmd still run"      "run"           "$ICODEX_CMD"

reset; parse_args --update
assert_eq "update cmd" "update" "$ICODEX_CMD"

reset; parse_args --no-proxy exec "hi"
assert_eq "no-proxy flag" "1" "$ICODEX_NO_PROXY"
assert_eq "passthrough joined" "exec hi" "${ICODEX_PASSTHROUGH[*]}"

reset; parse_args --model o3 -q
assert_eq "unknown flags passthrough" "--model o3 -q" "${ICODEX_PASSTHROUGH[*]}"

reset; parse_args -- --help
assert_eq "after -- goes to codex" "--help" "${ICODEX_PASSTHROUGH[*]}"

assert_contains "help text" "$(print_help)" "Usage:"

finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_args.sh`
Expected: FAIL — `lib/command/args.sh` missing.

- [ ] **Step 3: Implement `lib/command/args.sh`**

```bash
#!/usr/bin/env bash
# Parse icodex flags; collect the rest as passthrough for codex.
ICODEX_CMD="run"
ICODEX_NO_PROXY=0
ICODEX_SET_PROXY=""
ICODEX_PASSTHROUGH=()

parse_args() {
  while (( $# )); do
    case "$1" in
      --proxy)    ICODEX_SET_PROXY="${2:?--proxy requires a url}"; shift 2 ;;
      --no-proxy) ICODEX_NO_PROXY=1; shift ;;
      --clear)    ICODEX_CMD="clear";   shift ;;
      --update)   ICODEX_CMD="update";  shift ;;
      --install)  ICODEX_CMD="install"; shift ;;
      --version)  ICODEX_CMD="version"; shift ;;
      --help|-h)  ICODEX_CMD="help";    shift ;;
      --)         shift; ICODEX_PASSTHROUGH+=("$@"); break ;;
      *)          ICODEX_PASSTHROUGH+=("$@"); break ;;
    esac
  done
}

print_help() {
  cat <<'EOF'
icodex — isolated wrapper for OpenAI Codex CLI

Usage: icodex [icodex-flags] [-- codex-args...]

icodex flags:
  --proxy <url>   Save proxy URL and route codex through it
  --no-proxy      Run without proxy (ignore saved value)
  --clear         Remove saved proxy config (.codex_config)
  --update        Update codex binary to latest, re-pin lockfile
  --install       Install codex binary per lockfile (no launch)
  --version       Print icodex + codex versions
  --help, -h      Show this help

Anything after the first non-flag (or after --) is passed to codex verbatim.
EOF
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_args.sh`
Expected: `PASS=7 FAIL=0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add lib/command/args.sh tests/test_args.sh
git commit -m "feat(command): flag parsing + help, codex passthrough"
```

---

### Task 10: Launcher + entrypoint + project pin + smoke

**Files:**
- Create: `lib/launcher/launch.sh`
- Create: `icodex.sh`
- Create: `README.md`
- Create: `.codex-lockfile.json` (populated by a real `--update` run)
- Test: `tests/test_smoke.sh`

**Interfaces:**
- Consumes: every module above (sourced by `icodex.sh`).
- Produces: `launch_codex <args...>` (final `exec` of `$ICODEX_BIN`, or returns 1 with a hint if the binary is missing); the `icodex.sh` entrypoint wiring all modules and branching on `ICODEX_CMD`.

- [ ] **Step 1: Write the failing smoke test `tests/test_smoke.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

# --help exits 0 and prints usage
out="$("$ROOT/icodex.sh" --help)"; code=$?
assert_eq       "help exit 0" "0" "$code"
assert_contains "help usage"  "$out" "Usage:"

# --version exits 0 and names icodex even when codex isn't installed
out="$("$ROOT/icodex.sh" --version 2>/dev/null)"; code=$?
assert_eq       "version exit 0" "0" "$code"
assert_contains "version names icodex" "$out" "icodex"

# launch guard: launch_codex returns 1 when the binary is absent
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/launcher/launch.sh"
ICODEX_BIN="/nonexistent/codex"
assert_exit "launch guard -> 1" 1 launch_codex --help

finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_smoke.sh`
Expected: FAIL — `icodex.sh` / `lib/launcher/launch.sh` missing.

- [ ] **Step 3: Implement `lib/launcher/launch.sh`**

```bash
#!/usr/bin/env bash
# Final transparent exec of the isolated codex binary.
launch_codex() { # <args...>
  if [[ ! -x "$ICODEX_BIN" ]]; then
    log_error "codex binary missing — run: ./icodex.sh --install"
    return 1
  fi
  exec "$ICODEX_BIN" "$@"
}
```

- [ ] **Step 4: Implement the entrypoint `icodex.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

ICODEX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ICODEX_ROOT

for m in core/logging core/init core/validation command/args \
         binary/detect binary/lockfile binary/install \
         config/isolated proxy/proxy launcher/launch; do
  # shellcheck source=/dev/null
  source "$ICODEX_ROOT/lib/$m.sh"
done

main() {
  parse_args "$@"

  case "$ICODEX_CMD" in
    help)
      print_help; exit 0 ;;
    clear)
      proxy_clear "$ICODEX_CONFIG"; log_info "cleared $ICODEX_CONFIG"; exit 0 ;;
    version)
      printf 'icodex %s\n' "$(cat "$ICODEX_ROOT/VERSION" 2>/dev/null || echo dev)"
      if [[ -x "$ICODEX_BIN" ]]; then "$ICODEX_BIN" --version; else echo "codex: not installed"; fi
      exit 0 ;;
  esac

  require_tools || exit 1
  [[ -n "$ICODEX_SET_PROXY" ]] && proxy_save "$ICODEX_CONFIG" "$ICODEX_SET_PROXY"

  case "$ICODEX_CMD" in
    install) setup_codex_home; install_ensure;          exit $? ;;
    update)  setup_codex_home; install_ensure --update; exit $? ;;
  esac

  # default: run
  setup_codex_home
  install_ensure || exit 1
  (( ICODEX_NO_PROXY )) || proxy_apply "$ICODEX_CONFIG"
  launch_codex ${ICODEX_PASSTHROUGH[@]+"${ICODEX_PASSTHROUGH[@]}"}
}

main "$@"
```

- [ ] **Step 5: Make the entrypoint executable**

Run: `chmod +x icodex.sh`

- [ ] **Step 6: Run the smoke test to verify it passes**

Run: `bash tests/test_smoke.sh`
Expected: `PASS=5 FAIL=0`, exit 0.

- [ ] **Step 7: Run the full suite**

Run: `for t in tests/test_*.sh; do echo "== $t =="; bash "$t" || exit 1; done`
Expected: every file ends `PASS=n FAIL=0`, overall exit 0.

- [ ] **Step 8: Populate the real lockfile pin (requires network)**

Run: `./icodex.sh --update`
Expected: logs `pinned codex rust-v<semver> (sha256 <hex>)`; `.codex-lockfile.json` now holds the real `version`, `asset`, and `sha256`; `.codex-isolated/bin/codex` exists.

Verify: `cat .codex-lockfile.json` shows a non-empty `sha256`, and `./icodex.sh --version` prints both the icodex version and a real `codex-cli` version line.

> If offline: skip this step and commit a lockfile with the intended `version`/`asset` and an empty `sha256` (trust-on-first-use); re-run `--update` later to lock the sha.

- [ ] **Step 9: Write `README.md`**

```markdown
# icodex

Isolated bash wrapper for the [OpenAI Codex CLI](https://developers.openai.com/codex/cli),
built following the `iclaude` example. Installs a pinned static codex binary into the
project, isolates codex state via `CODEX_HOME`, and optionally routes traffic through a proxy.

## Usage

    ./icodex.sh --install          # fetch the pinned binary
    ./icodex.sh                    # launch codex in the isolated environment
    ./icodex.sh --proxy http://p:8080 exec "..."   # via proxy, args forwarded to codex
    ./icodex.sh --update           # update + re-pin the binary
    ./icodex.sh --version          # icodex + codex versions

State lives in `.codex-isolated/` (git-ignored). The binary is pinned by version + sha256
in `.codex-lockfile.json` (committed). Auth (`codex login` / `OPENAI_API_KEY`) is written
into the isolated `CODEX_HOME` by codex itself — the wrapper never stores credentials.
```

- [ ] **Step 10: Commit**

```bash
git add icodex.sh lib/launcher/launch.sh README.md .codex-lockfile.json tests/test_smoke.sh
git commit -m "feat(launcher): entrypoint orchestration, launch, README, pinned lockfile"
```

---

## Verification Against Success Criteria

After Task 10, confirm the spec's MVP success criteria by running real commands:

1. **Download + verify (criterion 1):** on a clean checkout, `./icodex.sh --install` downloads the pinned binary and the sha256 matches the lockfile (a mismatch aborts). Covered by Task 8 (tamper guard) + Task 10 Step 8.
2. **Config isolation (criterion 2):** after install, `.codex-isolated/` exists and `CODEX_HOME` points at it. Covered by Task 6 + Task 10.
3. **Codex starts isolated (criterion 3):** `./icodex.sh` execs the isolated binary with `CODEX_HOME` set. Manual: `./icodex.sh --version` shows the real codex version; `./icodex.sh` launches the TUI.
4. **Proxy routing (criterion 4):** `./icodex.sh --proxy <url> ...` exports `HTTPS_PROXY` into codex's environment. Covered by Task 7; verify manually against a real proxy (e.g. point at a local logging proxy and confirm codex requests appear).

---
review:
  plan_hash: f308559ce47ac3ac
  last_run: 2026-07-08
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-07-07-icodex-telemetry-intent.md
  spec: docs/superpowers/specs/2026-07-08-icodex-telemetry-design.md
---
# icodex Telemetry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add opt-in hybrid telemetry to icodex: metadata-only Codex OTel for Grafana and local trusted full-fidelity Langfuse capture.

**Architecture:** Introduce a focused `lib/telemetry/` layer that validates `ICODEX_TELEMETRY=off|otel|langfuse|both`, derives project/session metadata, writes Codex OTel config, starts a local Langfuse capture layer only when requested, and preserves Codex passthrough args and exit code. Full Langfuse capture is gated by a feasibility probe so implementation stops if the installed Codex cannot safely route traffic through a local capture provider/proxy.

**Tech Stack:** Bash modules and Bash tests only; Codex config TOML mutation by shell text region; local fake capture server fixtures for tests; no external network in tests.

---

## File Structure

- Create `lib/telemetry/telemetry.sh`: mode parsing, project/session derivation, top-level setup/cleanup orchestration, shared URL helpers.
- Create `lib/telemetry/otel.sh`: Codex OTel config region, Basic Auth header generation from `ICODEX_OTEL_CREDENTIALS`, `NO_PROXY` patching.
- Create `lib/telemetry/langfuse.sh`: local/trusted Langfuse URL validation, capture feasibility probe hook, capture lifecycle helpers.
- Modify `icodex.sh`: source telemetry modules and call setup before launch.
- Modify `lib/launcher/launch.sh`: keep direct `exec` for `off`; add wrapped launch helper for telemetry modes.
- Modify `.codex_config.example`: document `ICODEX_TELEMETRY`, OTel endpoint/credentials, and Langfuse local capture keys.
- Create `tests/test_telemetry_config.sh`: mode parsing, project/session derivation, URL validation.
- Create `tests/test_telemetry_otel.sh`: OTel config region, credentials header, `NO_PROXY`, prompt logging disabled.
- Create `tests/test_telemetry_langfuse.sh`: Langfuse required config, local URL acceptance, non-local rejection, fake capture lifecycle.
- Create `tests/test_telemetry_launch.sh`: direct launch vs wrapped launch, passthrough args, exit-code preservation, cleanup.

## Task 1: Telemetry Config Core

**Files:**
- Create: `lib/telemetry/telemetry.sh`
- Test: `tests/test_telemetry_config.sh`

- [ ] **Step 1: Write failing telemetry config tests**

Create `tests/test_telemetry_config.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/telemetry/telemetry.sh"

unset ICODEX_TELEMETRY
telemetry_mode_default
assert_eq "default mode off" "off" "$ICODEX_TELEMETRY"

for mode in off otel langfuse both; do
  ICODEX_TELEMETRY="$mode"
  assert_exit "valid mode $mode" 0 telemetry_validate_mode
done

ICODEX_TELEMETRY="bad"
assert_exit "invalid mode fails" 1 telemetry_validate_mode

tmp="$(mktemp -d)"
mkdir -p "$tmp/repo"
git -C "$tmp/repo" init >/dev/null 2>&1
mkdir -p "$tmp/repo/subdir"
project="$(telemetry_derive_project "$tmp/repo/subdir")"
assert_eq "git project basename" "repo" "$project"

nogit="$tmp/plain"
mkdir -p "$nogit"
project="$(telemetry_derive_project "$nogit")"
assert_eq "plain project basename" "plain" "$project"

sid="$(telemetry_new_session_id)"
case "$sid" in
  icodex-*) PASS=$((PASS+1)); echo "PASS [session id prefix]" ;;
  *) FAIL=$((FAIL+1)); echo "FAIL [session id prefix]: got '$sid'" ;;
esac

assert_exit "localhost trusted" 0 telemetry_url_is_local_trusted "http://localhost:3000"
assert_exit "127 trusted" 0 telemetry_url_is_local_trusted "http://127.0.0.1:3000"
assert_exit "private trusted" 0 telemetry_url_is_local_trusted "http://192.168.1.10:3000"
assert_exit "public rejected" 1 telemetry_url_is_local_trusted "https://example.com"
assert_exit "url credentials rejected" 1 telemetry_url_is_local_trusted "http://user:pass@localhost:3000"
assert_exit "missing scheme rejected" 1 telemetry_url_is_local_trusted "localhost:3000"

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run failing test**

Run:

```bash
bash tests/test_telemetry_config.sh
```

Expected: FAIL because `lib/telemetry/telemetry.sh` does not exist.

- [ ] **Step 3: Implement telemetry config core**

Create `lib/telemetry/telemetry.sh`:

```bash
#!/usr/bin/env bash
# Telemetry orchestration helpers. Telemetry is opt-in via ICODEX_TELEMETRY.

telemetry_mode_default() {
  ICODEX_TELEMETRY="${ICODEX_TELEMETRY:-off}"
}

telemetry_validate_mode() {
  telemetry_mode_default
  case "$ICODEX_TELEMETRY" in
    off|otel|langfuse|both) return 0 ;;
    *)
      log_error "invalid ICODEX_TELEMETRY='$ICODEX_TELEMETRY' (allowed: off|otel|langfuse|both)"
      return 1
      ;;
  esac
}

telemetry_derive_project() { # <dir>
  local dir="${1:-$PWD}" top name
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || top=""
  if [[ -n "$top" ]]; then
    name="$(basename "$top")"
  else
    name="$(basename "$dir")"
  fi
  name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//')"
  [[ -n "$name" ]] || name="unknown"
  printf '%s' "$name"
}

telemetry_new_session_id() {
  printf 'icodex-%s-%s\n' "$(date +%Y%m%d%H%M%S)" "$$"
}

telemetry_url_host() { # <url>
  local url="$1" rest host
  [[ "$url" == http://* || "$url" == https://* ]] || return 1
  rest="${url#*://}"
  [[ "$rest" != *@* ]] || return 1
  rest="${rest%%/*}"
  if [[ "$rest" == \[*\]* ]]; then
    host="${rest%%]*}"
    host="${host#[}"
  else
    host="${rest%%:*}"
  fi
  [[ -n "$host" ]] || return 1
  printf '%s\n' "$host"
}

telemetry_url_is_local_trusted() { # <url>
  local host
  host="$(telemetry_url_host "$1")" || return 1
  case "$host" in
    localhost|127.*|::1|10.*|192.168.*) return 0 ;;
    172.*)
      local second="${host#172.}"
      second="${second%%.*}"
      [[ "$second" =~ ^[0-9]+$ ]] && (( second >= 16 && second <= 31 ))
      return
      ;;
    *) return 1 ;;
  esac
}

telemetry_setup_context() {
  telemetry_validate_mode || return 1
  ICODEX_TELEMETRY_PROJECT="${ICODEX_TELEMETRY_PROJECT:-$(telemetry_derive_project "${ICODEX_PROJECT_ROOT:-$PWD}")}"
  ICODEX_TELEMETRY_SESSION_ID="${ICODEX_TELEMETRY_SESSION_ID:-$(telemetry_new_session_id)}"
  export ICODEX_TELEMETRY ICODEX_TELEMETRY_PROJECT ICODEX_TELEMETRY_SESSION_ID
}
```

- [ ] **Step 4: Run config test**

Run:

```bash
bash tests/test_telemetry_config.sh
```

Expected: `PASS` lines and final `FAIL=0`.

- [ ] **Step 5: Commit Task 1**

```bash
git add lib/telemetry/telemetry.sh tests/test_telemetry_config.sh
git commit -m "feat(telemetry): add telemetry config core"
```

## Task 2: OTel Metadata Path

**Files:**
- Create: `lib/telemetry/otel.sh`
- Test: `tests/test_telemetry_otel.sh`

- [ ] **Step 1: Write failing OTel tests**

Create `tests/test_telemetry_otel.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/telemetry/telemetry.sh"
source "$ROOT/lib/telemetry/otel.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cfg="$tmp/config.toml"
printf '[sandbox]\nmode = "workspace-write"\n' > "$cfg"

ICODEX_HOME_DIR="$tmp"
ICODEX_TELEMETRY_PROJECT="repo"
ICODEX_TELEMETRY_SESSION_ID="icodex-test-session"
ICODEX_OTEL_ENDPOINT=""
unset ICODEX_OTEL_CREDENTIALS NO_PROXY no_proxy

telemetry_otel_configure "$cfg"
out="$(cat "$cfg")"
assert_contains "otel start marker" "$out" "# icodex:telemetry-otel:start"
assert_contains "otel exporter table" "$out" "[otel.exporter.otlp]"
assert_contains "otel exporter endpoint" "$out" 'endpoint = "http://127.0.0.1:4318"'
assert_contains "prompt logging disabled" "$out" "otel.log_user_prompt = false"
assert_contains "project resource" "$out" "icodex.project=repo"
assert_contains "session resource" "$out" "icodex.session_id=icodex-test-session"
assert_eq "no proxy localhost" "" "${NO_PROXY:-}"

ICODEX_OTEL_ENDPOINT="http://otel.local:4318"
ICODEX_OTEL_CREDENTIALS="otel:secret"
telemetry_otel_configure "$cfg"
out="$(cat "$cfg")"
expected="$(printf '%s' 'otel:secret' | base64 -w 0)"
assert_contains "basic auth header" "$out" "Authorization=Basic ${expected}"
assert_eq "no duplicate region" "1" "$(grep -c '# icodex:telemetry-otel:start' "$cfg")"
assert_contains "NO_PROXY contains endpoint host" "${NO_PROXY:-}" "otel.local"

finish
```

- [ ] **Step 2: Run failing OTel test**

Run:

```bash
bash tests/test_telemetry_otel.sh
```

Expected: FAIL because `lib/telemetry/otel.sh` does not exist.

- [ ] **Step 3: Implement OTel module**

Create `lib/telemetry/otel.sh`:

```bash
#!/usr/bin/env bash
# Codex OpenTelemetry metadata-only configuration.

_TELEMETRY_OTEL_START="# icodex:telemetry-otel:start"
_TELEMETRY_OTEL_END="# icodex:telemetry-otel:end"

telemetry_otel_endpoint() {
  printf '%s\n' "${ICODEX_OTEL_ENDPOINT:-http://127.0.0.1:4318}"
}

telemetry_otel_header() {
  [[ -n "${ICODEX_OTEL_CREDENTIALS:-}" ]] || return 0
  local b64
  b64="$(printf '%s' "$ICODEX_OTEL_CREDENTIALS" | base64 -w 0)"
  printf 'Authorization=Basic %s\n' "$b64"
}

telemetry_no_proxy_add_host() { # <url>
  local host
  host="$(telemetry_url_host "$1")" || return 0
  [[ "$host" == localhost || "$host" == 127.* || "$host" == "::1" ]] && return 0
  if [[ ",${NO_PROXY:-}," != *",${host},"* ]]; then
    NO_PROXY="${NO_PROXY:+${NO_PROXY},}${host}"
    no_proxy="$NO_PROXY"
    export NO_PROXY no_proxy
  fi
}

telemetry_otel_region() {
  local endpoint header attrs
  endpoint="$(telemetry_otel_endpoint)"
  header="$(telemetry_otel_header)"
  attrs="service.name=codex,service.namespace=icodex,icodex.project=${ICODEX_TELEMETRY_PROJECT:-unknown},icodex.session_id=${ICODEX_TELEMETRY_SESSION_ID:-unknown},wrapper.version=$(cat "$ICODEX_ROOT/VERSION" 2>/dev/null || echo dev)"
  printf '%s\n' "$_TELEMETRY_OTEL_START"
  printf '[otel]\n'
  printf 'environment = "local"\n'
  printf 'log_user_prompt = false\n'
  printf 'resource_attributes = "%s"\n' "$attrs"
  printf '[otel.exporter.otlp]\n'
  printf 'endpoint = "%s"\n' "$endpoint"
  if [[ -n "$header" ]]; then
    printf 'headers = "%s"\n' "$header"
  fi
  printf '%s\n' "$_TELEMETRY_OTEL_END"
}

telemetry_otel_configure() { # <config.toml>
  local file="$1" tmp
  local endpoint
  endpoint="$(telemetry_otel_endpoint)"
  telemetry_url_host "$endpoint" >/dev/null || { log_error "invalid ICODEX_OTEL_ENDPOINT='$endpoint'"; return 1; }
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    awk -v s="$_TELEMETRY_OTEL_START" -v e="$_TELEMETRY_OTEL_END" '
      $0 == s { skip=1; next }
      $0 == e { skip=0; next }
      !skip { print }
    ' "$file" > "$tmp"
  fi
  telemetry_otel_region >> "$tmp"
  if [[ ! -f "$file" ]] || ! cmp -s "$tmp" "$file"; then
    cat "$tmp" > "$file"
  fi
  rm -f "$tmp"
  telemetry_no_proxy_add_host "$endpoint"
}
```

- [ ] **Step 4: Run OTel test**

Run:

```bash
bash tests/test_telemetry_otel.sh
```

Expected: `FAIL=0`.

- [ ] **Step 5: Commit Task 2**

```bash
git add lib/telemetry/otel.sh tests/test_telemetry_otel.sh
git commit -m "feat(telemetry): add codex otel metadata path"
```

## Task 3: Langfuse Capture Validation And Lifecycle

**Files:**
- Create: `lib/telemetry/langfuse.sh`
- Test: `tests/test_telemetry_langfuse.sh`

- [ ] **Step 1: Write failing Langfuse tests**

Create `tests/test_telemetry_langfuse.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/telemetry/telemetry.sh"
source "$ROOT/lib/telemetry/langfuse.sh"

unset ICODEX_LANGFUSE_BASE_URL ICODEX_LANGFUSE_PUBLIC_KEY ICODEX_LANGFUSE_SECRET_KEY
assert_exit "missing config fails" 1 telemetry_langfuse_validate_config

ICODEX_LANGFUSE_BASE_URL="https://example.com"
ICODEX_LANGFUSE_PUBLIC_KEY="pk-test"
ICODEX_LANGFUSE_SECRET_KEY="sk-test"
assert_exit "public langfuse rejected" 1 telemetry_langfuse_validate_config

ICODEX_LANGFUSE_BASE_URL="http://127.0.0.1:3000"
assert_exit "local langfuse accepted" 0 telemetry_langfuse_validate_config

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fake="$tmp/fake-capture"
cat > "$fake" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$$" > "$ICODEX_LANGFUSE_CAPTURE_PID_FILE"
while :; do sleep 1; done
EOF
chmod +x "$fake"

ICODEX_LANGFUSE_CAPTURE_BIN="$fake"
ICODEX_LANGFUSE_CAPTURE_PID_FILE="$tmp/capture.pid"
telemetry_langfuse_start_capture
pid="$(cat "$ICODEX_LANGFUSE_CAPTURE_PID_FILE")"
kill -0 "$pid" 2>/dev/null
assert_eq "capture process running" "0" "$?"
telemetry_langfuse_stop_capture
kill -0 "$pid" 2>/dev/null
assert_eq "capture process stopped" "1" "$?"

finish
```

- [ ] **Step 2: Run failing Langfuse test**

Run:

```bash
bash tests/test_telemetry_langfuse.sh
```

Expected: FAIL because `lib/telemetry/langfuse.sh` does not exist.

- [ ] **Step 3: Implement Langfuse module**

Create `lib/telemetry/langfuse.sh`:

```bash
#!/usr/bin/env bash
# Local trusted Langfuse full-capture lifecycle.

telemetry_langfuse_validate_config() {
  [[ -n "${ICODEX_LANGFUSE_BASE_URL:-}" ]] || { log_error "ICODEX_LANGFUSE_BASE_URL is required for langfuse telemetry"; return 1; }
  [[ -n "${ICODEX_LANGFUSE_PUBLIC_KEY:-}" ]] || { log_error "ICODEX_LANGFUSE_PUBLIC_KEY is required for langfuse telemetry"; return 1; }
  [[ -n "${ICODEX_LANGFUSE_SECRET_KEY:-}" ]] || { log_error "ICODEX_LANGFUSE_SECRET_KEY is required for langfuse telemetry"; return 1; }
  telemetry_url_is_local_trusted "$ICODEX_LANGFUSE_BASE_URL" || { log_error "ICODEX_LANGFUSE_BASE_URL must be local/trusted"; return 1; }
}

telemetry_langfuse_capture_bin() {
  printf '%s\n' "${ICODEX_LANGFUSE_CAPTURE_BIN:-$ICODEX_SHARED_DIR/bin/icodex-langfuse-capture}"
}

telemetry_langfuse_start_capture() {
  telemetry_langfuse_validate_config || return 1
  local bin pid_file
  bin="$(telemetry_langfuse_capture_bin)"
  [[ -x "$bin" ]] || { log_error "Langfuse capture binary missing: $bin"; return 1; }
  ICODEX_LANGFUSE_CAPTURE_PID_FILE="${ICODEX_LANGFUSE_CAPTURE_PID_FILE:-$ICODEX_HOME_DIR/langfuse-capture.pid}"
  export ICODEX_LANGFUSE_BASE_URL ICODEX_LANGFUSE_PUBLIC_KEY ICODEX_LANGFUSE_SECRET_KEY
  export ICODEX_TELEMETRY_PROJECT ICODEX_TELEMETRY_SESSION_ID ICODEX_LANGFUSE_CAPTURE_PID_FILE
  "$bin" &
  ICODEX_LANGFUSE_CAPTURE_PID="$!"
  export ICODEX_LANGFUSE_CAPTURE_PID
  sleep 0.1
  kill -0 "$ICODEX_LANGFUSE_CAPTURE_PID" 2>/dev/null || { log_error "Langfuse capture failed to start"; return 1; }
}

telemetry_langfuse_stop_capture() {
  local pid="${ICODEX_LANGFUSE_CAPTURE_PID:-}"
  [[ -n "$pid" ]] || return 0
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}
```

- [ ] **Step 4: Run Langfuse test**

Run:

```bash
bash tests/test_telemetry_langfuse.sh
```

Expected: `FAIL=0`.

- [ ] **Step 5: Commit Task 3**

```bash
git add lib/telemetry/langfuse.sh tests/test_telemetry_langfuse.sh
git commit -m "feat(telemetry): add langfuse capture lifecycle"
```

## Task 4: Launch Integration And Exit-Code Preservation

**Files:**
- Modify: `icodex.sh`
- Modify: `lib/launcher/launch.sh`
- Modify: `lib/telemetry/telemetry.sh`
- Test: `tests/test_telemetry_launch.sh`

- [ ] **Step 1: Write failing launch tests**

Create `tests/test_telemetry_launch.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/telemetry/telemetry.sh"
source "$ROOT/lib/launcher/launch.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fake="$tmp/codex"
cat > "$fake" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$ICODEX_TEST_ARGS_FILE"
exit "${ICODEX_TEST_EXIT_CODE:-0}"
EOF
chmod +x "$fake"

ICODEX_BIN="$fake"
ICODEX_TEST_ARGS_FILE="$tmp/args"
ICODEX_TEST_EXIT_CODE=7

launch_codex_wrapped exec "hello world"
rc="$?"
assert_eq "wrapped preserves exit code" "7" "$rc"
assert_eq "wrapped preserves args" "exec hello world" "$(cat "$ICODEX_TEST_ARGS_FILE")"

cleanup_file="$tmp/cleanup"
telemetry_register_cleanup "printf cleaned > '$cleanup_file'"
ICODEX_TEST_EXIT_CODE=0
launch_codex_wrapped run
assert_eq "cleanup ran" "cleaned" "$(cat "$cleanup_file")"

finish
```

- [ ] **Step 2: Run failing launch test**

Run:

```bash
bash tests/test_telemetry_launch.sh
```

Expected: FAIL because `launch_codex_wrapped` and `telemetry_register_cleanup` do not exist.

- [ ] **Step 3: Implement wrapped launch and cleanup registry**

Modify `lib/telemetry/telemetry.sh`, append:

```bash
_ICODEX_TELEMETRY_CLEANUPS=()

telemetry_register_cleanup() { # <shell-snippet>
  _ICODEX_TELEMETRY_CLEANUPS+=("$1")
}

telemetry_run_cleanups() {
  local item
  for item in "${_ICODEX_TELEMETRY_CLEANUPS[@]}"; do
    eval "$item"
  done
}
```

Modify `lib/launcher/launch.sh`:

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

launch_codex_wrapped() { # <args...>
  if [[ ! -x "$ICODEX_BIN" ]]; then
    log_error "codex binary missing — run: ./icodex.sh --install"
    return 1
  fi
  "$ICODEX_BIN" "$@"
  local rc=$?
  if command -v telemetry_run_cleanups >/dev/null 2>&1; then
    telemetry_run_cleanups
  fi
  return "$rc"
}
```

- [ ] **Step 4: Run launch test**

Run:

```bash
bash tests/test_telemetry_launch.sh
```

Expected: `FAIL=0`.

- [ ] **Step 5: Wire telemetry modules into `icodex.sh`**

Modify the source list in `icodex.sh` to include:

```bash
telemetry/telemetry telemetry/otel telemetry/langfuse
```

Add after `ensure_iwiki_binding` and before `install_ensure`:

```bash
telemetry_setup_context || exit 1
case "$ICODEX_TELEMETRY" in
  otel|both) telemetry_otel_configure "$ICODEX_HOME_DIR/config.toml" || exit 1 ;;
esac
case "$ICODEX_TELEMETRY" in
  langfuse|both)
    telemetry_langfuse_start_capture || exit 1
    telemetry_register_cleanup telemetry_langfuse_stop_capture
    ;;
esac
```

Replace final launch line:

```bash
if [[ "${ICODEX_TELEMETRY:-off}" == "off" ]]; then
  launch_codex ${ICODEX_PASSTHROUGH[@]+"${ICODEX_PASSTHROUGH[@]}"}
else
  launch_codex_wrapped ${ICODEX_PASSTHROUGH[@]+"${ICODEX_PASSTHROUGH[@]}"}
  exit $?
fi
```

- [ ] **Step 6: Run focused tests**

Run:

```bash
bash tests/test_telemetry_config.sh
bash tests/test_telemetry_otel.sh
bash tests/test_telemetry_langfuse.sh
bash tests/test_telemetry_launch.sh
```

Expected: all end with `FAIL=0`.

- [ ] **Step 7: Commit Task 4**

```bash
git add icodex.sh lib/launcher/launch.sh lib/telemetry/telemetry.sh tests/test_telemetry_launch.sh
git commit -m "feat(telemetry): wire telemetry into launch path"
```

## Task 5: Full-Capture Feasibility Probe

**Files:**
- Modify: `lib/telemetry/langfuse.sh`
- Create: `tests/test_telemetry_feasibility.sh`

- [ ] **Step 1: Write failing feasibility test**

Create `tests/test_telemetry_feasibility.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/telemetry/telemetry.sh"
source "$ROOT/lib/telemetry/langfuse.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cfg="$tmp/config.toml"
ICODEX_HOME_DIR="$tmp"
ICODEX_LANGFUSE_CAPTURE_PORT=18999
ICODEX_TELEMETRY_PROJECT="repo"
ICODEX_TELEMETRY_SESSION_ID="session"

telemetry_langfuse_write_provider_config "$cfg"
out="$(cat "$cfg")"
assert_contains "custom provider" "$out" "[model_providers.icodex-langfuse-capture]"
assert_contains "base url points local" "$out" "http://127.0.0.1:18999/v1"
assert_contains "provider marker" "$out" "# icodex:langfuse-provider:start"

finish
```

- [ ] **Step 2: Run failing feasibility test**

Run:

```bash
bash tests/test_telemetry_feasibility.sh
```

Expected: FAIL because `telemetry_langfuse_write_provider_config` does not exist.

- [ ] **Step 3: Implement provider config writer**

Append to `lib/telemetry/langfuse.sh`:

```bash
_TELEMETRY_LANGFUSE_PROVIDER_START="# icodex:langfuse-provider:start"
_TELEMETRY_LANGFUSE_PROVIDER_END="# icodex:langfuse-provider:end"

telemetry_langfuse_capture_port() {
  printf '%s\n' "${ICODEX_LANGFUSE_CAPTURE_PORT:-18765}"
}

telemetry_langfuse_provider_region() {
  local port
  port="$(telemetry_langfuse_capture_port)"
  printf '%s\n' "$_TELEMETRY_LANGFUSE_PROVIDER_START"
  printf '[model_providers.icodex-langfuse-capture]\n'
  printf 'name = "icodex-langfuse-capture"\n'
  printf 'base_url = "http://127.0.0.1:%s/v1"\n' "$port"
  printf 'env_key = "OPENAI_API_KEY"\n'
  printf 'wire_api = "responses"\n'
  printf 'stream_max_retries = 0\n'
  printf '%s\n' "$_TELEMETRY_LANGFUSE_PROVIDER_END"
}

telemetry_langfuse_write_provider_config() { # <config.toml>
  local file="$1" tmp
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    awk -v s="$_TELEMETRY_LANGFUSE_PROVIDER_START" -v e="$_TELEMETRY_LANGFUSE_PROVIDER_END" '
      $0 == s { skip=1; next }
      $0 == e { skip=0; next }
      !skip { print }
    ' "$file" > "$tmp"
  fi
  telemetry_langfuse_provider_region >> "$tmp"
  if [[ ! -f "$file" ]] || ! cmp -s "$tmp" "$file"; then
    cat "$tmp" > "$file"
  fi
  rm -f "$tmp"
}
```

- [ ] **Step 4: Run feasibility config test**

Run:

```bash
bash tests/test_telemetry_feasibility.sh
```

Expected: `FAIL=0`.

- [ ] **Step 5: Add human checkpoint note to implementation evidence**

Before proceeding to Task 6, run an actual local feasibility probe with the installed Codex version using a fake local capture server and a harmless prompt in a temporary workspace. Record the result in the eventual result report. If Codex cannot route a request through the custom provider without breaking auth, streaming, passthrough args, or exit-code preservation, stop implementation and report the blocker instead of continuing.

- [ ] **Step 6: Commit Task 5**

```bash
git add lib/telemetry/langfuse.sh tests/test_telemetry_feasibility.sh
git commit -m "feat(telemetry): add langfuse provider feasibility wiring"
```

## Task 6: Documentation

**Files:**
- Modify: `.codex_config.example`
- Modify: `docs/README.ru.md`
- Update iwiki page through MCP after implementation

- [ ] **Step 1: Update `.codex_config.example`**

Add this section after the iwiki section or before it if that keeps runtime observability near proxy settings:

```text
# Hybrid telemetry (off by default).
#
#   off      no telemetry, default
#   otel     metadata-only Codex OpenTelemetry for local collector/Grafana
#   langfuse full prompt/response capture to local trusted self-hosted Langfuse
#   both     otel + langfuse
#
# Langfuse capture intentionally records prompt and response content. Use it only
# with a local trusted Langfuse instance. Grafana/OTel remains metadata-only.
#ICODEX_TELEMETRY=off
#ICODEX_OTEL_ENDPOINT=http://127.0.0.1:4318
#ICODEX_OTEL_CREDENTIALS=otel:password
#ICODEX_LANGFUSE_BASE_URL=http://127.0.0.1:3000
#ICODEX_LANGFUSE_PUBLIC_KEY=pk-lf-...
#ICODEX_LANGFUSE_SECRET_KEY=sk-lf-...
```

- [ ] **Step 2: Update README**

Add a short Russian section to `docs/README.ru.md`:

```markdown
## Телеметрия

`icodex` поддерживает opt-in hybrid telemetry через `.codex_config`.

- `ICODEX_TELEMETRY=otel` включает metadata-only OpenTelemetry для local collector/Grafana.
- `ICODEX_TELEMETRY=langfuse` включает full prompt/response capture в local trusted Langfuse.
- `ICODEX_TELEMETRY=both` включает оба канала.
- По умолчанию telemetry выключена.

Grafana/OTel не получает prompt/response bodies. Full capture разрешён только для local trusted Langfuse URL.
```

- [ ] **Step 3: Run docs grep**

Run:

```bash
rg -n "ICODEX_TELEMETRY|ICODEX_OTEL|ICODEX_LANGFUSE|Телеметрия" .codex_config.example docs/README.ru.md
```

Expected: all six config variables and README section appear.

- [ ] **Step 4: Update iwiki**

Use `wiki_write_page` or `wiki_update_page` in domain `icodex` to document the new telemetry behavior after implementation. The page must state:

- telemetry is off by default;
- `otel` is metadata-only for Grafana;
- `langfuse` captures prompt/response content to local trusted Langfuse;
- `both` enables both;
- secrets stay in `.codex_config`.

Then run:

```text
wiki_lint(domain="icodex")
```

Expected: no new broken refs or stale page for telemetry docs.

- [ ] **Step 5: Commit Task 6**

```bash
git add .codex_config.example docs/README.ru.md
git commit -m "docs(telemetry): document hybrid telemetry config"
```

## Task 7: Final Verification

**Files:**
- All telemetry files from prior tasks
- Plan/result evidence

- [ ] **Step 1: Run focused telemetry tests**

```bash
bash tests/test_telemetry_config.sh
bash tests/test_telemetry_otel.sh
bash tests/test_telemetry_langfuse.sh
bash tests/test_telemetry_launch.sh
bash tests/test_telemetry_feasibility.sh
```

Expected: each script ends with `FAIL=0`.

- [ ] **Step 2: Run syntax checks for changed Bash files**

```bash
bash -n lib/telemetry/telemetry.sh
bash -n lib/telemetry/otel.sh
bash -n lib/telemetry/langfuse.sh
bash -n lib/launcher/launch.sh
bash -n icodex.sh
```

Expected: no output, exit code 0.

- [ ] **Step 3: Run full suite**

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: all tests pass.

- [ ] **Step 4: Check dirty diff for secrets**

```bash
git diff -- . ':!docs/superpowers/reports/*.html' | rg -n "sk-|pk-lf-|secret|password|Authorization=Basic" || true
```

Expected: only fake/example values or no output. No real secret values.

- [ ] **Step 5: Run result chain**

```text
/check-chain result docs/superpowers/plans/2026-07-08-icodex-telemetry.md
```

Expected: result report shows all plan tasks DONE or an explicit human checkpoint if full-capture feasibility failed.

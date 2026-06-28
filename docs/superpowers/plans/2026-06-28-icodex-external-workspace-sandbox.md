# icodex External Workspace Sandbox Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `icodex` launch Codex successfully from external workspaces by granting the isolated Codex launcher binary a narrow read-only sandbox permission.

**Architecture:** Add a small launch-time config helper that upserts a literal read-only `$ICODEX_BIN` entry into `[permissions.dev-safe.filesystem]` in the live `.codex-isolated/config.toml`. Source and call that helper only on the default launch path, after `setup_codex_home` resolves `CODEX_HOME`, and before plugin wiring or `install_ensure` can start Codex. Tests prove the helper is idempotent, corrects stale access, preserves existing deny rules, and does not run on `--install`/`--update`.

**Tech Stack:** Bash (`set -euo pipefail` entrypoint style), `awk`, dependency-free shell tests in `tests/`, Codex managed filesystem permissions in TOML.

---

## Global Constraints

- Work on branch `dev-icodex-external-workspace-sandbox` or the current approved `dev-*` branch. Do not commit to `main`, `master`, or `prod`.
- Conversation and questions are Russian. Code comments, docs, commit messages are English.
- Do not read auth, token, credential, secret, or denied environment files.
- Do not weaken existing `dev-safe` deny rules for secrets, environment files, tokens, `.ssh`, `.aws`, `.gnupg`, or kube config.
- Do not grant write access to `.codex-isolated/bin` or the whole `icodex` repository.
- Do not use `--add-dir` as the primary fix.
- Do not copy or install the Codex binary into target workspaces.
- Do not move `CODEX_HOME` back to global `~/.codex`.
- HUMAN CHECKPOINT: pause if Codex managed permissions cannot represent a literal read-only path entry for `$ICODEX_BIN`.

## Project Context

- Primary language: Bash.
- Test framework: dependency-free shell tests using `tests/helpers.sh`.
- `docs/wiki/` is not present in this workspace, so iwiki docs maintenance is skipped for this plan.
- `rg` and `tree` may be absent in the local environment; use `find`, `grep`, and `sed` in verification commands.
- Current launch order in `icodex.sh`: load config, parse args, install/update fast paths, then default launch setup/plugin/install/proxy/exec.

## File Structure

- Create `lib/config/permissions.sh`: isolated helper for launch-time sandbox permission edits. Owns TOML string escaping, idempotent filesystem permission upsert, and `ensure_launcher_binary_permission`.
- Modify `icodex.sh`: source `config/permissions` and call `ensure_launcher_binary_permission` only on the default launch path after `setup_codex_home`.
- Modify `tests/test_plugin.sh`: add focused coverage for the live config mutation, while preserving existing Superpowers wiring tests.
- Modify `tests/test_smoke.sh`: add orchestration guards that `icodex.sh` sources the permissions module, calls the helper on launch, and keeps install/update branches binary-only.
- No manual edit to `.codex-isolated/config.toml` is required for portability; the launcher updates the live file at runtime.

---

### Task 1: Add Failing Permission Wiring Tests

**Files:**
- Modify: `tests/test_plugin.sh`
- Test: `tests/test_plugin.sh`

- [ ] **Step 1: Replace `tests/test_plugin.sh` with a failing test that covers launcher binary permissions and existing Superpowers wiring**

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/config/permissions.sh"

# Build a fake isolated home with a vendored cache + committed config.
tmp="$(mktemp -d)"
export ICODEX_ROOT="$tmp"
export ICODEX_HOME_DIR="$tmp/.codex-isolated"
export ICODEX_BIN="$ICODEX_HOME_DIR/bin/codex"
CACHE="$ICODEX_HOME_DIR/plugins/cache/superpowers/superpowers/6.0.3"
MARKETPLACE="$ICODEX_HOME_DIR/tmp/marketplaces/superpowers"
mkdir -p "$CACHE/.codex-plugin" "$ICODEX_HOME_DIR/bin"
printf '{}' > "$CACHE/.codex-plugin/plugin.json"
cat > "$ICODEX_HOME_DIR/config.toml" <<'EOF'
[permissions.dev-safe.filesystem]
":minimal" = "read"
"~/.ssh" = "deny"
"~/.aws" = "deny"

[permissions.dev-safe.filesystem.":workspace_roots"]
"." = "write"
"**/.env" = "deny"
"**/.token" = "deny"
"**/secrets/**" = "deny"

[marketplaces.superpowers]
source_type = "local"
source = "__ICODEX_ROOT__/.codex-isolated/plugins/cache/superpowers/superpowers/<ver>"

[plugins."superpowers@superpowers"]
enabled = true
EOF

source "$ROOT/lib/plugin/superpowers.sh"

# 1. first run: add read-only launcher permission and keep plugin rewrite behavior
ensure_launcher_binary_permission
ensure_superpowers_wiring
cfg="$ICODEX_HOME_DIR/config.toml"
assert_eq "source rewritten to generated marketplace" "1" \
  "$(grep -c "^source = \"$MARKETPLACE\"$" "$cfg")"
assert_exit "marketplace manifest created" 0 test -f "$MARKETPLACE/.agents/plugins/marketplace.json"
assert_exit "api marketplace manifest created" 0 test -f "$MARKETPLACE/.agents/plugins/api_marketplace.json"
assert_exit "marketplace plugin path resolves" 0 test -f "$MARKETPLACE/plugins/superpowers/.codex-plugin/plugin.json"
assert_contains "manifest names superpowers" \
  "$(cat "$MARKETPLACE/.agents/plugins/marketplace.json")" '"name": "superpowers"'
assert_contains "manifest uses relative plugin path" \
  "$(cat "$MARKETPLACE/.agents/plugins/marketplace.json")" '"path": "./plugins/superpowers"'
assert_eq "codex binary allowed read-only" "1" \
  "$(grep -c "^\"$ICODEX_BIN\" = \"read\"$" "$cfg")"
assert_eq "codex bin directory not granted write" "0" \
  "$(grep -c "^\"$ICODEX_HOME_DIR/bin\" = \"write\"$" "$cfg")"
assert_eq "workspace env deny preserved" "1" \
  "$(grep -c '^"**/.env" = "deny"$' "$cfg")"
assert_eq "workspace token deny preserved" "1" \
  "$(grep -c '^"**/.token" = "deny"$' "$cfg")"
assert_eq "workspace secrets deny preserved" "1" \
  "$(grep -c '^"**/secrets/**" = "deny"$' "$cfg")"
assert_eq "ssh deny preserved" "1" \
  "$(grep -c '^"~/.ssh" = "deny"$' "$cfg")"

# 2. idempotent: a second call leaves the file byte-identical
before="$(cat "$cfg")"
ensure_launcher_binary_permission
ensure_superpowers_wiring
assert_eq "idempotent second call" "$before" "$(cat "$cfg")"

# 3. stale launcher permission is corrected to read-only
sed -i "s#^\"$ICODEX_BIN\" = \"read\"#\"$ICODEX_BIN\" = \"write\"#" "$cfg"
ensure_launcher_binary_permission
assert_eq "stale binary write corrected" "1" \
  "$(grep -c "^\"$ICODEX_BIN\" = \"read\"$" "$cfg")"
assert_eq "stale binary write removed" "0" \
  "$(grep -c "^\"$ICODEX_BIN\" = \"write\"$" "$cfg")"

# 4. CWD-independence: run from an unrelated dir, still resolves and rewrites
( cd /tmp && ensure_launcher_binary_permission && ensure_superpowers_wiring )
assert_eq "still correct after foreign CWD" "1" \
  "$(grep -c "^source = \"$MARKETPLACE\"$" "$cfg")"

# 5. stale source is corrected
sed -i 's#^source = .*#source = "/wrong/path"#' "$cfg"
ensure_superpowers_wiring
assert_eq "stale source corrected" "1" \
  "$(grep -c "^source = \"$MARKETPLACE\"$" "$cfg")"

# 6. other marketplace sections are untouched
printf '\n[marketplaces.other]\nsource = "/keep/me"\n' >> "$cfg"
ensure_superpowers_wiring
assert_eq "other section preserved" "1" "$(grep -c '^source = "/keep/me"$' "$cfg")"

# 7. missing cache -> warn, no crash, no rewrite
cfg_before_missing="$(cat "$cfg")"
rm -rf "$ICODEX_HOME_DIR/plugins"
warn="$(ensure_superpowers_wiring 2>&1 >/dev/null)"
assert_contains "warns when not vendored" "$warn" "not vendored"
assert_eq "config untouched on missing cache" "$cfg_before_missing" "$(cat "$cfg")"

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_plugin.sh`

Expected: FAIL before implementation with an error like:

```text
tests/test_plugin.sh: line 6: /.../lib/config/permissions.sh: No such file or directory
```

- [ ] **Step 3: Commit the failing test**

```bash
git add tests/test_plugin.sh
git commit -m "test(config): cover launcher binary sandbox permission"
```

---

### Task 2: Implement the Launch-Time Permission Helper

**Files:**
- Create: `lib/config/permissions.sh`
- Test: `tests/test_plugin.sh`

- [ ] **Step 1: Create `lib/config/permissions.sh`**

```bash
#!/usr/bin/env bash
# Launch-time permission wiring for paths icodex itself needs inside Codex's
# sandbox, even when the target workspace is a different repository.

_toml_basic_string_escape() { # <value>
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

_ensure_filesystem_permission_entry() { # <config> <path> <access>
  local config="$1" path="$2" access="$3" escaped tmp
  escaped="$(_toml_basic_string_escape "$path")"
  tmp="$(mktemp)"
  awk -v key="\"$escaped\"" -v access="$access" '
    BEGIN {
      section = "[permissions.dev-safe.filesystem]"
      line = key " = \"" access "\""
    }
    function emit_missing() {
      if (insec && !done) {
        print line
        done = 1
      }
    }
    /^\[/ {
      emit_missing()
      insec = ($0 == section)
      if (insec) found_section = 1
    }
    insec {
      trimmed = $0
      sub(/^[[:space:]]*/, "", trimmed)
      if (index(trimmed, key) == 1) {
        rest = substr(trimmed, length(key) + 1)
        if (rest ~ /^[[:space:]]*=/) {
          if (!done) {
            print line
            done = 1
          }
          next
        }
      }
    }
    { print }
    END {
      emit_missing()
      if (!found_section) {
        print ""
        print section
        print line
      }
    }
  ' "$config" > "$tmp"
  cmp -s "$tmp" "$config" || cat "$tmp" > "$config"
  rm -f "$tmp"
}

ensure_launcher_binary_permission() {
  local config="$ICODEX_HOME_DIR/config.toml"
  if [[ ! -f "$config" ]]; then
    log_error "missing $config — cannot configure launcher binary sandbox access"
    return 0
  fi
  _ensure_filesystem_permission_entry "$config" "$ICODEX_BIN" "read"
}
```

- [ ] **Step 2: Run the focused test to verify it passes**

Run: `bash tests/test_plugin.sh`

Expected: PASS lines for launcher permission insertion, idempotence, stale write correction, deny-rule preservation, and Superpowers wiring; final line:

```text
PASS=<number> FAIL=0
```

- [ ] **Step 3: Run syntax validation**

Run: `bash -n lib/config/permissions.sh tests/test_plugin.sh`

Expected: no output and exit code `0`.

- [ ] **Step 4: Commit the helper**

```bash
git add lib/config/permissions.sh tests/test_plugin.sh
git commit -m "fix(config): grant codex launcher read permission"
```

---

### Task 3: Wire the Helper Into the Default Launch Path

**Files:**
- Modify: `icodex.sh`
- Modify: `tests/test_smoke.sh`
- Test: `tests/test_smoke.sh`, `tests/test_plugin.sh`

- [ ] **Step 1: Replace `tests/test_smoke.sh` with orchestration guards**

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

# invoking via a symlink must resolve modules from the real script dir
td="$(mktemp -d)"
ln -s "$ROOT/icodex.sh" "$td/icodex"
out="$("$td/icodex" --help 2>&1)"; code=$?
assert_eq       "symlink invocation exit 0" "0" "$code"
assert_contains "symlink resolves modules"  "$out" "Usage:"
rm -rf "$td"

# launch guard: launch_codex returns 1 when the binary is absent
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/launcher/launch.sh"
ICODEX_BIN="/nonexistent/codex"
assert_exit "launch guard -> 1" 1 launch_codex --help

# icodex.sh must source the plugin module and call launch-time wiring
assert_eq "sources permissions module" "1" \
  "$(grep -c 'config/permissions' "$ROOT/icodex.sh")"
assert_eq "sources plugin module" "1" \
  "$(grep -c 'plugin/superpowers' "$ROOT/icodex.sh")"
assert_eq "calls wiring on launch" "1" \
  "$(grep -c 'ensure_superpowers_wiring' "$ROOT/icodex.sh")"
assert_eq "calls binary permission wiring on launch" "1" \
  "$(grep -c 'ensure_launcher_binary_permission' "$ROOT/icodex.sh")"

# install/update branch must NOT call launch-time wiring: the single-line
# install)/update) case branches must contain zero wiring calls.
assert_eq "install branch skips binary permission wiring" "0" \
  "$(grep -E 'install\)|update\)' "$ROOT/icodex.sh" | grep -c ensure_launcher_binary_permission)"
assert_eq "install branch skips superpowers wiring" "0" \
  "$(grep -E 'install\)|update\)' "$ROOT/icodex.sh" | grep -c ensure_superpowers_wiring)"

finish
```

- [ ] **Step 2: Run smoke test to verify it fails before orchestration is wired**

Run: `bash tests/test_smoke.sh`

Expected: FAIL on `sources permissions module` and/or `calls binary permission wiring on launch`.

- [ ] **Step 3: Modify `icodex.sh` to source `config/permissions`**

Replace the module list in `icodex.sh` with this block:

```bash
for m in core/logging core/init core/validation command/args \
         binary/detect binary/lockfile binary/install \
         config/isolated config/permissions config/env proxy/proxy symlink/symlink \
         plugin/superpowers plugin/iwiki launcher/launch; do
  # shellcheck source=/dev/null
  source "$ICODEX_ROOT/lib/$m.sh"
done
```

- [ ] **Step 4: Modify the default launch block in `icodex.sh`**

Replace the default launch block with:

```bash
# default: run
setup_codex_home
ensure_launcher_binary_permission
ensure_superpowers_wiring
ensure_iwiki_wiring
install_ensure || exit 1
(( ICODEX_DISABLE_PROXY )) || proxy_apply
launch_codex ${ICODEX_PASSTHROUGH[@]+"${ICODEX_PASSTHROUGH[@]}"}
```

- [ ] **Step 5: Run orchestration tests**

Run:

```bash
bash tests/test_smoke.sh
bash tests/test_plugin.sh
```

Expected: both scripts end with `FAIL=0`.

- [ ] **Step 6: Run syntax validation**

Run: `bash -n icodex.sh tests/test_smoke.sh`

Expected: no output and exit code `0`.

- [ ] **Step 7: Commit the launch wiring**

```bash
git add icodex.sh tests/test_smoke.sh
git commit -m "fix(launch): wire launcher sandbox permission"
```

---

### Task 4: Verify Runtime Config Mutation and Safety Boundaries

**Files:**
- Modify: none
- Test: `tests/test_plugin.sh`, `tests/test_smoke.sh`, all shell tests

- [ ] **Step 1: Run focused verification**

Run:

```bash
bash tests/test_plugin.sh
bash tests/test_smoke.sh
```

Expected: both scripts end with:

```text
FAIL=0
```

- [ ] **Step 2: Run the full shell test suite**

Run:

```bash
for t in tests/test_*.sh; do echo "== $t =="; bash "$t"; done
```

Expected: every test script ends with `FAIL=0`. If any unrelated pre-existing test fails, capture the failing script name and output before changing code.

- [ ] **Step 3: Run Bash syntax checks on changed shell files**

Run:

```bash
bash -n icodex.sh lib/config/permissions.sh tests/test_plugin.sh tests/test_smoke.sh
```

Expected: no output and exit code `0`.

- [ ] **Step 4: Trigger the default launch path far enough to rewrite live config**

Run:

```bash
./icodex.sh --help >/dev/null
```

Expected: exit code `0`. This command does not trigger the default launch path and should not be used as proof of config mutation.

Run the default launch path only if the local Codex binary is installed and it is acceptable to start Codex:

```bash
./icodex.sh -- --version
```

Expected: exit code `0`, or a Codex CLI version output. If the command cannot be run locally because the binary is absent or network installation is intentionally skipped, rely on `tests/test_plugin.sh` for config mutation proof and record that runtime launch was not exercised.

- [ ] **Step 5: Inspect the live config permission entry**

Run:

```bash
grep -F "\"$PWD/.codex-isolated/bin/codex\" = \"read\"" .codex-isolated/config.toml
```

Expected:

```text
"/absolute/path/to/icodex/.codex-isolated/bin/codex" = "read"
```

The printed path must be the actual `$ICODEX_BIN` path for this checkout.

- [ ] **Step 6: Confirm broad access was not introduced**

Run:

```bash
grep -F "\"$PWD/.codex-isolated/bin\" = \"write\"" .codex-isolated/config.toml
```

Expected: no output and exit code `1`.

Run:

```bash
grep -E '"\*\*/\.env" = "deny"|"\*\*/\.token" = "deny"|"\*\*/secrets/\*\*" = "deny"|"\*\*/\*\.pem" = "deny"|"\*\*/\*\.key" = "deny"' .codex-isolated/config.toml
```

Expected: output includes the existing deny entries for env files, tokens/secrets, and key material.

- [ ] **Step 7: Commit verification-only updates if any were required**

If no files changed during verification, do not commit.

If a small test correction was required, commit only that correction:

```bash
git add tests/test_plugin.sh tests/test_smoke.sh
git commit -m "test(launch): tighten launcher permission verification"
```

---

### Task 5: Final Review and Handoff

**Files:**
- Modify: none
- Test: git diff and status

- [ ] **Step 1: Review the final diff**

Run:

```bash
git diff --stat
git diff -- icodex.sh lib/config/permissions.sh tests/test_plugin.sh tests/test_smoke.sh
```

Expected: the diff is limited to:

```text
icodex.sh
lib/config/permissions.sh
tests/test_plugin.sh
tests/test_smoke.sh
```

Any unrelated file changes should be left untouched unless they were part of this task before execution started.

- [ ] **Step 2: Check branch and working tree**

Run:

```bash
git status --short --branch
```

Expected: current branch is `dev-*`. Working tree is clean except for unrelated pre-existing user changes that are explicitly out of scope.

- [ ] **Step 3: Record final verification evidence**

In the PR body or handoff note, include:

```markdown
Verification:
- bash tests/test_plugin.sh
- bash tests/test_smoke.sh
- for t in tests/test_*.sh; do echo "== $t =="; bash "$t"; done
- bash -n icodex.sh lib/config/permissions.sh tests/test_plugin.sh tests/test_smoke.sh

Runtime check:
- Live config contains `"/abs/path/to/.codex-isolated/bin/codex" = "read"`.
- Live config does not contain `"/abs/path/to/.codex-isolated/bin" = "write"`.
- Existing dev-safe deny rules for env, token, secrets, and key material remain present.
```

- [ ] **Step 4: Commit the final handoff only if documentation was edited**

If this plan is being executed and no documentation changed, do not create a commit.

If documentation was updated during execution, use:

```bash
git add docs/superpowers/plans/2026-06-28-icodex-external-workspace-sandbox.md
git commit -m "docs(plan): add external workspace sandbox plan"
```

---

## Self-Review

- Spec coverage: acceptance criteria map to Task 1 and Task 4. Root cause and chosen approach map to Task 2 and Task 3. Rejected approaches are captured in Global Constraints. Data flow maps to Task 3. Tests from the spec map to Task 1, Task 3, and Task 4.
- Placeholder scan: no prohibited placeholder markers remain.
- Type/name consistency: the plan consistently uses `ensure_launcher_binary_permission`, `_ensure_filesystem_permission_entry`, `_toml_basic_string_escape`, `ICODEX_HOME_DIR`, and `ICODEX_BIN`.

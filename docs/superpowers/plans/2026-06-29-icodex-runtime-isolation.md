---
review:
  plan_hash: "dd72062fdbb41998"
  spec_hash: "dca0402951279942"
  last_run: 2026-06-29
  phases:
    structure:     { status: passed }
    coverage:      { status: passed }
    dependencies:  { status: passed }
    verifiability: { status: passed }
    consistency:   { status: passed }
  findings:
    - id: F-001
      phase: dependencies
      severity: WARNING
      section: "Task 1 / Step 1"
      fragment: "note: test_env.sh sources lib/core/init.sh; confirm it does — if not, add source"
      text: >-
        test_env.sh does not currently source lib/core/init.sh; the hedged parenthetical could be
        skipped by an implementer appending bare asserts.
      fix: >-
        Reworded Step 1: sourcing lib/core/init.sh (with ICODEX_ROOT preset) is now a mandatory,
        unhedged part of the snippet.
      verdict: fixed
    - id: F-002
      phase: verifiability
      severity: INFO
      section: "Task 4 / Step 1 (test_isolated.sh)"
      fragment: "Run from a non-git working dir so resolve_project_root falls back to pwd -P"
      text: >-
        Test assumed mktemp dir under /tmp is not inside a git repo; would break on a host whose
        TMPDIR sits inside a checkout.
      fix: >-
        Added `export GIT_CEILING_DIRECTORIES="$tmp"` before resolve_codex_home so git cannot
        ascend above tmp.
      verdict: fixed
    - id: F-003
      phase: consistency
      severity: INFO
      section: "Task 3 / Step 3 vs superpowers.sh:9"
      fragment: "Update the function's doc comment (line 9) to read: Anchored at $ICODEX_SHARED_DIR"
      text: >-
        Current doc comment says $ICODEX_ROOT while code globs $ICODEX_HOME_DIR; Task 3 already
        fixes both glob and comment to $ICODEX_SHARED_DIR. End state consistent.
      fix: No change needed — plan already corrects the comment in the same step.
      verdict: wontfix
chain:
  intent: docs/superpowers/intents/2026-06-28-icodex-external-workspace-sandbox-intent.md
  spec: docs/superpowers/specs/2026-06-29-icodex-runtime-isolation-design.md
---

# icodex Runtime Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make icodex isolation explicit and safe by default — per-project `CODEX_HOME` plus a `workspace-write` sandbox default with explicit escalation.

**Architecture:** Split the single `ICODEX_HOME_DIR` into a stable shared store (`.codex-isolated`: binary, uv, plugin cache, shared `auth.json`, config template) and a dynamic per-project home under `.codex-homes/<id>` exported as `CODEX_HOME`. The per-project home symlinks the shared `plugins` and `auth.json`, copies the config template once, and has its managed lines (sandbox mode, marketplace source, binary grant, project trust) upserted idempotently each run. Sandbox defaults to `workspace-write`; `--full-access` / `ICODEX_SANDBOX` escalate to `danger-full-access` with a stderr warning.

**Tech Stack:** Bash (`set -euo pipefail`), awk, `ln`, `git`, `_sha256`. No new dependencies. Tests are standalone bash sourcing `tests/helpers.sh`.

## Global Constraints

- Bash with `#!/usr/bin/env bash`; `set -euo pipefail` in `lib/`, `set -uo pipefail` in tests. (verbatim from spec / AGENTS.md)
- Dependency-light: only bash / awk / ln / git / `_sha256`. No new tools.
- Two-space indentation inside functions; functions `lowercase_with_underscores`; wrapper env vars use the `ICODEX_` prefix.
- `approval_policy` is NEVER changed by this work — only `sandbox_mode`.
- Sandbox allowed values, verbatim: `read-only`, `workspace-write`, `danger-full-access`. Default `workspace-write`.
- Warning string, verbatim (after the `[icodex] WARN:` prefix from `log_warn`): `sandbox = danger-full-access — full filesystem access enabled (project: <id>)`.
- Per-project home id, verbatim: `<basename>-<short-sha256>` where short = first 12 hex chars of `_sha256` over the absolute project root.
- Run the full suite with: `for t in tests/test_*.sh; do bash "$t" || exit 1; done`.

---

### Task 1: Split shared vs home paths in init.sh

**Files:**
- Modify: `lib/core/init.sh`
- Test: `tests/test_env.sh` (extend)

**Interfaces:**
- Produces: globals `ICODEX_SHARED_DIR` (= `$ICODEX_ROOT/.codex-isolated`), `ICODEX_HOMES_DIR` (= `$ICODEX_ROOT/.codex-homes`), `ICODEX_PROJECT_ROOT` (default `""`, set later by `resolve_codex_home`). `ICODEX_BIN` and `ICODEX_STAMP` now derive from `ICODEX_SHARED_DIR/bin` (paths byte-identical to before). `ICODEX_HOME_DIR` keeps a placeholder default `= $ICODEX_SHARED_DIR` (overwritten per run in Task 4).

- [ ] **Step 1: Write the failing test** — append to `tests/test_env.sh` before `finish`. `test_env.sh` does NOT currently source `lib/core/init.sh`, so this snippet sources it (with `ICODEX_ROOT` preset, which init.sh honors via its `: "${ICODEX_ROOT:=...}"` default). Add it verbatim:

```bash
# --- path split: shared store vs per-project homes (Task 1) ---
ICODEX_ROOT="/proj"
source "$ROOT/lib/core/init.sh"
assert_eq "shared dir"  "/proj/.codex-isolated" "$ICODEX_SHARED_DIR"
assert_eq "homes dir"   "/proj/.codex-homes"    "$ICODEX_HOMES_DIR"
assert_eq "bin in shared"   "/proj/.codex-isolated/bin/codex"         "$ICODEX_BIN"
assert_eq "stamp in shared" "/proj/.codex-isolated/bin/.codex-version" "$ICODEX_STAMP"
assert_eq "project root default empty" "" "$ICODEX_PROJECT_ROOT"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_env.sh`
Expected: FAIL — `ICODEX_SHARED_DIR` unbound / empty.

- [ ] **Step 3: Edit `lib/core/init.sh`** — replace lines 5-10 (the `ICODEX_HOME_DIR` / `ICODEX_BIN` / `ICODEX_STAMP` / `ICODEX_LOCKFILE` / `ICODEX_CONFIG` / `ICODEX_PROJECT_ID` block) so the head reads:

```bash
ICODEX_SHARED_DIR="$ICODEX_ROOT/.codex-isolated"   # stable shared store (assets)
ICODEX_HOMES_DIR="$ICODEX_ROOT/.codex-homes"       # parent of per-project homes
ICODEX_HOME_DIR="$ICODEX_SHARED_DIR"               # placeholder; set per run in setup_codex_home
ICODEX_PROJECT_ROOT=""                             # set per run in resolve_codex_home
ICODEX_BIN="$ICODEX_SHARED_DIR/bin/codex"
ICODEX_STAMP="$ICODEX_SHARED_DIR/bin/.codex-version"
ICODEX_LOCKFILE="$ICODEX_ROOT/.codex-lockfile.json"
ICODEX_CONFIG="$ICODEX_ROOT/.codex_config"
ICODEX_PROJECT_ID="$(basename "$ICODEX_ROOT")"
ICODEX_REPO="openai/codex"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_env.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/init.sh tests/test_env.sh
git commit -m "refactor(init): split shared store and per-project home paths"
```

---

### Task 2: Point binary/uv install at the shared store

**Files:**
- Modify: `lib/binary/install.sh` (replace `$ICODEX_HOME_DIR/bin` with `$ICODEX_SHARED_DIR/bin`)
- Test: `tests/test_install.sh` (extend fixture)

**Interfaces:**
- Consumes: `ICODEX_SHARED_DIR` (Task 1).
- Produces: `ensure_uv_dependency` installs uv to `$ICODEX_SHARED_DIR/bin/uv`; `_extract_codex` stages into `$ICODEX_SHARED_DIR/bin`. Binary paths unchanged at runtime because `ICODEX_BIN` already points there.

- [ ] **Step 1: Make the test fixture shared-aware** — in `tests/test_install.sh` `setup_case()`, add after the `ICODEX_HOME_DIR=...` line (line 16):

```bash
  ICODEX_SHARED_DIR="$ICODEX_HOME_DIR"   # in tests the home IS the shared store
```

(Existing assertions reference `$ICODEX_HOME_DIR/bin/uv`; with `ICODEX_SHARED_DIR == ICODEX_HOME_DIR` they keep passing once the source is repointed.)

- [ ] **Step 2: Run test to verify current state** — it still passes (fixture sets both equal, source not yet changed):

Run: `bash tests/test_install.sh`
Expected: PASS (this step only proves the fixture change is non-breaking).

- [ ] **Step 3: Repoint `lib/binary/install.sh`** — replace every `$ICODEX_HOME_DIR/bin` with `$ICODEX_SHARED_DIR/bin`. Exact occurrences:
  - line 62: `local target="$ICODEX_SHARED_DIR/bin/uv" source`
  - line 69: `mkdir -p "$ICODEX_SHARED_DIR/bin"`
  - line 75: `if ! _install_uv_from_network "$ICODEX_SHARED_DIR/bin"; then`
  - line 94: `mkdir -p "$ICODEX_SHARED_DIR/bin"`
  - line 95: `install_tmp="$ICODEX_SHARED_DIR/bin/.codex.new.$$"`

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_install.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/binary/install.sh tests/test_install.sh
git commit -m "refactor(binary): install codex + uv into the shared store"
```

---

### Task 3: Read the plugin cache from the shared store

**Files:**
- Modify: `lib/plugin/superpowers.sh:12` (cache glob root)
- Test: `tests/test_plugin.sh` (add shared var to fixture)

**Interfaces:**
- Consumes: `ICODEX_SHARED_DIR` (Task 1).
- Produces: `_superpowers_cache_dir` globs `$ICODEX_SHARED_DIR/plugins/cache/*`; the marketplace root, manifest, and `source` rewrite continue to target `$ICODEX_HOME_DIR` (per-project).

- [ ] **Step 1: Make the test fixture shared-aware** — in `tests/test_plugin.sh`, add after line 11 (`export ICODEX_HOME_DIR=...`):

```bash
export ICODEX_SHARED_DIR="$ICODEX_HOME_DIR"   # cache lives in the shared store
```

Also update the missing-cache step (line 109) to remove the cache from the shared path — change `rm -rf "$ICODEX_HOME_DIR/plugins"` to `rm -rf "$ICODEX_SHARED_DIR/plugins"` (identical path in this test, but expresses intent).

- [ ] **Step 2: Run test to verify it still fails on the not-yet-changed source** — it should still PASS here (paths equal), proving the fixture edit is safe:

Run: `bash tests/test_plugin.sh`
Expected: PASS.

- [ ] **Step 3: Repoint the cache glob** — in `lib/plugin/superpowers.sh`, change line 12 inside `_superpowers_cache_dir`:

```bash
  for m in "$ICODEX_SHARED_DIR"/plugins/cache/*/superpowers/*/; do
```

Update the function's doc comment (line 9) to read: `# Anchored at $ICODEX_SHARED_DIR so the glob is independent of the process CWD and the per-project home.`

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_plugin.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/plugin/superpowers.sh tests/test_plugin.sh
git commit -m "refactor(plugin): glob the vendored cache from the shared store"
```

---

### Task 4: Per-project home resolution + setup_codex_home

**Files:**
- Modify: `lib/config/isolated.sh` (rewrite)
- Modify: `.gitignore` (ignore `.codex-homes/`)
- Test: `tests/test_isolated.sh` (rewrite)

**Interfaces:**
- Consumes: `ICODEX_SHARED_DIR`, `ICODEX_HOMES_DIR`, `_sha256` (init.sh).
- Produces:
  - `resolve_project_root()` → echoes the git toplevel of `$PWD`, else `pwd -P`.
  - `resolve_codex_home()` → sets `ICODEX_PROJECT_ROOT` and `ICODEX_HOME_DIR="$ICODEX_HOMES_DIR/<basename>-<short-sha256>"`.
  - `setup_codex_home()` → resolves the home, creates it, symlinks `plugins` and `auth.json` to the shared store, copies the template `config.toml` if absent, exports `CODEX_HOME`.
  - `setup_shared_dirs()` → `mkdir -p "$ICODEX_SHARED_DIR/bin"` (used by install/update in Task 8).

- [ ] **Step 1: Write the failing test** — replace the whole body of `tests/test_isolated.sh` with:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

tmp="$(mktemp -d)"
ICODEX_ROOT="$tmp"
source "$ROOT/lib/core/init.sh"     # defines ICODEX_SHARED_DIR/HOMES_DIR/_sha256
source "$ROOT/lib/config/isolated.sh"

# Build a shared store fixture: plugins dir + config template
mkdir -p "$ICODEX_SHARED_DIR/plugins"
printf 'sandbox_mode = "workspace-write"\n' > "$ICODEX_SHARED_DIR/config.toml"

# Run from a non-git working dir so resolve_project_root falls back to pwd -P
work="$tmp/work/sub"; mkdir -p "$work"
unset CODEX_HOME
( cd "$work" && declare -f >/dev/null )   # no-op guard

cd "$work"
export GIT_CEILING_DIRECTORIES="$tmp"   # keep git from finding a repo above tmp on CI hosts
resolve_codex_home
want_hash="$(printf '%s' "$work" | _sha256 | cut -c1-12)"
assert_eq "project root is cwd"   "$work" "$ICODEX_PROJECT_ROOT"
assert_eq "home id basename+hash" "$ICODEX_HOMES_DIR/sub-$want_hash" "$ICODEX_HOME_DIR"

setup_codex_home
assert_eq  "CODEX_HOME exported" "$ICODEX_HOME_DIR" "${CODEX_HOME:-}"
assert_exit "home created"       0 test -d "$ICODEX_HOME_DIR"
assert_exit "plugins symlink"    0 test -L "$ICODEX_HOME_DIR/plugins"
assert_eq  "plugins -> shared"   "$ICODEX_SHARED_DIR/plugins" "$(readlink "$ICODEX_HOME_DIR/plugins")"
assert_exit "auth symlink"       0 test -L "$ICODEX_HOME_DIR/auth.json"
assert_eq  "auth -> shared"      "$ICODEX_SHARED_DIR/auth.json" "$(readlink "$ICODEX_HOME_DIR/auth.json")"
assert_exit "config copied"      0 test -f "$ICODEX_HOME_DIR/config.toml"

# idempotent: a second setup leaves the symlinks intact and does not clobber config edits
printf 'edited = true\n' >> "$ICODEX_HOME_DIR/config.toml"
before="$(cat "$ICODEX_HOME_DIR/config.toml")"
setup_codex_home
assert_eq "config not clobbered on re-run" "$before" "$(cat "$ICODEX_HOME_DIR/config.toml")"

# setup_shared_dirs makes the shared bin dir
setup_shared_dirs
assert_exit "shared bin dir" 0 test -d "$ICODEX_SHARED_DIR/bin"

cd "$ROOT"
rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_isolated.sh`
Expected: FAIL — `resolve_codex_home`/`setup_shared_dirs` not defined.

- [ ] **Step 3: Rewrite `lib/config/isolated.sh`** with:

```bash
#!/usr/bin/env bash
# Per-project CODEX_HOME isolation. Expensive assets (binary, uv, plugin cache,
# auth) live in the shared store ($ICODEX_SHARED_DIR); per-project state lives in
# a home under $ICODEX_HOMES_DIR keyed by the target project root.

# Echo the target project root: the git toplevel of the CWD, else the real CWD.
resolve_project_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd -P
}

# Set ICODEX_PROJECT_ROOT and the per-project ICODEX_HOME_DIR.
resolve_codex_home() {
  local hash id
  ICODEX_PROJECT_ROOT="$(resolve_project_root)"
  hash="$(printf '%s' "$ICODEX_PROJECT_ROOT" | _sha256 | cut -c1-12)"
  id="$(basename "$ICODEX_PROJECT_ROOT")-$hash"
  ICODEX_HOME_DIR="$ICODEX_HOMES_DIR/$id"
}

# Symlink a shared-store entry into the per-project home (idempotent).
_link_shared() { # <name>
  local name="$1" target="$ICODEX_HOME_DIR/$name" src="$ICODEX_SHARED_DIR/$name"
  [[ -L "$target" ]] && return 0
  rm -rf "$target" 2>/dev/null || true
  ln -s "$src" "$target"
}

# Create the shared bin dir (install/update path; no per-project home needed).
setup_shared_dirs() {
  mkdir -p "$ICODEX_SHARED_DIR/bin"
}

# Build the per-project home and export CODEX_HOME (run path).
setup_codex_home() {
  resolve_codex_home
  mkdir -p "$ICODEX_HOME_DIR"
  _link_shared plugins
  _link_shared auth.json
  [[ -f "$ICODEX_HOME_DIR/config.toml" ]] \
    || cp "$ICODEX_SHARED_DIR/config.toml" "$ICODEX_HOME_DIR/config.toml"
  export CODEX_HOME="$ICODEX_HOME_DIR"
}
```

- [ ] **Step 4: Add `.codex-homes/` to `.gitignore`** — append after the `.codex_config` block:

```
# Per-project CODEX_HOME directories — runtime state, never committed
.codex-homes/
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test_isolated.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/config/isolated.sh tests/test_isolated.sh .gitignore
git commit -m "feat(config): per-project CODEX_HOME with shared plugins and auth"
```

---

### Task 5: Sandbox mode resolution and idempotent upsert

**Files:**
- Create: `lib/config/sandbox.sh`
- Test: `tests/test_sandbox.sh` (new)

**Interfaces:**
- Consumes: `ICODEX_HOME_DIR` (Task 4), `log_warn`/`log_error` (logging.sh), `ICODEX_SANDBOX` (config env, optional), `ICODEX_FULL_ACCESS` (flag, Task 6; default 0).
- Produces:
  - `resolve_sandbox_mode()` → echoes effective mode; precedence `default(workspace-write) < ICODEX_SANDBOX < ICODEX_FULL_ACCESS`. Returns 1 + `log_error` on an invalid `ICODEX_SANDBOX`.
  - `_upsert_toml_toplevel <config> <key> <value>` → idempotent awk upsert of a top-level `key = "value"` line.
  - `apply_sandbox_mode()` → resolves the mode, upserts `sandbox_mode` into `$ICODEX_HOME_DIR/config.toml`, warns on `danger-full-access`. Returns 1 if resolution fails.

- [ ] **Step 1: Write the failing test** — create `tests/test_sandbox.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/config/sandbox.sh"

tmp="$(mktemp -d)"
ICODEX_HOME_DIR="$tmp/home"; mkdir -p "$ICODEX_HOME_DIR"
seed() { printf 'bypass_hook_trust = true\nsandbox_mode = "danger-full-access"\napproval_policy = "on-request"\n\n[features]\nmulti_agent = true\n' > "$ICODEX_HOME_DIR/config.toml"; }

# precedence: default is workspace-write
unset ICODEX_SANDBOX; ICODEX_FULL_ACCESS=0
assert_eq "default mode" "workspace-write" "$(resolve_sandbox_mode)"

# env overrides default
ICODEX_SANDBOX="read-only"
assert_eq "env mode" "read-only" "$(resolve_sandbox_mode)"

# flag overrides env
ICODEX_FULL_ACCESS=1
assert_eq "flag overrides env" "danger-full-access" "$(resolve_sandbox_mode)"

# invalid env -> non-zero
ICODEX_FULL_ACCESS=0; ICODEX_SANDBOX="bogus"
( resolve_sandbox_mode >/dev/null 2>&1 ); assert_eq "invalid env nonzero" "1" "$?"

# apply upserts the top-level key (replaces existing danger-full-access)
unset ICODEX_SANDBOX; ICODEX_FULL_ACCESS=0; seed
apply_sandbox_mode
assert_eq "sandbox upserted to default" "1" \
  "$(grep -cFx 'sandbox_mode = "workspace-write"' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "old danger value removed" "0" \
  "$(grep -cFx 'sandbox_mode = "danger-full-access"' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "approval_policy untouched" "1" \
  "$(grep -cFx 'approval_policy = "on-request"' "$ICODEX_HOME_DIR/config.toml")"

# idempotent: second apply is byte-identical
before="$(cat "$ICODEX_HOME_DIR/config.toml")"
apply_sandbox_mode
assert_eq "apply idempotent" "$before" "$(cat "$ICODEX_HOME_DIR/config.toml")"

# danger-full-access prints the warning
ICODEX_FULL_ACCESS=1; seed
warn="$(apply_sandbox_mode 2>&1 >/dev/null)"
assert_contains "warns on full access" "$warn" "full filesystem access enabled"

# upsert inserts the key when absent, before the first section
printf '[features]\nx = 1\n' > "$ICODEX_HOME_DIR/bare.toml"
_upsert_toml_toplevel "$ICODEX_HOME_DIR/bare.toml" sandbox_mode "workspace-write"
assert_eq "inserted before section" "1" \
  "$(grep -cFx 'sandbox_mode = "workspace-write"' "$ICODEX_HOME_DIR/bare.toml")"
head1="$(head -1 "$ICODEX_HOME_DIR/bare.toml")"
assert_eq "inserted at top" 'sandbox_mode = "workspace-write"' "$head1"

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_sandbox.sh`
Expected: FAIL — `lib/config/sandbox.sh` does not exist.

- [ ] **Step 3: Create `lib/config/sandbox.sh`:**

```bash
#!/usr/bin/env bash
# Effective sandbox mode resolution and idempotent config write.
# Precedence (low -> high): workspace-write default < ICODEX_SANDBOX < --full-access.
# approval_policy is never touched here; only sandbox_mode is managed.

# Echo the effective sandbox mode; return 1 + log_error on an invalid ICODEX_SANDBOX.
resolve_sandbox_mode() {
  if (( ${ICODEX_FULL_ACCESS:-0} )); then
    printf 'danger-full-access\n'
    return 0
  fi
  local mode="${ICODEX_SANDBOX:-workspace-write}"
  case "$mode" in
    read-only|workspace-write|danger-full-access) printf '%s\n' "$mode" ;;
    *) log_error "invalid ICODEX_SANDBOX '$mode' (want: read-only|workspace-write|danger-full-access)"; return 1 ;;
  esac
}

# Idempotently upsert a top-level `key = "value"` line (before the first [section]).
_upsert_toml_toplevel() { # <config> <key> <value>
  local config="$1" key="$2" val="$3" tmp
  tmp="$(mktemp)"
  awk -v key="$key" -v val="$val" '
    BEGIN { done = 0 }
    /^[[:space:]]*\[/ {
      if (!done) { print key " = \"" val "\""; done = 1 }
      print; next
    }
    !done && $0 ~ ("^[[:space:]]*" key "[[:space:]]*=") {
      print key " = \"" val "\""; done = 1; next
    }
    { print }
    END { if (!done) print key " = \"" val "\"" }
  ' "$config" > "$tmp"
  cmp -s "$tmp" "$config" || cat "$tmp" > "$config"
  rm -f "$tmp"
}

# Resolve and write sandbox_mode into the per-project config; warn on full access.
apply_sandbox_mode() {
  local config="$ICODEX_HOME_DIR/config.toml" mode
  mode="$(resolve_sandbox_mode)" || return 1
  _upsert_toml_toplevel "$config" sandbox_mode "$mode"
  if [[ "$mode" == "danger-full-access" ]]; then
    log_warn "sandbox = danger-full-access — full filesystem access enabled (project: $(basename "$ICODEX_HOME_DIR"))"
  fi
  return 0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_sandbox.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/config/sandbox.sh tests/test_sandbox.sh
git commit -m "feat(config): safe-by-default sandbox mode with explicit escalation"
```

---

### Task 6: --full-access flag

**Files:**
- Modify: `lib/command/args.sh` (flag var + case + help)
- Test: `tests/test_args.sh` (extend)

**Interfaces:**
- Consumes: nothing new.
- Produces: global `ICODEX_FULL_ACCESS` (default 0; set to 1 by `--full-access`), consumed by `resolve_sandbox_mode` (Task 5).

- [ ] **Step 1: Write the failing test** — in `tests/test_args.sh`, add `ICODEX_FULL_ACCESS=0` to the `reset()` helper (line 8) and append before `finish`:

```bash
reset; parse_args --full-access
assert_eq "full-access sets flag" "1" "$ICODEX_FULL_ACCESS"
assert_eq "full-access keeps run cmd" "run" "$ICODEX_CMD"

reset; parse_args --full-access -- foo
assert_eq "full-access then passthrough" "foo" "${ICODEX_PASSTHROUGH[*]}"

assert_contains "help documents full-access" "$(print_help)" "--full-access"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_args.sh`
Expected: FAIL — `ICODEX_FULL_ACCESS` unbound / flag unrecognized (`--full-access` lands in passthrough).

- [ ] **Step 3: Edit `lib/command/args.sh`:**
  - After line 6 (`ICODEX_PASSTHROUGH=()`), add: `ICODEX_FULL_ACCESS=0`
  - In the `case` (after the `--no-proxy` line ~14), add:

```bash
      --full-access) ICODEX_FULL_ACCESS=1; shift ;;
```

  - In `print_help`, add under the flags list (after the `--no-proxy` lines):

```
  --full-access   Escalate sandbox to danger-full-access for this run (prints a warning)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_args.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/command/args.sh tests/test_args.sh
git commit -m "feat(args): add --full-access sandbox escalation flag"
```

---

### Task 7: Auto-trust the launched project

**Files:**
- Modify: `lib/config/permissions.sh` (add `ensure_project_trust`)
- Test: `tests/test_trust.sh` (new)

**Interfaces:**
- Consumes: `_toml_basic_string_escape` (permissions.sh).
- Produces: `ensure_project_trust <config> <root>` → idempotently appends a `[projects."<root>"]` block with `trust_level = "trusted"` when absent. Governs trust only; does not alter `approval_policy`.

- [ ] **Step 1: Write the failing test** — create `tests/test_trust.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/config/permissions.sh"

tmp="$(mktemp -d)"
cfg="$tmp/config.toml"
printf 'sandbox_mode = "workspace-write"\napproval_policy = "on-request"\n' > "$cfg"
root="/home/user/Project/some-repo"

ensure_project_trust "$cfg" "$root"
assert_eq "trust block added" "1" "$(grep -cF "[projects.\"$root\"]" "$cfg")"
assert_eq "trust level trusted" "1" "$(grep -cFx 'trust_level = "trusted"' "$cfg")"
assert_eq "approval_policy untouched" "1" "$(grep -cFx 'approval_policy = "on-request"' "$cfg")"

# idempotent: a second call adds no duplicate block
ensure_project_trust "$cfg" "$root"
assert_eq "trust block not duplicated" "1" "$(grep -cF "[projects.\"$root\"]" "$cfg")"

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_trust.sh`
Expected: FAIL — `ensure_project_trust` not defined.

- [ ] **Step 3: Append to `lib/config/permissions.sh`:**

```bash
# Idempotently mark the launched project as trusted in the per-project config.
# Governs project trust only; it does not change approval_policy.
ensure_project_trust() { # <config> <project_root>
  local config="$1" root="$2" escaped
  [[ -f "$config" ]] || return 0
  escaped="$(_toml_basic_string_escape "$root")"
  grep -qF "[projects.\"$escaped\"]" "$config" && return 0
  printf '\n[projects."%s"]\ntrust_level = "trusted"\n' "$escaped" >> "$config"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_trust.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/config/permissions.sh tests/test_trust.sh
git commit -m "feat(config): auto-trust the launched project in its per-project config"
```

---

### Task 8: Wire the new run path in icodex.sh

**Files:**
- Modify: `icodex.sh` (source `config/sandbox`; install/update use `setup_shared_dirs`; run path adds sandbox + trust)
- Test: `tests/test_smoke.sh` (update launch-order awk + add sandbox source assertion)

**Interfaces:**
- Consumes: `setup_codex_home`, `setup_shared_dirs` (Task 4), `apply_sandbox_mode` (Task 5), `ensure_project_trust` (Task 7), `ICODEX_PROJECT_ROOT` (Task 4).
- Produces: the final run-path ordering (below). Install/update create no per-project home.

Run-path order (the awk in the smoke test asserts exactly this):

```bash
  setup_codex_home
  apply_sandbox_mode || exit 1
  ensure_project_trust "$ICODEX_HOME_DIR/config.toml" "$ICODEX_PROJECT_ROOT"
  ensure_launcher_binary_permission
  ensure_superpowers_wiring
  install_ensure || exit 1
  ensure_uv_dependency || exit 1
  (( ICODEX_DISABLE_PROXY )) || proxy_apply
  launch_codex ${ICODEX_PASSTHROUGH[@]+"${ICODEX_PASSTHROUGH[@]}"}
```

- [ ] **Step 1: Update the smoke test** — in `tests/test_smoke.sh`:

  (a) Add a sandbox-source assertion after the existing `sources plugin module` assertion (~line 34):

```bash
assert_eq "sources sandbox module" "1" \
  "$(grep -c 'config/sandbox' "$ROOT/icodex.sh")"
```

  (b) Add wiring-call assertions near the other launch-wiring asserts (~line 42):

```bash
assert_eq "calls apply_sandbox_mode on launch" "1" \
  "$(grep -Ec '^[[:space:]]*apply_sandbox_mode \|\| exit 1[[:space:]]*$' "$ROOT/icodex.sh")"
assert_eq "calls ensure_project_trust on launch" "1" \
  "$(grep -Ec '^[[:space:]]*ensure_project_trust ' "$ROOT/icodex.sh")"
```

  (c) Replace the launch-order awk block (lines 45-55) with one that includes the new steps:

```bash
launch_order_ok="$(awk '
  /# default: run/ { inblock = 1; step = 0; next }
  inblock && /^[[:space:]]*setup_codex_home[[:space:]]*$/ && step == 0 { step = 1; next }
  inblock && /^[[:space:]]*apply_sandbox_mode \|\| exit 1[[:space:]]*$/ && step == 1 { step = 2; next }
  inblock && /^[[:space:]]*ensure_project_trust / && step == 2 { step = 3; next }
  inblock && /^[[:space:]]*ensure_launcher_binary_permission[[:space:]]*$/ && step == 3 { step = 4; next }
  inblock && /^[[:space:]]*ensure_superpowers_wiring[[:space:]]*$/ && step == 4 { step = 5; next }
  inblock && /^[[:space:]]*install_ensure \|\| exit 1[[:space:]]*$/ && step == 5 { step = 6; next }
  inblock && /^[[:space:]]*ensure_uv_dependency \|\| exit 1[[:space:]]*$/ && step == 6 { step = 7; next }
  inblock && /^[[:space:]]*\(\([[:space:]]*ICODEX_DISABLE_PROXY[[:space:]]*\)\)[[:space:]]*\|\|[[:space:]]*proxy_apply[[:space:]]*$/ && step == 7 { step = 8; next }
  inblock && /^[[:space:]]*launch_codex[[:space:]]/ && step == 8 { print 1; found = 1; exit }
  END { if (!found) print 0 }
' "$ROOT/icodex.sh")"
assert_eq "default launch wiring order" "1" "$launch_order_ok"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_smoke.sh`
Expected: FAIL — sandbox module not sourced; new wiring calls absent; order mismatch.

- [ ] **Step 3: Edit `icodex.sh`:**

  (a) Add `config/sandbox` to the source loop (after `config/permissions`), so the `config/*` group reads:

```bash
         config/isolated config/permissions config/sandbox config/env proxy/proxy symlink/symlink \
```

  (b) In the `install`/`update` case (lines 49-50), replace `setup_codex_home` with `setup_shared_dirs`:

```bash
    install) setup_shared_dirs; install_ensure          || exit 1; ensure_uv_dependency || exit 1; install_symlink; exit 0 ;;
    update)  setup_shared_dirs; install_ensure --update || exit 1; ensure_uv_dependency || exit 1; install_symlink; exit 0 ;;
```

  (c) Replace the default run block (lines 53-60) with:

```bash
  # default: run
  setup_codex_home
  apply_sandbox_mode || exit 1
  ensure_project_trust "$ICODEX_HOME_DIR/config.toml" "$ICODEX_PROJECT_ROOT"
  ensure_launcher_binary_permission
  ensure_superpowers_wiring
  install_ensure || exit 1
  ensure_uv_dependency || exit 1
  (( ICODEX_DISABLE_PROXY )) || proxy_apply
  launch_codex ${ICODEX_PASSTHROUGH[@]+"${ICODEX_PASSTHROUGH[@]}"}
```

- [ ] **Step 4: Run the smoke + update-scope tests to verify they pass**

Run: `bash tests/test_smoke.sh && bash tests/test_update_scope.sh`
Expected: PASS (update-scope still passes: `setup_shared_dirs` only makes a dir; superpowers wiring is not called on the update branch).

- [ ] **Step 5: Commit**

```bash
git add icodex.sh tests/test_smoke.sh
git commit -m "feat(launcher): wire per-project home, sandbox, and trust on the run path"
```

---

### Task 9: Full suite + docs regeneration

**Files:**
- Verify: all `tests/test_*.sh`
- Modify (docs): regenerate `docs/wiki/config.md` and `docs/wiki/architecture.md` via iwiki for the changed isolation/sandbox behavior.

**Interfaces:** none (verification + docs).

- [ ] **Step 1: Run the whole suite**

Run: `for t in tests/test_*.sh; do echo "== $t =="; bash "$t" || { echo "FAILED: $t"; break; }; done`
Expected: every file ends `PASS=… FAIL=0`.

- [ ] **Step 2: Manual smoke from a foreign directory** — confirm the home resolves outside the wrapper repo and the default mode is safe:

```bash
cd /tmp && mkdir -p icodex-probe && cd icodex-probe
ICODEX_ROOT=<abs path to wrapper> bash <wrapper>/icodex.sh --help >/dev/null && echo "help ok"
```

Expected: no error. (A full launch needs the binary; `--help` exercises sourcing only.)

- [ ] **Step 3: Regenerate the affected wiki pages** — per the repo's iwiki workflow:

Run: `iwiki:iwiki-ingest lib/config/isolated.sh` and `iwiki:iwiki-ingest lib/config/sandbox.sh`, then `/iwiki-lint`.
Expected: `config.md` documents per-project homes + sandbox precedence; `architecture.md` "CODEX_HOME isolation" reflects the shared-vs-home split; lint reports no broken `[[refs]]`.

- [ ] **Step 4: Commit docs**

```bash
git add docs/wiki/
git commit -m "docs(wiki): per-project CODEX_HOME and sandbox isolation"
```

---

## Self-Review

**Spec coverage:**
- P0 #1 sandbox safe-by-default → Tasks 5 (resolution/upsert/warning), 6 (`--full-access`), 8 (run-path apply). ✓
- P0 #2 per-project CODEX_HOME → Tasks 1 (path split), 2 (install→shared), 3 (cache→shared), 4 (home resolution/symlinks/template), 8 (run-path wiring, install/update→shared). ✓
- Shared auth via symlink → Task 4 `_link_shared auth.json`. ✓
- approval_policy unchanged → asserted in Tasks 5 and 7 tests; never written. ✓
- gap #8 auto-trust → Task 7. ✓
- `.codex-homes/` git-ignored → Task 4 Step 4. ✓
- Migration (assets stay, orphan state safe) → no code (assets keep their paths); covered by Tasks 1-2 keeping `ICODEX_BIN` path identical. ✓
- Tests table (isolated, sandbox, install, update_scope, plugin, smoke, trust) → Tasks 4,5,2,8,3,8,7. ✓

**Placeholder scan:** No TBD/TODO; every code and test step shows full content. ✓

**Type/name consistency:** `resolve_project_root`, `resolve_codex_home`, `setup_codex_home`, `setup_shared_dirs`, `_link_shared`, `resolve_sandbox_mode`, `_upsert_toml_toplevel`, `apply_sandbox_mode`, `ensure_project_trust`, globals `ICODEX_SHARED_DIR`/`ICODEX_HOMES_DIR`/`ICODEX_HOME_DIR`/`ICODEX_PROJECT_ROOT`/`ICODEX_FULL_ACCESS` — used identically across tasks and the run-path block. ✓

**Out of scope (unchanged from spec):** home GC/`--list-homes`, isolated-auth mode, 3-level sandbox UX, other backlog items.

---
review:
  plan_hash: efe04dfdb319ac69
  spec_hash: 270d563ac1da3633
  last_run: 2026-06-29
  phases:
    structure:     { status: passed }
    coverage:      { status: passed }
    dependencies:  { status: passed }
    verifiability: { status: passed }
    consistency:   { status: passed }
  findings:
    - id: F-001
      phase: consistency
      severity: CRITICAL
      section: "Task 3: ensure_git_writable filesystem grant"
      section_hash: ee825f043c1255c6
      fragment: 'assert_eq "dev-safe ''.'' write preserved" "1" "$dot_in_devsafe"'
      text: >-
        The Task 3 Step 1 test seeds a config with `"." = "write"` in BOTH the
        dev-safe and ssh-on-request :workspace_roots tables, then asserts
        grep -cFx '"." = "write"' equals "1". Because the string occurs in two
        profiles, grep returns 2, so this assertion FAILS and Task 3 Step 4 can
        never reach PASS=<n> FAIL=0. The plan's own inline comment even notes
        "both profiles keep '.'=write (>=1)" yet asserts exactly 1.
      fix: >-
        Either change the expected value to "2", or scope the count to one
        profile via awk (mirroring the git_in_devsafe awk already in the test),
        or drop "." = "write" from the ssh-on-request seed table so only one
        occurrence remains.
      resolution: >-
        Fixed. The ambiguous grep -cFx assertion was replaced with a
        dot_in_devsafe awk count scoped to the dev-safe :workspace_roots section
        (mirroring the git_in_devsafe awk), expecting exactly 1. Verified against
        the seed: "." = "write" appears once in dev-safe and once in
        ssh-on-request; the awk only counts within dev-safe, so the count is 1
        and Task 3 Step 4 can reach PASS=<n> FAIL=0.
      verdict: fixed
      verdict_at: 2026-06-29
    - id: F-002
      phase: coverage
      severity: INFO
      section: "Task 6: Documentation"
      section_hash: d4e59115f26df4f0
      fragment: "## Testing (`tests/`, new `test_mode.sh` + extend `test_install.sh`)"
      text: >-
        The spec's Testing section header says "extend test_install.sh", but no
        plan task touches tests/test_install.sh (grep confirms zero references).
        The mismatch is minor: the spec body never specifies WHAT to add to
        test_install.sh, and all four of the spec's testing bullets are fully
        covered by the new tests/test_mode.sh. Left unaddressed it is a dangling
        spec reference rather than a missing behavior.
      fix: >-
        Either add a brief step extending tests/test_install.sh (e.g. assert a
        fresh install ships the .git-writable template), or treat the spec
        header's "extend test_install.sh" as superseded by test_mode.sh and note
        that explicitly. No code behavior is at risk either way.
      resolution: >-
        Fixed. A Notes bullet now explicitly supersedes the spec's
        "extend test_install.sh" clause, stating no change to tests/test_install.sh
        is required and that the .git-writable template is verified by Task 5
        Step 7 plus run-mode behavior by the new tests/test_mode.sh. Matches the
        second fix option.
      verdict: fixed
      verdict_at: 2026-06-29
chain:
  intent: null
  spec: docs/superpowers/specs/2026-06-29-icodex-run-profiles-design.md
---
# icodex Run Profiles (ICODEX_MODE) + `.git` Writability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `.codex_config` select a complete run profile via one `ICODEX_MODE` preset (sandbox + approval + managed permissions) and make codex able to write `.git` in every writable mode.

**Architecture:** Generalize `lib/config/sandbox.sh` from a sandbox-only resolver into a run-mode resolver/applier: `resolve_mode` maps an `ICODEX_MODE` preset (with granular env overrides) to the triple `sandbox approval permissions`; `apply_mode` upserts `sandbox_mode` + `approval_policy`, adds/removes `default_permissions`, and delegates the `.git/` filesystem grant to a new `ensure_git_writable` in `lib/config/permissions.sh`. The `full-auto` preset removes the managed layer entirely (no prompts, `.git` writable). All writes are idempotent upserts so existing per-project homes migrate on the next run.

**Tech Stack:** Bash (`set -euo pipefail`), awk, dependency-free shell tests (`tests/helpers.sh`). No new tools.

## Global Constraints

- `#!/usr/bin/env bash`; `set -euo pipefail` in `lib/`, `set -uo pipefail` in tests.
- Two-space indent; functions `lowercase_with_underscores`; env vars `ICODEX_` prefix.
- Dependency-light: bash + awk + existing helpers; no new tools.
- CODEX_HOME isolation, proxy, binary install, and trust logic are untouched.
- Presets (exact values):
  - `ro` → `read-only on-request dev-safe`
  - `safe` → `workspace-write on-request dev-safe`
  - `full-ask` → `danger-full-access on-request ssh-on-request` (the default when `ICODEX_MODE` is unset)
  - `full-auto` → `danger-full-access never none` (`none` = remove `default_permissions`)
- Precedence: `defaults (full-ask) < ICODEX_MODE < granular (ICODEX_SANDBOX | ICODEX_APPROVAL | ICODEX_PERMISSIONS)`. The existing `--full-access` / `ICODEX_FULL_ACCESS` still forces the sandbox field to `danger-full-access`.
- Granular value sets: `ICODEX_SANDBOX ∈ {read-only, workspace-write, danger-full-access}`; `ICODEX_APPROVAL ∈ {untrusted, on-failure, on-request, never}`; `ICODEX_PERMISSIONS ∈ {dev-safe, ssh-on-request, none}`.
- Invalid preset/value → `log_error` + non-zero return; `icodex.sh` exits 1 before launching codex.
- Tests run individually: `bash tests/test_<name>.sh`; a passing run ends with `PASS=<n> FAIL=0`.

---

### Task 1: `_remove_toml_toplevel` helper

Removes a top-level `key = ...` line (before the first `[section]`) idempotently. Needed by `apply_mode` to drop `default_permissions` for `full-auto` / `ICODEX_PERMISSIONS=none`.

**Files:**
- Modify: `lib/config/sandbox.sh` (add helper next to `_upsert_toml_toplevel`)
- Test: `tests/test_sandbox.sh` (extend; sibling of the existing `_upsert_toml_toplevel` test)

**Interfaces:**
- Consumes: nothing.
- Produces: `_remove_toml_toplevel <config> <key>` — deletes every top-level line matching `^[[:space:]]*<key>[[:space:]]*=` that appears before the first `[section]`; byte-identical when the key is absent.

- [ ] **Step 1: Write the failing test**

Append before the final `rm -rf "$tmp"` / `finish` in `tests/test_sandbox.sh`:

```bash
# --- _remove_toml_toplevel: drops a top-level key, no-op when absent ---
printf 'sandbox_mode = "danger-full-access"\ndefault_permissions = "ssh-on-request"\n\n[features]\ndefault_permissions = "keep-me"\n' > "$ICODEX_HOME_DIR/rm.toml"
_remove_toml_toplevel "$ICODEX_HOME_DIR/rm.toml" default_permissions
assert_eq "top-level key removed" "0" \
  "$(grep -cFx 'default_permissions = "ssh-on-request"' "$ICODEX_HOME_DIR/rm.toml")"
assert_eq "in-section key preserved" "1" \
  "$(grep -cFx 'default_permissions = "keep-me"' "$ICODEX_HOME_DIR/rm.toml")"
assert_eq "other top-level key preserved" "1" \
  "$(grep -cFx 'sandbox_mode = "danger-full-access"' "$ICODEX_HOME_DIR/rm.toml")"
before_rm="$(cat "$ICODEX_HOME_DIR/rm.toml")"
_remove_toml_toplevel "$ICODEX_HOME_DIR/rm.toml" default_permissions
assert_eq "remove idempotent when absent" "$before_rm" "$(cat "$ICODEX_HOME_DIR/rm.toml")"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_sandbox.sh`
Expected: FAIL — `_remove_toml_toplevel: command not found` (function not defined), `FAIL` count > 0.

- [ ] **Step 3: Write minimal implementation**

In `lib/config/sandbox.sh`, add immediately after the `_upsert_toml_toplevel` function (after its closing `}`):

```bash
# Idempotently remove a top-level `key = ...` line (before the first [section]).
_remove_toml_toplevel() { # <config> <key>
  local config="$1" key="$2" tmp
  tmp="$(mktemp)"
  awk -v key="$key" '
    /^[[:space:]]*\[/ { insec = 1 }
    !insec && $0 ~ ("^[[:space:]]*" key "[[:space:]]*=") { next }
    { print }
  ' "$config" > "$tmp"
  cmp -s "$tmp" "$config" || cat "$tmp" > "$config"
  rm -f "$tmp"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_sandbox.sh`
Expected: PASS — output ends with `PASS=<n> FAIL=0`.

- [ ] **Step 5: Commit**

```bash
git add lib/config/sandbox.sh tests/test_sandbox.sh
git commit -m "feat(config): _remove_toml_toplevel for top-level key removal"
```

---

### Task 2: `resolve_mode` preset resolver

Maps `ICODEX_MODE` (default `full-ask`) to the effective `sandbox approval permissions` triple, applying granular overrides and validation. Reuses the existing `resolve_sandbox_mode` for the sandbox field whenever an explicit sandbox override is in play (so `--full-access`/`ICODEX_SANDBOX` precedence stays in one place).

**Files:**
- Modify: `lib/config/sandbox.sh` (add `_mode_preset` + `resolve_mode`)
- Test: `tests/test_mode.sh` (create)

**Interfaces:**
- Consumes: `resolve_sandbox_mode` (existing, unchanged), `log_error` (from `lib/core/logging.sh`).
- Produces:
  - `_mode_preset <mode>` — echoes `sandbox approval permissions` for `ro|safe|full-ask|full-auto`; returns 1 for any other name.
  - `resolve_mode` — echoes the effective `sandbox approval permissions` (space-separated, `permissions` may be the sentinel `none`); `log_error` + return 1 on any invalid value. Reads `ICODEX_MODE`, `ICODEX_SANDBOX`, `ICODEX_APPROVAL`, `ICODEX_PERMISSIONS`, `ICODEX_FULL_ACCESS`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_mode.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/config/sandbox.sh"
source "$ROOT/lib/config/permissions.sh"

clear_env() { unset ICODEX_MODE ICODEX_SANDBOX ICODEX_APPROVAL ICODEX_PERMISSIONS; ICODEX_FULL_ACCESS=0; }

# --- resolve_mode: presets ---
clear_env
assert_eq "default mode is full-ask" "danger-full-access on-request ssh-on-request" "$(resolve_mode)"
clear_env; ICODEX_MODE=ro
assert_eq "ro preset" "read-only on-request dev-safe" "$(resolve_mode)"
clear_env; ICODEX_MODE=safe
assert_eq "safe preset" "workspace-write on-request dev-safe" "$(resolve_mode)"
clear_env; ICODEX_MODE=full-ask
assert_eq "full-ask preset" "danger-full-access on-request ssh-on-request" "$(resolve_mode)"
clear_env; ICODEX_MODE=full-auto
assert_eq "full-auto preset" "danger-full-access never none" "$(resolve_mode)"

# --- resolve_mode: granular overrides ---
clear_env; ICODEX_MODE=safe; ICODEX_APPROVAL=never
assert_eq "approval override" "workspace-write never dev-safe" "$(resolve_mode)"
clear_env; ICODEX_MODE=safe; ICODEX_PERMISSIONS=none
assert_eq "permissions override none" "workspace-write on-request none" "$(resolve_mode)"
clear_env; ICODEX_MODE=safe; ICODEX_SANDBOX=danger-full-access
assert_eq "sandbox override" "danger-full-access on-request dev-safe" "$(resolve_mode)"
clear_env; ICODEX_MODE=ro; ICODEX_FULL_ACCESS=1
assert_eq "full-access flag forces sandbox" "danger-full-access on-request dev-safe" "$(resolve_mode)"

# --- resolve_mode: validation ---
clear_env; ICODEX_MODE=bogus
( resolve_mode >/dev/null 2>&1 ); assert_eq "invalid mode nonzero" "1" "$?"
clear_env; ICODEX_APPROVAL=bogus
( resolve_mode >/dev/null 2>&1 ); assert_eq "invalid approval nonzero" "1" "$?"
clear_env; ICODEX_PERMISSIONS=bogus
( resolve_mode >/dev/null 2>&1 ); assert_eq "invalid permissions nonzero" "1" "$?"
clear_env; ICODEX_SANDBOX=bogus
( resolve_mode >/dev/null 2>&1 ); assert_eq "invalid sandbox nonzero" "1" "$?"

finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_mode.sh`
Expected: FAIL — `resolve_mode: command not found`, `FAIL` count > 0.

- [ ] **Step 3: Write minimal implementation**

In `lib/config/sandbox.sh`, add after `resolve_sandbox_mode` (before `_upsert_toml_toplevel`):

```bash
# Echo "sandbox approval permissions" for a preset name; return 1 if unknown.
_mode_preset() { # <mode>
  case "$1" in
    ro)        printf 'read-only on-request dev-safe\n' ;;
    safe)      printf 'workspace-write on-request dev-safe\n' ;;
    full-ask)  printf 'danger-full-access on-request ssh-on-request\n' ;;
    full-auto) printf 'danger-full-access never none\n' ;;
    *)         return 1 ;;
  esac
}

# Validate <value> against the remaining args (allowed set); return 0/1.
_mode_valid() { # <value> <allowed...>
  local v="$1" a; shift
  for a in "$@"; do [[ "$v" == "$a" ]] && return 0; done
  return 1
}

# Echo the effective "sandbox approval permissions" triple. Preset (default
# full-ask) < ICODEX_MODE < granular ICODEX_SANDBOX/APPROVAL/PERMISSIONS.
# log_error + return 1 on any invalid value.
resolve_mode() {
  local mode="${ICODEX_MODE:-full-ask}" preset sandbox approval permissions
  if ! preset="$(_mode_preset "$mode")"; then
    log_error "invalid ICODEX_MODE '$mode' (want: ro|safe|full-ask|full-auto)"; return 1
  fi
  read -r sandbox approval permissions <<<"$preset"

  # Sandbox field: an explicit ICODEX_SANDBOX or --full-access defers to
  # resolve_sandbox_mode (its precedence + validation); else the preset stands.
  if [[ -n "${ICODEX_SANDBOX:-}" ]] || (( ${ICODEX_FULL_ACCESS:-0} )); then
    sandbox="$(resolve_sandbox_mode)" || return 1
  fi

  if [[ -n "${ICODEX_APPROVAL:-}" ]]; then
    _mode_valid "$ICODEX_APPROVAL" untrusted on-failure on-request never \
      || { log_error "invalid ICODEX_APPROVAL '$ICODEX_APPROVAL' (want: untrusted|on-failure|on-request|never)"; return 1; }
    approval="$ICODEX_APPROVAL"
  fi

  if [[ -n "${ICODEX_PERMISSIONS:-}" ]]; then
    _mode_valid "$ICODEX_PERMISSIONS" dev-safe ssh-on-request none \
      || { log_error "invalid ICODEX_PERMISSIONS '$ICODEX_PERMISSIONS' (want: dev-safe|ssh-on-request|none)"; return 1; }
    permissions="$ICODEX_PERMISSIONS"
  fi

  printf '%s %s %s\n' "$sandbox" "$approval" "$permissions"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_mode.sh`
Expected: PASS — output ends with `PASS=<n> FAIL=0`.

- [ ] **Step 5: Commit**

```bash
git add lib/config/sandbox.sh tests/test_mode.sh
git commit -m "feat(config): resolve_mode preset resolver with granular overrides"
```

---

### Task 3: `ensure_git_writable` filesystem grant

Dedicated helper that idempotently grants `".git/" = "write"` under a named profile's `:workspace_roots` table. Per spec finding F-002 it MUST parameterize the full section path `[permissions.<profile>.filesystem.":workspace_roots"]` for both `dev-safe` and `ssh-on-request` — it does NOT reuse the hardcoded `[permissions.dev-safe.filesystem]` of `_ensure_filesystem_permission_entry`.

**Files:**
- Modify: `lib/config/permissions.sh` (add `ensure_git_writable`)
- Test: `tests/test_mode.sh` (extend)

**Interfaces:**
- Consumes: nothing (self-contained awk).
- Produces: `ensure_git_writable <config> <profile>` — idempotently inserts `".git/" = "write"` under `[permissions.<profile>.filesystem.":workspace_roots"]`; byte-identical when already present; creates the subtable if absent; no-op when `<config>` is missing.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_mode.sh` before `finish`:

```bash
# --- ensure_git_writable: grants .git write under a profile's :workspace_roots ---
gt="$(mktemp -d)"; gcfg="$gt/config.toml"
cat > "$gcfg" <<'EOF'
[permissions.dev-safe.filesystem]
":minimal" = "read"

[permissions.dev-safe.filesystem.":workspace_roots"]
"." = "write"
"**/.env" = "deny"

[permissions.ssh-on-request.filesystem.":workspace_roots"]
"." = "write"
EOF

ensure_git_writable "$gcfg" dev-safe
git_in_devsafe="$(awk '
  /^\[/ { insec = ($0 == "[permissions.dev-safe.filesystem.\":workspace_roots\"]") }
  insec && $0 == "\".git/\" = \"write\"" { c++ }
  END { print c + 0 }
' "$gcfg")"
assert_eq "git write under dev-safe workspace_roots" "1" "$git_in_devsafe"
dot_in_devsafe="$(awk '
  /^\[/ { insec = ($0 == "[permissions.dev-safe.filesystem.\":workspace_roots\"]") }
  insec && $0 == "\".\" = \"write\"" { c++ }
  END { print c + 0 }
' "$gcfg")"
assert_eq "dev-safe '.' write preserved" "1" "$dot_in_devsafe"
assert_eq "dev-safe env deny preserved" "1" "$(grep -cFx '"**/.env" = "deny"' "$gcfg")"

ensure_git_writable "$gcfg" ssh-on-request
git_in_ssh="$(awk '
  /^\[/ { insec = ($0 == "[permissions.ssh-on-request.filesystem.\":workspace_roots\"]") }
  insec && $0 == "\".git/\" = \"write\"" { c++ }
  END { print c + 0 }
' "$gcfg")"
assert_eq "git write under ssh-on-request workspace_roots" "1" "$git_in_ssh"

before_git="$(cat "$gcfg")"
ensure_git_writable "$gcfg" dev-safe
assert_eq "ensure_git_writable idempotent" "$before_git" "$(cat "$gcfg")"
rm -rf "$gt"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_mode.sh`
Expected: FAIL — `ensure_git_writable: command not found`, `FAIL` count > 0.

- [ ] **Step 3: Write minimal implementation**

In `lib/config/permissions.sh`, add after `_ensure_filesystem_permission_entry` (before `ensure_launcher_binary_permission`):

```bash
# Idempotently grant ".git/" = "write" under a profile's :workspace_roots table,
# overriding codex's read-only re-mount of the .git protected path. The full
# section path is parameterized per <profile> (dev-safe / ssh-on-request).
ensure_git_writable() { # <config> <profile>
  local config="$1" profile="$2" section tmp
  [[ -f "$config" ]] || return 0
  section="[permissions.$profile.filesystem.\":workspace_roots\"]"
  tmp="$(mktemp)"
  awk -v section="$section" '
    BEGIN { key = "\".git/\""; line = key " = \"write\"" }
    function emit_missing() { if (insec && !done) { print line; done = 1 } }
    /^\[/ {
      emit_missing()
      insec = ($0 == section)
      if (insec) found = 1
    }
    insec {
      trimmed = $0
      sub(/^[[:space:]]*/, "", trimmed)
      if (index(trimmed, key) == 1) {
        rest = substr(trimmed, length(key) + 1)
        if (rest ~ /^[[:space:]]*=/) {
          if (!done) { print line; done = 1 }
          next
        }
      }
    }
    { print }
    END {
      emit_missing()
      if (!found) { print ""; print section; print line }
    }
  ' "$config" > "$tmp"
  cmp -s "$tmp" "$config" || cat "$tmp" > "$config"
  rm -f "$tmp"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_mode.sh`
Expected: PASS — output ends with `PASS=<n> FAIL=0`.

- [ ] **Step 5: Commit**

```bash
git add lib/config/permissions.sh tests/test_mode.sh
git commit -m "feat(config): ensure_git_writable grants .git write per profile"
```

---

### Task 4: `apply_mode` orchestrator (replaces `apply_sandbox_mode`)

Resolves the triple and writes it into the per-project `config.toml`: upsert `sandbox_mode` + `approval_policy`; for `none` remove `default_permissions` (managed layer off), otherwise upsert it and ensure `.git` is writable in that profile. Emits warnings for `danger-full-access` and for `none`. Removes the now-unused `apply_sandbox_mode` and migrates its `test_sandbox.sh` assertions.

**Files:**
- Modify: `lib/config/sandbox.sh` (add `apply_mode`, delete `apply_sandbox_mode`)
- Modify: `tests/test_sandbox.sh` (remove the `apply_sandbox_mode` block — lines covering `seed`/`apply_sandbox_mode`/idempotent/warning)
- Test: `tests/test_mode.sh` (extend with `apply_mode` cases)

**Interfaces:**
- Consumes: `resolve_mode` (Task 2), `_upsert_toml_toplevel` (existing), `_remove_toml_toplevel` (Task 1), `ensure_git_writable` (Task 3), `log_warn` (from `lib/core/logging.sh`), `ICODEX_HOME_DIR`.
- Produces: `apply_mode` — writes the resolved run mode into `$ICODEX_HOME_DIR/config.toml`; returns 1 if `resolve_mode` fails; idempotent on re-run.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_mode.sh` before `finish`:

```bash
# --- apply_mode: writes the resolved triple into the per-project config ---
mt="$(mktemp -d)"; ICODEX_HOME_DIR="$mt/home"; mkdir -p "$ICODEX_HOME_DIR"
seed_mode() {
  cat > "$ICODEX_HOME_DIR/config.toml" <<'EOF'
sandbox_mode = "workspace-write"
approval_policy = "on-request"
default_permissions = "ssh-on-request"

[permissions.dev-safe.filesystem.":workspace_roots"]
"." = "write"

[permissions.ssh-on-request.filesystem.":workspace_roots"]
"." = "write"
EOF
}

# safe: dev-safe profile, on-request, workspace-write, .git writable
clear_env; ICODEX_MODE=safe; seed_mode
apply_mode
cfg="$ICODEX_HOME_DIR/config.toml"
assert_eq "safe sandbox" "1" "$(grep -cFx 'sandbox_mode = "workspace-write"' "$cfg")"
assert_eq "safe approval" "1" "$(grep -cFx 'approval_policy = "on-request"' "$cfg")"
assert_eq "safe permissions" "1" "$(grep -cFx 'default_permissions = "dev-safe"' "$cfg")"
assert_eq "safe grants .git" "1" "$(grep -cFx '".git/" = "write"' "$cfg")"

# full-auto: removes default_permissions, approval never, danger sandbox
clear_env; ICODEX_MODE=full-auto; seed_mode
warn_auto="$(apply_mode 2>&1 >/dev/null)"
assert_eq "full-auto removes managed perms" "0" "$(grep -c '^default_permissions' "$cfg")"
assert_eq "full-auto approval never" "1" "$(grep -cFx 'approval_policy = "never"' "$cfg")"
assert_eq "full-auto sandbox danger" "1" "$(grep -cFx 'sandbox_mode = "danger-full-access"' "$cfg")"
assert_contains "full-auto warns danger" "$warn_auto" "full filesystem access enabled"
assert_contains "full-auto warns no managed perms" "$warn_auto" "managed permissions disabled"

# idempotent: second apply byte-identical
clear_env; ICODEX_MODE=full-ask; seed_mode
apply_mode
before_apply="$(cat "$cfg")"
apply_mode
assert_eq "apply_mode idempotent" "$before_apply" "$(cat "$cfg")"

# resolve failure propagates
clear_env; ICODEX_MODE=bogus; seed_mode
assert_exit "apply_mode fails on invalid mode" 1 apply_mode
rm -rf "$mt"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_mode.sh`
Expected: FAIL — `apply_mode: command not found`, `FAIL` count > 0.

- [ ] **Step 3: Write minimal implementation**

In `lib/config/sandbox.sh`, replace the entire `apply_sandbox_mode` function (the block starting `# Resolve and write sandbox_mode ...` through its closing `}`) with:

```bash
# Resolve the run mode and write it into the per-project config: sandbox_mode +
# approval_policy (top-level upserts), default_permissions (upsert, or removed for
# `none`), and the .git writability grant for the active managed profile. Warns on
# danger-full-access and on a disabled managed layer.
apply_mode() {
  local config="$ICODEX_HOME_DIR/config.toml" triple sandbox approval permissions
  triple="$(resolve_mode)" || return 1
  read -r sandbox approval permissions <<<"$triple"
  _upsert_toml_toplevel "$config" sandbox_mode "$sandbox"
  _upsert_toml_toplevel "$config" approval_policy "$approval"
  if [[ "$permissions" == "none" ]]; then
    _remove_toml_toplevel "$config" default_permissions
    log_warn "permissions = none — managed permissions disabled, no approval prompts (project: $(basename "$ICODEX_HOME_DIR"))"
  else
    _upsert_toml_toplevel "$config" default_permissions "$permissions"
    ensure_git_writable "$config" "$permissions"
  fi
  if [[ "$sandbox" == "danger-full-access" ]]; then
    log_warn "sandbox = danger-full-access — full filesystem access enabled (project: $(basename "$ICODEX_HOME_DIR"))"
  fi
  return 0
}
```

Also update the file's top comment in `lib/config/sandbox.sh` (lines describing scope): change the `approval_policy is never touched here; only sandbox_mode is managed.` line to:

```bash
# Run-mode resolution and idempotent config write: sandbox_mode, approval_policy,
# and the managed permission profile (default_permissions) are all managed here.
```

- [ ] **Step 4: Remove the stale `apply_sandbox_mode` block from `tests/test_sandbox.sh`**

Delete the block in `tests/test_sandbox.sh` that begins with the comment `# apply upserts the top-level key (replaces existing danger-full-access)` and runs through the `assert_contains "warns on full access" ...` line (the three `apply_sandbox_mode` invocations and the `seed` helper definition on the preceding line). Keep the `resolve_sandbox_mode` tests and the `_upsert_toml_toplevel` "inserts before section" test, plus the `_remove_toml_toplevel` test added in Task 1.

After editing, confirm no references remain:

Run: `grep -c apply_sandbox_mode tests/test_sandbox.sh`
Expected: `0`

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/test_mode.sh && bash tests/test_sandbox.sh`
Expected: both end with `PASS=<n> FAIL=0`.

- [ ] **Step 6: Commit**

```bash
git add lib/config/sandbox.sh tests/test_mode.sh tests/test_sandbox.sh
git commit -m "feat(config): apply_mode writes full run profile, replaces apply_sandbox_mode"
```

---

### Task 5: Wire `apply_mode` into the run path + template `.git` grant

Swap the run-path call, refresh the template `config.toml` (grant `.git/` write in both shipped profiles and rewrite the safety-mode comments to describe `ICODEX_MODE`), and update the smoke test that pins the launch wiring and order.

**Files:**
- Modify: `icodex.sh:55`
- Modify: `.codex-isolated/config.toml` (both `:workspace_roots` tables + the comment block at lines ~30-48)
- Modify: `tests/test_smoke.sh:45-46,54`

**Interfaces:**
- Consumes: `apply_mode` (Task 4).
- Produces: run path calls `apply_mode || exit 1` in place of `apply_sandbox_mode || exit 1`; fresh installs ship `.git`-writable `dev-safe` / `ssh-on-request` profiles.

- [ ] **Step 1: Update the smoke test (failing first)**

In `tests/test_smoke.sh`, change the assertion at lines 45-46 to:

```bash
assert_eq "calls apply_mode on launch" "1" \
  "$(grep -Ec '^[[:space:]]*apply_mode \|\| exit 1[[:space:]]*$' "$ROOT/icodex.sh")"
```

And in the `launch_order_ok` awk (line 54) change:

```bash
  inblock && /^[[:space:]]*apply_mode \|\| exit 1[[:space:]]*$/ && step == 1 { step = 2; next }
```

- [ ] **Step 2: Run smoke test to verify it fails**

Run: `bash tests/test_smoke.sh`
Expected: FAIL — `calls apply_mode on launch` expected `1` got `0` (icodex.sh still calls `apply_sandbox_mode`).

- [ ] **Step 3: Update the run path**

In `icodex.sh`, change line 55 from:

```bash
  apply_sandbox_mode || exit 1
```

to:

```bash
  apply_mode || exit 1
```

- [ ] **Step 4: Run smoke test to verify it passes**

Run: `bash tests/test_smoke.sh`
Expected: PASS — ends with `PASS=<n> FAIL=0`.

- [ ] **Step 5: Grant `.git` write in the template profiles**

In `.codex-isolated/config.toml`, under `[permissions.dev-safe.filesystem.":workspace_roots"]`, add `".git/" = "write"` immediately after the `"." = "write"` line:

```toml
[permissions.dev-safe.filesystem.":workspace_roots"]
"." = "write"
".git/" = "write"
```

Do the same under `[permissions.ssh-on-request.filesystem.":workspace_roots"]`:

```toml
[permissions.ssh-on-request.filesystem.":workspace_roots"]
"." = "write"
".git/" = "write"
```

- [ ] **Step 6: Refresh the safety-mode comments**

In `.codex-isolated/config.toml`, replace the comment block currently spanning the "Launch safety modes" / "Permission profiles" notes (the lines beginning `# Launch safety modes:` through the `# - ssh-on-request: ...` bullet) with:

```toml
# Run modes (set ICODEX_MODE in .codex_config; default is full-ask):
# - ro:        read-only sandbox, on-request approval, dev-safe profile.
# - safe:      workspace-write, on-request approval, dev-safe profile.
# - full-ask:  danger-full-access, on-request approval, ssh-on-request profile.
# - full-auto: danger-full-access, never approval, managed permissions removed
#              (no prompts at all; .git writable). = --dangerously-bypass-approvals-and-sandbox.
# icodex rewrites sandbox_mode / approval_policy / default_permissions and grants
# ".git/" = "write" in the active profile on every run. Granular ICODEX_SANDBOX /
# ICODEX_APPROVAL / ICODEX_PERMISSIONS override individual fields.
#
# Permission profiles (managed filesystem/network rules, selected by default_permissions):
# - dev-safe:       locked down. No network, no SSH material.
# - ssh-on-request: outbound network + read-only ~/.ssh for SSH-based work.
```

- [ ] **Step 7: Verify the template is byte-stable under `ensure_git_writable`**

Run:

```bash
cp .codex-isolated/config.toml /tmp/tmpl-before.toml
bash -c 'set -euo pipefail; source lib/config/permissions.sh; ensure_git_writable /tmp/tmpl-before.toml dev-safe; ensure_git_writable /tmp/tmpl-before.toml ssh-on-request'
diff /tmp/tmpl-before.toml .codex-isolated/config.toml && echo IDEMPOTENT
```

Expected: prints `IDEMPOTENT` (the shipped template already contains the `.git/` grant, so the helper makes no change).

- [ ] **Step 8: Run the full suite**

Run: `for f in tests/test_*.sh; do echo "== $f =="; bash "$f" | tail -1; done`
Expected: every file's last line is `PASS=<n> FAIL=0`.

- [ ] **Step 9: Commit**

```bash
git add icodex.sh .codex-isolated/config.toml tests/test_smoke.sh
git commit -m "feat: wire apply_mode into run path; ship .git-writable profiles"
```

---

### Task 6: Documentation (`.codex_config.example`, README, help, wiki)

Surface `ICODEX_MODE` to users and regenerate the wiki page. Per spec finding F-001, `print_help` gets one line naming `ICODEX_MODE` + its four presets; the full key reference lives in `.codex_config.example` and the wiki.

**Files:**
- Modify: `.codex_config.example`
- Modify: `lib/command/args.sh` (`print_help` text)
- Modify: `README.md`
- Modify: `docs/wiki/config.md` (via iwiki ingest)

**Interfaces:**
- Consumes: nothing (docs only).
- Produces: documented `ICODEX_MODE` + granular keys.

- [ ] **Step 1: Add the `ICODEX_MODE` block to `.codex_config.example`**

In `.codex_config.example`, immediately before the existing `# Filesystem sandbox for codex:` block, insert:

```bash
# Run mode — bundles sandbox, approval, and managed permissions. Default: full-ask.
#   ro        read-only sandbox, asks before commands, no network/SSH.
#   safe      workspace-write, asks before commands, no network/SSH, .git writable.
#   full-ask  full filesystem access, still asks for risky actions, network + SSH read.
#   full-auto full access, NEVER asks (no prompts at all), managed permissions off.
# Granular overrides below take precedence over the preset, per field.
#ICODEX_MODE=full-ask

# Approval policy override: untrusted | on-failure | on-request | never.
#ICODEX_APPROVAL=on-request

# Managed permission profile override: dev-safe | ssh-on-request | none
# (`none` removes the managed layer entirely, like full-auto).
#ICODEX_PERMISSIONS=ssh-on-request
```

Then change the existing `# Filesystem sandbox` comment to mark it a granular override — replace its first sentence so it reads:

```bash
# Filesystem sandbox override (granular): read-only | workspace-write | danger-full-access.
# Overrides only the sandbox field of ICODEX_MODE.
```

- [ ] **Step 2: Add one help line in `print_help`**

In `lib/command/args.sh`, inside the `print_help` heredoc, add this line directly under the `Persistent settings:` line:

```
  ICODEX_MODE selects a run profile: ro | safe | full-ask (default) | full-auto.
```

- [ ] **Step 3: Document `ICODEX_MODE` in README**

In `README.md`, locate the section that documents `.codex_config` / `ICODEX_SANDBOX` and add a short subsection (match the file's existing heading style and prose voice):

```markdown
### Run mode (`ICODEX_MODE`)

One preset sets the sandbox, approval policy, and managed permission profile together:

| `ICODEX_MODE` | Sandbox | Approval | Managed permissions | `.git` writable |
|---------------|---------|----------|---------------------|-----------------|
| `ro` | read-only | on-request | dev-safe | no |
| `safe` | workspace-write | on-request | dev-safe | yes |
| `full-ask` (default) | danger-full-access | on-request | ssh-on-request | yes |
| `full-auto` | danger-full-access | never (no prompts) | off | yes |

`full-auto` is the "full, no-stop" mode — equivalent to
`--dangerously-bypass-approvals-and-sandbox`. The granular keys `ICODEX_SANDBOX`,
`ICODEX_APPROVAL`, and `ICODEX_PERMISSIONS` override individual fields of the preset.
```

- [ ] **Step 4: Verify docs reference no removed symbols**

Run: `grep -rn "apply_sandbox_mode" README.md docs/ .codex_config.example`
Expected: no output (no doc references the removed function).

- [ ] **Step 5: Regenerate the wiki page + lint**

Run the iwiki skills (per project CLAUDE.md "Keep Docs Current"):
- Invoke `iwiki:iwiki-ingest` on `lib/config/sandbox.sh` and `lib/config/permissions.sh` to regenerate `docs/wiki/config.md` (the "Sandbox mode" / "Sandbox permission wiring" sections must become run-mode aware: presets, precedence, `.git` writability, two-layer model, `default_permissions` removal for `none`).
- Invoke `/iwiki-lint`.

Expected: lint reports no broken `[[refs]]`, no orphan or stale pages.

- [ ] **Step 6: Commit**

```bash
git add .codex_config.example lib/command/args.sh README.md docs/wiki/config.md
git commit -m "docs: document ICODEX_MODE run profiles and granular overrides"
```

---

## Self-Review

**1. Spec coverage:**
- ICODEX_MODE presets (ro/safe/full-ask/full-auto) → Task 2 (`resolve_mode`) + Global Constraints.
- Default full-ask → Task 2 test "default mode is full-ask".
- full-auto removes managed layer (no prompts, .git writable) → Task 1 (`_remove_toml_toplevel`) + Task 4 (`apply_mode` `none` branch + warning).
- `.git` writability fix (per-run migration) → Task 3 (`ensure_git_writable`) + Task 4 wiring; fresh-install template → Task 5 steps 5-7.
- Precedence + granular overrides + validation → Task 2.
- `apply_sandbox_mode` → `apply_mode` swap → Task 4 + Task 5.
- Warnings (danger / none) → Task 4.
- Docs (.codex_config.example, wiki, README, print_help) → Task 6, incl. pinned F-001/F-002 decisions.
- No new CLI flags (YAGNI) → confirmed: only `.codex_config` keys; `--full-access` unchanged.

**2. Placeholder scan:** No TBD/TODO; every code step shows complete code; every test step shows assertions; commands have expected output.

**3. Type consistency:** Function names consistent across tasks — `resolve_mode`, `apply_mode`, `_mode_preset`, `_mode_valid`, `_remove_toml_toplevel`, `ensure_git_writable`. Triple ordering is always `sandbox approval permissions`. `none` sentinel handled identically in `resolve_mode` (Task 2) and `apply_mode` (Task 4). `ensure_git_writable <config> <profile>` signature matches its caller in `apply_mode`.

## Notes

- The spec's Testing header says "new `test_mode.sh` + extend `test_install.sh`", but `test_install.sh` covers only `install_ensure` (binary download/verify) and never receives the per-project template; the `.git`-writable template is verified instead by Task 5 Step 7 and the run-mode behavior by the new `tests/test_mode.sh`. The "extend `test_install.sh`" clause is therefore superseded — no change to `tests/test_install.sh` is required.
- `resolve_sandbox_mode` is retained (still used by `resolve_mode` for the explicit-sandbox path and still covered by `tests/test_sandbox.sh`); only `apply_sandbox_mode` is removed.
- `apply_mode` calls `ensure_git_writable` (in `permissions.sh`) — `tests/test_mode.sh` sources both `sandbox.sh` and `permissions.sh`; `icodex.sh` already sources both before the run path.

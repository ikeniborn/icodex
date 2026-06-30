---
review:
  plan_hash: d2ea1b9a692a3bd4
  spec_hash: 0bfd265e61f4ecd6
  last_run: 2026-06-30
  phases:
    structure:     { status: passed }
    coverage:      { status: passed }
    dependencies:  { status: passed }
    verifiability: { status: passed }
    consistency:   { status: passed }
  findings: []
chain:
  intent: null
  spec:   docs/superpowers/specs/2026-06-30-icodex-iwiki-mcp-design.md
---

# icodex iwiki-mcp Server Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Register the `iwiki-mcp` stdio MCP server in every Codex home icodex launches, always on, with non-secret settings fixed in the server block and the one secret forwarded from the environment.

**Architecture:** Mirror icodex's existing launch-path wiring. `lib/config/env.sh` gains a de-prefix mapping (`ICODEX_IWIKI_LLM_KEY` → `IWIKI_LLM_KEY`) and unblocks the `ICODEX_IWIKI_*` wrapper; a new `lib/iwiki/iwiki.sh` maintains a delimited `# icodex:iwiki:*` region holding `[mcp_servers.iwiki]` in the per-home `config.toml` (`ensure_iwiki_wiring`) and seeds a project-root `.iwiki.toml` (domain == project basename) symlinked into the home for per-project binding (`ensure_iwiki_binding`); `icodex.sh` sources the module and calls all three at launch.

**Tech Stack:** Bash (POSIX-ish, `set -uo pipefail`), `awk`/`cmp` region mechanism, dependency-free shell tests under `tests/` (`tests/helpers.sh`).

## Global Constraints

- **Target: Codex only (icodex).** Do not touch iclaude or the Claude-side engine plugin.
- **Always on.** No enable/disable gate for the iwiki wiring.
- **System binary, hardcoded path:** `command = "/home/ikeniborn/.local/bin/iwiki-mcp"`.
- **Secret out of git.** Only `IWIKI_LLM_KEY` leaves the block (via `env_vars`); it lives solely in `.codex_config` as `ICODEX_IWIKI_LLM_KEY`. Never write the secret into any git-tracked file (`lib/**`, `.codex-isolated/config.toml`, `.codex_config.example`).
- **Non-secret settings literal in the block:** `IWIKI_BASE_DIR = "/home/ikeniborn/Documents/Project/iwiki-personal"`, `IWIKI_LLM_BASE_URL = "https://litellm.ikeniborn.ru/v1"`, `IWIKI_EMBED_MODEL = "ollama-bge-m3"`, `IWIKI_EMBED_DIMENSIONS = "1024"`.
- **Per-project binding via `.iwiki.toml`:** seed `read = ["<basename>"]` / `write = "<basename>"` (`<basename>` = `basename "$ICODEX_PROJECT_ROOT"`) in the project root only when absent (never overwrite); symlink `$ICODEX_HOME_DIR/.iwiki.toml` → the project file. No `IWIKI_PROJECT_DIR` (the symlink delivers binding via the server's cwd == `CODEX_HOME`). Seed regardless of whether the domain exists in the base.
- **Raw `IWIKI_*` keys stay rejected** by `.codex_config` allowlisting; only the `ICODEX_IWIKI_*` wrapper is honored.
- Tests are run individually: `bash tests/test_<name>.sh` (exit 0 = all pass, via `finish`).
- Commit messages in English; end with the `Co-Authored-By` trailer the repo uses.

---

## File Structure

- **Modify** `lib/config/env.sh` — `_config_key_allowed` unblocks `ICODEX_IWIKI_*`; new `apply_iwiki_env()` de-prefix mapping.
- **Create** `lib/iwiki/iwiki.sh` — `ensure_iwiki_wiring()` region resync into per-home `config.toml`; `ensure_iwiki_binding()` seed `.iwiki.toml` + home symlink.
- **Modify** `icodex.sh` — source `iwiki/iwiki`; call `apply_iwiki_env` after `apply_api_key`; call `ensure_iwiki_wiring` and `ensure_iwiki_binding` after `ensure_idd_wiring`.
- **Modify** `.codex_config.example` — commented `#ICODEX_IWIKI_LLM_KEY=...` with docs.
- **Create** `tests/test_iwiki_env.sh` — allowlist + `apply_iwiki_env` unit tests.
- **Create** `tests/test_iwiki_wiring.sh` — region insertion/idempotency unit tests.
- **Create** `tests/test_iwiki_binding.sh` — `.iwiki.toml` seed + symlink unit tests.
- **Manual, not committed:** add `ICODEX_IWIKI_LLM_KEY=<secret>` to the live git-ignored `.codex_config` (Task 4).

---

## Task 1: env.sh — allowlist `ICODEX_IWIKI_*` + `apply_iwiki_env`

**Files:**
- Modify: `lib/config/env.sh` (`_config_key_allowed` lines 6-12; add `apply_iwiki_env` after `apply_api_key`, after line 34)
- Test: `tests/test_iwiki_env.sh` (create)

**Interfaces:**
- Consumes: `load_config <file>` (exports allowed `ICODEX_*` keys), existing in `env.sh`.
- Produces:
  - `_config_key_allowed <key>` → exit 0 for `ICODEX_IWIKI_LLM_KEY` (and any `ICODEX_*`), exit 1 for raw `IWIKI_*`.
  - `apply_iwiki_env()` → exports `IWIKI_LLM_KEY` from `ICODEX_IWIKI_LLM_KEY` when set and `IWIKI_LLM_KEY` not already set; no-op (returns 0) otherwise.

- [ ] **Step 1: Write the failing test**

Create `tests/test_iwiki_env.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/config/env.sh"

tmp="$(mktemp -d)"; cfg="$tmp/.codex_config"
trap 'rm -rf "$tmp"' EXIT

# --- _config_key_allowed: ICODEX_IWIKI_* wrapper allowed, raw IWIKI_* rejected ---
assert_exit "ICODEX_IWIKI_LLM_KEY allowed" 0 _config_key_allowed ICODEX_IWIKI_LLM_KEY
assert_exit "raw IWIKI_LLM_KEY rejected"   1 _config_key_allowed IWIKI_LLM_KEY
assert_exit "raw IWIKI_BASE_DIR rejected"  1 _config_key_allowed IWIKI_BASE_DIR
assert_exit "ICODEX_PROXY still allowed"   0 _config_key_allowed ICODEX_PROXY

# --- load_config exports the wrapper key; raw key in file is ignored ---
cat > "$cfg" <<'EOF'
ICODEX_IWIKI_LLM_KEY=sk-secret
IWIKI_LLM_KEY=raw-should-be-ignored
EOF
unset ICODEX_IWIKI_LLM_KEY IWIKI_LLM_KEY
load_config "$cfg"
assert_eq "wrapper key loaded"        "sk-secret" "${ICODEX_IWIKI_LLM_KEY:-}"
assert_eq "raw key in file ignored"   ""          "${IWIKI_LLM_KEY:-}"

# --- apply_iwiki_env: maps wrapper -> IWIKI_LLM_KEY when target unset ---
unset IWIKI_LLM_KEY; ICODEX_IWIKI_LLM_KEY="sk-secret"
apply_iwiki_env
assert_eq "mapped to IWIKI_LLM_KEY" "sk-secret" "${IWIKI_LLM_KEY:-}"

# --- ambient IWIKI_LLM_KEY wins over the wrapper ---
unset IWIKI_LLM_KEY; export IWIKI_LLM_KEY="sk-ambient"; ICODEX_IWIKI_LLM_KEY="sk-config"
apply_iwiki_env
assert_eq "ambient IWIKI_LLM_KEY wins" "sk-ambient" "${IWIKI_LLM_KEY:-}"

# --- no wrapper -> no-op returns 0, leaves IWIKI_LLM_KEY untouched ---
unset IWIKI_LLM_KEY ICODEX_IWIKI_LLM_KEY
assert_exit "no wrapper -> noop 0" 0 apply_iwiki_env
assert_eq "IWIKI_LLM_KEY stays unset" "" "${IWIKI_LLM_KEY:-}"

finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_iwiki_env.sh`
Expected: FAIL — `ICODEX_IWIKI_LLM_KEY allowed` expects exit 0 but current `_config_key_allowed` returns 1; `apply_iwiki_env` is undefined (function not found → non-zero).

- [ ] **Step 3: Edit `_config_key_allowed`**

In `lib/config/env.sh`, replace the current function (lines 6-12):

```bash
_config_key_allowed() { # <key>
  case "$1" in
    ICODEX_IWIKI_*|IWIKI_[A-Z0-9_]*) return 1 ;;
    ICODEX_[A-Z0-9_]*) return 0 ;;
    *) return 1 ;;
  esac
}
```

with:

```bash
_config_key_allowed() { # <key>
  case "$1" in
    IWIKI_[A-Z0-9_]*) return 1 ;;   # raw IWIKI_* must go through the ICODEX_ wrapper
    ICODEX_[A-Z0-9_]*) return 0 ;;  # includes ICODEX_IWIKI_* (e.g. ICODEX_IWIKI_LLM_KEY)
    *) return 1 ;;
  esac
}
```

- [ ] **Step 4: Add `apply_iwiki_env`**

In `lib/config/env.sh`, immediately after the `apply_api_key()` function (after line 34), add:

```bash
# apply_iwiki_env — map ICODEX_IWIKI_LLM_KEY (from .codex_config) to IWIKI_LLM_KEY
# for the iwiki MCP server. The config.toml [mcp_servers.iwiki] block forwards
# IWIKI_LLM_KEY via env_vars; all other iwiki settings are literal in that block.
# An IWIKI_LLM_KEY already in the environment takes precedence.
apply_iwiki_env() {
  [[ -n "${ICODEX_IWIKI_LLM_KEY:-}" ]] || return 0
  export IWIKI_LLM_KEY="${IWIKI_LLM_KEY:-$ICODEX_IWIKI_LLM_KEY}"
}
```

- [ ] **Step 5: Run the new test and the existing env test**

Run: `bash tests/test_iwiki_env.sh`
Expected: PASS (`PASS=… FAIL=0`).

Run: `bash tests/test_env.sh`
Expected: PASS — existing assertions are unaffected (no existing test places an `ICODEX_IWIKI_*` key in a config file; raw `IWIKI_*` stays ignored).

- [ ] **Step 6: Commit**

```bash
git add lib/config/env.sh tests/test_iwiki_env.sh
git commit -m "feat(iwiki): allow ICODEX_IWIKI_* wrapper and map IWIKI_LLM_KEY

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `lib/iwiki/iwiki.sh` — `ensure_iwiki_wiring` + `ensure_iwiki_binding`

**Files:**
- Create: `lib/iwiki/iwiki.sh`
- Test: `tests/test_iwiki_wiring.sh` (create), `tests/test_iwiki_binding.sh` (create)

**Interfaces:**
- Consumes: `$ICODEX_HOME_DIR` (per-project Codex home; its `config.toml` is a real file copied by `setup_codex_home`), `$ICODEX_PROJECT_ROOT` (the target project root set by `resolve_codex_home`).
- Produces:
  - `ensure_iwiki_wiring()` → ensures exactly one `# icodex:iwiki:start` … `# icodex:iwiki:end` region (containing the `[mcp_servers.iwiki]` block) at the end of `$ICODEX_HOME_DIR/config.toml`; idempotent; no-op (returns 0) when `ICODEX_HOME_DIR` is unset or the file is absent.
  - `ensure_iwiki_binding()` → seeds `$ICODEX_PROJECT_ROOT/.iwiki.toml` with `read = ["<basename>"]` / `write = "<basename>"` when absent (never overwrites); ensures `$ICODEX_HOME_DIR/.iwiki.toml` is a symlink to it (re-point stale, create when missing, leave a pre-existing real file); idempotent; no-op (returns 0) when `ICODEX_PROJECT_ROOT` or `ICODEX_HOME_DIR` is unset.

- [ ] **Step 1: Write the failing test**

Create `tests/test_iwiki_wiring.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

assert_exit "iwiki module exists" 0 test -f "$ROOT/lib/iwiki/iwiki.sh"
if [[ ! -f "$ROOT/lib/iwiki/iwiki.sh" ]]; then
  finish; exit $?
fi
source "$ROOT/lib/iwiki/iwiki.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- inserts the region into an existing config.toml ---
export ICODEX_HOME_DIR="$tmp/home"
mkdir -p "$ICODEX_HOME_DIR"
printf 'model = "gpt-5.5"\n[features]\nmulti_agent = true\n' > "$ICODEX_HOME_DIR/config.toml"
ensure_iwiki_wiring
cfg="$(cat "$ICODEX_HOME_DIR/config.toml")"
assert_contains "block header present"  "$cfg" "[mcp_servers.iwiki]"
assert_contains "command present"       "$cfg" "/home/ikeniborn/.local/bin/iwiki-mcp"
assert_contains "env_vars present"      "$cfg" 'env_vars = ["IWIKI_LLM_KEY"]'
assert_contains "base dir present"      "$cfg" "IWIKI_BASE_DIR"
assert_contains "original key kept"     "$cfg" 'model = "gpt-5.5"'
assert_eq "exactly one start marker" "1" "$(grep -c '# icodex:iwiki:start' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "region is at end of file" "# icodex:iwiki:end" "$(tail -n1 "$ICODEX_HOME_DIR/config.toml")"

# --- idempotent: second run is byte-identical ---
before="$(cat "$ICODEX_HOME_DIR/config.toml")"
ensure_iwiki_wiring
after="$(cat "$ICODEX_HOME_DIR/config.toml")"
assert_eq "idempotent second run" "$before" "$after"
assert_eq "still one start marker" "1" "$(grep -c '# icodex:iwiki:start' "$ICODEX_HOME_DIR/config.toml")"

# --- stale region is replaced, not duplicated ---
cat > "$ICODEX_HOME_DIR/config.toml" <<'EOF'
model = "gpt-5.5"
# icodex:iwiki:start
[mcp_servers.iwiki]
command = "/old/path/iwiki-mcp"
# icodex:iwiki:end
EOF
ensure_iwiki_wiring
cfg="$(cat "$ICODEX_HOME_DIR/config.toml")"
assert_eq "stale: one start marker" "1" "$(grep -c '# icodex:iwiki:start' "$ICODEX_HOME_DIR/config.toml")"
assert_contains "stale: new command" "$cfg" "/home/ikeniborn/.local/bin/iwiki-mcp"
assert_eq "stale: old command gone" "0" "$(grep -c '/old/path/iwiki-mcp' "$ICODEX_HOME_DIR/config.toml")"

# --- no-op when home is unset ---
unset ICODEX_HOME_DIR
assert_exit "unset home -> noop 0" 0 ensure_iwiki_wiring

# --- no-op when config.toml is absent ---
export ICODEX_HOME_DIR="$tmp/empty"
mkdir -p "$ICODEX_HOME_DIR"
assert_exit "absent config -> noop 0" 0 ensure_iwiki_wiring
assert_eq "absent config not created" "1" "$([[ -f "$ICODEX_HOME_DIR/config.toml" ]] && echo 0 || echo 1)"

finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_iwiki_wiring.sh`
Expected: FAIL — `iwiki module exists` fails (file absent), test exits early.

- [ ] **Step 3: Create `lib/iwiki/iwiki.sh`**

```bash
#!/usr/bin/env bash
# Wire the iwiki MCP server into the per-project Codex home config.toml at launch.
# Always on: a delimited region registers [mcp_servers.iwiki]. Non-secret settings
# are literal; the secret IWIKI_LLM_KEY is forwarded from the environment via
# env_vars (mapped by apply_iwiki_env in lib/config/env.sh). Mirrors the region
# mechanism in lib/config/isolated.sh (_sync_agents_base_region).

_IWIKI_REGION_START="# icodex:iwiki:start"
_IWIKI_REGION_END="# icodex:iwiki:end"

# Emit the static [mcp_servers.iwiki] block (without the region markers).
# command/env_vars precede the [.env] subtable header so they bind to the
# parent table, not the subtable.
_iwiki_region_body() {
  cat <<'EOF'
[mcp_servers.iwiki]
command = "/home/ikeniborn/.local/bin/iwiki-mcp"
env_vars = ["IWIKI_LLM_KEY"]
[mcp_servers.iwiki.env]
IWIKI_BASE_DIR = "/home/ikeniborn/Documents/Project/iwiki-personal"
IWIKI_LLM_BASE_URL = "https://litellm.ikeniborn.ru/v1"
IWIKI_EMBED_MODEL = "ollama-bge-m3"
IWIKI_EMBED_DIMENSIONS = "1024"
EOF
}

# Strip any existing iwiki region from the home config.toml, then append a fresh
# one at the end of the file. Idempotent: rewrites only when the content differs.
# No-op when ICODEX_HOME_DIR is unset or the config file does not exist.
ensure_iwiki_wiring() {
  [[ -n "${ICODEX_HOME_DIR:-}" ]] || return 0
  local file="$ICODEX_HOME_DIR/config.toml" body tmp
  [[ -f "$file" ]] || return 0
  body="$(_iwiki_region_body)"
  tmp="$(mktemp)"
  awk -v s="$_IWIKI_REGION_START" -v e="$_IWIKI_REGION_END" '
    $0 == s { skip=1; next }
    $0 == e { skip=0; next }
    !skip { print }
  ' "$file" > "$tmp"
  printf '%s\n%s\n%s\n' "$_IWIKI_REGION_START" "$body" "$_IWIKI_REGION_END" >> "$tmp"
  if ! cmp -s "$tmp" "$file"; then
    cat "$tmp" > "$file"
  fi
  rm -f "$tmp"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_iwiki_wiring.sh`
Expected: PASS (`PASS=… FAIL=0`).

- [ ] **Step 5: Commit**

```bash
git add lib/iwiki/iwiki.sh tests/test_iwiki_wiring.sh
git commit -m "feat(iwiki): add ensure_iwiki_wiring region for Codex config.toml

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 6: Write the failing binding test**

Create `tests/test_iwiki_binding.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/iwiki/iwiki.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- seeds .iwiki.toml with domain == project basename when absent ---
export ICODEX_PROJECT_ROOT="$tmp/myproj"
export ICODEX_HOME_DIR="$tmp/home"
mkdir -p "$ICODEX_PROJECT_ROOT" "$ICODEX_HOME_DIR"
ensure_iwiki_binding
toml="$(cat "$ICODEX_PROJECT_ROOT/.iwiki.toml")"
assert_contains "seed read domain"  "$toml" 'read = ["myproj"]'
assert_contains "seed write domain" "$toml" 'write = "myproj"'
assert_eq "home symlink created" "0" "$([[ -L "$ICODEX_HOME_DIR/.iwiki.toml" ]] && echo 0 || echo 1)"
assert_eq "symlink target" "$ICODEX_PROJECT_ROOT/.iwiki.toml" "$(readlink "$ICODEX_HOME_DIR/.iwiki.toml")"

# --- never overwrites an existing project .iwiki.toml ---
printf 'read = ["custom"]\nwrite = "custom"\n' > "$ICODEX_PROJECT_ROOT/.iwiki.toml"
ensure_iwiki_binding
toml="$(cat "$ICODEX_PROJECT_ROOT/.iwiki.toml")"
assert_contains "existing preserved" "$toml" 'read = ["custom"]'
assert_eq "no basename overwrite" "0" "$(grep -c 'myproj' "$ICODEX_PROJECT_ROOT/.iwiki.toml")"

# --- idempotent: symlink stable across a second run ---
before="$(readlink "$ICODEX_HOME_DIR/.iwiki.toml")"
ensure_iwiki_binding
assert_eq "symlink stable" "$before" "$(readlink "$ICODEX_HOME_DIR/.iwiki.toml")"

# --- re-points a stale home symlink ---
rm -f "$ICODEX_HOME_DIR/.iwiki.toml"
ln -s "$tmp/old-target" "$ICODEX_HOME_DIR/.iwiki.toml"
ensure_iwiki_binding
assert_eq "stale symlink re-pointed" "$ICODEX_PROJECT_ROOT/.iwiki.toml" "$(readlink "$ICODEX_HOME_DIR/.iwiki.toml")"

# --- no-op when project root unset ---
unset ICODEX_PROJECT_ROOT
assert_exit "unset project root -> noop 0" 0 ensure_iwiki_binding

# --- no-op when home unset ---
export ICODEX_PROJECT_ROOT="$tmp/myproj"; unset ICODEX_HOME_DIR
assert_exit "unset home -> noop 0" 0 ensure_iwiki_binding

finish
```

- [ ] **Step 7: Run test to verify it fails**

Run: `bash tests/test_iwiki_binding.sh`
Expected: FAIL — `ensure_iwiki_binding` is undefined (function not found → assertions error / non-zero).

- [ ] **Step 8: Add `ensure_iwiki_binding` to `lib/iwiki/iwiki.sh`**

Append to `lib/iwiki/iwiki.sh` (after `ensure_iwiki_wiring`):

```bash
# Seed a project-root .iwiki.toml (domain == project basename) when absent and
# symlink it into the Codex home so the iwiki MCP server (cwd == CODEX_HOME)
# resolves the per-project read/write binding. Never overwrites an existing
# project .iwiki.toml (it is the user's truth, e.g. a prior wiki_bind). No-op
# when the project root or home is unknown.
ensure_iwiki_binding() {
  [[ -n "${ICODEX_PROJECT_ROOT:-}" && -n "${ICODEX_HOME_DIR:-}" ]] || return 0
  local toml="$ICODEX_PROJECT_ROOT/.iwiki.toml" link="$ICODEX_HOME_DIR/.iwiki.toml" domain
  domain="$(basename "$ICODEX_PROJECT_ROOT")"
  if [[ ! -e "$toml" ]]; then
    printf 'read = ["%s"]\nwrite = "%s"\n' "$domain" "$domain" > "$toml"
  fi
  if [[ -L "$link" ]]; then
    [[ "$(readlink "$link")" == "$toml" ]] || { rm -f "$link"; ln -s "$toml" "$link"; }
  elif [[ ! -e "$link" ]]; then
    ln -s "$toml" "$link"
  fi
}
```

- [ ] **Step 9: Run test to verify it passes**

Run: `bash tests/test_iwiki_binding.sh`
Expected: PASS (`PASS=… FAIL=0`).

- [ ] **Step 10: Commit**

```bash
git add lib/iwiki/iwiki.sh tests/test_iwiki_binding.sh
git commit -m "feat(iwiki): seed .iwiki.toml and symlink it into the Codex home

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `icodex.sh` — source the module and call it at launch

**Files:**
- Modify: `icodex.sh` (module `source` loop lines 16-22; `main()` after `apply_api_key` line 27; `main()` after `ensure_idd_wiring` line 60)

**Interfaces:**
- Consumes: `apply_iwiki_env` (Task 1), `ensure_iwiki_wiring` + `ensure_iwiki_binding` (Task 2).
- Produces: a launch path that exports `IWIKI_LLM_KEY`, writes the iwiki region into the active home `config.toml`, and seeds + symlinks `.iwiki.toml` on every run.

- [ ] **Step 1: Add the module to the `source` loop**

In `icodex.sh`, change the loop list (lines 16-19) from:

```bash
for m in core/logging core/init core/validation command/args \
         binary/detect binary/lockfile binary/install \
         config/isolated config/permissions config/sandbox config/env proxy/proxy symlink/symlink \
         plugin/superpowers caveman/caveman idd/idd launcher/launch; do
```

to (add `iwiki/iwiki` after `idd/idd`):

```bash
for m in core/logging core/init core/validation command/args \
         binary/detect binary/lockfile binary/install \
         config/isolated config/permissions config/sandbox config/env proxy/proxy symlink/symlink \
         plugin/superpowers caveman/caveman idd/idd iwiki/iwiki launcher/launch; do
```

- [ ] **Step 2: Call `apply_iwiki_env` after `apply_api_key`**

In `main()`, change (line 27 area):

```bash
  load_config "$ICODEX_CONFIG"
  apply_api_key
  parse_args "$@"
```

to:

```bash
  load_config "$ICODEX_CONFIG"
  apply_api_key
  apply_iwiki_env
  parse_args "$@"
```

- [ ] **Step 3: Call `ensure_iwiki_wiring` and `ensure_iwiki_binding` after `ensure_idd_wiring`**

In `main()`, in the default run block, change (line 60 area):

```bash
  ensure_caveman_wiring
  ensure_idd_wiring
  install_ensure || exit 1
```

to:

```bash
  ensure_caveman_wiring
  ensure_idd_wiring
  ensure_iwiki_wiring
  ensure_iwiki_binding
  install_ensure || exit 1
```

(Both run after `setup_codex_home`, which calls `resolve_codex_home` to set `ICODEX_PROJECT_ROOT` and create the home — so both `ensure_iwiki_binding` inputs are populated.)

- [ ] **Step 4: Verify the script parses and the wiring is present**

Run: `bash -n icodex.sh`
Expected: no output, exit 0 (syntax OK).

Run: `grep -n "iwiki/iwiki\|apply_iwiki_env\|ensure_iwiki_wiring\|ensure_iwiki_binding" icodex.sh`
Expected: four matches — the module in the `source` loop, `apply_iwiki_env` after `apply_api_key`, and `ensure_iwiki_wiring` + `ensure_iwiki_binding` after `ensure_idd_wiring`.

- [ ] **Step 5: Verify the module loads in icodex.sh's source order**

Run:
```bash
bash -c 'ICODEX_ROOT="$PWD"; for m in core/logging core/init core/validation command/args binary/detect binary/lockfile binary/install config/isolated config/permissions config/sandbox config/env proxy/proxy symlink/symlink plugin/superpowers caveman/caveman idd/idd iwiki/iwiki launcher/launch; do source "lib/$m.sh" || { echo "FAIL $m"; exit 1; }; done; type apply_iwiki_env ensure_iwiki_wiring ensure_iwiki_binding >/dev/null && echo OK'
```
Expected: `OK` (all modules source cleanly and the three functions are defined).

- [ ] **Step 6: Run the full relevant test set**

Run: `bash tests/test_iwiki_env.sh && bash tests/test_iwiki_wiring.sh && bash tests/test_iwiki_binding.sh && bash tests/test_env.sh`
Expected: each prints `PASS=… FAIL=0`.

- [ ] **Step 7: Commit**

```bash
git add icodex.sh
git commit -m "feat(iwiki): wire apply_iwiki_env, ensure_iwiki_wiring and ensure_iwiki_binding into launch

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Config docs + live secret

**Files:**
- Modify: `.codex_config.example` (append iwiki section at end of file)
- Manual (not committed, git-ignored): `.codex_config`

**Interfaces:**
- Consumes: `apply_iwiki_env` / `load_config` (Task 1) read `ICODEX_IWIKI_LLM_KEY` from `.codex_config`.
- Produces: documented config key; live secret available to launches.

- [ ] **Step 1: Append the iwiki section to `.codex_config.example`**

Add at the end of `.codex_config.example`:

```bash
# iwiki MCP server (always on in every Codex home). All non-secret settings are
# fixed in the [mcp_servers.iwiki] block (see lib/iwiki/iwiki.sh): base dir, LLM
# base URL, embed model/dimensions. The ONLY key needed here is the secret API
# key, forwarded to the server as IWIKI_LLM_KEY via the config.toml `env_vars`
# allowlist. Keep it here (this file is git-ignored, chmod 600) — never in a
# tracked config.
#ICODEX_IWIKI_LLM_KEY=sk-...
```

- [ ] **Step 2: Verify the example documents only the secret**

Run: `grep -c '^#ICODEX_IWIKI_' .codex_config.example`
Expected: `1` (only the single commented `ICODEX_IWIKI_LLM_KEY` line; no other iwiki keys, because the rest are literal in the block).

Run: `grep -ci 'sk-secret\|5Z3\|actual.key' .codex_config.example`
Expected: `0` (no real secret value in the tracked example).

- [ ] **Step 3: Commit the example**

```bash
git add .codex_config.example
git commit -m "docs(iwiki): document ICODEX_IWIKI_LLM_KEY in config example

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 4: Add the live secret (manual, not committed)**

Add the real key to the git-ignored `.codex_config`. Use the existing value from the Claude-side registration (`.claude.json` `mcpServers.iwiki.env.IWIKI_LLM_KEY`). Run:

```bash
grep -q '^ICODEX_IWIKI_LLM_KEY=' .codex_config || printf 'ICODEX_IWIKI_LLM_KEY=%s\n' '<paste-secret-here>' >> .codex_config
chmod 600 .codex_config
git check-ignore .codex_config
```
Expected: `git check-ignore` prints `.codex_config` (confirming it is git-ignored, so the secret will not be committed). Do **not** `git add .codex_config`.

---

## Task 5: End-to-end verification in a live home

**Files:** none (verification only)

**Interfaces:**
- Consumes: the full launch wiring (Tasks 1-4).
- Produces: confirmation that a real per-home `config.toml` ends up with a valid, parseable `[mcp_servers.iwiki]` block, and that `.iwiki.toml` is seeded + symlinked.

- [ ] **Step 1: Wire an existing home directly and confirm the region**

Run (uses a real existing home; safe — `ensure_iwiki_wiring` only edits the git-ignored per-home `config.toml`):
```bash
source lib/iwiki/iwiki.sh
export ICODEX_HOME_DIR="$PWD/.codex-homes/icodex-2992c6be0dc6"
ensure_iwiki_wiring
tail -n 12 "$ICODEX_HOME_DIR/config.toml"
```
Expected: the `# icodex:iwiki:start` … `# icodex:iwiki:end` region with the `[mcp_servers.iwiki]` block printed at the end of the file.

- [ ] **Step 2: Confirm the home config.toml is valid TOML**

Run:
```bash
python3 -c "import tomllib,sys; d=tomllib.load(open('$ICODEX_HOME_DIR/config.toml','rb')); print(d['mcp_servers']['iwiki']['command']); print(d['mcp_servers']['iwiki']['env']['IWIKI_BASE_DIR']); print(d['mcp_servers']['iwiki']['env_vars'])"
```
Expected:
```
/home/ikeniborn/.local/bin/iwiki-mcp
/home/ikeniborn/Documents/Project/iwiki-personal
['IWIKI_LLM_KEY']
```

- [ ] **Step 3: Confirm idempotency on the real home**

Run:
```bash
b="$(cat "$ICODEX_HOME_DIR/config.toml")"; ensure_iwiki_wiring; a="$(cat "$ICODEX_HOME_DIR/config.toml")"; [ "$b" = "$a" ] && echo IDEMPOTENT
```
Expected: `IDEMPOTENT`.

- [ ] **Step 4: Verify `.iwiki.toml` seed + home symlink on a temp project**

Run:
```bash
tmp="$(mktemp -d)/myproj"; mkdir -p "$tmp"; export ICODEX_PROJECT_ROOT="$tmp"; export ICODEX_HOME_DIR="$tmp/.home"; mkdir -p "$ICODEX_HOME_DIR"
ensure_iwiki_binding
cat "$ICODEX_PROJECT_ROOT/.iwiki.toml"; readlink "$ICODEX_HOME_DIR/.iwiki.toml"
```
Expected: `.iwiki.toml` printing `read = ["myproj"]` / `write = "myproj"`, then the readlink prints `$ICODEX_PROJECT_ROOT/.iwiki.toml`.

- [ ] **Step 5 (optional, requires the secret set): smoke-launch Codex**

If a real run is desired: `./icodex.sh` in a project, then inside the session list MCP tools and confirm the `wiki_*` tools appear (and `wiki_status` reports the base and the project's bound domain). If embeddings calls fail, check that `ICODEX_IWIKI_LLM_KEY` is set in `.codex_config`.

---

## Self-Review

**Spec coverage:**
- Static server block (Component 1) → Task 2 (`_iwiki_region_body`), verified Task 5 Step 2.
- `.codex_config` / `.codex_config.example` secret-only (Component 2) → Task 4.
- `env.sh` allowlist + `apply_iwiki_env` (Component 3) → Task 1.
- `lib/iwiki/iwiki.sh` region resync + `.iwiki.toml` binding (Component 4) → Task 2 (`ensure_iwiki_wiring`, `ensure_iwiki_binding`).
- Per-project binding via `.iwiki.toml` (seed domain==basename, never overwrite, home symlink) → Task 2 Steps 6-10, verified Task 5 Step 4.
- `icodex.sh` source + three calls (Component 5) → Task 3.
- Error handling (missing secret/binary; region/binding write safety) → covered by `apply_iwiki_env` no-op (Task 1), region + binding no-op guards (Task 2), and Task 5 verification.
- Testing section (`test_iwiki_wiring.sh`, `test_iwiki_env.sh`, `test_iwiki_binding.sh`) → Tasks 1-2.
- Out of scope items respected: no iclaude changes, no isolated install, no `IWIKI_PROJECT_DIR` (binding via symlink instead), no gate, non-secrets fixed in block.

**Placeholder scan:** No TBD/TODO; every code step shows complete content. The only literal `<paste-secret-here>` is an intentional manual action on a git-ignored file (Task 4 Step 4), not committed code.

**Type/name consistency:** `apply_iwiki_env`, `ensure_iwiki_wiring`, `ensure_iwiki_binding`, `_iwiki_region_body`, `_IWIKI_REGION_START/END`, `ICODEX_IWIKI_LLM_KEY`, `IWIKI_LLM_KEY` used identically across Tasks 1-5. Region markers `# icodex:iwiki:start` / `# icodex:iwiki:end` match between the module and every test/verification. `.iwiki.toml` seed format (`read = ["<basename>"]` / `write = "<basename>"`) matches between Task 2 implementation, its test, and Task 5 Step 4.

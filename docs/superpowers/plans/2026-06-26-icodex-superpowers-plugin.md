---
review:
  plan_hash: 84458bcd8c9518bd
  spec_hash: b1eb4cd16243f9c4
  last_run: 2026-06-26
  phases:
    structure:     { status: passed }
    coverage:      { status: passed }
    dependencies:  { status: passed }
    verifiability: { status: passed }
    consistency:   { status: passed }
  findings:
    - id: F-002
      phase: verifiability
      severity: WARNING
      section: "Task 5 Step 1"
      section_hash: 48c53c5c59e7a019
      fragment: "assert_contains \"install branch has no wiring\" ... \":\""
      text: "The assertion targeted grep -n output, which always begins with 'NN:', so the substring ':' always matched — tautological, did not verify the claim."
      fix: "Replaced with a meaningful check: the install)/update) case lines contain zero ensure_superpowers_wiring calls (grep -c == 0)."
      verdict: fixed
      verdict_at: 2026-06-26
    - id: F-005
      phase: consistency
      severity: INFO
      section: "Task 4 Step 4"
      section_hash: 7751ede50ea2fbef
      fragment: "[features]\\nmulti_agent = true\\n\\nbypass_hook_trust = true"
      text: "bypass_hook_trust placed after [features] would become features.bypass_hook_trust; spec §2 lists it as a top-level key."
      fix: "Moved bypass_hook_trust = true to the root table (before any [section]) in config.toml.example, with an explanatory comment."
      verdict: fixed
      verdict_at: 2026-06-26
    - id: F-001
      phase: verifiability
      severity: INFO
      section: "Task 6 Step 7"
      section_hash: 4bb07083999e29ab
      fragment: "./icodex.sh --version            # materializes config.toml ... (no)"
      text: "The --version line in the executable block verified nothing (it exits before the launch block)."
      fix: "Replaced with `./icodex.sh exec true` to actually trigger the wiring, then the plugin-list check."
      verdict: fixed
      verdict_at: 2026-06-26
    - id: F-003
      phase: verifiability
      severity: INFO
      section: "Task 4 Step 5"
      section_hash: 7751ede50ea2fbef
      fragment: "git check-ignore evaluates the rule, not file presence"
      text: "check-ignore on a not-yet-existing path is correct and depends on the test's cd \"$ROOT\" (already present)."
      fix: "No change required; cd \"$ROOT\" already guarantees repo context."
      verdict: accepted
      verdict_at: 2026-06-26
    - id: F-004
      phase: dependencies
      severity: INFO
      section: "Task 3 Step 3"
      section_hash: cae5e57a367943d3
      fragment: "find ... -name '[0-9]*' | head -1"
      text: "Version-dir match assumes a numeric leading char; fragile only if upstream names a version non-numerically. Network wrapper is unit-test-exempt by design."
      fix: "Acceptable for the pinned sha; could tighten the regex later."
      verdict: accepted
      verdict_at: 2026-06-26
chain:
  intent: null
  spec: docs/superpowers/specs/2026-06-26-icodex-superpowers-plugin-design.md
result_check:
  verdict: OK
  plan_hash: 84458bcd8c9518bd
  last_run: 2026-06-26
---

# Superpowers Codex Plugin Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Superpowers skills framework inside `icodex` as a git-delivered Codex plugin — installed cache, user skills, and wiring all travel in the repo; `--install` builds only the binary (through the configured proxy).

**Architecture:** The plugin's installed cache is committed under `.codex-isolated/plugins/cache/superpowers/superpowers/<ver>/`. The one machine-specific value — the marketplace `source` absolute path — is rewritten at every launch by a new `lib/plugin/superpowers.sh` module from `$ICODEX_ROOT`. The committed `config.toml.example` carries the marketplace/plugin/features wiring; the live `config.toml` is git-ignored runtime, mirroring the existing `.codex_config` / `.codex_config.example` split. A maintainer `scripts/vendor-superpowers.sh` regenerates the committed cache when bumping versions.

**Tech Stack:** Bash (POSIX-ish, `set -euo pipefail`), the OpenAI Codex CLI (`codex plugin …`), the project's dependency-free `tests/helpers.sh` harness, `awk`/`rsync`/`find`/`curl`.

## Global Constraints

- Branch: `dev-superpowers-plugin` (already created from main); never commit to main; close via PR. The spec + report commit already landed.
- All shell modules start with `#!/usr/bin/env bash`; library functions assume the entrypoint set `set -euo pipefail`. Tests use `set -uo pipefail`.
- All code comments, commit messages, docs: English. Conversation: Russian.
- No secrets in committed files. The API key stays in `.codex_config` (`ICODEX_API_KEY`, git-ignored, 0600).
- `.codex-isolated/` is a whitelist gitignore: ignore everything, then re-include only curated, shareable artifacts.
- A fresh clone must be offline-ready except for the binary: no plugin install step, no network for Superpowers.
- Marketplace name: the plan assumed canonicalization to the literal `superpowers`, but the as-built implementation uses the upstream-authoritative `superpowers-dev` (Codex derives the name from the vendored `.claude-plugin/marketplace.json`; canonicalization was not achievable). The name is deterministic/machine-independent and the launcher derives it from the cache path, so it never hard-depends on the literal. See spec §4.1 "As-built note".
- Logging: `log_info` / `log_warn` / `log_error` (from `lib/core/logging.sh`, all to stderr).
- Pin the codex binary present at `.codex-isolated/bin/codex` (codex-cli 0.142.2) is used for the integration verification step.

---

### Task 1: Proxy-aware binary fetch (R4)

Route the binary download **and** the latest-release lookup through `ICODEX_PROXY` from `.codex_config`, unless `--no-proxy` was passed. Today `lib/binary/install.sh` curls GitHub directly, ignoring the proxy.

**Files:**
- Modify: `lib/binary/install.sh` (add `_curl_proxy_args`; wire into `_download` and `_resolve_latest`)
- Test: `tests/test_install.sh` (extend; if absent, create)

**Interfaces:**
- Consumes: `ICODEX_PROXY` and `ICODEX_DISABLE_PROXY` (already exported by `lib/config/env.sh` `load_config` and `lib/command/args.sh` before install runs).
- Produces: `_curl_proxy_args()` → prints `--proxy\n<url>` (two lines) when a proxy applies, nothing otherwise.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_install.sh` (create the file with this content if it does not yet exist):

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/core/init.sh"
source "$ROOT/lib/binary/install.sh"

# _curl_proxy_args emits "--proxy <url>" only when a proxy is set and not disabled
unset ICODEX_DISABLE_PROXY
out="$(ICODEX_PROXY='http://p:8080' _curl_proxy_args | tr '\n' ' ')"
assert_eq "proxy args when set"     "--proxy http://p:8080 " "$out"

out="$(ICODEX_PROXY='http://p:8080' ICODEX_DISABLE_PROXY=1 _curl_proxy_args | tr '\n' ' ')"
assert_eq "no args when disabled"   "" "$out"

out="$(unset ICODEX_PROXY; _curl_proxy_args | tr '\n' ' ')"
assert_eq "no args when unset"      "" "$out"

finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_install.sh`
Expected: FAIL — `_curl_proxy_args: command not found` (or a FAIL line), since the function does not exist yet.

- [ ] **Step 3: Add the helper and wire the two curl call sites**

In `lib/binary/install.sh`, add the helper near the top of the `--- Seams ---` block:

```bash
# Emit curl proxy args from .codex_config (ICODEX_PROXY), honoring --no-proxy.
# One arg per line so callers can read it into an array.
_curl_proxy_args() {
  [[ -n "${ICODEX_PROXY:-}" ]] || return 0
  (( ${ICODEX_DISABLE_PROXY:-0} )) && return 0
  printf '%s\n' "--proxy" "$ICODEX_PROXY"
}
```

Replace `_download` with:

```bash
_download() { # <url> <dest>
  local pargs=(); while IFS= read -r a; do pargs+=("$a"); done < <(_curl_proxy_args)
  curl -fsSL ${pargs[@]+"${pargs[@]}"} "$1" -o "$2"
}
```

Replace `_resolve_latest` with:

```bash
_resolve_latest() {
  local pargs=(); while IFS= read -r a; do pargs+=("$a"); done < <(_curl_proxy_args)
  curl -fsSL ${pargs[@]+"${pargs[@]}"} "https://api.github.com/repos/$ICODEX_REPO/releases/latest" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_install.sh`
Expected: PASS — all three `_curl_proxy_args` assertions, `FAIL=0`.

- [ ] **Step 5: Commit**

```bash
git add lib/binary/install.sh tests/test_install.sh
git commit -m "feat(install): route binary fetch through ICODEX_PROXY"
```

---

### Task 2: Plugin wiring module (`lib/plugin/superpowers.sh`) (R3, R5)

The heart of the integration: at launch, materialize the live `config.toml` from the committed example and rewrite the marketplace `source` line to this host's absolute cache path. Pure filesystem logic, fully testable offline.

**Files:**
- Create: `lib/plugin/superpowers.sh`
- Test: `tests/test_plugin.sh`

**Interfaces:**
- Consumes: `ICODEX_ROOT`, `ICODEX_HOME_DIR` (from `lib/core/init.sh`); `log_warn` / `log_error`.
- Produces:
  - `_superpowers_cache_dir()` → prints the absolute vendored cache dir (`…/plugins/cache/<mkt>/superpowers/<ver>`) or nothing.
  - `_superpowers_marketplace_name <cache_dir>` → prints the marketplace name (`superpowers`).
  - `_rewrite_marketplace_source <config> <mkt> <abs>` → idempotently rewrites the `source` line inside `[marketplaces.<mkt>]`.
  - `ensure_superpowers_wiring()` → orchestrates the above; safe no-op + warn when the plugin is not vendored.

- [ ] **Step 1: Write the failing test**

Create `tests/test_plugin.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"

# Build a fake isolated home with a vendored cache + example config.
tmp="$(mktemp -d)"
export ICODEX_ROOT="$tmp"
export ICODEX_HOME_DIR="$tmp/.codex-isolated"
CACHE="$ICODEX_HOME_DIR/plugins/cache/superpowers/superpowers/6.0.3"
mkdir -p "$CACHE/.codex-plugin"
printf '{}' > "$CACHE/.codex-plugin/plugin.json"
cat > "$ICODEX_HOME_DIR/config.toml.example" <<'EOF'
[marketplaces.superpowers]
source_type = "local"
source = "__ICODEX_ROOT__/.codex-isolated/plugins/cache/superpowers/superpowers/<ver>"

[plugins."superpowers@superpowers"]
enabled = true
EOF

source "$ROOT/lib/plugin/superpowers.sh"

# 1. first run: materialize config.toml and rewrite source to the absolute cache dir
ensure_superpowers_wiring
cfg="$ICODEX_HOME_DIR/config.toml"
assert_exit "config.toml materialized" 0 test -f "$cfg"
assert_eq "source rewritten to abs cache" "1" \
  "$(grep -c "^source = \"$CACHE\"$" "$cfg")"

# 2. idempotent: a second call leaves the file byte-identical
before="$(cat "$cfg")"; ensure_superpowers_wiring
assert_eq "idempotent second call" "$before" "$(cat "$cfg")"

# 3. CWD-independence: run from an unrelated dir, still resolves and rewrites
( cd /tmp && ensure_superpowers_wiring )
assert_eq "still correct after foreign CWD" "1" \
  "$(grep -c "^source = \"$CACHE\"$" "$cfg")"

# 4. stale source is corrected
sed -i 's#^source = .*#source = "/wrong/path"#' "$cfg"
ensure_superpowers_wiring
assert_eq "stale source corrected" "1" \
  "$(grep -c "^source = \"$CACHE\"$" "$cfg")"

# 5. other marketplace sections are untouched
printf '\n[marketplaces.other]\nsource = "/keep/me"\n' >> "$cfg"
ensure_superpowers_wiring
assert_eq "other section preserved" "1" "$(grep -c '^source = "/keep/me"$' "$cfg")"

# 6. missing cache -> warn, no crash, no rewrite
rm -rf "$ICODEX_HOME_DIR/plugins"
warn="$(ensure_superpowers_wiring 2>&1 >/dev/null)"
assert_contains "warns when not vendored" "$warn" "not vendored"

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_plugin.sh`
Expected: FAIL — `lib/plugin/superpowers.sh: No such file or directory`.

- [ ] **Step 3: Write the module**

Create `lib/plugin/superpowers.sh`:

```bash
#!/usr/bin/env bash
# Wire the git-vendored Superpowers plugin into the live config.toml at launch.
#
# The committed artifact is path-portable: the marketplace `source` must resolve
# to a valid path on every host and is rewritten here from $ICODEX_ROOT. Codex
# validates the source on every launch, so this runs on the default (launch) path.

# Echo the absolute vendored cache dir, or nothing when the plugin is not vendored.
# Anchored at $ICODEX_ROOT so the glob is independent of the process CWD.
_superpowers_cache_dir() {
  local m
  for m in "$ICODEX_ROOT"/.codex-isolated/plugins/cache/*/superpowers/*/; do
    [[ -d "$m" ]] || continue
    printf '%s\n' "${m%/}"
    return 0
  done
  return 0
}

# Derive the marketplace name from the cache path: …/cache/<mkt>/superpowers/<ver>
_superpowers_marketplace_name() { # <cache_dir>
  basename "$(dirname "$(dirname "$1")")"
}

# Idempotently rewrite the `source` line inside [marketplaces.<mkt>] to <abs>.
_rewrite_marketplace_source() { # <config> <mkt> <abs>
  local config="$1" mkt="$2" abs="$3" tmp
  tmp="$(mktemp)"
  awk -v mkt="$mkt" -v abs="$abs" '
    /^\[/ { insec = ($0 == "[marketplaces." mkt "]") }
    insec && /^[[:space:]]*source[[:space:]]*=/ { print "source = \"" abs "\""; next }
    { print }
  ' "$config" > "$tmp"
  cmp -s "$tmp" "$config" || cat "$tmp" > "$config"
  rm -f "$tmp"
}

# Orchestrate: materialize config.toml from the example, then fix the source path.
ensure_superpowers_wiring() {
  local example="$ICODEX_HOME_DIR/config.toml.example"
  local config="$ICODEX_HOME_DIR/config.toml"
  if [[ ! -f "$config" ]]; then
    if [[ -f "$example" ]]; then
      cp "$example" "$config"
    else
      log_error "missing $example — cannot configure superpowers"
      return 0
    fi
  fi
  local cache mkt
  cache="$(_superpowers_cache_dir)"
  if [[ -z "$cache" ]]; then
    log_warn "superpowers plugin not vendored under .codex-isolated/plugins/cache"
    return 0
  fi
  mkt="$(_superpowers_marketplace_name "$cache")"
  _rewrite_marketplace_source "$config" "$mkt" "$cache"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_plugin.sh`
Expected: PASS — all six groups, `FAIL=0`.

- [ ] **Step 5: Commit**

```bash
git add lib/plugin/superpowers.sh tests/test_plugin.sh
git commit -m "feat(plugin): launch-time superpowers wiring via ICODEX_ROOT"
```

---

### Task 3: Maintainer vendoring — normalize logic (`scripts/vendor-superpowers.sh`)

The maintainer tool that turns a real `codex plugin add` into the committed cache. Split into a thin network wrapper (calls codex into a scratch home) and a pure `_vendor_normalize` function (copy → strip `.git`/nested `.gitignore` → canonical path → hygiene asserts) that is unit-tested on a fixture.

**Files:**
- Create: `scripts/vendor-superpowers.sh`
- Test: `tests/test_vendor.sh`

**Interfaces:**
- Consumes: `log_error` / `log_info`; `rsync`, `find`.
- Produces: `_vendor_normalize <src_cache_dir> <dest_cache_root> <plugin> <ver>` → writes `<dest_cache_root>/superpowers/<plugin>/<ver>/`, stripped and verified; returns non-zero on hygiene failure.

- [ ] **Step 1: Write the failing test**

Create `tests/test_vendor.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/scripts/vendor-superpowers.sh"   # sourcing must not execute the wrapper

tmp="$(mktemp -d)"
# fake scratch cache with auto-derived marketplace name, nested .git + .gitignore
SRC="$tmp/scratch/plugins/cache/superpowers-dev/superpowers/6.0.3"
mkdir -p "$SRC/.codex-plugin" "$SRC/.git" "$SRC/skills/brainstorming"
printf '{}' > "$SRC/.codex-plugin/plugin.json"
printf 'tmp/\n' > "$SRC/.gitignore"
printf 'x\n'    > "$SRC/skills/brainstorming/.gitignore"

DEST="$tmp/.codex-isolated/plugins/cache"
_vendor_normalize "$SRC" "$DEST" superpowers 6.0.3
out="$DEST/superpowers/superpowers/6.0.3"

assert_exit "canonical path created"        0 test -f "$out/.codex-plugin/plugin.json"
assert_exit "nested .git stripped"          1 test -d "$out/.git"
assert_eq   "no nested .gitignore remains"  "0" "$(find "$out" -name .gitignore | wc -l | tr -d ' ')"
assert_exit "skill content preserved"       0 test -d "$out/skills/brainstorming"

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_vendor.sh`
Expected: FAIL — `scripts/vendor-superpowers.sh: No such file or directory`.

- [ ] **Step 3: Write the script**

Create `scripts/vendor-superpowers.sh`:

```bash
#!/usr/bin/env bash
# Maintainer tool: regenerate the committed Superpowers plugin cache.
#
#   ./scripts/vendor-superpowers.sh <sha>
#
# Installs Superpowers into a scratch CODEX_HOME via the real `codex plugin`
# commands, then normalizes the produced cache into the repo at the canonical
# path .codex-isolated/plugins/cache/superpowers/superpowers/<ver>/ (git-tracked).
# "Install once on one machine -> deliver via git."
set -euo pipefail
VENDOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Pure: copy a scratch cache dir into the canonical repo location and de-lint it.
_vendor_normalize() { # <src_cache_dir> <dest_cache_root> <plugin> <ver>
  local src="$1" destroot="$2" plugin="$3" ver="$4"
  local dest="$destroot/superpowers/$plugin/$ver"
  rm -rf "$dest"; mkdir -p "$dest"
  rsync -a --delete "$src/" "$dest/"
  rm -rf "$dest/.git"
  find "$dest" -name .gitignore -delete
  [[ -z "$(find "$dest" -name .gitignore -print -quit)" ]] || { log_error "nested .gitignore remained in $dest"; return 1; }
  [[ -f "$dest/.codex-plugin/plugin.json" ]] || { log_error "plugin.json missing after vendoring $dest"; return 1; }
  return 0
}

# Network wrapper — only runs when executed directly, never when sourced by tests.
_vendor_main() {
  local sha="${1:?usage: vendor-superpowers.sh <immutable-sha>}"
  local bin="$VENDOR_ROOT/.codex-isolated/bin/codex"
  [[ -x "$bin" ]] || { log_error "codex binary missing — run ./icodex.sh --install"; return 1; }
  local scratch; scratch="$(mktemp -d)"
  CODEX_HOME="$scratch" "$bin" plugin marketplace add obra/superpowers --ref "$sha" >&2
  local mkt; mkt="$(grep -oE '\[marketplaces\.[^]]+\]' "$scratch/config.toml" | head -1 | sed -E 's/\[marketplaces\.(.+)\]/\1/')"
  CODEX_HOME="$scratch" "$bin" plugin add "superpowers@$mkt" >&2
  local srccache; srccache="$(find "$scratch/plugins/cache" -type d -path '*/superpowers/*' -name '[0-9]*' | head -1)"
  local ver; ver="$(basename "$srccache")"
  _vendor_normalize "$srccache" "$VENDOR_ROOT/.codex-isolated/plugins/cache" superpowers "$ver"
  rm -rf "$scratch"
  log_info "vendored superpowers $ver — update the <ver> note in config.toml.example and: git add .codex-isolated/plugins"
}

# Run the wrapper only on direct execution (so tests can source the file safely).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # shellcheck source=/dev/null
  source "$VENDOR_ROOT/lib/core/logging.sh"
  _vendor_main "$@"
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_vendor.sh`
Expected: PASS — all four assertions, `FAIL=0`.

- [ ] **Step 5: Syntax-check the wrapper and commit**

Run: `bash -n scripts/vendor-superpowers.sh && echo OK`
Expected: `OK`

```bash
git add scripts/vendor-superpowers.sh tests/test_vendor.sh
git commit -m "feat(vendor): superpowers cache vendoring script + normalize tests"
```

---

### Task 4: Committed `config.toml.example` + `.gitignore` whitelist

Create the committed config template carrying the plugin wiring, and flip `.gitignore` so skills, plugins, and the example travel in git while the live `config.toml` and codex-managed system skills stay ignored.

**Files:**
- Create: `.codex-isolated/config.toml.example`
- Modify: `.gitignore`
- Test: `tests/test_gitignore.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: the committed `[marketplaces.superpowers]` / `[plugins."superpowers@superpowers"]` / `[features]` wiring that Task 2's launcher rewrites.

- [ ] **Step 1: Write the failing test**

Create `tests/test_gitignore.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
cd "$ROOT"

ci() { git check-ignore -q "$1"; }   # 0 => ignored, 1 => tracked-eligible

assert_exit "example is tracked"        1 ci .codex-isolated/config.toml.example
assert_exit "live config is ignored"    0 ci .codex-isolated/config.toml
assert_exit "user skills are tracked"   1 ci .codex-isolated/skills/context-awareness/SKILL.md
assert_exit "system skills are ignored" 0 ci .codex-isolated/skills/.system/x
assert_exit "plugin cache is tracked"   1 ci .codex-isolated/plugins/cache/superpowers/superpowers/6.0.3/x
assert_exit "binary stays ignored"      0 ci .codex-isolated/bin/codex

finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_gitignore.sh`
Expected: FAIL — `example is tracked` and the skills/plugins assertions fail (current `.gitignore` ignores them).

- [ ] **Step 3: Update `.gitignore`**

Replace the `.codex-isolated` whitelist block at the top of `.gitignore` with:

```gitignore
# icodex — CODEX_HOME (.codex-isolated) holds the isolated codex state.
# Whitelist: ignore everything, then re-include only curated, shareable artifacts.
.codex-isolated/*
!.codex-isolated/AGENTS.md
!.codex-isolated/AGENTS.override.md
!.codex-isolated/config.toml.example

# user skills travel in git; codex-managed system skills do not
!.codex-isolated/skills/
!.codex-isolated/skills/**
.codex-isolated/skills/.system/

# installed plugins travel in git (no re-install on clone)
!.codex-isolated/plugins/
!.codex-isolated/plugins/**
```

(The previous `!.codex-isolated/config.toml` line is removed — the live `config.toml` is now ignored.)

- [ ] **Step 4: Create `.codex-isolated/config.toml.example`**

Base it on the current committed `config.toml` plus the wiring. Create the file:

```toml
# Codex configuration template for the isolated icodex environment (CODEX_HOME =
# .codex-isolated). The live config.toml is git-ignored and generated from this
# file on first launch; the launcher then rewrites the marketplace `source` line
# to this host's absolute path (see lib/plugin/superpowers.sh).
#
# Do NOT put secrets here. The API key goes in .codex_config as ICODEX_API_KEY
# (git-ignored, chmod 600) or via `codex login` (auth.json, git-ignored).

# Example — point the default provider at a custom OpenAI-compatible endpoint:
#
# model = "gpt-5-codex"
# model_provider = "litellm"
#
# [model_providers.litellm]
# name = "litellm"
# base_url = "https://litellm.ikeniborn.ru/v1"
# env_key = "OPENAI_API_KEY"

# --- Superpowers plugin (vendored under .codex-isolated/plugins/cache) ---
# bypass_hook_trust is a TOP-LEVEL key: it must appear before any [section] so it
# stays in the root table (a key after [features] would become features.bypass_…).
# It lets the plugin's SessionStart hook fire non-interactively.
bypass_hook_trust = true

# The <ver> segment below is illustrative: the launcher rewrites the whole
# `source` line from the real cache path on each run (see spec §4.1/§4.2).
[marketplaces.superpowers]
source_type = "local"
source = "__ICODEX_ROOT__/.codex-isolated/plugins/cache/superpowers/superpowers/<ver>"

[plugins."superpowers@superpowers"]
enabled = true

[features]
multi_agent = true
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test_gitignore.sh`
Expected: PASS — all six assertions. (The plugin-cache assertion checks a path that need not exist yet; `git check-ignore` evaluates the rule, not file presence.)

- [ ] **Step 6: Commit**

```bash
git add .gitignore .codex-isolated/config.toml.example tests/test_gitignore.sh
git commit -m "feat(config): committed config.toml.example + skills/plugins git whitelist"
```

---

### Task 5: Wire the launcher into `icodex.sh`

Source the new module and call `ensure_superpowers_wiring` on the default (launch) path only — never on `--install` / `--update` (those build only the binary).

**Files:**
- Modify: `icodex.sh` (module source list; default branch)
- Test: `tests/test_smoke.sh` (extend; if absent, create)

**Interfaces:**
- Consumes: `ensure_superpowers_wiring` (Task 2).
- Produces: launch ordering — `setup_codex_home` → `ensure_superpowers_wiring` → proxy → `launch_codex`.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_smoke.sh` (create with this content if absent):

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

# icodex.sh must source the plugin module and call ensure_superpowers_wiring
assert_eq "sources plugin module" "1" \
  "$(grep -c 'plugin/superpowers' "$ROOT/icodex.sh")"
assert_eq "calls wiring on launch" "1" \
  "$(grep -c 'ensure_superpowers_wiring' "$ROOT/icodex.sh")"

# install/update branch must NOT call the wiring (binary-only): the single-line
# install)/update) case branches must contain zero ensure_superpowers_wiring calls
assert_eq "install branch binary-only" "0" \
  "$(grep -E 'install\)|update\)' "$ROOT/icodex.sh" | grep -c ensure_superpowers_wiring)"

finish
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_smoke.sh`
Expected: FAIL — `sources plugin module` and `calls wiring on launch` are `0`.

- [ ] **Step 3: Edit `icodex.sh`**

Add `plugin/superpowers` to the module loop (after `launcher/launch`):

```bash
for m in core/logging core/init core/validation command/args \
         binary/detect binary/lockfile binary/install \
         config/isolated config/env proxy/proxy symlink/symlink \
         plugin/superpowers launcher/launch; do
```

In `main()`, in the default (run) section, call the wiring after `setup_codex_home`:

```bash
  # default: run
  setup_codex_home
  ensure_superpowers_wiring
  install_ensure || exit 1
  (( ICODEX_DISABLE_PROXY )) || proxy_apply
  launch_codex ${ICODEX_PASSTHROUGH[@]+"${ICODEX_PASSTHROUGH[@]}"}
```

Leave the `install)` / `update)` branch (which `exit`s before the default block) unchanged — it stays binary-only.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_smoke.sh`
Expected: PASS — all assertions, `FAIL=0`.

- [ ] **Step 5: Run the whole suite**

Run: `for t in tests/test_*.sh; do echo "== $t"; bash "$t" || exit 1; done`
Expected: every file ends `PASS=… FAIL=0`.

- [ ] **Step 6: Commit**

```bash
git add icodex.sh tests/test_smoke.sh
git commit -m "feat(launcher): call superpowers wiring on the launch path"
```

---

### Task 6: Vendor the real plugin + migrate config + README (integration)

The one-time apply: stop tracking the live `config.toml`, vendor the actual plugin cache, commit the user skills, and document it. Ends with an end-to-end offline check against the real codex binary.

**Files:**
- Run: `scripts/vendor-superpowers.sh`
- Remove from index: `.codex-isolated/config.toml`
- Add to index: `.codex-isolated/plugins/cache/superpowers/superpowers/<ver>/**`, `.codex-isolated/skills/**` (minus `.system/`)
- Modify: `README.md`

**Interfaces:**
- Consumes: Tasks 1–5 (proxy fetch, wiring module, vendor script, example+gitignore, launcher hook).
- Produces: a clone-ready repo whose only install action is the binary.

- [ ] **Step 1: Ensure the binary is present (for vendoring + verification)**

Run: `./icodex.sh --install`
Expected: `.codex-isolated/bin/codex` present (fetched through the proxy if `ICODEX_PROXY` is set).

- [ ] **Step 2: Stop tracking the live config.toml**

Run:
```bash
git rm --cached .codex-isolated/config.toml
git check-ignore -q .codex-isolated/config.toml && echo "now ignored"
```
Expected: `now ignored` (the live file stays on disk, untracked).

- [ ] **Step 3: Vendor the real plugin cache**

Pick the Superpowers release commit sha to pin (an immutable commit, not a tag), then:
```bash
./scripts/vendor-superpowers.sh <immutable-sha>
ls .codex-isolated/plugins/cache/superpowers/superpowers/
```
Expected: a single `<ver>/` directory (e.g. `6.0.3/`) containing `.codex-plugin/plugin.json`, `skills/`, `hooks/`. Update the `<ver>` note in `config.toml.example` if the comment should name the concrete version.

- [ ] **Step 4: Verify vendoring hygiene**

Run:
```bash
find .codex-isolated/plugins/cache -name .gitignore
git ls-files .codex-isolated/plugins/cache | wc -l
```
Expected: the `find` prints nothing; the `wc -l` is > 0 (tree fully tracked).

- [ ] **Step 5: Stage skills + plugins, confirm system skills excluded**

Run:
```bash
git add .codex-isolated/skills .codex-isolated/plugins
git status --short .codex-isolated/skills/.system 2>/dev/null
git ls-files .codex-isolated/skills/.system | wc -l
```
Expected: the last `wc -l` is `0` (system skills not staged).

- [ ] **Step 6: Update README**

In `README.md`, under "What lives in git", replace the bullet that says `config.toml` is committed, and add a Superpowers note. Insert:

```markdown
- **Committed** — curated codex config under `CODEX_HOME`: `.codex-isolated/AGENTS.md`,
  `AGENTS.override.md`, and **`config.toml.example`** (the live `config.toml` is generated
  from it on first launch and is git-ignored). The **Superpowers plugin** ships pre-installed:
  its skills (`.codex-isolated/skills/`, excluding codex-managed `.system/`) and its plugin
  cache (`.codex-isolated/plugins/cache/superpowers/…`) are committed, so a clone has the full
  skills framework with **no plugin install** — only the binary is fetched on `--install`.
- The launcher rewrites the plugin's marketplace `source` to this host's absolute path on
  every run (from `ICODEX_ROOT`), so the committed plugin is portable across machines.
```

Also note in the proxy section that `--install` fetches the binary through `ICODEX_PROXY`.

- [ ] **Step 7: End-to-end offline verification**

Run:
```bash
# Trigger the launch path once so ensure_superpowers_wiring materializes config.toml:
./icodex.sh exec true
# Then confirm the plugin loads from the committed cache:
CODEX_HOME="$PWD/.codex-isolated" .codex-isolated/bin/codex plugin list --json 2>/dev/null \
  | grep -o '"name": *"superpowers"' | head -1
```
Expected: `"name": "superpowers"` — the plugin loads from the committed cache after the launcher fixed `source`.

> Note: `--install` / `--update` / `--version` all exit before the launch block, so they never materialize `config.toml`. The wiring runs only on the default launch path; `./icodex.sh exec true` exercises it (a real, harmless codex invocation).

- [ ] **Step 8: Commit**

```bash
git add README.md .codex-isolated/skills .codex-isolated/plugins .gitignore
git commit -m "feat(superpowers): vendor plugin cache + user skills; migrate config.toml -> example"
```

---

### Task 7: Full-suite gate + PR

**Files:** none (verification + PR)

- [ ] **Step 1: Run the entire test suite**

Run: `for t in tests/test_*.sh; do echo "== $t"; bash "$t" || { echo "SUITE FAIL: $t"; exit 1; }; done; echo ALL-GREEN`
Expected: `ALL-GREEN`.

- [ ] **Step 2: Confirm a clean clone would be offline-ready**

Run:
```bash
git ls-files .codex-isolated/plugins/cache | head -1     # cache tracked
git ls-files .codex-isolated/skills | grep -v '/.system/' | head -1   # skills tracked
git check-ignore -q .codex-isolated/config.toml && echo "live config ignored"
```
Expected: a tracked cache path, a tracked skill path, and `live config ignored`.

- [ ] **Step 3: Open the PR**

Use the `git-workflow` skill to push `dev-superpowers-plugin` and open a PR into `main` summarizing: git-delivered Superpowers plugin, binary-only install through proxy, launch-time `source` rewrite via `ICODEX_ROOT`. Then remove the branch's worktree if one was used (none here).

---

## Self-Review

**Spec coverage:**
- R1 (plugin in git) → Task 6 (vendor cache + commit), Task 4 (whitelist). ✓
- R2 (skills in git) → Task 4 (whitelist), Task 6 (stage skills, exclude `.system`). ✓
- R3 (deliver via git, no re-install; install only binary) → Task 2 (wiring, no `plugin add`), Task 5 (launch-only call; install branch untouched), Task 6 (committed cache). ✓
- R4 (binary via proxy) → Task 1. ✓
- R5 (`ICODEX_ROOT` source rewrite; `-c` doesn't work) → Task 2 (`_rewrite_marketplace_source`, anchored glob), Task 5 (launch ordering). ✓
- Spec §4.4 canonical name + pin-by-sha + hygiene → Task 3 (`_vendor_normalize`, sha arg), Task 6 step 4. ✓
- Spec §8 tests (idempotent, stale, CWD-independent, named section, missing cache, proxy on/off, gitignore tracking, no nested .gitignore) → Tasks 1–4 tests. ✓
- Spec §6 migration (`git rm --cached`, example) → Task 6 steps 2/6, Task 4. ✓

**Placeholder scan:** No `TODO`/`TBD`; the only `<ver>` / `<immutable-sha>` / `__ICODEX_ROOT__` tokens are intentional, documented sentinels/arguments, not plan gaps. ✓

**Type/name consistency:** `ensure_superpowers_wiring`, `_superpowers_cache_dir`, `_superpowers_marketplace_name`, `_rewrite_marketplace_source`, `_curl_proxy_args`, `_vendor_normalize` are used with identical names/signatures across the tasks that define and call them. ✓

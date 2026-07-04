---
review:
  plan_hash: ee852834e4b2eccf
  last_run: 2026-07-04
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: null
  spec: docs/superpowers/specs/2026-07-02-05-loen-icodex-integration-design.md
result_check:
  verdict: OK
  plan_hash: ee852834e4b2eccf
  last_run: 2026-07-04
---

# 05 LoEn icodex Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vendor the standalone LoEn plugin source into icodex and wire it into each isolated Codex runtime with mode-controlled enablement.

**Architecture:** Keep LoEn source ownership under `plugins/loen/` and generate a committed Codex cache under `.codex-isolated/plugins/cache/icodex-local/loen/<version>/`. Add a LoEn-specific runtime adapter that creates a per-home local marketplace, symlinks the vendored cache into it, updates the per-project `config.toml`, exports `LOEN_MODE`, and disables LoEn cleanly when `ICODEX_LOEN_MODE=off`. The adapter follows the Superpowers portable-marketplace pattern but does not call Superpowers modules and does not depend on legacy iwiki plugin paths.

**Tech Stack:** Bash modules and fixture tests, Python 3 standard library for JSON manifest parsing, existing Codex plugin marketplace config conventions, iwiki MCP docs updates after implementation.

Spec: `docs/superpowers/specs/2026-07-02-05-loen-icodex-integration-design.md`

---

## Scope Check

This spec covers one subsystem: icodex-side LoEn vendoring and launch-time wiring. It does not change LoEn workflow skills, hook enforcement behavior, agent isolation, automation governance, Codex binary installation, or iwiki MCP registration.

Preserve the existing historical cache under `.codex-isolated/plugins/cache/iclaude/loen/0.5.1/` during this plan. The new adapter must only select `.codex-isolated/plugins/cache/icodex-local/loen/<version>/`, so the older cache cannot be chosen accidentally.

## File Structure

- **Create** `scripts/vendor-loen.sh` - maintainer script that copies `plugins/loen/` into the canonical committed cache, strips generated artifacts, and validates required plugin assets.
- **Create** `lib/plugin/loen.sh` - launch-time adapter for LoEn marketplace creation, `config.toml` upserts, mode handling, and disable behavior.
- **Create** `tests/test_loen_plugin.sh` - focused fixture suite for vendoring, runtime marketplace wiring, mode handling, idempotency, and legacy path exclusion.
- **Modify** `tests/test_update_scope.sh` - extend binary-only install/update coverage so LoEn wiring is not called by `--install` or `--update`.
- **Modify** `icodex.sh` - source `plugin/loen` and call `ensure_loen_wiring` only on the default launch path.
- **Generate** `.codex-isolated/plugins/cache/icodex-local/loen/0.1.0/` - committed cache produced from `plugins/loen/.codex-plugin/plugin.json` version `0.1.0`.
- **Update via iwiki MCP** `loen-overview` and create `loen-icodex-integration` after code passes.

## Execution Prerequisites

Follow the project branch workflow before Task 1. If no suitable `dev-*` branch already exists, use `git-workflow` and `superpowers:using-git-worktrees`: ask whether to create a worktree, then create a branch such as `dev-05-loen-icodex-integration` from the intended base branch. Run all commands from the repository root.

The spec gate is already recorded in `docs/superpowers/specs/2026-07-02-05-loen-icodex-integration-design.md` with hash `49f2df9f89be46c5`. If the spec body changes, rerun:

```text
/check-chain spec docs/superpowers/specs/2026-07-02-05-loen-icodex-integration-design.md
```

Expected: `OK` or `OK (cached, hash match)`.

---

### Task 1: Add LoEn Integration Fixture Coverage

**Files:**
- Create: `tests/test_loen_plugin.sh`
- Modify: `tests/test_update_scope.sh`
- Read: `tests/helpers.sh`
- Read: `docs/superpowers/specs/2026-07-02-05-loen-icodex-integration-design.md`

- [ ] **Step 1: Create the failing LoEn integration suite**

Create `tests/test_loen_plugin.sh` with this content:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

assert_exit "vendor script exists" 0 test -f "$ROOT/scripts/vendor-loen.sh"
assert_exit "loen adapter exists" 0 test -f "$ROOT/lib/plugin/loen.sh"

version="$(python3 - "$ROOT/plugins/loen/.codex-plugin/plugin.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(data["version"])
PY
)"
assert_eq "source manifest version used by integration" "0.1.0" "$version"

repo="$tmp/repo"
mkdir -p "$repo/scripts" "$repo/plugins" "$repo/.codex-isolated/plugins/cache"
cp "$ROOT/scripts/vendor-loen.sh" "$repo/scripts/vendor-loen.sh" 2>/dev/null || true
cp -R "$ROOT/plugins/loen" "$repo/plugins/loen"

vendor_log="$tmp/vendor.log"
vendor_code=0
( cd "$repo" && bash scripts/vendor-loen.sh ) >"$vendor_log" 2>&1 || vendor_code=$?
assert_eq "vendor command exits zero" "0" "$vendor_code"

cache="$repo/.codex-isolated/plugins/cache/icodex-local/loen/$version"
manifest="$cache/.codex-plugin/plugin.json"
assert_exit "canonical loen cache created" 0 test -d "$cache"
assert_exit "vendored cache has codex manifest" 0 test -f "$manifest"
for required in skills hooks agents assets docs; do
  assert_exit "vendored cache preserves $required" 0 test -e "$cache/$required"
done
assert_exit "generated pycache stripped" 1 test -d "$cache/hooks/__pycache__"
assert_eq "generated pyc stripped" "0" "$(find "$cache" -name '*.pyc' | wc -l | tr -d ' ')"
assert_eq "nested git dirs stripped" "0" "$(find "$cache" -name .git -type d | wc -l | tr -d ' ')"
assert_eq "nested gitignore files stripped" "0" "$(find "$cache" -name .gitignore | wc -l | tr -d ' ')"
assert_contains "vendor log names canonical cache" "$(cat "$vendor_log")" ".codex-isolated/plugins/cache/icodex-local/loen/$version"

vendored_summary="$(python3 - "$manifest" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(data.get("name", ""))
print(data.get("version", ""))
print(data.get("skills", ""))
print(data.get("hooks", ""))
print(data.get("agents", ""))
print(data.get("assets", ""))
print(data.get("interface", {}).get("displayName", ""))
PY
)"
assert_eq "vendored manifest name" "loen" "$(sed -n '1p' <<<"$vendored_summary")"
assert_eq "vendored manifest version" "$version" "$(sed -n '2p' <<<"$vendored_summary")"
assert_eq "vendored manifest skills path" "./skills/" "$(sed -n '3p' <<<"$vendored_summary")"
assert_eq "vendored manifest hooks path" "./hooks/hooks.json" "$(sed -n '4p' <<<"$vendored_summary")"
assert_eq "vendored manifest agents path" "./agents/" "$(sed -n '5p' <<<"$vendored_summary")"
assert_eq "vendored manifest assets path" "./assets/" "$(sed -n '6p' <<<"$vendored_summary")"
assert_eq "vendored manifest display name" "LoEn" "$(sed -n '7p' <<<"$vendored_summary")"

export ICODEX_ROOT="$tmp/runtime"
export ICODEX_SHARED_DIR="$ICODEX_ROOT/.codex-isolated"
export ICODEX_HOME_DIR="$ICODEX_ROOT/.codex-homes/demo"
export ICODEX_BIN="$ICODEX_SHARED_DIR/bin/codex"
mkdir -p "$ICODEX_SHARED_DIR/plugins/cache/icodex-local/loen" "$ICODEX_SHARED_DIR/bin" "$ICODEX_HOME_DIR"
cp -R "$cache" "$ICODEX_SHARED_DIR/plugins/cache/icodex-local/loen/$version"
touch "$ICODEX_BIN"
chmod +x "$ICODEX_BIN"

cat > "$ICODEX_HOME_DIR/config.toml" <<'EOF_CONFIG'
bypass_hook_trust = true

[marketplaces.openai-curated]
source_type = "local"
source = "/keep/openai-curated"

[plugins."superpowers@openai-curated"]
enabled = true
EOF_CONFIG

if [[ -f "$ROOT/lib/plugin/loen.sh" ]]; then
  source "$ROOT/lib/plugin/loen.sh"
fi

unset ICODEX_LOEN_MODE LOEN_MODE
wire_code=0
ensure_loen_wiring >/dev/null 2>"$tmp/loen-warn.log" || wire_code=$?
cfg="$ICODEX_HOME_DIR/config.toml"
marketplace="$ICODEX_HOME_DIR/tmp/marketplaces/icodex-local"
assert_eq "loen wiring exits zero" "0" "$wire_code"
assert_eq "default mode exported" "advisory" "${LOEN_MODE:-}"
assert_exit "runtime marketplace manifest created" 0 test -f "$marketplace/.agents/plugins/marketplace.json"
assert_exit "runtime api marketplace manifest created" 0 test -f "$marketplace/.agents/plugins/api_marketplace.json"
assert_exit "runtime loen symlink resolves" 0 test -f "$marketplace/plugins/loen/.codex-plugin/plugin.json"
assert_contains "loen marketplace section written" "$(cat "$cfg")" "[marketplaces.icodex-local]"
assert_contains "loen marketplace source points to runtime root" "$(cat "$cfg")" "source = \"$marketplace\""
assert_contains "loen plugin enabled" "$(cat "$cfg")" "[plugins.\"loen@icodex-local\"]"
assert_contains "loen plugin enabled true" "$(cat "$cfg")" "enabled = true"
assert_contains "other marketplace preserved" "$(cat "$cfg")" "source = \"/keep/openai-curated\""
assert_contains "marketplace manifest names loen" "$(cat "$marketplace/.agents/plugins/marketplace.json")" '"name": "loen"'
assert_contains "marketplace manifest uses relative loen path" "$(cat "$marketplace/.agents/plugins/marketplace.json")" '"path": "./plugins/loen"'

before="$(cat "$cfg")"
ensure_loen_wiring >/dev/null 2>&1
assert_eq "loen wiring idempotent" "$before" "$(cat "$cfg")"

for mode in advisory enforce strict; do
  export ICODEX_LOEN_MODE="$mode"
  ensure_loen_wiring >/dev/null 2>&1
  assert_eq "mode exported: $mode" "$mode" "${LOEN_MODE:-}"
  enabled_count="$(awk '
    /^\[/ { insec = ($0 == "[plugins.\"loen@icodex-local\"]") }
    insec && $0 == "enabled = true" { count++ }
    END { print count + 0 }
  ' "$cfg")"
  assert_eq "plugin enabled in $mode" "1" "$enabled_count"
done

export ICODEX_LOEN_MODE="off"
ensure_loen_wiring >/dev/null 2>&1
assert_eq "off mode exported" "off" "${LOEN_MODE:-}"
off_enabled_count="$(awk '
  /^\[/ { insec = ($0 == "[plugins.\"loen@icodex-local\"]") }
  insec && $0 == "enabled = true" { count++ }
  END { print count + 0 }
' "$cfg")"
assert_eq "off mode leaves no enabled LoEn plugin" "0" "$off_enabled_count"
assert_exit "off mode keeps vendored cache" 0 test -f "$ICODEX_SHARED_DIR/plugins/cache/icodex-local/loen/$version/.codex-plugin/plugin.json"

export ICODEX_LOEN_MODE="bogus"
ensure_loen_wiring >/dev/null 2>"$tmp/invalid-mode.log"
assert_eq "invalid mode falls back to advisory" "advisory" "${LOEN_MODE:-}"
assert_contains "invalid mode warns" "$(cat "$tmp/invalid-mode.log")" "invalid ICODEX_LOEN_MODE"

legacy_refs="$(grep -R "lib/plugin/iwiki.sh" "$ROOT/lib/plugin/loen.sh" 2>/dev/null || true)"
assert_eq "loen adapter does not reference legacy iwiki plugin path" "" "$legacy_refs"

rm -rf "$ICODEX_SHARED_DIR/plugins/cache/icodex-local/loen"
missing_before="$(cat "$cfg")"
unset ICODEX_LOEN_MODE
missing_code=0
missing_warn="$(ensure_loen_wiring 2>&1 >/dev/null)" || missing_code=$?
assert_eq "missing loen cache does not fail" "0" "$missing_code"
assert_contains "missing cache warns" "$missing_warn" "LoEn plugin not vendored"
assert_eq "missing cache leaves config untouched" "$missing_before" "$(cat "$cfg")"

finish
```

Run:

```bash
bash -n tests/test_loen_plugin.sh
```

Expected: exit 0.

- [ ] **Step 2: Replace install/update scope test with LoEn guard coverage**

Replace `tests/test_update_scope.sh` with this content:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

tmp="$(mktemp -d)"
work="$tmp/repo"
mkdir -p "$work/lib/plugin" "$work/lib/core" "$work/lib/command" "$work/lib/binary" \
  "$work/lib/config" "$work/lib/proxy" "$work/lib/symlink" "$work/lib/launcher" \
  "$work/.codex-isolated/bin"

cp "$ROOT/icodex.sh" "$work/icodex.sh"
cp -R "$ROOT/lib" "$work/"
chmod +x "$work/icodex.sh"

cat >> "$work/lib/plugin/superpowers.sh" <<'EOF_STUB'
ensure_superpowers_wiring() {
  echo "ERROR: ensure_superpowers_wiring called during install/update" >&2
  return 99
}
EOF_STUB

cat >> "$work/lib/plugin/loen.sh" <<'EOF_STUB'
ensure_loen_wiring() {
  echo "ERROR: ensure_loen_wiring called during install/update" >&2
  return 98
}
EOF_STUB

cat >> "$work/lib/core/validation.sh" <<'EOF_STUB'
require_tools() { return 0; }
EOF_STUB

cat >> "$work/lib/binary/install.sh" <<'EOF_STUB'
install_ensure() {
  if [[ "${1:-}" == "--update" ]]; then
    echo "install_ensure --update" > "$ICODEX_ROOT/update-called"
    return 0
  fi
  if [[ -z "${1:-}" ]]; then
    echo "install_ensure install" > "$ICODEX_ROOT/install-called"
    return 0
  fi
  return 97
}
ensure_uv_dependency() {
  echo "uv" >> "$ICODEX_ROOT/uv-called"
  return 0
}
EOF_STUB

cat >> "$work/lib/symlink/symlink.sh" <<'EOF_STUB'
install_symlink() { echo "symlink" >> "$ICODEX_ROOT/symlink-called"; }
EOF_STUB

update_out="$("$work/icodex.sh" --update 2>&1)"
update_rc=$?
assert_eq "update exits zero" "0" "$update_rc"
assert_eq "install update called" "install_ensure --update" "$(cat "$work/update-called")"
assert_contains "uv dependency ensured on update" "$(cat "$work/uv-called")" "uv"
assert_contains "symlink refreshed on update" "$(cat "$work/symlink-called")" "symlink"
assert_eq "superpowers not called on update" "0" "$(grep -c 'ensure_superpowers_wiring called' <<<"$update_out")"
assert_eq "loen not called on update" "0" "$(grep -c 'ensure_loen_wiring called' <<<"$update_out")"

install_out="$("$work/icodex.sh" --install 2>&1)"
install_rc=$?
assert_eq "install exits zero" "0" "$install_rc"
assert_eq "install ensure called" "install_ensure install" "$(cat "$work/install-called")"
assert_eq "superpowers not called on install" "0" "$(grep -c 'ensure_superpowers_wiring called' <<<"$install_out")"
assert_eq "loen not called on install" "0" "$(grep -c 'ensure_loen_wiring called' <<<"$install_out")"
assert_exit "install/update did not vendor LoEn" 1 test -d "$work/.codex-isolated/plugins/cache/icodex-local/loen"

rm -rf "$tmp"
finish
```

Run:

```bash
bash -n tests/test_update_scope.sh
```

Expected: exit 0.

- [ ] **Step 3: Run focused tests and verify the expected failures**

Run:

```bash
bash tests/test_loen_plugin.sh
```

Expected: non-zero exit. Output includes at least:

```text
FAIL [vendor script exists]
FAIL [loen adapter exists]
FAIL=
```

Run:

```bash
bash tests/test_update_scope.sh
```

Expected at this point: it may still pass before `icodex.sh` sources LoEn, but after Task 4 it must prove LoEn is not called by `--install` or `--update`.

- [ ] **Step 4: Commit the failing fixture coverage**

```bash
git add tests/test_loen_plugin.sh tests/test_update_scope.sh
git commit -m "test(loen): cover icodex integration wiring"
```

Expected: commit succeeds and includes only the two test files.

---

### Task 2: Implement LoEn Vendoring

**Files:**
- Create: `scripts/vendor-loen.sh`
- Generate: `.codex-isolated/plugins/cache/icodex-local/loen/0.1.0/`
- Test: `tests/test_loen_plugin.sh`

- [ ] **Step 1: Add the LoEn vendoring script**

Create `scripts/vendor-loen.sh` with this content:

```bash
#!/usr/bin/env bash
# Maintainer tool: regenerate the committed LoEn plugin cache from plugins/loen/.
#
#   ./scripts/vendor-loen.sh
#
# The source tree stays editable under plugins/loen/. This script creates the
# portable Codex cache used by icodex launch-time marketplace wiring.
set -euo pipefail
VENDOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOEN_VENDOR_MARKETPLACE="${LOEN_VENDOR_MARKETPLACE:-icodex-local}"

_loen_manifest_version() { # <manifest>
  python3 - "$1" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
name = data.get("name")
version = data.get("version")
if name != "loen":
  raise SystemExit(f"manifest name must be loen, got {name!r}")
if not isinstance(version, str) or not version.strip():
  raise SystemExit("manifest version is missing")
print(version)
PY
}

_loen_validate_cache() { # <cache_dir>
  local cache="$1" manifest="$cache/.codex-plugin/plugin.json" required
  [[ -f "$manifest" ]] || { log_error "plugin.json missing after vendoring $cache"; return 1; }
  for required in skills hooks agents assets docs; do
    [[ -e "$cache/$required" ]] || { log_error "required LoEn asset missing after vendoring: $required"; return 1; }
  done
  [[ -z "$(find "$cache" -name .git -type d -print -quit)" ]] || { log_error "nested .git remained in $cache"; return 1; }
  [[ -z "$(find "$cache" -name .gitignore -print -quit)" ]] || { log_error "nested .gitignore remained in $cache"; return 1; }
  [[ -z "$(find "$cache" -name '*.pyc' -print -quit)" ]] || { log_error "generated pyc remained in $cache"; return 1; }
  [[ -z "$(find "$cache" -type d -name __pycache__ -print -quit)" ]] || { log_error "generated __pycache__ remained in $cache"; return 1; }
}

_vendor_loen_normalize() { # <src_plugin_dir> <dest_cache_root> [marketplace]
  local src="$1" destroot="$2" marketplace="${3:-$LOEN_VENDOR_MARKETPLACE}"
  local manifest version dest
  manifest="$src/.codex-plugin/plugin.json"
  [[ -f "$manifest" ]] || { log_error "LoEn source manifest missing: $manifest"; return 1; }
  version="$(_loen_manifest_version "$manifest")" || return 1
  dest="$destroot/$marketplace/loen/$version"

  rm -rf "$dest"
  mkdir -p "$dest"
  cp -R "$src/." "$dest/"

  find "$dest" -name .git -type d -prune -exec rm -rf {} +
  find "$dest" -type d -name __pycache__ -prune -exec rm -rf {} +
  find "$dest" \( -name .gitignore -o -name '*.pyc' -o -name '.DS_Store' \) -delete
  _loen_validate_cache "$dest"
  printf '%s\n' "$dest"
}

_vendor_loen_main() {
  local dest
  dest="$(_vendor_loen_normalize "$VENDOR_ROOT/plugins/loen" "$VENDOR_ROOT/.codex-isolated/plugins/cache" "$LOEN_VENDOR_MARKETPLACE")" || return 1
  log_info "vendored LoEn to ${dest#$VENDOR_ROOT/}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # shellcheck source=/dev/null
  source "$VENDOR_ROOT/lib/core/logging.sh"
  _vendor_loen_main "$@"
fi
```

Run:

```bash
bash -n scripts/vendor-loen.sh
```

Expected: exit 0.

- [ ] **Step 2: Mark the script executable**

Run:

```bash
chmod +x scripts/vendor-loen.sh
```

Expected: exit 0.

- [ ] **Step 3: Run the vendor command against the real source tree**

Run:

```bash
./scripts/vendor-loen.sh
```

Expected output includes:

```text
vendored LoEn to .codex-isolated/plugins/cache/icodex-local/loen/0.1.0
```

- [ ] **Step 4: Verify the generated cache shape**

Run:

```bash
test -f .codex-isolated/plugins/cache/icodex-local/loen/0.1.0/.codex-plugin/plugin.json
test -d .codex-isolated/plugins/cache/icodex-local/loen/0.1.0/skills
test -d .codex-isolated/plugins/cache/icodex-local/loen/0.1.0/hooks
test -d .codex-isolated/plugins/cache/icodex-local/loen/0.1.0/agents
test -d .codex-isolated/plugins/cache/icodex-local/loen/0.1.0/assets
test -d .codex-isolated/plugins/cache/icodex-local/loen/0.1.0/docs
test "$(find .codex-isolated/plugins/cache/icodex-local/loen/0.1.0 -name '*.pyc' | wc -l | tr -d ' ')" = "0"
```

Expected: exit 0.

- [ ] **Step 5: Run the focused test and verify only adapter failures remain**

Run:

```bash
bash tests/test_loen_plugin.sh
```

Expected: still non-zero until Task 3, but vendoring assertions pass. Remaining failures mention missing `ensure_loen_wiring` or missing LoEn adapter behavior.

- [ ] **Step 6: Commit vendoring**

```bash
git add scripts/vendor-loen.sh .codex-isolated/plugins/cache/icodex-local/loen/0.1.0
git commit -m "feat(loen): vendor plugin cache"
```

Expected: commit succeeds and includes the vendor script plus generated LoEn cache.

---

### Task 3: Implement Runtime LoEn Adapter

**Files:**
- Create: `lib/plugin/loen.sh`
- Test: `tests/test_loen_plugin.sh`

- [ ] **Step 1: Add the launch-time adapter**

Create `lib/plugin/loen.sh` with this content:

```bash
#!/usr/bin/env bash
# Wire the git-vendored LoEn plugin into each per-project Codex home.
#
# LoEn is vendored under .codex-isolated/plugins/cache/icodex-local/loen/<ver>/.
# The runtime marketplace root lives under the per-project CODEX_HOME so Codex
# sees a valid host-local marketplace source on every launch.

_LOEN_MARKETPLACE="icodex-local"

_loen_mode() {
  local value="${ICODEX_LOEN_MODE:-advisory}"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    off|advisory|enforce|strict) printf '%s\n' "$value" ;;
    *)
      log_warn "invalid ICODEX_LOEN_MODE '$value'; using advisory"
      printf 'advisory\n'
      ;;
  esac
}

_loen_cache_dir() {
  local m
  for m in "$ICODEX_SHARED_DIR"/plugins/cache/"$_LOEN_MARKETPLACE"/loen/*/; do
    [[ -d "$m" ]] || continue
    [[ -f "$m/.codex-plugin/plugin.json" ]] || continue
    printf '%s\n' "${m%/}"
    return 0
  done
  return 0
}

_loen_marketplace_name() { # <cache_dir>
  basename "$(dirname "$(dirname "$1")")"
}

_loen_marketplace_root() { # <mkt>
  printf '%s/tmp/marketplaces/%s\n' "$ICODEX_HOME_DIR" "$1"
}

_write_loen_marketplace_manifest() { # <root> <mkt>
  local root="$1" mkt="$2"
  mkdir -p "$root/.agents/plugins"
  cat > "$root/.agents/plugins/marketplace.json" <<EOF
{
  "name": "$mkt",
  "interface": {
    "displayName": "icodex local"
  },
  "plugins": [
    {
      "name": "loen",
      "source": {
        "source": "local",
        "path": "./plugins/loen"
      },
      "policy": {
        "installation": "AVAILABLE",
        "authentication": "ON_INSTALL",
        "products": [
          "CODEX"
        ]
      },
      "category": "Developer Tools"
    }
  ]
}
EOF
  cp "$root/.agents/plugins/marketplace.json" "$root/.agents/plugins/api_marketplace.json"
}

_ensure_loen_marketplace_root() { # <cache_dir> <mkt>
  local cache="$1" mkt="$2" root plugin_link
  root="$(_loen_marketplace_root "$mkt")"
  plugin_link="$root/plugins/loen"

  mkdir -p "$root/plugins"
  if [[ -e "$plugin_link" || -L "$plugin_link" ]]; then
    rm -rf "$plugin_link"
  fi
  ln -s "$cache" "$plugin_link"
  _write_loen_marketplace_manifest "$root" "$mkt"
  printf '%s\n' "$root"
}

_loen_toml_escape() { # <value>
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

_loen_remove_section() { # <config> <header>
  local config="$1" header="$2" tmp
  tmp="$(mktemp)"
  awk -v header="$header" '
    /^\[/ { skip = ($0 == header) }
    !skip { print }
  ' "$config" > "$tmp"
  cmp -s "$tmp" "$config" || cat "$tmp" > "$config"
  rm -f "$tmp"
}

_loen_upsert_marketplace_section() { # <config> <mkt> <source>
  local config="$1" mkt="$2" source="$3" escaped
  escaped="$(_loen_toml_escape "$source")"
  _loen_remove_section "$config" "[marketplaces.$mkt]"
  {
    printf '\n[marketplaces.%s]\n' "$mkt"
    printf 'source_type = "local"\n'
    printf 'source = "%s"\n' "$escaped"
  } >> "$config"
}

_loen_upsert_plugin_section() { # <config> <mkt> <enabled>
  local config="$1" mkt="$2" enabled="$3"
  _loen_remove_section "$config" "[plugins.\"loen@$mkt\"]"
  {
    printf '\n[plugins."loen@%s"]\n' "$mkt"
    printf 'enabled = %s\n' "$enabled"
  } >> "$config"
}

_loen_disable_wiring() { # <config> <mkt>
  local config="$1" mkt="$2"
  _loen_remove_section "$config" "[marketplaces.$mkt]"
  _loen_upsert_plugin_section "$config" "$mkt" "false"
}

ensure_loen_wiring() {
  local config="$ICODEX_HOME_DIR/config.toml"
  if [[ ! -f "$config" ]]; then
    log_error "missing $config - cannot configure LoEn"
    return 0
  fi

  local mode cache mkt marketplace
  mode="$(_loen_mode)"
  export LOEN_MODE="$mode"

  if [[ "$mode" == "off" ]]; then
    _loen_disable_wiring "$config" "$_LOEN_MARKETPLACE"
    return 0
  fi

  cache="$(_loen_cache_dir)"
  if [[ -z "$cache" ]]; then
    log_warn "LoEn plugin not vendored under .codex-isolated/plugins/cache/$_LOEN_MARKETPLACE/loen"
    return 0
  fi

  mkt="$(_loen_marketplace_name "$cache")"
  marketplace="$(_ensure_loen_marketplace_root "$cache" "$mkt")"
  _loen_upsert_marketplace_section "$config" "$mkt" "$marketplace"
  _loen_upsert_plugin_section "$config" "$mkt" "true"
}
```

Run:

```bash
bash -n lib/plugin/loen.sh
```

Expected: exit 0.

- [ ] **Step 2: Run the focused integration suite**

Run:

```bash
bash tests/test_loen_plugin.sh
```

Expected:

```text
FAIL=0
```

- [ ] **Step 3: Run a syntax check for the new Bash files**

Run:

```bash
bash -n scripts/vendor-loen.sh
bash -n lib/plugin/loen.sh
bash -n tests/test_loen_plugin.sh
```

Expected: exit 0.

- [ ] **Step 4: Commit the adapter**

```bash
git add lib/plugin/loen.sh tests/test_loen_plugin.sh
git commit -m "feat(loen): wire runtime marketplace adapter"
```

Expected: commit succeeds and includes the adapter plus any focused test adjustment required by the adapter.

---

### Task 4: Wire LoEn Into the Launch Path

**Files:**
- Modify: `icodex.sh`
- Modify: `tests/test_update_scope.sh`
- Test: `tests/test_loen_plugin.sh`
- Test: `tests/test_update_scope.sh`

- [ ] **Step 1: Source the LoEn adapter in the entrypoint**

In `icodex.sh`, replace the module source list with this exact block:

```bash
for m in core/logging core/init core/validation command/args \
         binary/detect binary/lockfile binary/install \
         config/isolated config/permissions config/sandbox config/env config/ca_trust proxy/proxy symlink/symlink \
         plugin/superpowers plugin/loen caveman/caveman idd/idd iwiki/iwiki launcher/launch; do
  # shellcheck source=/dev/null
  source "$ICODEX_ROOT/lib/$m.sh"
done
```

Run:

```bash
bash -n icodex.sh
```

Expected: exit 0.

- [ ] **Step 2: Call LoEn wiring only on the default run path**

In `icodex.sh`, replace the plugin wiring part of the default run block with this exact sequence:

```bash
  ensure_launcher_binary_permission
  ensure_superpowers_wiring
  ensure_loen_wiring
  ensure_caveman_wiring
  ensure_idd_wiring
  ensure_iwiki_wiring
  ensure_iwiki_binding
  install_ensure || exit 1
```

Do not add `ensure_loen_wiring` to the `install)` or `update)` case arms.

Run:

```bash
grep -n "ensure_loen_wiring" icodex.sh
```

Expected: output has exactly one `ensure_loen_wiring` line, inside the default run block.

- [ ] **Step 3: Run focused launch/update tests**

Run:

```bash
bash tests/test_loen_plugin.sh
bash tests/test_update_scope.sh
```

Expected: both commands exit 0 and print `FAIL=0`.

- [ ] **Step 4: Verify default launch wiring in a copied fixture**

Run:

```bash
tmp="$(mktemp -d)"
mkdir -p "$tmp/repo"
cp -R icodex.sh lib plugins .codex-isolated "$tmp/repo/"
mkdir -p "$tmp/repo/.codex-isolated/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/repo/.codex-isolated/bin/codex"
chmod +x "$tmp/repo/.codex-isolated/bin/codex"
cat >> "$tmp/repo/lib/launcher/launch.sh" <<'EOF'
launch_codex() {
  echo "CODEX_HOME=$CODEX_HOME"
  echo "LOEN_MODE=${LOEN_MODE:-}"
  return 0
}
EOF
( cd "$tmp/repo" && ICODEX_LOEN_MODE=strict ./icodex.sh -- --version )
rm -rf "$tmp"
```

Expected output includes:

```text
LOEN_MODE=strict
```

- [ ] **Step 5: Commit launch wiring**

```bash
git add icodex.sh tests/test_update_scope.sh
git commit -m "feat(loen): enable launch-time wiring"
```

Expected: commit succeeds and includes the entrypoint plus update-scope test.

---

### Task 5: Verify, Document, and Close the Chain

**Files:**
- Read: `docs/superpowers/specs/2026-07-02-05-loen-icodex-integration-design.md`
- Read: `docs/superpowers/plans/2026-07-02-05-loen-icodex-integration.md`
- Update via iwiki MCP: `loen-overview`
- Create via iwiki MCP: `loen-icodex-integration`

- [ ] **Step 1: Run focused tests**

Run:

```bash
bash tests/test_loen_plugin.sh
bash tests/test_update_scope.sh
bash tests/test_loen_plugin_core.sh
```

Expected: each command exits 0 and prints `FAIL=0`.

- [ ] **Step 2: Run the full Bash suite**

Run:

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: exit 0. Every test file prints a final line with `FAIL=0`.

- [ ] **Step 3: Update iwiki overview**

Use `wiki_update_page` on domain `icodex`, slug `loen-overview`, heading `Layer Sequence`, with this section body:

```markdown
LoEn is split into sequential layers. The overview owns shared boundaries and sequencing; each layer owns its own acceptance criteria and implementation plan.

| Order | Layer | Wiki | Scope |
|---|---|---|---|
| 1 | `01-loen-plugin-core` | [[loen-plugin-core]] | Editable plugin source, manifest, skills, templates, inert hook assets, and agent asset names |
| 2 | `02-loen-runtime-artifacts` | [[loen-runtime-artifacts]] | `docs/loen/<topic>/` artifacts, `loop.yaml`, per-topic `audit.html`, and task log row rules |
| 3 | `03-loen-enforcement-hooks` | [[loen-enforcement-hooks]] | Blocking/advisory loop gates, scope guard, tool guard, permission guard, evidence gate, and audit writer behavior |
| 4 | `04-loen-agent-isolation` | [[loen-agent-isolation]] | Planner/worker/verifier/reviewer/researcher role separation, context capsules, Codex profile split metadata, and WASM-first verifier model |
| 5 | `05-loen-icodex-integration` | [[loen-icodex-integration]] | Vendoring, launch-time marketplace wiring, `ICODEX_LOEN_MODE`, and off/advisory/enforce/strict runtime enablement in icodex |
| 6 | `06-loen-automation-governance` | Not implemented yet | Scheduled/background loop governance, human-review counters, and no-auto-merge policy |
```

Expected: MCP call succeeds and auto-reindexes the domain.

- [ ] **Step 4: Create the LoEn icodex integration wiki page**

Use `wiki_write_page` on domain `icodex`, slug `loen-icodex-integration`, source `lib/plugin/loen.sh`, with this markdown:

```markdown
# LoEn icodex Integration

## Overview

The LoEn icodex integration layer vendors the editable `plugins/loen/` source tree into the committed Codex plugin cache and wires that cache into each per-project isolated Codex home at launch time.

This layer is an adapter. LoEn source assets remain independent from icodex internals, while icodex owns cache placement, marketplace source rewriting, mode export, and enable/disable behavior.

## Vendored Cache

`scripts/vendor-loen.sh` copies `plugins/loen/` into `.codex-isolated/plugins/cache/icodex-local/loen/<version>/`, where `<version>` comes from `plugins/loen/.codex-plugin/plugin.json`.

The script validates `.codex-plugin/plugin.json` and required `skills`, `hooks`, `agents`, `assets`, and `docs` directories. It strips generated files such as `__pycache__`, `*.pyc`, nested `.git`, nested `.gitignore`, and `.DS_Store` before the cache is committed.

## Launch Wiring

`lib/plugin/loen.sh` selects only the `icodex-local/loen/<version>` cache, creates a runtime marketplace under `$ICODEX_HOME_DIR/tmp/marketplaces/icodex-local`, symlinks `plugins/loen` to the committed cache, writes `marketplace.json` and `api_marketplace.json`, and upserts `[marketplaces.icodex-local]` plus `[plugins."loen@icodex-local"]` in the per-project `config.toml`.

`icodex.sh` sources `plugin/loen` and calls `ensure_loen_wiring` on the default launch path after Superpowers wiring. The `--install` and `--update` paths remain binary-only and do not call LoEn wiring or vendoring.

## Runtime Modes

`ICODEX_LOEN_MODE` accepts `off`, `advisory`, `enforce`, and `strict`. Unset mode defaults to `advisory`.

For enabled modes, icodex exports `LOEN_MODE` for Codex hook subprocesses and enables the LoEn plugin. In `off` mode, icodex exports `LOEN_MODE=off` and removes or disables runtime LoEn config entries without deleting the editable source tree or committed cache.

Invalid mode values warn and fall back to `advisory`.

## Validation

`tests/test_loen_plugin.sh` validates cache vendoring, required assets, generated artifact stripping, runtime marketplace creation, config upserts, idempotency, mode export, off-mode disable behavior, missing-cache tolerance, and absence of references to legacy `lib/plugin/iwiki.sh`.

`tests/test_update_scope.sh` validates that `--install` and `--update` do not call `ensure_loen_wiring` and do not create a LoEn cache.
```

Expected: MCP call succeeds and auto-reindexes the domain.

- [ ] **Step 5: Run iwiki lint**

Run through MCP:

```text
wiki_lint(domain="icodex")
```

Expected: no broken refs. Pre-existing advisory or stale entries unrelated to this task may remain, but the new `loen-icodex-integration` page must not be orphaned or missing source.

- [ ] **Step 6: Run result reconciliation**

Run:

```text
/check-chain result docs/superpowers/plans/2026-07-02-05-loen-icodex-integration.md
```

Expected: `OK`. The result tab in `docs/superpowers/reports/05-loen-icodex-integration-results.html` is updated, and the chain row closes with `Result: OK`.

- [ ] **Step 7: Commit docs and chain artifacts**

```bash
git add docs/superpowers/specs/2026-07-02-05-loen-icodex-integration-design.md docs/superpowers/plans/2026-07-02-05-loen-icodex-integration.md docs/superpowers/reports/05-loen-icodex-integration-results.html
git commit -m "docs(loen): record icodex integration chain"
```

Expected: commit succeeds and includes only chain artifacts unless `/check-chain result` updated additional chain-generated files.

## Self-Review

Spec coverage:
- Vendoring flow: Task 1 and Task 2.
- Launch-time wiring: Task 1, Task 3, and Task 4.
- Runtime modes: Task 1 and Task 3.
- Legacy iwiki exclusion: Task 1.
- Install/update binary-only behavior: Task 1 and Task 4.
- Acceptance criteria: Task 5 verification and result reconciliation.

Placeholder scan:
- No placeholder tasks are left in this plan.
- Every code-writing step includes the exact file content or exact block to replace.

Type and name consistency:
- Script function names are `_vendor_loen_normalize`, `_vendor_loen_main`, and `ensure_loen_wiring`.
- Marketplace name is consistently `icodex-local`.
- Plugin enablement section is consistently `[plugins."loen@icodex-local"]`.

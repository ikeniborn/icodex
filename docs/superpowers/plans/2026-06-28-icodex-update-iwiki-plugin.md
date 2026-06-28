# icodex Update and iwiki Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep `--update` strictly Codex-binary-only and add `iwiki` as a full git-delivered Codex plugin with skills, engine, and verified hook automation.

**Architecture:** Add a dedicated `lib/plugin/iwiki.sh` beside the existing Superpowers wiring instead of refactoring shared plugin infrastructure. Vendor a Codex-adapted `iwiki` plugin under `.codex-isolated/plugins/cache/ai-wiki/iwiki/<version>/`, rewrite its marketplace `source` at launch, and keep install/update paths free of plugin work.

**Tech Stack:** Bash (`set -euo pipefail` style modules), dependency-free shell tests in `tests/`, Python 3.12 iwiki engine run by `uv`, Codex plugin cache/config layout.

---

## File Structure

- Modify `icodex.sh`: source `plugin/iwiki` and call `ensure_iwiki_wiring` only on the default launch path.
- Create `lib/plugin/iwiki.sh`: launch-time source rewrite for the vendored `iwiki` cache.
- Modify `lib/config/env.sh`: export parsed `IWIKI_*` and `UV_BIN` values from `.codex_config`.
- Modify `.codex-isolated/config.toml.example`: add `[marketplaces.ai-wiki]` and `[plugins."iwiki@ai-wiki"]`.
- Modify `.codex_config.example`: document `IWIKI_*` and `UV_BIN` settings.
- Create `scripts/vendor-iwiki.sh`: maintainer tool that copies and normalizes the `ai-wiki-plugin` source into Codex cache layout.
- Create `tests/test_iwiki_plugin.sh`: unit tests for `lib/plugin/iwiki.sh`.
- Create `tests/test_update_scope.sh`: guard test proving `--update` does not call plugin wiring.
- Create `tests/test_env.sh` additions or a focused new case: verify `IWIKI_*`/`UV_BIN` parsing is explicit and non-executing.
- Create `tests/test_iwiki_vendor.sh`: fixture tests for `scripts/vendor-iwiki.sh`.
- Create `tests/test_iwiki_hooks_probe.sh`: record supported Codex hook events and command context before claiming full automation.
- Commit vendored files under `.codex-isolated/plugins/cache/ai-wiki/iwiki/<version>/` after hygiene checks.
- Modify `README.md`: clarify `--update` binary-only and document iwiki requirements/config.

### Task 1: Guard `--update` Binary-Only Scope

**Files:**
- Create: `tests/test_update_scope.sh`
- Modify: `README.md`
- Test: `tests/test_update_scope.sh`, `tests/test_args.sh`, `tests/test_install.sh`

- [ ] **Step 1: Write the failing update-scope test**

Create `tests/test_update_scope.sh`:

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
  echo "ERROR: ensure_superpowers_wiring called during update" >&2
  return 99
}
EOF_STUB

cat > "$work/lib/plugin/iwiki.sh" <<'EOF_STUB'
ensure_iwiki_wiring() {
  echo "ERROR: ensure_iwiki_wiring called during update" >&2
  return 98
}
EOF_STUB

cat >> "$work/lib/core/validation.sh" <<'EOF_STUB'
require_tools() { return 0; }
EOF_STUB

cat >> "$work/lib/binary/install.sh" <<'EOF_STUB'
install_ensure() {
  [[ "${1:-}" == "--update" ]] || return 97
  echo "install_ensure $1" > "$ICODEX_ROOT/update-called"
  return 0
}
EOF_STUB

cat >> "$work/lib/symlink/symlink.sh" <<'EOF_STUB'
install_symlink() { echo "symlink" > "$ICODEX_ROOT/symlink-called"; }
EOF_STUB

out="$("$work/icodex.sh" --update 2>&1)"
rc=$?
assert_eq "update exits zero" "0" "$rc"
assert_eq "install update called" "install_ensure --update" "$(cat "$work/update-called")"
assert_eq "symlink refreshed" "symlink" "$(cat "$work/symlink-called")"
assert_eq "superpowers not called" "0" "$(grep -c 'ensure_superpowers_wiring called' <<<"$out")"
assert_eq "iwiki not called" "0" "$(grep -c 'ensure_iwiki_wiring called' <<<"$out")"

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run the test to verify current behavior**

Run: `bash tests/test_update_scope.sh`

Expected before implementation: FAIL if `icodex.sh` sources a missing `plugin/iwiki` or calls plugin wiring on update. PASS is acceptable if the current orchestration already preserves the binary-only path after `plugin/iwiki.sh` exists.

- [ ] **Step 3: Update user-facing wording**

In `README.md`, ensure the usage block says:

```markdown
    ./icodex.sh --update           # update + re-pin the Codex binary only
```

Ensure the install/update paragraph says:

```markdown
`--install` and `--update` fetch only the Codex binary. Vendored plugins and
skills ship through git and are updated only by maintainer scripts.
```

- [ ] **Step 4: Run verification**

Run:

```bash
bash tests/test_update_scope.sh
bash tests/test_args.sh
bash tests/test_install.sh
```

Expected: all three end with `FAIL=0`.

- [ ] **Step 5: Commit**

```bash
git add tests/test_update_scope.sh README.md
git commit -m "test(update): guard codex binary-only update path"
```

### Task 2: Add `iwiki` Launch-Time Wiring

**Files:**
- Create: `lib/plugin/iwiki.sh`
- Create: `tests/test_iwiki_plugin.sh`
- Modify: `icodex.sh`
- Modify: `.codex-isolated/config.toml.example`
- Test: `tests/test_iwiki_plugin.sh`, `tests/test_plugin.sh`, `tests/test_update_scope.sh`

- [ ] **Step 1: Write the failing iwiki wiring test**

Create `tests/test_iwiki_plugin.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"

tmp="$(mktemp -d)"
export ICODEX_ROOT="$tmp"
export ICODEX_HOME_DIR="$tmp/.codex-isolated"
CACHE="$ICODEX_HOME_DIR/plugins/cache/ai-wiki/iwiki/0.6.5"
mkdir -p "$CACHE/.codex-plugin" "$ICODEX_HOME_DIR"
printf '{}' > "$CACHE/.codex-plugin/plugin.json"

cat > "$ICODEX_HOME_DIR/config.toml.example" <<'EOF_CFG'
[marketplaces.superpowers-dev]
source_type = "local"
source = "/keep/superpowers"

[plugins."superpowers@superpowers-dev"]
enabled = true

[marketplaces.ai-wiki]
source_type = "local"
source = "__ICODEX_ROOT__/.codex-isolated/plugins/cache/ai-wiki/iwiki/<ver>"

[plugins."iwiki@ai-wiki"]
enabled = true
EOF_CFG

source "$ROOT/lib/plugin/iwiki.sh"

ensure_iwiki_wiring
cfg="$ICODEX_HOME_DIR/config.toml"
assert_eq "config materialized" "0" "$(test -f "$cfg"; echo $?)"
assert_eq "iwiki source rewritten" "1" "$(grep -c "^source = \"$CACHE\"$" "$cfg")"
assert_eq "superpowers source preserved" "1" "$(grep -c '^source = "/keep/superpowers"$' "$cfg")"

before="$(cat "$cfg")"
ensure_iwiki_wiring
assert_eq "idempotent second call" "$before" "$(cat "$cfg")"

sed -i 's#^source = "'"$CACHE"'"#source = "/wrong/iwiki"#' "$cfg"
( cd /tmp && ensure_iwiki_wiring )
assert_eq "stale source corrected from foreign CWD" "1" "$(grep -c "^source = \"$CACHE\"$" "$cfg")"

cfg_before_missing="$(cat "$cfg")"
rm -rf "$ICODEX_HOME_DIR/plugins"
warn="$(ensure_iwiki_wiring 2>&1 >/dev/null)"
assert_contains "warns when not vendored" "$warn" "iwiki plugin not vendored"
assert_eq "config untouched on missing cache" "$cfg_before_missing" "$(cat "$cfg")"

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_iwiki_plugin.sh`

Expected: FAIL with `lib/plugin/iwiki.sh: No such file or directory`.

- [ ] **Step 3: Implement `lib/plugin/iwiki.sh`**

Create `lib/plugin/iwiki.sh`:

```bash
#!/usr/bin/env bash
# Wire the git-vendored iwiki plugin into the live config.toml at launch.

_iwiki_cache_dir() {
  local m
  for m in "$ICODEX_HOME_DIR"/plugins/cache/*/iwiki/*/; do
    [[ -d "$m" ]] || continue
    printf '%s\n' "${m%/}"
    return 0
  done
  return 0
}

_iwiki_marketplace_name() { # <cache_dir>
  basename "$(dirname "$(dirname "$1")")"
}

_iwiki_rewrite_marketplace_source() { # <config> <mkt> <abs>
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

ensure_iwiki_wiring() {
  local example="$ICODEX_HOME_DIR/config.toml.example"
  local config="$ICODEX_HOME_DIR/config.toml"
  if [[ ! -f "$config" ]]; then
    if [[ -f "$example" ]]; then
      cp "$example" "$config"
    else
      log_error "missing $example — cannot configure iwiki"
      return 0
    fi
  fi

  local cache mkt
  cache="$(_iwiki_cache_dir)"
  if [[ -z "$cache" ]]; then
    log_warn "iwiki plugin not vendored under .codex-isolated/plugins/cache"
    return 0
  fi

  mkt="$(_iwiki_marketplace_name "$cache")"
  _iwiki_rewrite_marketplace_source "$config" "$mkt" "$cache"
}
```

- [ ] **Step 4: Add iwiki config template sections**

Edit `.codex-isolated/config.toml.example` and add these sections after the Superpowers plugin section:

```toml
# --- iwiki plugin (vendored under .codex-isolated/plugins/cache) ---
[marketplaces.ai-wiki]
source_type = "local"
source = "__ICODEX_ROOT__/.codex-isolated/plugins/cache/ai-wiki/iwiki/<ver>"

[plugins."iwiki@ai-wiki"]
enabled = true
```

- [ ] **Step 5: Wire the module in `icodex.sh`**

In `icodex.sh`, update the module list so it includes `plugin/iwiki`:

```bash
for m in core/logging core/init core/validation command/args \
         binary/detect binary/lockfile binary/install \
         config/isolated config/env proxy/proxy symlink/symlink \
         plugin/superpowers plugin/iwiki launcher/launch; do
```

In the default launch path, call `ensure_iwiki_wiring` after `ensure_superpowers_wiring`:

```bash
  setup_codex_home
  ensure_superpowers_wiring
  ensure_iwiki_wiring
  install_ensure || exit 1
```

- [ ] **Step 6: Run verification**

Run:

```bash
bash tests/test_iwiki_plugin.sh
bash tests/test_plugin.sh
bash tests/test_update_scope.sh
```

Expected: all three end with `FAIL=0`.

- [ ] **Step 7: Commit**

```bash
git add icodex.sh lib/plugin/iwiki.sh tests/test_iwiki_plugin.sh .codex-isolated/config.toml.example
git commit -m "feat(plugin): add iwiki launch-time wiring"
```

### Task 3: Export iwiki Environment From `.codex_config`

**Files:**
- Modify: `lib/config/env.sh`
- Modify: `tests/test_env.sh`
- Modify: `.codex_config.example`
- Test: `tests/test_env.sh`

- [ ] **Step 1: Add failing config parsing tests**

Append to `tests/test_env.sh`:

```bash
tmp="$(mktemp -d)"
cfg="$tmp/.codex_config"
cat > "$cfg" <<'EOF_CFG'
ICODEX_PROXY=http://proxy.local:8080
IWIKI_LLM_BASE_URL=https://embeddings.local/v1
IWIKI_LLM_KEY=secret-value
IWIKI_AUTO_QUERY=0
UV_BIN=/opt/uv
OPENAI_API_KEY=ignored
BAD_KEY=ignored
EOF_CFG

unset ICODEX_PROXY IWIKI_LLM_BASE_URL IWIKI_LLM_KEY IWIKI_AUTO_QUERY UV_BIN BAD_KEY
load_config "$cfg"
assert_eq "icodex key still parsed" "http://proxy.local:8080" "${ICODEX_PROXY:-}"
assert_eq "iwiki base url parsed" "https://embeddings.local/v1" "${IWIKI_LLM_BASE_URL:-}"
assert_eq "iwiki key parsed" "secret-value" "${IWIKI_LLM_KEY:-}"
assert_eq "iwiki switch parsed" "0" "${IWIKI_AUTO_QUERY:-}"
assert_eq "uv bin parsed" "/opt/uv" "${UV_BIN:-}"
assert_eq "non-allowlisted key ignored" "" "${BAD_KEY:-}"

rm -rf "$tmp"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_env.sh`

Expected: FAIL for the new `IWIKI_*` and `UV_BIN` assertions.

- [ ] **Step 3: Update `load_config` allowlist**

Modify `lib/config/env.sh` so `load_config` accepts only `ICODEX_*`, `IWIKI_*`, and `UV_BIN`:

```bash
_config_key_allowed() { # <key>
  case "$1" in
    ICODEX_[A-Z0-9_]*|IWIKI_[A-Z0-9_]*|UV_BIN) return 0 ;;
    *) return 1 ;;
  esac
}

load_config() { # <config_file>
  local file="$1" line key val
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[A-Z][A-Z0-9_]*= ]] || continue
    key="${line%%=*}"
    val="${line#*=}"
    _config_key_allowed "$key" || continue
    export "$key=$val"
  done < "$file"
}
```

Update the file header comment:

```bash
# KEY=value lines; only ICODEX_*, IWIKI_*, and UV_BIN keys are honored.
```

- [ ] **Step 4: Document iwiki config**

Append to `.codex_config.example`:

```bash
# iwiki embeddings endpoint. Required for /iwiki-init, /iwiki-ingest, and
# /iwiki-query. Keep secrets in this git-ignored file or in your shell.
#IWIKI_LLM_BASE_URL=https://your-openai-compatible-endpoint/v1
#IWIKI_LLM_KEY=...

# Optional iwiki tuning.
#IWIKI_EMBED_MODEL=text-embedding-3-small
#IWIKI_EMBED_DIMENSIONS=1536
#IWIKI_TOP_K=8
#IWIKI_SCORE_THRESHOLD=0.2
#IWIKI_GRAPH_DEPTH=2
#IWIKI_CHUNK_SIZE=512
#IWIKI_CHUNK_OVERLAP=64
#IWIKI_SUMMARY_MAX_CHARS=400

# Optional iwiki automation switches. Set to 0 to disable.
#IWIKI_AUTO_BOOTSTRAP=1
#IWIKI_AUTO_QUERY=1
#IWIKI_AUTO_REINDEX=1
#IWIKI_AUTO_SYNC=1
#IWIKI_VALIDATE_SECTIONS=1
#IWIKI_SYNC_MAX_ASK=2

# Optional explicit path to uv if it is not on PATH.
#UV_BIN=/path/to/uv
```

- [ ] **Step 5: Run verification**

Run: `bash tests/test_env.sh`

Expected: ends with `FAIL=0`.

- [ ] **Step 6: Commit**

```bash
git add lib/config/env.sh tests/test_env.sh .codex_config.example
git commit -m "feat(config): allow iwiki environment settings"
```

### Task 4: Add iwiki Vendoring Script and Hygiene Tests

**Files:**
- Create: `scripts/vendor-iwiki.sh`
- Create: `tests/test_iwiki_vendor.sh`
- Test: `tests/test_iwiki_vendor.sh`

- [ ] **Step 1: Write failing vendor fixture test**

Create `tests/test_iwiki_vendor.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"

source "$ROOT/scripts/vendor-iwiki.sh" --lib-only

tmp="$(mktemp -d)"
src="$tmp/src"
destroot="$tmp/dest/plugins/cache"
mkdir -p "$src/.claude-plugin" "$src/skills/iwiki-query" "$src/engine/iwiki_engine" \
  "$src/hooks/__pycache__" "$src/engine/.venv" "$src/.git" "$destroot"

cat > "$src/.claude-plugin/plugin.json" <<'EOF_JSON'
{
  "name": "iwiki",
  "description": "Embedding-based documentation agent.",
  "version": "0.6.5",
  "author": { "name": "ikeniborn", "url": "https://github.com/ikeniborn" },
  "homepage": "https://github.com/ikeniborn/ai-wiki-plugin",
  "repository": "https://github.com/ikeniborn/ai-wiki-plugin",
  "keywords": ["documentation"],
  "license": "MIT"
}
EOF_JSON
cat > "$src/skills/iwiki-query/SKILL.md" <<'EOF_SKILL'
---
name: iwiki-query
description: Query docs/wiki.
---
EOF_SKILL
printf '[project]\nname = "iwiki-engine"\n' > "$src/engine/pyproject.toml"
printf 'lock\n' > "$src/engine/uv.lock"
printf '# pkg\n' > "$src/engine/iwiki_engine/__init__.py"
printf 'print("hook")\n' > "$src/hooks/iwiki-recall.py"
printf 'pyc\n' > "$src/hooks/__pycache__/x.pyc"
printf 'venv\n' > "$src/engine/.venv/file"

_vendor_iwiki_normalize "$src" "$destroot"

out="$destroot/ai-wiki/iwiki/0.6.5"
assert_exit "codex manifest exists" 0 test -f "$out/.codex-plugin/plugin.json"
assert_exit "skill copied" 0 test -f "$out/skills/iwiki-query/SKILL.md"
assert_exit "engine copied" 0 test -f "$out/engine/pyproject.toml"
assert_exit "hook copied" 0 test -f "$out/hooks/iwiki-recall.py"
assert_exit "venv stripped" 1 test -e "$out/engine/.venv"
assert_exit "pycache stripped" 1 test -e "$out/hooks/__pycache__"
assert_exit "git stripped" 1 test -e "$out/.git"
assert_contains "manifest name" "$(cat "$out/.codex-plugin/plugin.json")" '"name": "iwiki"'
assert_contains "manifest skills" "$(cat "$out/.codex-plugin/plugin.json")" '"skills": "./skills/"'

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_iwiki_vendor.sh`

Expected: FAIL because `scripts/vendor-iwiki.sh` does not exist.

- [ ] **Step 3: Implement `scripts/vendor-iwiki.sh`**

Create `scripts/vendor-iwiki.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$ROOT/lib/core/logging.sh"

_json_value() { # <file> <key>
  local file="$1" key="$2"
  sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | head -1
}

_write_codex_manifest() { # <src_manifest> <dest_manifest>
  local src="$1" dest="$2" name version description homepage repository license
  name="$(_json_value "$src" name)"
  version="$(_json_value "$src" version)"
  description="$(_json_value "$src" description)"
  homepage="$(_json_value "$src" homepage)"
  repository="$(_json_value "$src" repository)"
  license="$(_json_value "$src" license)"
  mkdir -p "$(dirname "$dest")"
  cat > "$dest" <<EOF_JSON
{
  "name": "$name",
  "version": "$version",
  "description": "$description",
  "author": {
    "name": "ikeniborn",
    "url": "https://github.com/ikeniborn"
  },
  "homepage": "$homepage",
  "repository": "$repository",
  "license": "$license",
  "keywords": [
    "documentation",
    "embeddings",
    "wiki",
    "semantic-search",
    "knowledge-graph"
  ],
  "skills": "./skills/"
}
EOF_JSON
}

_strip_iwiki_generated_artifacts() { # <dest>
  local dest="$1"
  find "$dest" -name .git -type d -prune -exec rm -rf {} +
  find "$dest" -name .venv -type d -prune -exec rm -rf {} +
  find "$dest" -name .pytest_cache -type d -prune -exec rm -rf {} +
  find "$dest" -name __pycache__ -type d -prune -exec rm -rf {} +
  find "$dest" -name '*.pyc' -type f -delete
  find "$dest" -name .gitignore -type f -delete
}

_vendor_iwiki_normalize() { # <source_plugin_root> <dest_cache_root>
  local src="$1" destroot="$2" manifest version dest
  manifest="$src/.claude-plugin/plugin.json"
  [[ -f "$manifest" ]] || { log_error "missing $manifest"; return 1; }
  version="$(_json_value "$manifest" version)"
  [[ -n "$version" ]] || { log_error "cannot read iwiki version"; return 1; }

  dest="$destroot/ai-wiki/iwiki/$version"
  rm -rf "$dest"
  mkdir -p "$dest"

  cp -R "$src/skills" "$dest/skills"
  cp -R "$src/engine" "$dest/engine"
  cp -R "$src/hooks" "$dest/hooks"
  [[ -f "$src/README.md" ]] && cp "$src/README.md" "$dest/README.md"
  [[ -f "$src/hooks/hooks.json" ]] && cp "$src/hooks/hooks.json" "$dest/hooks.json"
  _write_codex_manifest "$manifest" "$dest/.codex-plugin/plugin.json"
  _strip_iwiki_generated_artifacts "$dest"

  [[ -f "$dest/.codex-plugin/plugin.json" ]] || { log_error "codex manifest missing"; return 1; }
  [[ -d "$dest/skills" ]] || { log_error "skills missing"; return 1; }
  [[ -f "$dest/engine/pyproject.toml" ]] || { log_error "engine missing"; return 1; }
  [[ -d "$dest/hooks" ]] || { log_error "hooks missing"; return 1; }
  printf '%s\n' "$dest"
}

if [[ "${1:-}" == "--lib-only" ]]; then
  return 0 2>/dev/null || exit 0
fi

src="${1:-/home/ikeniborn/Documents/Project/ai-wiki-plugin}"
_vendor_iwiki_normalize "$src" "$ROOT/.codex-isolated/plugins/cache"
```

- [ ] **Step 4: Run vendor test**

Run: `bash tests/test_iwiki_vendor.sh`

Expected: ends with `FAIL=0`.

- [ ] **Step 5: Commit**

```bash
chmod +x scripts/vendor-iwiki.sh
git add scripts/vendor-iwiki.sh tests/test_iwiki_vendor.sh
git commit -m "feat(iwiki): add vendoring helper"
```

### Task 5: Vendor and Adapt iwiki Plugin

**Files:**
- Modify/create: `.codex-isolated/plugins/cache/ai-wiki/iwiki/<version>/**`
- Modify: `scripts/vendor-iwiki.sh` if adaptation hooks are added there
- Test: vendored hygiene commands, config-free engine smoke

- [ ] **Step 1: Run the vendoring script**

Run:

```bash
scripts/vendor-iwiki.sh /home/ikeniborn/Documents/Project/ai-wiki-plugin
```

Expected: prints `.codex-isolated/plugins/cache/ai-wiki/iwiki/0.6.5` or the source plugin's current version.

- [ ] **Step 2: Adapt skill path snippets**

In each vendored `skills/iwiki-*/SKILL.md`, replace Claude path resolution snippets with this Codex-safe block:

```bash
ENG="${CODEX_PLUGIN_ROOT:+${CODEX_PLUGIN_ROOT}/engine}"
[ -f "$ENG/pyproject.toml" ] || ENG="engine"
[ -f "$ENG/pyproject.toml" ] || ENG="$(ls -d "$CODEX_HOME"/plugins/cache/*/iwiki/*/engine 2>/dev/null | sort -V | tail -1)"
UV="${UV_BIN:-}"
[ -x "$UV" ] || UV="$(command -v uv)"
[ -x "$UV" ] || { echo "HALT: uv not found; set UV_BIN or install uv"; exit 2; }
[ -f "$ENG/pyproject.toml" ] || { echo "HALT: iwiki engine not found"; exit 2; }
```

Also replace prose references:

```text
CLAUDE_PLUGIN_ROOT -> CODEX_PLUGIN_ROOT when available, otherwise CODEX_HOME plugin cache
CLAUDE_CONFIG_DIR -> CODEX_HOME
Claude Code -> Codex
slash command -> skill
```

- [ ] **Step 3: Adapt hook helper environment handling**

In vendored `hooks/iwiki_common.py`, replace Claude-specific functions with these exact implementations:

```python
def codex_home() -> str | None:
    return os.environ.get("CODEX_HOME")


def plugin_root() -> str | None:
    env = os.environ.get("CODEX_PLUGIN_ROOT") or os.environ.get("PLUGIN_ROOT")
    if env and os.path.isdir(env):
        return env
    here = os.path.abspath(__file__)
    root = os.path.dirname(os.path.dirname(here))
    return root if os.path.isdir(root) else None
```

Update `cd_project()` to avoid `CLAUDE_PROJECT_DIR`:

```python
def cd_project() -> None:
    for key in ("CODEX_PROJECT_DIR", "PROJECT_DIR", "PWD"):
        pd = os.environ.get(key)
        if pd and os.path.isdir(pd):
            try:
                os.chdir(pd)
                return
            except Exception:
                pass
    try:
        p = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True, timeout=5)
        root = p.stdout.strip()
        if p.returncode == 0 and root and os.path.isdir(root):
            os.chdir(root)
    except Exception:
        pass
```

Update `resolve_uv()` to use `CODEX_HOME`:

```python
def resolve_uv() -> str | None:
    for cand in (os.environ.get("UV_BIN"), shutil.which("uv")):
        if cand and os.path.exists(cand) and os.access(cand, os.X_OK):
            return cand
    return None
```

Update `engine_dir()` cache lookup:

```python
def engine_dir() -> str | None:
    cands: list[str] = []
    pr = plugin_root()
    if pr:
        cands.append(os.path.join(pr, "engine"))
    cands.append("engine")
    ch = codex_home()
    if ch:
        cache = glob.glob(os.path.join(ch, "plugins", "cache", "*", "iwiki", "*", "engine"))
        cache.sort(key=_cache_version_key, reverse=True)
        cands += cache
    for c in cands:
        if os.path.isfile(os.path.join(c, "pyproject.toml")):
            return c
    return None
```

- [ ] **Step 4: Adapt `hooks.json` commands**

Place `hooks.json` at the plugin root with commands relative to the plugin root:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 hooks/iwiki-bootstrap.py",
            "timeout": 15
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 hooks/iwiki-recall.py",
            "timeout": 20
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "python3 hooks/iwiki-validate.py",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "python3 hooks/iwiki-reindex.py",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 hooks/iwiki-sync.py",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 5: Run hygiene checks**

Run:

```bash
test -f .codex-isolated/plugins/cache/ai-wiki/iwiki/0.6.5/.codex-plugin/plugin.json
test -f .codex-isolated/plugins/cache/ai-wiki/iwiki/0.6.5/engine/pyproject.toml
test -f .codex-isolated/plugins/cache/ai-wiki/iwiki/0.6.5/hooks.json
find .codex-isolated/plugins/cache/ai-wiki/iwiki -name .git -o -name .venv -o -name .pytest_cache -o -name __pycache__ -o -name '*.pyc'
```

Expected: the first three commands exit 0; the `find` command prints nothing.

- [ ] **Step 6: Run config-free engine smoke**

Run:

```bash
UV="${UV_BIN:-$(command -v uv)}"
"$UV" run --project .codex-isolated/plugins/cache/ai-wiki/iwiki/0.6.5/engine \
  python3 -m iwiki_engine --wiki-dir /tmp/iwiki-empty lint
```

Expected: exits 0 and prints JSON containing `"wiki_present": false`.

- [ ] **Step 7: Commit**

```bash
git add .codex-isolated/plugins/cache/ai-wiki scripts/vendor-iwiki.sh
git commit -m "feat(iwiki): vendor codex plugin cache"
```

### Task 6: Probe Codex Hook Support

**Files:**
- Create: `tests/test_iwiki_hooks_probe.sh`
- Create: `docs/superpowers/reports/iwiki-hook-probe.md`
- Test: `tests/test_iwiki_hooks_probe.sh`

- [ ] **Step 1: Write hook probe script**

Create `tests/test_iwiki_hooks_probe.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

if [[ ! -x "$ROOT/.codex-isolated/bin/codex" ]]; then
  echo "SKIP: codex binary not installed"
  finish
  exit 0
fi

report="$ROOT/docs/superpowers/reports/iwiki-hook-probe.md"
mkdir -p "$(dirname "$report")"
{
  echo "# iwiki Hook Probe"
  echo
  echo "Date: $(date +%F)"
  echo
  echo "Codex version:"
  "$ROOT/.codex-isolated/bin/codex" --version || true
  echo
  echo "Local hook examples confirmed in repository:"
  echo "- PostToolUse"
  echo "- Stop"
  echo
  echo "Manual verification required for:"
  echo "- SessionStart"
  echo "- UserPromptSubmit"
  echo "- PreToolUse"
  echo
  echo "Result: record actual event support during implementation before claiming full automation."
} > "$report"

assert_exit "probe report written" 0 test -f "$report"
assert_contains "mentions SessionStart" "$(cat "$report")" "SessionStart"
finish
```

- [ ] **Step 2: Run the probe**

Run: `bash tests/test_iwiki_hooks_probe.sh`

Expected: `FAIL=0`; if Codex is absent, the test records a skip-like message and still exits cleanly.

- [ ] **Step 3: Update probe report with actual results**

If a local Codex run confirms hook events, edit `docs/superpowers/reports/iwiki-hook-probe.md` so it contains:

```markdown
## Confirmed

- PostToolUse: supported
- Stop: supported
- PreToolUse: supported or unsupported
- SessionStart: supported or unsupported
- UserPromptSubmit: supported or unsupported

## Command Context

- Relative commands run from: plugin root or other observed cwd
- Environment variables observed: CODEX_HOME, CODEX_PLUGIN_ROOT, CODEX_PROJECT_DIR if present
```

Use the actual observed values, not guesses.

- [ ] **Step 4: Commit**

```bash
git add tests/test_iwiki_hooks_probe.sh docs/superpowers/reports/iwiki-hook-probe.md
git commit -m "test(iwiki): record codex hook probe"
```

### Task 7: Documentation and End-to-End Verification

**Files:**
- Modify: `README.md`
- Modify: `.codex_config.example`
- Test: full local suite

- [ ] **Step 1: Update README**

Add an `iwiki` paragraph under "What lives in git":

```markdown
- The **iwiki plugin** ships pre-installed as a vendored Codex plugin under
  `.codex-isolated/plugins/cache/ai-wiki/iwiki/...`. It provides `iwiki-*`
  skills, the Python embedding/search engine, and supported hook automation.
  Users do not run `codex plugin add`; the launcher rewrites the local
  marketplace `source` path on each run.
```

Add an `iwiki` requirements paragraph:

```markdown
iwiki requires `uv` plus `IWIKI_LLM_BASE_URL` and `IWIKI_LLM_KEY` for
embedding-backed commands (`iwiki-init`, `iwiki-ingest`, `iwiki-query`).
Config-free health commands such as lint can run without those variables.
```

- [ ] **Step 2: Run the focused suite**

Run:

```bash
bash tests/test_args.sh
bash tests/test_install.sh
bash tests/test_update_scope.sh
bash tests/test_plugin.sh
bash tests/test_iwiki_plugin.sh
bash tests/test_env.sh
bash tests/test_iwiki_vendor.sh
bash tests/test_iwiki_hooks_probe.sh
```

Expected: every test ends with `FAIL=0`.

- [ ] **Step 3: Run plugin-list smoke when binary is installed**

Run:

```bash
if [[ -x .codex-isolated/bin/codex ]]; then
  ./icodex.sh exec true >/tmp/icodex-iwiki-smoke.out 2>/tmp/icodex-iwiki-smoke.err || true
  CODEX_HOME="$PWD/.codex-isolated" .codex-isolated/bin/codex plugin list --json
fi
```

Expected when the binary exists: JSON includes an enabled `iwiki` plugin. If `exec true` cannot run because auth/model config is unavailable, the wiring should still have rewritten `.codex-isolated/config.toml`; inspect that file for the absolute `ai-wiki/iwiki/<version>` source.

- [ ] **Step 4: Confirm update did not touch plugin artifacts**

Run:

```bash
before="$(git status --short .codex-isolated/plugins .codex-isolated/skills .codex-isolated/config.toml.example)"
./icodex.sh --update || true
after="$(git status --short .codex-isolated/plugins .codex-isolated/skills .codex-isolated/config.toml.example)"
test "$before" = "$after"
```

Expected: the final `test` exits 0. If network prevents `--update`, record that the command could not complete because release download failed; do not claim this verification passed.

- [ ] **Step 5: Commit docs**

```bash
git add README.md .codex_config.example
git commit -m "docs(iwiki): document vendored plugin setup"
```

## Final Verification

- [ ] Run `git status --short` and verify only expected working-tree changes remain.
- [ ] Run all focused tests listed in Task 7.
- [ ] Record any skipped network-dependent checks in the final response.
- [ ] Use `superpowers:verification-before-completion` before claiming implementation complete.

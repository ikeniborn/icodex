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
export ICODEX_SHARED_DIR="$ICODEX_HOME_DIR"
export ICODEX_BIN="$ICODEX_HOME_DIR/bin/codex"
CACHE="$ICODEX_HOME_DIR/plugins/cache/openai-curated/superpowers/11c74d6b"
PIN="$ICODEX_ROOT/vendor/superpowers/pin"
MARKETPLACE="$ICODEX_HOME_DIR/tmp/marketplaces/openai-curated"
mkdir -p "$CACHE/.codex-plugin" "$CACHE/skills/brainstorming" "$CACHE/skills/writing-plans" "$ICODEX_HOME_DIR/bin"
mkdir -p "$(dirname "$PIN")"
printf 'openai-curated/superpowers/11c74d6b\n' > "$PIN"
printf '{"name":"superpowers"}' > "$CACHE/.codex-plugin/plugin.json"
printf '{"status":"legacy-unverified-cache-generation","cache_generation":"11c74d6b","source_ref":null}\n' > "$CACHE/.icodex-vendor-provenance.json"
printf -- '---\nname: brainstorming\ndescription: test\n---\n' > "$CACHE/skills/brainstorming/SKILL.md"
printf -- '---\nname: writing-plans\ndescription: test\n---\n' > "$CACHE/skills/writing-plans/SKILL.md"
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

[marketplaces.openai-curated]
source_type = "local"
source = "__ICODEX_ROOT__/.codex-isolated/plugins/cache/superpowers/superpowers/<ver>"

[plugins."superpowers@openai-curated"]
enabled = true
EOF

source "$ROOT/lib/plugin/superpowers.sh"

# 1. first run: add read-only launcher permission and keep plugin rewrite behavior
ensure_launcher_binary_permission
ensure_superpowers_wiring
cfg="$ICODEX_HOME_DIR/config.toml"
assert_eq "source rewritten to generated marketplace" "1" \
  "$(grep -cFx "source = \"$MARKETPLACE\"" "$cfg")"
assert_exit "marketplace manifest created" 0 test -f "$MARKETPLACE/.agents/plugins/marketplace.json"
assert_exit "api marketplace manifest created" 0 test -f "$MARKETPLACE/.agents/plugins/api_marketplace.json"
assert_exit "marketplace plugin path resolves" 0 test -f "$MARKETPLACE/plugins/superpowers/.codex-plugin/plugin.json"
assert_exit "brainstorming skill link resolves" 0 test -f "$ICODEX_HOME_DIR/skills/brainstorming/SKILL.md"
assert_exit "writing-plans skill link resolves" 0 test -f "$ICODEX_HOME_DIR/skills/writing-plans/SKILL.md"
assert_eq "brainstorming skill points to vendored cache" "$CACHE/skills/brainstorming" \
  "$(readlink "$ICODEX_HOME_DIR/skills/brainstorming")"
assert_eq "writing-plans skill points to vendored cache" "$CACHE/skills/writing-plans" \
  "$(readlink "$ICODEX_HOME_DIR/skills/writing-plans")"
assert_contains "manifest names superpowers" \
  "$(cat "$MARKETPLACE/.agents/plugins/marketplace.json")" '"name": "superpowers"'
assert_contains "manifest uses relative plugin path" \
  "$(cat "$MARKETPLACE/.agents/plugins/marketplace.json")" '"path": "./plugins/superpowers"'
assert_eq "codex binary allowed read-only" "1" \
  "$(grep -cFx "\"$ICODEX_BIN\" = \"read\"" "$cfg")"
binary_perm_in_section="$(awk -v key="\"$ICODEX_BIN\" = \"read\"" '
  /^\[/ { insec = ($0 == "[permissions.dev-safe.filesystem]") }
  insec && $0 == key { count++ }
  END { print count + 0 }
' "$cfg")"
assert_eq "codex binary allowed read-only in dev-safe filesystem" "1" "$binary_perm_in_section"
escaped_bin="$ICODEX_HOME_DIR/bin/codex\"quoted\\slash"
_ensure_filesystem_permission_entry "$cfg" "$escaped_bin" "read"
assert_eq "quoted/backslash path escaped for toml" "1" \
  "$(grep -cFx "\"$ICODEX_HOME_DIR/bin/codex\\\"quoted\\\\slash\" = \"read\"" "$cfg")"
assert_eq "codex bin directory not granted write" "0" \
  "$(grep -cFx "\"$ICODEX_HOME_DIR/bin\" = \"write\"" "$cfg")"
assert_eq "workspace env deny preserved" "1" \
  "$(grep -cFx '"**/.env" = "deny"' "$cfg")"
assert_eq "workspace token deny preserved" "1" \
  "$(grep -cFx '"**/.token" = "deny"' "$cfg")"
assert_eq "workspace secrets deny preserved" "1" \
  "$(grep -cFx '"**/secrets/**" = "deny"' "$cfg")"
assert_eq "ssh deny preserved" "1" \
  "$(grep -cFx '"~/.ssh" = "deny"' "$cfg")"

# 2. idempotent: a second call leaves the file byte-identical
before="$(cat "$cfg")"
ensure_launcher_binary_permission
ensure_superpowers_wiring
assert_eq "idempotent second call" "$before" "$(cat "$cfg")"

# 3. stale launcher permission is corrected to read-only
sed -i "s#^\"$ICODEX_BIN\" = \"read\"#\"$ICODEX_BIN\" = \"write\"#" "$cfg"
ensure_launcher_binary_permission
assert_eq "stale binary write corrected" "1" \
  "$(grep -cFx "\"$ICODEX_BIN\" = \"read\"" "$cfg")"
assert_eq "stale binary write removed" "0" \
  "$(grep -cFx "\"$ICODEX_BIN\" = \"write\"" "$cfg")"

# 4. CWD-independence: run from an unrelated dir, still resolves and rewrites
cwd_code=0
( cd /tmp && ensure_launcher_binary_permission && ensure_superpowers_wiring ) || cwd_code=$?
assert_eq "wiring succeeds from foreign CWD" "0" "$cwd_code"
assert_eq "still correct after foreign CWD" "1" \
  "$(grep -cFx "source = \"$MARKETPLACE\"" "$cfg")"

# 5. stale source is corrected
sed -i 's#^source = .*#source = "/wrong/path"#' "$cfg"
ensure_superpowers_wiring
assert_eq "stale source corrected" "1" \
  "$(grep -cFx "source = \"$MARKETPLACE\"" "$cfg")"

# 5b. quoted-only equivalent marketplace table uses the same identity semantics.
sed -i 's/^\[marketplaces.openai-curated\]$/[marketplaces."openai-curated"]/' "$cfg"
sed -i 's#^source = .*#source = "/quoted/wrong/path"#' "$cfg"
ensure_superpowers_wiring
assert_eq "quoted marketplace source rewritten" "1" \
  "$(grep -cFx "source = \"$MARKETPLACE\"" "$cfg")"
assert_exit "plugin wiring has no tomllib dependency" 1 grep -qF "tomllib" "$ROOT/lib/plugin/superpowers.sh"

# 6. other marketplace sections are untouched
printf '\n[marketplaces.other]\nsource = "/keep/me"\n' >> "$cfg"
ensure_superpowers_wiring
assert_eq "other section preserved" "1" "$(grep -cFx 'source = "/keep/me"' "$cfg")"

# 7. extra unpinned cache does not affect exact selection.
mkdir -p "$ICODEX_SHARED_DIR/plugins/cache/other/superpowers/999/skills/brainstorming"
printf test > "$ICODEX_SHARED_DIR/plugins/cache/other/superpowers/999/skills/brainstorming/SKILL.md"
ensure_superpowers_wiring
assert_eq "extra cache does not change pinned skill target" "$CACHE/skills/brainstorming" \
  "$(readlink "$ICODEX_HOME_DIR/skills/brainstorming")"

assert_preflight_failure() { # <description> <expected-message>
  local desc="$1" expected="$2" code=0 output
  local cfg_before marketplace_before links_before
  cfg_before="$(sha256sum "$cfg")"
  marketplace_before="$(find "$ICODEX_HOME_DIR/tmp" -type f -o -type l | sort | xargs -r ls -ld)"
  links_before="$(find "$ICODEX_HOME_DIR/skills" -type l -print -exec readlink {} \; | sort)"
  output="$(ensure_superpowers_wiring 2>&1)" || code=$?
  assert_exit "$desc fails" 1 test "$code" -eq 0
  assert_contains "$desc reports cause" "$output" "$expected"
  assert_eq "$desc preserves config" "$cfg_before" "$(sha256sum "$cfg")"
  assert_eq "$desc preserves marketplace root" "$marketplace_before" "$(find "$ICODEX_HOME_DIR/tmp" -type f -o -type l | sort | xargs -r ls -ld)"
  assert_eq "$desc preserves skill links" "$links_before" "$(find "$ICODEX_HOME_DIR/skills" -type l -print -exec readlink {} \; | sort)"
}

# 8. all invalid state fails before config, marketplace, or skill-link mutations.
cp "$cfg" "$cfg.before-array-table"
cat > "$cfg" <<'EOF'
[marketplaces."openai-curated"]
source_type = "local"
source = "/direct/wrong/path"

[[marketplaces."openai-curated".mirrors]]
source = "/keep/nested"

[plugins."superpowers@openai-curated"]
enabled = true
EOF
ensure_superpowers_wiring
assert_eq "direct marketplace source rewritten with nested array table" "1" \
  "$(grep -cFx "source = \"$MARKETPLACE\"" "$cfg")"
assert_eq "nested array-table source unchanged" "1" \
  "$(grep -cFx 'source = "/keep/nested"' "$cfg")"
sed -i '/^\[marketplaces\."openai-curated"\]$/,/^\[/ { /^source = /d; }' "$cfg"
assert_preflight_failure "nested array-table source without direct source" "marketplace mismatch"
mv "$cfg.before-array-table" "$cfg"

cp "$cfg" "$cfg.before-scanner-regressions"
cat > "$cfg" <<'EOF'
[marketplaces."openai-curated"]
source_type = "local"
[malformed
source = "/must/not/count"

[plugins."superpowers@openai-curated"]
enabled = true
EOF
assert_preflight_failure "malformed header clears marketplace context" "marketplace mismatch"

cat > "$cfg" <<'EOF'
[marketplaces."openai-curated"]
source_type = "local"
description = """
source = "/inside/multiline/string"
"""

[plugins."superpowers@openai-curated"]
enabled = true
EOF
assert_preflight_failure "multiline string source without direct source" "marketplace mismatch"

sed -i '/^source_type = "local"$/a source = "/direct/wrong/path"' "$cfg"
ensure_superpowers_wiring
assert_eq "direct source rewritten beside multiline string" "1" \
  "$(grep -cFx "source = \"$MARKETPLACE\"" "$cfg")"
assert_eq "multiline string source unchanged" "1" \
  "$(grep -cFx 'source = "/inside/multiline/string"' "$cfg")"
mv "$cfg.before-scanner-regressions" "$cfg"

rm -f "$PIN"
assert_preflight_failure "missing pin" "pin missing"
printf '../escape\n' > "$PIN"
assert_preflight_failure "malformed pin" "pin malformed"
printf './superpowers/11c74d6b\n' > "$PIN"
assert_preflight_failure "dot pin segment" "pin malformed"
printf 'openai-curated/superpowers/..\n' > "$PIN"
assert_preflight_failure "dotdot pin segment" "pin malformed"
printf 'openai-curated/superpowers/missing\n' > "$PIN"
assert_preflight_failure "missing pinned target" "pinned cache missing"
printf 'openai-curated/superpowers/11c74d6b\n' > "$PIN"
mv "$CACHE" "$CACHE.saved"
assert_preflight_failure "renamed pinned target" "pinned cache missing"
mv "$CACHE.saved" "$CACHE"
mv "$CACHE/.icodex-vendor-provenance.json" "$CACHE/.icodex-vendor-provenance.saved"
assert_preflight_failure "missing generation provenance" "provenance invalid"
mv "$CACHE/.icodex-vendor-provenance.saved" "$CACHE/.icodex-vendor-provenance.json"
printf '{broken' > "$CACHE/.icodex-vendor-provenance.json"
assert_preflight_failure "malformed generation provenance" "provenance invalid"
printf '{"status":"verified-immutable-source-ref","source_ref":"not-a-sha"}' > "$CACHE/.icodex-vendor-provenance.json"
assert_preflight_failure "nonimmutable generation provenance" "provenance invalid"
printf '{"status":"legacy-unverified-cache-generation","cache_generation":"11c74d6b","source_ref":null}\n' > "$CACHE/.icodex-vendor-provenance.json"
printf '{broken' > "$CACHE/.codex-plugin/plugin.json"
assert_preflight_failure "malformed plugin json" "plugin manifest invalid"
printf '{"name":"wrong"}' > "$CACHE/.codex-plugin/plugin.json"
assert_preflight_failure "wrong plugin name" "plugin manifest invalid"
printf '{"name":"superpowers"}' > "$CACHE/.codex-plugin/plugin.json"
printf '\n[marketplaces.openai-curated]\nsource_type = "local"\n' >> "$cfg"
assert_preflight_failure "duplicate marketplace table" "marketplace mismatch"
sed -i '$d' "$cfg"; sed -i '$d' "$cfg"; sed -i '$d' "$cfg"
printf '\n[marketplaces."openai-curated"]\nsource_type = "local"\n' >> "$cfg"
assert_preflight_failure "quoted equivalent marketplace table" "marketplace mismatch"
sed -i '$d' "$cfg"; sed -i '$d' "$cfg"; sed -i '$d' "$cfg"
printf '\n[plugins."superpowers@openai-curated"]\nenabled = true\n' >> "$cfg"
assert_preflight_failure "duplicate plugin table" "marketplace mismatch"
sed -i '$d' "$cfg"; sed -i '$d' "$cfg"; sed -i '$d' "$cfg"
sed -i 's/superpowers@openai-curated/superpowers@wrong-marketplace/' "$cfg"
assert_preflight_failure "marketplace mismatch" "marketplace mismatch"

rm -rf "$tmp"
finish

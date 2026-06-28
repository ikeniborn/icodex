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
  "$(grep -cFx "source = \"$MARKETPLACE\"" "$cfg")"
assert_exit "marketplace manifest created" 0 test -f "$MARKETPLACE/.agents/plugins/marketplace.json"
assert_exit "api marketplace manifest created" 0 test -f "$MARKETPLACE/.agents/plugins/api_marketplace.json"
assert_exit "marketplace plugin path resolves" 0 test -f "$MARKETPLACE/plugins/superpowers/.codex-plugin/plugin.json"
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

# 6. other marketplace sections are untouched
printf '\n[marketplaces.other]\nsource = "/keep/me"\n' >> "$cfg"
ensure_superpowers_wiring
assert_eq "other section preserved" "1" "$(grep -cFx 'source = "/keep/me"' "$cfg")"

# 7. missing cache -> warn, no crash, no rewrite
cfg_before_missing="$(cat "$cfg")"
rm -rf "$ICODEX_HOME_DIR/plugins"
missing_code=0
warn="$(ensure_superpowers_wiring 2>&1 >/dev/null)" || missing_code=$?
assert_eq "missing cache does not fail" "0" "$missing_code"
assert_contains "warns when not vendored" "$warn" "not vendored"
assert_eq "config untouched on missing cache" "$cfg_before_missing" "$(cat "$cfg")"

rm -rf "$tmp"
finish

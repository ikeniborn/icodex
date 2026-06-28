#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"

tmp="$(mktemp -d)"
export ICODEX_ROOT="$tmp"
export ICODEX_HOME_DIR="$tmp/.codex-isolated"
CACHE="$ICODEX_HOME_DIR/plugins/cache/ai-wiki/iwiki/0.6.5"
mkdir -p "$CACHE/.codex-plugin"
printf '{}' > "$CACHE/.codex-plugin/plugin.json"
cat > "$ICODEX_HOME_DIR/config.toml.example" <<'EOF'
[marketplaces.superpowers]
source_type = "local"
source = "/keep/superpowers"

[plugins."superpowers@superpowers"]
enabled = true

[marketplaces.ai-wiki]
source_type = "local"
source = "__ICODEX_ROOT__/.codex-isolated/plugins/cache/ai-wiki/iwiki/<ver>"

[plugins."iwiki@ai-wiki"]
enabled = true
EOF

source "$ROOT/lib/plugin/iwiki.sh"

# 1. first run: materialize config.toml from example and rewrite iwiki source
ensure_iwiki_wiring
cfg="$ICODEX_HOME_DIR/config.toml"
assert_exit "config materialized from example" 0 test -f "$cfg"
assert_eq "iwiki source rewritten to cache path" "1" \
  "$(grep -c "^source = \"$CACHE\"$" "$cfg")"
assert_eq "superpowers source preserved" "1" \
  "$(grep -c '^source = "/keep/superpowers"$' "$cfg")"

# 2. idempotent: a second call leaves the file byte-identical
before="$(cat "$cfg")"; ensure_iwiki_wiring
assert_eq "idempotent second call" "$before" "$(cat "$cfg")"

# 3. CWD-independence: stale source is corrected from an unrelated dir
sed -i 's#^source = "'"$CACHE"'"$#source = "/wrong/path"#' "$cfg"
( cd /tmp && ensure_iwiki_wiring )
assert_eq "stale source corrected from foreign CWD" "1" \
  "$(grep -c "^source = \"$CACHE\"$" "$cfg")"

# 4. unrelated marketplace cache is ignored
sed -i 's#^source = "'"$CACHE"'"$#source = "/wrong/path"#' "$cfg"
rm -rf "$CACHE"
mkdir -p "$ICODEX_HOME_DIR/plugins/cache/other/iwiki/9.9.9/.codex-plugin"
printf '{}' > "$ICODEX_HOME_DIR/plugins/cache/other/iwiki/9.9.9/.codex-plugin/plugin.json"
cfg_before_other="$(cat "$cfg")"
warn="$(ensure_iwiki_wiring 2>&1 >/dev/null)"
assert_contains "warns when only unrelated iwiki cache exists" "$warn" "iwiki plugin not vendored"
assert_eq "config untouched with only unrelated iwiki cache" "$cfg_before_other" "$(cat "$cfg")"
mkdir -p "$CACHE/.codex-plugin"
printf '{}' > "$CACHE/.codex-plugin/plugin.json"
ensure_iwiki_wiring
assert_eq "ai-wiki cache still rewrites when unrelated cache exists" "1" \
  "$(grep -c "^source = \"$CACHE\"$" "$cfg")"

# 5. missing cache -> warn, no crash, no rewrite
cfg_before_missing="$(cat "$cfg")"
rm -rf "$ICODEX_HOME_DIR/plugins"
warn="$(ensure_iwiki_wiring 2>&1 >/dev/null)"
assert_contains "warns when not vendored" "$warn" "iwiki plugin not vendored"
assert_eq "config untouched on missing cache" "$cfg_before_missing" "$(cat "$cfg")"

rm -rf "$tmp"
finish

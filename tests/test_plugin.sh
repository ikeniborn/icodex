#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"

# Build a fake isolated home with a vendored cache + committed config.
tmp="$(mktemp -d)"
export ICODEX_ROOT="$tmp"
export ICODEX_HOME_DIR="$tmp/.codex-isolated"
CACHE="$ICODEX_HOME_DIR/plugins/cache/superpowers/superpowers/6.0.3"
mkdir -p "$CACHE/.codex-plugin"
printf '{}' > "$CACHE/.codex-plugin/plugin.json"
cat > "$ICODEX_HOME_DIR/config.toml" <<'EOF'
[marketplaces.superpowers]
source_type = "local"
source = "__ICODEX_ROOT__/.codex-isolated/plugins/cache/superpowers/superpowers/<ver>"

[plugins."superpowers@superpowers"]
enabled = true
EOF

source "$ROOT/lib/plugin/superpowers.sh"

# 1. first run: rewrite source to the absolute cache dir
ensure_superpowers_wiring
cfg="$ICODEX_HOME_DIR/config.toml"
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
cfg_before_missing="$(cat "$cfg")"
rm -rf "$ICODEX_HOME_DIR/plugins"
warn="$(ensure_superpowers_wiring 2>&1 >/dev/null)"
assert_contains "warns when not vendored" "$warn" "not vendored"
assert_eq "config untouched on missing cache" "$cfg_before_missing" "$(cat "$cfg")"

rm -rf "$tmp"
finish

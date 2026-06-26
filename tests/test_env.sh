#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/config/env.sh"

tmp="$(mktemp -d)"; cfg="$tmp/.codex_config"

# --- load_config: only ICODEX_* lines are exported; others/comments ignored ---
cat > "$cfg" <<'EOF'
# a comment line
ICODEX_PROXY=http://proxy.local:8080
ICODEX_NO_PROXY=localhost,127.0.0.1,github.com
ICODEX_REPO=acme/codex-fork
PROXY_URL=should-be-ignored
NOT_PREFIXED=nope
EOF
unset ICODEX_PROXY ICODEX_NO_PROXY ICODEX_REPO PROXY_URL NOT_PREFIXED
load_config "$cfg"
assert_eq "ICODEX_PROXY loaded"    "http://proxy.local:8080" "${ICODEX_PROXY:-}"
assert_eq "ICODEX_NO_PROXY loaded" "localhost,127.0.0.1,github.com" "${ICODEX_NO_PROXY:-}"
assert_eq "ICODEX_REPO loaded"     "acme/codex-fork"          "${ICODEX_REPO:-}"
assert_eq "comment ignored"        ""                         "${a:-}"
assert_eq "non-ICODEX key ignored" ""                         "${NOT_PREFIXED:-}"
assert_eq "legacy PROXY_URL ignored" ""                       "${PROXY_URL:-}"

# --- value may contain '=' (e.g. query string) ---
printf 'ICODEX_PROXY=http://h:8080/?a=b\n' > "$cfg"
unset ICODEX_PROXY; load_config "$cfg"
assert_eq "value keeps '='" "http://h:8080/?a=b" "${ICODEX_PROXY:-}"

# --- missing file is a silent no-op (returns 0) ---
assert_exit "missing file -> 0" 0 load_config "$tmp/absent"

# --- _config_set: upsert preserves other keys, creates 0600 ---
cfg2="$tmp/.codex_config2"
_config_set "$cfg2" ICODEX_REPO "openai/codex"
_config_set "$cfg2" ICODEX_PROXY "http://p:1"
perm="$(stat -c '%a' "$cfg2" 2>/dev/null || stat -f '%Lp' "$cfg2")"
assert_eq "config_set file is 600" "600" "$perm"
unset ICODEX_REPO ICODEX_PROXY; load_config "$cfg2"
assert_eq "set: REPO preserved"  "openai/codex" "${ICODEX_REPO:-}"
assert_eq "set: PROXY added"     "http://p:1"   "${ICODEX_PROXY:-}"

# --- _config_set replaces an existing key without duplicating it ---
_config_set "$cfg2" ICODEX_PROXY "http://p:2"
lines="$(grep -c '^ICODEX_PROXY=' "$cfg2")"
assert_eq "no duplicate key" "1" "$lines"
unset ICODEX_PROXY; load_config "$cfg2"
assert_eq "set: PROXY replaced" "http://p:2" "${ICODEX_PROXY:-}"

rm -rf "$tmp"
finish

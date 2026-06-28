#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/config/env.sh"

tmp="$(mktemp -d)"; cfg="$tmp/.codex_config"

# --- load_config: allowed ICODEX_* lines are exported; unrelated keys/comments ignored ---
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

# --- load_config: iwiki and uv allowlist; unrelated env keys ignored ---
cat > "$cfg" <<'EOF'
ICODEX_PROXY=http://proxy.local:8080
IWIKI_LLM_BASE_URL=https://embeddings.local/v1
IWIKI_LLM_KEY=secret-value
IWIKI_AUTO_QUERY=0
UV_BIN=/opt/uv
UV_BIN_EXTRA=ignored
OPENAI_API_KEY=ignored
BAD_KEY=ignored
EOF
unset ICODEX_PROXY IWIKI_LLM_BASE_URL IWIKI_LLM_KEY IWIKI_AUTO_QUERY UV_BIN UV_BIN_EXTRA BAD_KEY OPENAI_API_KEY
load_config "$cfg"
assert_eq "ICODEX_PROXY allowlisted" "http://proxy.local:8080" "${ICODEX_PROXY:-}"
assert_eq "IWIKI_LLM_BASE_URL allowlisted" "https://embeddings.local/v1" "${IWIKI_LLM_BASE_URL:-}"
assert_eq "IWIKI_LLM_KEY allowlisted" "secret-value" "${IWIKI_LLM_KEY:-}"
assert_eq "IWIKI_AUTO_QUERY allowlisted" "0" "${IWIKI_AUTO_QUERY:-}"
assert_eq "UV_BIN allowlisted" "/opt/uv" "${UV_BIN:-}"
assert_eq "UV_BIN_EXTRA ignored" "" "${UV_BIN_EXTRA:-}"
assert_eq "BAD_KEY ignored" "" "${BAD_KEY:-}"
assert_eq "OPENAI_API_KEY ignored by load_config" "" "${OPENAI_API_KEY:-}"

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

# --- apply_api_key: ICODEX_API_KEY -> OPENAI_API_KEY when the latter is unset ---
unset OPENAI_API_KEY ICODEX_API_KEY
ICODEX_API_KEY="sk-test123"
apply_api_key
assert_eq "api key mapped to OPENAI_API_KEY" "sk-test123" "${OPENAI_API_KEY:-}"

# ambient OPENAI_API_KEY takes precedence over ICODEX_API_KEY
unset OPENAI_API_KEY ICODEX_API_KEY
export OPENAI_API_KEY="sk-ambient"; ICODEX_API_KEY="sk-config"
apply_api_key
assert_eq "ambient OPENAI_API_KEY wins" "sk-ambient" "${OPENAI_API_KEY:-}"

# no ICODEX_API_KEY -> no-op
unset OPENAI_API_KEY ICODEX_API_KEY
assert_exit "no key -> noop returns 0" 0 apply_api_key
assert_eq "no OPENAI_API_KEY set" "" "${OPENAI_API_KEY:-}"

rm -rf "$tmp"
finish

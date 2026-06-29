#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/config/env.sh"
source "$ROOT/lib/proxy/proxy.sh"

tmp="$(mktemp -d)"; cfg="$tmp/.codex_config"

# proxy_save upserts ICODEX_PROXY (0600) and preserves other ICODEX_* keys
_config_set "$cfg" ICODEX_REPO "openai/codex"
proxy_save "$cfg" "http://proxy.local:8080"
perm="$(stat -c '%a' "$cfg" 2>/dev/null || stat -f '%Lp' "$cfg")"
assert_eq "config is 600" "600" "$perm"
assert_eq "proxy persisted as ICODEX_PROXY" "1" "$(grep -c '^ICODEX_PROXY=http://proxy.local:8080$' "$cfg")"
assert_eq "other key preserved"             "1" "$(grep -c '^ICODEX_REPO=openai/codex$' "$cfg")"

# proxy_apply exports all four *_PROXY vars from $ICODEX_PROXY (set by load_config)
unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy ICODEX_PROXY NO_PROXY no_proxy ICODEX_NO_PROXY
load_config "$cfg"
proxy_apply
assert_eq "HTTPS_PROXY exported" "http://proxy.local:8080" "${HTTPS_PROXY:-}"
assert_eq "HTTP_PROXY exported"  "http://proxy.local:8080" "${HTTP_PROXY:-}"
assert_eq "https_proxy exported" "http://proxy.local:8080" "${https_proxy:-}"
assert_eq "http_proxy exported"  "http://proxy.local:8080" "${http_proxy:-}"
assert_eq "NO_PROXY not set without host list" "" "${NO_PROXY:-}"

# ICODEX_NO_PROXY is a host bypass list, exported as NO_PROXY / no_proxy
unset NO_PROXY no_proxy
ICODEX_PROXY="http://p:8080" ICODEX_NO_PROXY="localhost,127.0.0.1,github.com" proxy_apply
assert_eq "NO_PROXY exported" "localhost,127.0.0.1,github.com" "${NO_PROXY:-}"
assert_eq "no_proxy exported" "localhost,127.0.0.1,github.com" "${no_proxy:-}"

# proxy_apply is a no-op when ICODEX_PROXY is unset or empty
unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy ICODEX_PROXY
proxy_apply
assert_eq "no export when unset" "" "${HTTPS_PROXY:-}"
ICODEX_PROXY="" proxy_apply
assert_eq "no export when empty" "" "${HTTPS_PROXY:-}"

# pre-existing loose-perm config is tightened to 600 on save
printf 'ICODEX_REPO=x\n' > "$tmp/pre"; chmod 644 "$tmp/pre"
proxy_save "$tmp/pre" "http://new:9090"
perm_pre="$(stat -c '%a' "$tmp/pre" 2>/dev/null || stat -f '%Lp' "$tmp/pre")"
assert_eq "existing config tightened to 600" "600" "$perm_pre"

# proxy_clear removes the config
proxy_clear "$cfg"
assert_exit "config cleared" 1 test -f "$cfg"

# --- _proxy_host_port: parse host+port from a proxy URL (Task 1) ---
assert_eq "host:port explicit"      "h 8080" "$(_proxy_host_port http://h:8080)"
assert_eq "http default port"       "h 80"   "$(_proxy_host_port http://h)"
assert_eq "https default port"      "h 443"  "$(_proxy_host_port https://h)"
assert_eq "socks5 default port"     "h 1080" "$(_proxy_host_port socks5://h)"
assert_eq "userinfo and path strip" "h 3128" "$(_proxy_host_port http://MASKING@h:3128/x)"
assert_eq "schemeless host:port"    "h 9"    "$(_proxy_host_port h:9)"

rm -rf "$tmp"
finish

#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/proxy/proxy.sh"

tmp="$(mktemp -d)"; cfg="$tmp/.codex_config"

proxy_save "$cfg" "http://proxy.local:8080"
assert_exit "config written" 0 test -f "$cfg"
perm="$(stat -c '%a' "$cfg" 2>/dev/null || stat -f '%Lp' "$cfg")"
assert_eq "config is 600" "600" "$perm"

unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy
proxy_apply "$cfg"
assert_eq "HTTPS_PROXY exported" "http://proxy.local:8080" "${HTTPS_PROXY:-}"
assert_eq "http_proxy exported"  "http://proxy.local:8080" "${http_proxy:-}"
assert_eq "HTTP_PROXY exported"  "http://proxy.local:8080" "${HTTP_PROXY:-}"
assert_eq "https_proxy exported" "http://proxy.local:8080" "${https_proxy:-}"

printf 'PROXY_URL=old\n' > "$tmp/.codex_config_pre"
chmod 644 "$tmp/.codex_config_pre"
proxy_save "$tmp/.codex_config_pre" "http://new:9090"
perm_pre="$(stat -c '%a' "$tmp/.codex_config_pre" 2>/dev/null || stat -f '%Lp' "$tmp/.codex_config_pre")"
assert_eq "existing config tightened to 600" "600" "$perm_pre"

unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy
proxy_apply "$tmp/absent"
assert_eq "no export when absent" "" "${HTTPS_PROXY:-}"

unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy
printf 'PROXY_URL=\n' > "$tmp/.codex_config_empty"
proxy_apply "$tmp/.codex_config_empty"
assert_eq "no export when empty url" "" "${HTTPS_PROXY:-}"

proxy_clear "$cfg"
assert_exit "config cleared" 1 test -f "$cfg"

rm -rf "$tmp"
finish

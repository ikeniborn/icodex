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

unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy
proxy_apply "$tmp/absent"
assert_eq "no export when absent" "" "${HTTPS_PROXY:-}"

proxy_clear "$cfg"
assert_exit "config cleared" 1 test -f "$cfg"

rm -rf "$tmp"
finish

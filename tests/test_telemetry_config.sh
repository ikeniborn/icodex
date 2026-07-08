#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/telemetry/telemetry.sh"

unset ICODEX_TELEMETRY
telemetry_mode_default
assert_eq "default mode off" "off" "$ICODEX_TELEMETRY"

for mode in off otel langfuse both; do
  ICODEX_TELEMETRY="$mode"
  assert_exit "valid mode $mode" 0 telemetry_validate_mode
done

ICODEX_TELEMETRY="bad"
assert_exit "invalid mode fails" 1 telemetry_validate_mode

tmp="$(mktemp -d)"
mkdir -p "$tmp/repo"
git -C "$tmp/repo" init >/dev/null 2>&1
mkdir -p "$tmp/repo/subdir"
project="$(telemetry_derive_project "$tmp/repo/subdir")"
assert_eq "git project basename" "repo" "$project"

nogit="$tmp/plain"
mkdir -p "$nogit"
project="$(telemetry_derive_project "$nogit")"
assert_eq "plain project basename" "plain" "$project"

sid="$(telemetry_new_session_id)"
case "$sid" in
  icodex-*) PASS=$((PASS+1)); echo "PASS [session id prefix]" ;;
  *) FAIL=$((FAIL+1)); echo "FAIL [session id prefix]: got '$sid'" ;;
esac

assert_exit "localhost trusted" 0 telemetry_url_is_local_trusted "http://localhost:3000"
assert_exit "localhost query trusted" 0 telemetry_url_is_local_trusted "http://localhost?x=1"
assert_exit "localhost fragment trusted" 0 telemetry_url_is_local_trusted "http://localhost#x"
assert_exit "path at trusted" 0 telemetry_url_is_local_trusted "http://localhost/path@x"
assert_exit "127 trusted" 0 telemetry_url_is_local_trusted "http://127.0.0.1:3000"
assert_exit "ipv6 loopback trusted" 0 telemetry_url_is_local_trusted "http://[::1]:3000"
assert_exit "private trusted" 0 telemetry_url_is_local_trusted "http://192.168.1.10:3000"
assert_exit "public rejected" 1 telemetry_url_is_local_trusted "https://example.com"
assert_exit "url credentials rejected" 1 telemetry_url_is_local_trusted "http://user:pass@localhost:3000"
assert_exit "missing scheme rejected" 1 telemetry_url_is_local_trusted "localhost:3000"
assert_exit "10 hostname rejected" 1 telemetry_url_is_local_trusted "http://10.evil.com"
assert_exit "192 hostname rejected" 1 telemetry_url_is_local_trusted "http://192.168.evil.com"
assert_exit "172 hostname rejected" 1 telemetry_url_is_local_trusted "http://172.20.evil.com"
assert_exit "ipv6 suffix hostname rejected" 1 telemetry_url_is_local_trusted "http://[::1].evil.com"
assert_exit "ipv6 suffix text rejected" 1 telemetry_url_is_local_trusted "http://[::1]evil.com"
assert_exit "invalid 10 octet rejected" 1 telemetry_url_is_local_trusted "http://10.999.999.999"
assert_exit "invalid 192 octet rejected" 1 telemetry_url_is_local_trusted "http://192.168.1.999"
assert_exit "invalid 172 octet rejected" 1 telemetry_url_is_local_trusted "http://172.20.0.999"

rm -rf "$tmp"
finish

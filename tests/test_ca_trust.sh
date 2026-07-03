#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/config/ca_trust.sh"

if ! command -v openssl >/dev/null 2>&1; then
  echo "SKIP [ca_trust]: openssl not available"; exit 0
fi

# --- fixtures -------------------------------------------------------------

tmp="$(mktemp -d)"
# A valid RSA cert OpenSSL can decode (the key itself is discarded).
openssl req -x509 -newkey rsa:2048 -nodes -keyout /dev/null \
  -out "$tmp/valid.crt" -subj "/CN=icodex-test" -days 1 >/dev/null 2>&1
# A cert block whose body OpenSSL cannot decode -- stands in for a GOST cert.
garbage="$(printf -- '-----BEGIN CERTIFICATE-----\nZ2FyYmFnZQ==\n-----END CERTIFICATE-----\n')"

mixed="$tmp/mixed-bundle.crt"     # one good + one undecodable
{ printf '# leading comment ignored\n'; cat "$tmp/valid.crt"; printf '%s\n' "$garbage"; } > "$mixed"
clean_src="$tmp/clean-bundle.crt" # all decodable
cat "$tmp/valid.crt" > "$clean_src"

# --- _ca_scan_and_filter --------------------------------------------------

out="$tmp/filtered.crt"
_ca_scan_and_filter "$mixed" "$out"; rc=$?
assert_eq "scan flags problem when a cert can't decode" "0" "$rc"
kept="$(grep -c 'BEGIN CERTIFICATE' "$out" 2>/dev/null || echo 0)"
assert_eq "filtered bundle keeps only decodable certs" "1" "$kept"

out2="$tmp/filtered2.crt"
_ca_scan_and_filter "$clean_src" "$out2"; rc=$?
assert_eq "scan reports OK when every cert decodes" "1" "$rc"
assert_eq "clean source leaves no filtered file" "absent" \
  "$([[ -e "$out2" ]] && echo present || echo absent)"

# --- ensure_ca_trust: problem host ---------------------------------------

_ca_default_bundle() { printf '%s\n' "$mixed"; }   # seam: point at the fixture
ICODEX_SHARED_DIR="$tmp/shared"
unset CURL_CA_BUNDLE SSL_CERT_FILE ICODEX_CA_BUNDLE ICODEX_CA_FIX

ensure_ca_trust
assert_eq "exports CURL_CA_BUNDLE on a broken host" "$tmp/shared/ca-trust/ca-nogost.crt" "${CURL_CA_BUNDLE:-}"
assert_eq "mirrors into SSL_CERT_FILE" "$tmp/shared/ca-trust/ca-nogost.crt" "${SSL_CERT_FILE:-}"
assert_eq "wrote the filtered bundle" "yes" "$([[ -s "$CURL_CA_BUNDLE" ]] && echo yes || echo no)"

# --- ensure_ca_trust: idempotent (cache hit, no rescan) -------------------

printf 'SENTINEL\n' >> "$CURL_CA_BUNDLE"     # tamper; a rescan would overwrite it
unset CURL_CA_BUNDLE SSL_CERT_FILE
ensure_ca_trust
assert_eq "cache hit re-exports without rescanning" "$tmp/shared/ca-trust/ca-nogost.crt" "${CURL_CA_BUNDLE:-}"
assert_eq "unchanged source is not re-filtered" "yes" \
  "$(grep -q SENTINEL "$CURL_CA_BUNDLE" && echo yes || echo no)"

# Source change (new mtime) invalidates the cache and re-filters.
touch -d '2031-01-01' "$mixed"
unset CURL_CA_BUNDLE SSL_CERT_FILE
ensure_ca_trust
assert_eq "changed source triggers a re-filter" "no" \
  "$(grep -q SENTINEL "${CURL_CA_BUNDLE:-/dev/null}" && echo yes || echo no)"

# --- ensure_ca_trust: healthy host is a no-op -----------------------------

_ca_default_bundle() { printf '%s\n' "$clean_src"; }
ICODEX_SHARED_DIR="$tmp/shared-ok"
unset CURL_CA_BUNDLE SSL_CERT_FILE
ensure_ca_trust
assert_eq "no export when the system bundle is fine" "" "${CURL_CA_BUNDLE:-}"

# --- non-destructive: respect a pre-set bundle ----------------------------

_ca_default_bundle() { printf '%s\n' "$mixed"; }
export CURL_CA_BUNDLE="/user/own.crt"; unset SSL_CERT_FILE
ensure_ca_trust
assert_eq "never clobbers a user-set CURL_CA_BUNDLE" "/user/own.crt" "$CURL_CA_BUNDLE"

# --- explicit override ----------------------------------------------------

unset CURL_CA_BUNDLE SSL_CERT_FILE
export ICODEX_CA_BUNDLE="$clean_src"
ensure_ca_trust
assert_eq "ICODEX_CA_BUNDLE override wins" "$clean_src" "${CURL_CA_BUNDLE:-}"
unset ICODEX_CA_BUNDLE

# --- opt out --------------------------------------------------------------

unset CURL_CA_BUNDLE SSL_CERT_FILE
export ICODEX_CA_FIX=off
ensure_ca_trust
assert_eq "ICODEX_CA_FIX=off disables the workaround" "" "${CURL_CA_BUNDLE:-}"
unset ICODEX_CA_FIX

rm -rf "$tmp"
finish

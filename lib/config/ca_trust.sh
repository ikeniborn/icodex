#!/usr/bin/env bash
# Work around the ALT Linux / OpenSSL 1.1.1w curl breakage. The system CA trust
# bundle ships GOST-algorithm roots (Mincifry, CryptoPro, Rostelecom, ...) whose
# public keys curl's OpenSSL build cannot decode; loading the bundle aborts the
# whole trust store, so every curl HTTPS call fails with
#   error:0B09406F ... x509_pubkey_decode: unsupported algorithm
# codex itself is unaffected (it uses rustls + bundled roots), but curl
# subprocesses spawned inside the session are. We detect the condition locally
# (no network) and, when present, export CURL_CA_BUNDLE / SSL_CERT_FILE pointing
# at a GOST-free copy of the bundle so those subprocesses can verify TLS again.
#
# Guarantees:
#   - Idempotent: the filtered bundle is cached and keyed to the source bundle's
#     path+mtime; an unchanged source means no rescan, just a re-export.
#   - Non-destructive: never edits the system trust; writes only inside
#     $ICODEX_SHARED_DIR; respects a pre-set CURL_CA_BUNDLE / SSL_CERT_FILE and
#     the ICODEX_CA_BUNDLE override; opt out entirely with ICODEX_CA_FIX=off.
#   - Best-effort: a missing tool or unreadable bundle degrades to a no-op and
#     never blocks the launch.

# --- Seams (overridable in tests) ---

# Echo the CA file curl loads by default. First existing candidate wins.
_ca_default_bundle() {
  local b
  for b in \
    /etc/pki/tls/certs/ca-bundle.crt \
    /usr/share/ca-certificates/ca-bundle.crt \
    /etc/ssl/certs/ca-certificates.crt \
    /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem ; do
    [[ -f "$b" ]] && { printf '%s\n' "$b"; return 0; }
  done
  return 1
}

# Portable mtime (GNU stat, then BSD stat, then 0).
_ca_mtime() { # <file>
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

# Write a GOST-free copy of <src> to <out>. A cert is kept only when OpenSSL can
# decode its public key -- the exact operation curl's SSL_CTX performs when it
# loads the bundle. Exit 0 when at least one cert was dropped (the workaround is
# needed and <out> was written); exit 1 when every cert decoded (no problem, and
# <out> is left untouched).
_ca_scan_and_filter() { # <src> <out>
  local src="$1" out="$2" tmpd f dropped=0 kept=0
  command -v openssl >/dev/null 2>&1 || return 1
  tmpd="$(mktemp -d)" || return 1
  # Split into one file per certificate; ignore anything outside cert blocks so
  # leading comments never masquerade as an undecodable cert.
  awk -v d="$tmpd" '
    /-----BEGIN CERTIFICATE-----/ { inc=1; n++ }
    inc                          { print > (d "/c" n) }
    /-----END CERTIFICATE-----/  { inc=0 }
  ' "$src"
  : > "$out.tmp"
  for f in "$tmpd"/c*; do
    [[ -s "$f" ]] || continue
    if openssl x509 -in "$f" -noout -pubkey 2>/dev/null \
         | openssl pkey -pubin -noout >/dev/null 2>&1; then
      cat "$f" >> "$out.tmp"; kept=$((kept+1))
    else
      dropped=$((dropped+1))
    fi
  done
  rm -rf "$tmpd"
  if (( dropped > 0 && kept > 0 )); then
    mv -f "$out.tmp" "$out"; return 0
  fi
  rm -f "$out.tmp"; return 1
}

# Export the curl/OpenSSL trust overrides without clobbering a user's own.
_ca_export() { # <bundle>
  export CURL_CA_BUNDLE="$1"
  export SSL_CERT_FILE="${SSL_CERT_FILE:-$1}"
}

# Detect the GOST/curl breakage and, if present, point curl subprocesses at a
# GOST-free bundle. Safe to call on every run; a no-op on healthy hosts.
ensure_ca_trust() {
  [[ "${ICODEX_CA_FIX:-auto}" == off ]] && return 0
  # User already manages curl trust -> leave it alone.
  [[ -n "${CURL_CA_BUNDLE:-}" ]] && return 0
  # Explicit override wins and skips detection entirely.
  if [[ -n "${ICODEX_CA_BUNDLE:-}" && -f "${ICODEX_CA_BUNDLE}" ]]; then
    _ca_export "$ICODEX_CA_BUNDLE"; return 0
  fi
  command -v openssl >/dev/null 2>&1 || return 0

  local src; src="$(_ca_default_bundle)" || return 0
  local dir="$ICODEX_SHARED_DIR/ca-trust"
  local clean="$dir/ca-nogost.crt" stamp="$dir/.stamp"
  local sig="$src:$(_ca_mtime "$src")"

  # Idempotent fast path: verdict cached for this exact source state.
  if [[ -f "$stamp" && "$(cat "$stamp" 2>/dev/null)" == "$sig" ]]; then
    [[ -s "$clean" ]] && _ca_export "$clean"
    return 0
  fi

  mkdir -p "$dir" || return 0
  if _ca_scan_and_filter "$src" "$clean"; then
    printf '%s\n' "$sig" > "$stamp"
    _ca_export "$clean"
    log_warn "curl CA trust: system bundle has certs OpenSSL can't decode (GOST); routing curl/SSL via $clean"
  else
    rm -f "$clean"
    printf '%s\n' "$sig" > "$stamp"
  fi
  return 0
}

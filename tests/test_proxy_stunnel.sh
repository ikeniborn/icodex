#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/config/ca_trust.sh"
source "$ROOT/lib/proxy/proxy.sh"
assert_exit 'stunnel module exists' 0 test -f "$ROOT/lib/proxy/stunnel.sh"
[[ -f "$ROOT/lib/proxy/stunnel.sh" ]] || { finish; exit 1; }
source "$ROOT/lib/proxy/stunnel.sh"
tmp="$(mktemp -d)"
trap 'proxy_stunnel_stop; rm -rf "$tmp"' EXIT
for row in 'ubuntu apt-get stunnel4' 'debian apt-get stunnel4' 'altlinux apt-get stunnel' 'fedora dnf stunnel' 'rhel dnf stunnel' 'arch pacman stunnel' 'opensuse-tumbleweed zypper stunnel' 'alpine apk stunnel'; do
  read -r distro manager package <<< "$row"
  _proxy_stunnel_install_command "$distro"
  assert_eq "$distro manager" "$manager" "${ICODEX_STUNNEL_INSTALL_CMD[0]}"
  assert_eq "$distro package" "$package" "${ICODEX_STUNNEL_INSTALL_CMD[${#ICODEX_STUNNEL_INSTALL_CMD[@]}-1]}"
done
assert_exit 'unsupported distribution rejected' 1 _proxy_stunnel_install_command unknown
printf 'ca' > "$tmp/ca"
ICODEX_CA_BUNDLE="$tmp/missing" SSL_CERT_FILE="$tmp/ca"
assert_exit 'invalid explicit CA does not fall through' 1 _proxy_stunnel_ca_file
ICODEX_CA_BUNDLE="$tmp/ca"
assert_eq 'explicit CA selected' "$tmp/ca" "$(_proxy_stunnel_ca_file)"
unset ICODEX_CA_BUNDLE SSL_CERT_FILE
proxy_stunnel_find() { return 1; }
_proxy_stunnel_install() { echo called >> "$tmp/install"; return 1; }
assert_exit 'no TTY refuses installation' 1 proxy_stunnel_require </dev/null
assert_exit 'no installation side effect' 1 test -e "$tmp/install"
proxy_stunnel_stop
proxy_stunnel_stop
assert_eq 'idempotent cleanup' '' "${ICODEX_STUNNEL_PID:-}"
finish

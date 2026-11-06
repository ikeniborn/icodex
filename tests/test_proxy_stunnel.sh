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
# Execute the installer with fake privilege/package commands and real apt config parsing.
mkdir "$tmp/bin"
cat > "$tmp/bin/sudo" <<'SH'
#!/usr/bin/env bash
exec "$@"
SH
cat > "$tmp/bin/apt-get" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$APT_TEST_DIR/args"
while (( $# )); do
  if [[ "$1" == -c ]]; then
    shift
    printf '%s' "$1" > "$APT_TEST_DIR/config-path"
    apt-config -c "$1" dump > "$APT_TEST_DIR/effective"
  fi
  shift
done
exit 17
SH
chmod +x "$tmp/bin/"*
cat > "$tmp/apt.conf" <<'CONF'
Dir::Etc::main "/dev/null";
Dir::Etc::parts "-";
Acquire::http::Proxy "http://bad.invalid:9";
Acquire::https::Proxy "http://bad.invalid:9";
Acquire::http::Proxy::example.test "http://bad.invalid:9";
Acquire::https::Proxy::example.test "http://bad.invalid:9";
Acquire::http::Proxy-Auto-Detect "/bad/detect";
Acquire::https::ProxyAutoDetect "/bad/detect";
CONF
if command -v apt-config >/dev/null; then
  _proxy_stunnel_install_command ubuntu
  assert_exit 'apt failure status preserved' 17 env PATH="$tmp/bin:$PATH" APT_CONFIG="$tmp/apt.conf" APT_TEST_DIR="$tmp" bash -c 'source "$1/lib/core/logging.sh"; source "$1/lib/proxy/stunnel.sh"; _proxy_stunnel_install_command ubuntu; _proxy_stunnel_install' bash "$ROOT"
  effective="$(cat "$tmp/effective" 2>/dev/null)"
  assert_contains 'apt HTTP direct' "$effective" 'Acquire::http::Proxy "DIRECT"'
  assert_contains 'apt HTTPS direct' "$effective" 'Acquire::https::Proxy "DIRECT"'
  assert_exit 'apt host and autodetect proxies removed' 1 grep -E 'bad.invalid|/bad/detect' "$tmp/effective"
  assert_exit 'apt temporary config cleaned after failure' 1 test -e "$(cat "$tmp/config-path" 2>/dev/null)"
fi
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

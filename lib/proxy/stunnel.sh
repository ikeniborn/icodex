#!/usr/bin/env bash
# Own one foreground TLS transport per invocation. Never start a system service.
proxy_stunnel_find() {
  command -v stunnel 2>/dev/null || command -v stunnel4 2>/dev/null
}

_proxy_stunnel_install_command() {
  case "$1" in
    debian|ubuntu) ICODEX_STUNNEL_INSTALL_CMD=(apt-get install stunnel4) ;;
    altlinux|alt) ICODEX_STUNNEL_INSTALL_CMD=(apt-get install stunnel) ;;
    fedora|rhel|centos|rocky|almalinux) ICODEX_STUNNEL_INSTALL_CMD=(dnf install stunnel) ;;
    arch) ICODEX_STUNNEL_INSTALL_CMD=(pacman -S --needed stunnel) ;;
    opensuse*|sles) ICODEX_STUNNEL_INSTALL_CMD=(zypper install stunnel) ;;
    alpine) ICODEX_STUNNEL_INSTALL_CMD=(apk add stunnel) ;;
    *) return 1 ;;
  esac
}

_proxy_stunnel_install() (
  local -a privilege=()
  if (( EUID != 0 )); then
    command -v sudo >/dev/null || { log_warn "sudo unavailable; install stunnel manually"; return 1; }
    privilege=(sudo)
  fi
  local apt_config=""
  local -a command=("${ICODEX_STUNNEL_INSTALL_CMD[@]}")
  if [[ "${command[0]}" == apt-get ]]; then
    apt_config="$(mktemp)" || return 1
    trap 'rm -f -- "$apt_config"' EXIT
    # Clear host-specific and automatic proxy settings as well as the defaults.
    cat > "$apt_config" <<'CONF'
#clear Acquire::http::Proxy;
#clear Acquire::https::Proxy;
#clear Acquire::http::Proxy-Auto-Detect;
#clear Acquire::https::Proxy-Auto-Detect;
#clear Acquire::http::ProxyAutoDetect;
#clear Acquire::https::ProxyAutoDetect;
Acquire::http::Proxy "DIRECT";
Acquire::https::Proxy "DIRECT";
CONF
    command+=(-c "$apt_config")
  fi
  # Keep other package managers on their native repository configuration.
  env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
    "${privilege[@]}" "${command[@]}"
)

proxy_stunnel_require() {
  proxy_stunnel_find >/dev/null && return 0
  if [[ "${ICODEX_STUNNEL_OFFERED:-0}" == 1 ]]; then return 1; fi
  ICODEX_STUNNEL_OFFERED=1
  if [[ "$(uname -s)" != Linux || ! -t 0 ]]; then
    log_warn "stunnel missing; HTTPS candidate unavailable (installation requires an interactive Linux terminal)"
    return 1
  fi
  local ID="" reply=""
  [[ ! -r /etc/os-release ]] || source /etc/os-release
  if ! _proxy_stunnel_install_command "$ID" || ! command -v "${ICODEX_STUNNEL_INSTALL_CMD[0]}" >/dev/null; then
    log_warn "automatic stunnel installation unavailable; install the package manually"
    return 1
  fi
  local routing="Repository access uses host settings."
  [[ "${ICODEX_STUNNEL_INSTALL_CMD[0]}" != apt-get ]] || routing="APT repository access is direct, without a proxy."
  printf '[icodex] Install stunnel using %s? Administrator privileges and native package scripts may be required. %s [y/N] ' "${ICODEX_STUNNEL_INSTALL_CMD[*]}" "$routing" >&2
  read -r reply || reply=""
  [[ "$(_proxy_unreachable_action 1 "$reply")" == continue ]] || return 1
  _proxy_stunnel_install || { log_warn "stunnel installation failed; trying the next proxy"; return 1; }
  proxy_stunnel_find >/dev/null
}

_proxy_stunnel_ca_file() {
  local ca="${ICODEX_CA_BUNDLE:-${SSL_CERT_FILE:-${CURL_CA_BUNDLE:-}}}"
  if [[ -z "$ca" ]]; then ca="$(_ca_default_bundle)" || return 1; fi
  [[ -r "$ca" && -f "$ca" && "$ca" != *[[:cntrl:]]* ]] || return 1
  printf '%s\n' "$ca"
}

proxy_stunnel_stop() {
  local pid="${ICODEX_STUNNEL_PID:-}" tick
  if [[ -n "$pid" ]]; then
    kill -TERM "$pid" 2>/dev/null || true
    for ((tick=0; tick<20; tick++)); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then kill -KILL "$pid" 2>/dev/null || true; fi
    wait "$pid" 2>/dev/null || true
  fi
  ICODEX_STUNNEL_PID=""
  if [[ -n "${ICODEX_STUNNEL_DIR:-}" ]]; then rm -rf -- "$ICODEX_STUNNEL_DIR"; fi
  ICODEX_STUNNEL_DIR=""
}

proxy_stunnel_start() {
  local url="$1" executable ca host port upstream userinfo="" authority attempt local_port tick
  proxy_stunnel_require || return 1
  executable="$(proxy_stunnel_find)" || return 1
  ca="$(_proxy_stunnel_ca_file)" || { log_warn "no readable CA bundle for HTTPS proxy"; return 1; }
  read -r host port < <(_proxy_host_port "$url")
  upstream="$host:$port"
  [[ "$host" != *:* ]] || upstream="[$host]:$port"
  authority="${url#*://}"; authority="${authority%%[/?#]*}"
  [[ "$authority" != *@* ]] || userinfo="${authority%@*}@"
  for ((attempt=0; attempt<3; attempt++)); do
    proxy_stunnel_stop
    ICODEX_STUNNEL_DIR="$(mktemp -d)" || return 1
    local_port=$((20000 + RANDOM))
    (
      umask 077
      {
        printf 'foreground = yes\nsyslog = no\npid =\ndebug = debug\n[icodex-proxy]\nclient = yes\n'
        printf 'accept = 127.0.0.1:%s\nconnect = %s\nverifyChain = yes\nCAfile = %s\n' "$local_port" "$upstream" "$ca"
        if [[ "$host" == *:* || "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
          printf 'checkIP = %s\n' "$host"
        else
          printf 'checkHost = %s\nsni = %s\n' "$host" "$host"
        fi
      } > "$ICODEX_STUNNEL_DIR/client.conf"
      : > "$ICODEX_STUNNEL_DIR/startup.log"
    )
    LC_ALL=C "$executable" "$ICODEX_STUNNEL_DIR/client.conf" >"$ICODEX_STUNNEL_DIR/startup.log" 2>&1 &
    ICODEX_STUNNEL_PID=$!
    for ((tick=0; tick<30; tick++)); do
      kill -0 "$ICODEX_STUNNEL_PID" 2>/dev/null || break
      if grep -Fq "bound to 127.0.0.1:$local_port" "$ICODEX_STUNNEL_DIR/startup.log"; then
        ICODEX_PROXY_ACTIVE="http://${userinfo}127.0.0.1:$local_port"
        return 0
      fi
      sleep 0.1
    done
    # Retry only a local bind collision, not invalid TLS configuration.
    if ! grep -qi 'Address already in use' "$ICODEX_STUNNEL_DIR/startup.log"; then break; fi
  done
  proxy_stunnel_stop
  log_warn "HTTPS proxy tunnel failed to start"
  return 1
}

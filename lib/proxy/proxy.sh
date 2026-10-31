#!/usr/bin/env bash
# Persist and apply the proxy for codex. The persistent values live in the config
# file (see config/env.sh): ICODEX_PROXY is the proxy URL; ICODEX_NO_PROXY is a
# comma-separated host bypass list (standard NO_PROXY semantics). proxy_apply
# exports the standard *_PROXY / NO_PROXY vars, which Codex (Rust reqwest) honors.
proxy_save() { # <config_file> <url>
  proxy_validate "$2" || return 1
  _config_set "$1" ICODEX_PROXY "$2"
}

# Clear inherited routes before any wrapper network operation or direct fallback.
proxy_disable() {
  unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
}

proxy_validate() { # <url>; never include the input in diagnostics
  local url="$1" scheme="http" host port
  [[ "$url" != *://* ]] || scheme="${url%%://*}"
  case "$scheme" in
    http|https|socks4|socks4a|socks5|socks5h) ;;
    *) log_error "unsupported proxy scheme; use http, https, socks4, socks4a, socks5, or socks5h"; return 1 ;;
  esac
  if [[ -z "$url" || "$url" =~ [[:space:][:cntrl:]] ]]; then
    log_error "invalid proxy URL"; return 1
  fi
  read -r host port < <(_proxy_host_port "$url")
  if [[ -z "$host" || ! "$port" =~ ^[0-9]{1,5}$ ]] || (( 10#$port < 1 || 10#$port > 65535 )); then
    log_error "invalid proxy host or port"; return 1
  fi
}

proxy_clear() { # <config_file>
  rm -f "$1"
}

proxy_apply() { # exports *_PROXY from $ICODEX_PROXY; NO_PROXY from $ICODEX_NO_PROXY
  [[ -n "${ICODEX_PROXY:-}" ]] || return 0
  export HTTPS_PROXY="$ICODEX_PROXY" HTTP_PROXY="$ICODEX_PROXY" https_proxy="$ICODEX_PROXY" http_proxy="$ICODEX_PROXY"
  if [[ -n "${ICODEX_NO_PROXY:-}" ]]; then
    export NO_PROXY="$ICODEX_NO_PROXY" no_proxy="$ICODEX_NO_PROXY"
  fi
}

# Echo "host port" parsed from a proxy URL. Strips scheme, userinfo, and path;
# defaults the port by scheme (https=443, socks*=1080, otherwise 80).
_proxy_host_port() { # <url>
  local url="$1" scheme rest host port
  if [[ "$url" == *"://"* ]]; then
    scheme="${url%%://*}"
    rest="${url#*://}"
  else
    scheme=""
    rest="$url"
  fi
  rest="${rest%%[/?#]*}"  # isolate authority before stripping userinfo
  rest="${rest##*@}"
  if [[ "$rest" =~ ^\[([[:xdigit:]:.]+)\](:([0-9]+))?$ ]]; then
    host="${BASH_REMATCH[1]}"
    port="${BASH_REMATCH[3]}"
  elif [[ "$rest" =~ ^([[:alnum:]._-]+)(:([0-9]+))?$ ]]; then
    host="${BASH_REMATCH[1]}"
    port="${BASH_REMATCH[3]}"
  else
    return 1
  fi
  if [[ -z "$port" ]]; then
    case "$scheme" in
      https) port=443 ;;
      socks5|socks5h|socks4|socks4a) port=1080 ;;
      *) port=80 ;;
    esac
  fi
  printf '%s %s\n' "$host" "$port"
}

# Probe an authenticated tunnel, without sending account credentials. Pass proxy
# credentials through stdin, not argv. Ignore curlrc and inherited bypass rules.
_proxy_probe() {
  local escaped="$ICODEX_PROXY" result rc=0 connect status
  escaped="${escaped//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  result=$(printf 'proxy = "%s"\n' "$escaped" | curl -q --config - \
    --noproxy '' --silent --connect-timeout 3 --max-time 8 \
    --output /dev/null --write-out '%{http_connect} %{http_code}' \
    https://chatgpt.com/backend-api/wham/accounts/check 2>/dev/null) || rc=$?
  read -r connect status <<< "$result"
  if [[ "$connect" == 407 ]]; then
    log_warn "proxy authentication rejected (HTTP 407)"; return 1
  fi
  case "$rc" in
    0) ;;
    5) log_warn "proxy DNS resolution failed"; return 1 ;;
    7) log_warn "proxy TCP connection failed"; return 1 ;;
    28) log_warn "proxy connection or target request timed out"; return 1 ;;
    35) log_warn "proxy or target TLS handshake failed"; return 1 ;;
    60) log_warn "proxy or target TLS certificate verification failed"; return 1 ;;
    97) log_warn "SOCKS negotiation or authentication failed"; return 1 ;;
    *) log_warn "proxy tunnel probe failed (curl code $rc)"; return 1 ;;
  esac
  case "$status" in
    2??|401) return 0 ;;
    *) log_warn "proxy probe target rejected request (HTTP ${status:-000})"; return 1 ;;
  esac
}

# Echo "continue" or "exit" for the proxy-unreachable case. Only an explicit n/N
# at an interactive prompt exits; an empty reply, y/Y, EOF, or no TTY continues.
_proxy_unreachable_action() { # <tty:0|1> <reply>
  local tty="$1" reply="$2"
  if [[ "$tty" == 1 && "$reply" =~ ^[Nn]$ ]]; then
    printf 'exit\n'
  else
    printf 'continue\n'
  fi
}

# Probe the tunnel before launch; preserve the existing direct-fallback choice.
# A successful probe does not guarantee later Codex connections will succeed.
proxy_ensure() {
  [[ -n "${ICODEX_PROXY:-}" ]] || return 0
  proxy_validate "$ICODEX_PROXY" || return 1
  if _proxy_probe; then
    proxy_apply
    return 0
  fi
  local tty=0 reply=""
  if [[ -t 0 ]]; then
    tty=1
    printf '[icodex] Continue without proxy? [Y/n] ' >&2
    read -r reply || reply=""
  fi
  if [[ "$(_proxy_unreachable_action "$tty" "$reply")" == exit ]]; then
    log_error "aborted: configured proxy probe failed"
    exit 1
  fi
  proxy_disable
  log_warn "continuing directly without proxy; later Codex connections were not verified"
  return 0
}

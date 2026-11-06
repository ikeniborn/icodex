#!/usr/bin/env bash
# Persist and apply the proxy for codex. The persistent values live in the config
# file (see config/env.sh): ICODEX_PROXY is the proxy URL; ICODEX_NO_PROXY is a
# comma-separated host bypass list (standard NO_PROXY semantics). proxy_apply
# exports the standard *_PROXY / NO_PROXY vars, which Codex (Rust reqwest) honors.
proxy_save() { # <config_file> <url>
  proxy_parse_list "$2" || return 1
  _config_set "$1" ICODEX_PROXY "$2"
}

# Clear inherited routes before any wrapper network operation or direct fallback.
proxy_disable() {
  unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
  ICODEX_PROXY_ACTIVE=""
}

# Parse the full list before persisting or attempting any route.
proxy_parse_list() {
  local rest="$1" candidate
  ICODEX_PROXY_CANDIDATES=()
  [[ "$rest" != *[[:cntrl:]]* ]] || { log_error "invalid proxy list"; return 1; }
  while :; do
    candidate="${rest%%,*}"
    candidate="${candidate#"${candidate%%[! ]*}"}"
    candidate="${candidate%"${candidate##*[! ]}"}"
    proxy_validate "$candidate" || return 1
    ICODEX_PROXY_CANDIDATES+=("$candidate")
    [[ "$rest" == *,* ]] || break
    rest="${rest#*,}"
  done
}

proxy_cleanup() {
  if declare -F proxy_stunnel_stop >/dev/null; then proxy_stunnel_stop; fi
}

proxy_prepare_candidate() {
  ICODEX_PROXY_ACTIVE="$1"
  if [[ "$1" == https://* ]]; then
    if ! declare -F proxy_stunnel_start >/dev/null; then
      log_warn "HTTPS proxy requires the stunnel module"
      return 1
    fi
    proxy_stunnel_start "$1" || return 1
  fi
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
  local active="${ICODEX_PROXY_ACTIVE-${ICODEX_PROXY:-}}"
  [[ -n "$active" ]] || return 0
  unset ALL_PROXY all_proxy
  export HTTPS_PROXY="$active" HTTP_PROXY="$active" https_proxy="$active" http_proxy="$active"
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
_proxy_probe_target() { printf '%s\n' https://chatgpt.com/backend-api/wham/accounts/check; }

_proxy_probe() {
  local escaped="${ICODEX_PROXY_ACTIVE-${ICODEX_PROXY:-}}" result rc=0 connect status
  escaped="${escaped//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  result=$(printf 'proxy = "%s"\n' "$escaped" | curl -q --config - \
    --noproxy '' --silent --connect-timeout 3 --max-time 8 \
    --output /dev/null --write-out '%{http_connect} %{http_code}' \
    "$(_proxy_probe_target)" 2>/dev/null) || rc=$?
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
  case "${ICODEX_PROXY_ACTIVE-${ICODEX_PROXY:-}}" in
    socks*) ;;
    *) [[ "$connect" == 200 ]] || { log_warn "proxy CONNECT failed"; return 1; } ;;
  esac
  case "$status" in
    2??|401) return 0 ;;
    *) log_warn "proxy probe target rejected request (HTTP ${status:-000})"; return 1 ;;
  esac
}

# Direct fallback requires an affirmative answer from an interactive user.
_proxy_unreachable_action() { # <tty:0|1> <reply>
  if [[ "$1" == 1 && "$2" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]; then
    printf 'continue\n'
  else
    printf 'exit\n'
  fi
}

proxy_ensure() {
  [[ -n "${ICODEX_PROXY:-}" ]] || return 0
  proxy_parse_list "$ICODEX_PROXY" || return 1
  local candidate index=0 tty=0 reply=""
  for candidate in "${ICODEX_PROXY_CANDIDATES[@]}"; do
    index=$((index + 1))
    log_info "checking proxy candidate $index"
    if proxy_prepare_candidate "$candidate" && _proxy_probe; then
      proxy_apply
      log_info "selected proxy candidate $index"
      return 0
    fi
    proxy_cleanup
  done
  proxy_disable
  if [[ -t 0 ]]; then
    tty=1
    printf '[icodex] All proxies failed. Continue without proxy? [y/N] ' >&2
    read -r reply || reply=""
  fi
  if [[ "$(_proxy_unreachable_action "$tty" "$reply")" == exit ]]; then
    log_error "aborted: no working proxy and no direct-connection consent"
    return 1
  fi
  log_warn "continuing directly with user consent"
}

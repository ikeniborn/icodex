#!/usr/bin/env bash
# Persist and apply the proxy for codex. The persistent values live in the config
# file (see config/env.sh): ICODEX_PROXY is the proxy URL; ICODEX_NO_PROXY is a
# comma-separated host bypass list (standard NO_PROXY semantics). proxy_apply
# exports the standard *_PROXY / NO_PROXY vars, which Codex (Rust reqwest) honors.
proxy_save() { # <config_file> <url>
  _config_set "$1" ICODEX_PROXY "$2"
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
  rest="${rest##*@}"      # strip user:pass@ userinfo
  rest="${rest%%/*}"      # strip /path
  host="${rest%%:*}"
  if [[ "$rest" == *:* ]]; then
    port="${rest##*:}"
  else
    case "$scheme" in
      https) port=443 ;;
      socks5|socks5h|socks4) port=1080 ;;
      *) port=80 ;;
    esac
  fi
  printf '%s %s\n' "$host" "$port"
}

# Return 0 if a TCP connection to host:port opens within <timeout> seconds, else 1.
# host/port are passed as positional args to the inner shell (no path injection).
proxy_reachable() { # <host> <port> [timeout=3]
  local host="$1" port="$2" t="${3:-3}"
  timeout "$t" bash -c 'exec 3<>/dev/tcp/"$0"/"$1"' "$host" "$port" 2>/dev/null
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

# Probe ICODEX_PROXY before launch; apply it if reachable, else prompt (TTY) or
# warn-and-skip (no TTY). Never lets codex hang on a dead proxy. exit 1 only when
# an interactive user answers n/N.
proxy_ensure() {
  [[ -n "${ICODEX_PROXY:-}" ]] || return 0
  local host port
  read -r host port < <(_proxy_host_port "$ICODEX_PROXY")
  if proxy_reachable "$host" "$port"; then
    proxy_apply
    return 0
  fi
  log_warn "proxy $ICODEX_PROXY unreachable"
  local tty=0 reply=""
  if [[ -t 0 ]]; then
    tty=1
    printf '[icodex] Continue without proxy? [Y/n] ' >&2
    read -r reply || reply=""
  fi
  if [[ "$(_proxy_unreachable_action "$tty" "$reply")" == exit ]]; then
    log_error "aborted: proxy $ICODEX_PROXY unreachable"
    exit 1
  fi
  log_warn "continuing without proxy"
  return 0
}

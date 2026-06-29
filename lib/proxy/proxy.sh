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

#!/usr/bin/env bash
# Persist and apply proxy env vars for codex (Rust reqwest honors them natively).
proxy_save() { # <config_file> <url>
  ( umask 177; printf 'PROXY_URL=%s\n' "$2" > "$1" )
  chmod 600 "$1"
}

proxy_clear() { # <config_file>
  rm -f "$1"
}

proxy_apply() { # <config_file>
  local file="$1" url
  [[ -f "$file" ]] || return 0
  url="$(sed -n 's/^PROXY_URL=//p' "$file" | head -1)"
  [[ -n "$url" ]] || return 0
  export HTTPS_PROXY="$url" HTTP_PROXY="$url" https_proxy="$url" http_proxy="$url"
}

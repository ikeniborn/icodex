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

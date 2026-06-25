#!/usr/bin/env bash
# Persist and apply the proxy for codex. The persistent value is stored as
# ICODEX_PROXY in the config file (see config/env.sh); proxy_apply exports the
# standard *_PROXY vars from $ICODEX_PROXY, which load_config (or the --proxy
# flag) provides. Codex (Rust reqwest) honors *_PROXY natively.
proxy_save() { # <config_file> <url>
  _config_set "$1" ICODEX_PROXY "$2"
}

proxy_clear() { # <config_file>
  rm -f "$1"
}

proxy_apply() { # exports *_PROXY from $ICODEX_PROXY (no-op if unset/empty)
  [[ -n "${ICODEX_PROXY:-}" ]] || return 0
  export HTTPS_PROXY="$ICODEX_PROXY" HTTP_PROXY="$ICODEX_PROXY" https_proxy="$ICODEX_PROXY" http_proxy="$ICODEX_PROXY"
}

#!/usr/bin/env bash

detect_pii_proxy() {
  [[ -f "${ICODEX_PII_PROXY_SERVER_SCRIPT:-}" ]] || return 1
  [[ -d "${ICODEX_PII_PROXY_VENV:-}" ]] || return 1
  [[ -x "${ICODEX_PII_PROXY_VENV:-}/bin/python3" ]] || return 1
}

get_pii_proxy_python() {
  local py="${ICODEX_PII_PROXY_VENV:-}/bin/python3"
  [[ -x "$py" ]] || return 1
  printf '%s\n' "$py"
}

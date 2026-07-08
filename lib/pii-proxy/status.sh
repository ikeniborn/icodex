#!/usr/bin/env bash

check_pii_proxy_status() {
  echo "PII proxy status"
  if [[ ! -f "${ICODEX_PII_PROXY_SERVER_SCRIPT:-}" || ! -d "${ICODEX_PII_PROXY_VENV:-}" ]]; then
    echo "not installed"
    return 0
  fi
  echo "server: $ICODEX_PII_PROXY_SERVER_SCRIPT"
  echo "venv: $ICODEX_PII_PROXY_VENV"
  local engine
  engine="$(cat "$ICODEX_PII_PROXY_VENV/pii_proxy_engine" 2>/dev/null || echo unknown)"
  echo "engine: $engine"
  if [[ "$engine" == "nlp" ]]; then
    echo "spacy en: $(cat "$ICODEX_PII_PROXY_VENV/spacy_model_en" 2>/dev/null || echo missing)"
    echo "spacy ru: $(cat "$ICODEX_PII_PROXY_VENV/spacy_model_ru" 2>/dev/null || echo missing)"
  fi
  if [[ -f "$ICODEX_PII_PROXY_LOG_DIR/server.port" ]]; then
    echo "port: $(cat "$ICODEX_PII_PROXY_LOG_DIR/server.port")"
  else
    echo "not running"
  fi
}

#!/usr/bin/env bash

_pii_python_ok() {
  python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null
}

_pii_venv_create() {
  python3 -m venv "$ICODEX_PII_PROXY_VENV"
}

_pii_pip_install() {
  "$ICODEX_PII_PROXY_VENV/bin/python3" -m pip install "$@"
}

_pii_spacy_download() {
  local lang="$1" primary="$2" fallback="$3"
  "$ICODEX_PII_PROXY_VENV/bin/python3" -m spacy download "$primary" --upgrade \
    || "$ICODEX_PII_PROXY_VENV/bin/python3" -m spacy download "$fallback"
}

install_isolated_pii_proxy() {
  _pii_python_ok || { log_error "Python 3.8+ required for PII proxy"; return 1; }
  mkdir -p "$(dirname "$ICODEX_PII_PROXY_VENV")"
  [[ -d "$ICODEX_PII_PROXY_VENV" ]] || _pii_venv_create || return 1
  _pii_pip_install --upgrade pip >/dev/null 2>&1 || true
  _pii_pip_install requests || return 1
  if [[ "${ICODEX_PII_ENGINE:-rules}" == "nlp" ]]; then
    _pii_pip_install presidio-analyzer presidio-anonymizer spacy --prefer-binary || return 1
    _pii_spacy_download en "${ICODEX_PII_SPACY_EN_MODEL:-en_core_web_lg}" en_core_web_sm || return 1
    _pii_spacy_download ru "${ICODEX_PII_SPACY_RU_MODEL:-ru_core_news_lg}" ru_core_news_sm || return 1
    printf '%s\n' "${ICODEX_PII_SPACY_EN_MODEL:-en_core_web_lg}" > "$ICODEX_PII_PROXY_VENV/spacy_model_en"
    printf '%s\n' "${ICODEX_PII_SPACY_RU_MODEL:-ru_core_news_lg}" > "$ICODEX_PII_PROXY_VENV/spacy_model_ru"
  fi
  printf '%s\n' "${ICODEX_PII_ENGINE:-rules}" > "$ICODEX_PII_PROXY_VENV/pii_proxy_engine"
  mkdir -p "$(dirname "$ICODEX_PII_PROXY_SERVER_SCRIPT")" "$ICODEX_PII_PROXY_LOG_DIR"
  ln -sf "$ICODEX_ROOT/lib/pii-proxy/server.py" "$ICODEX_PII_PROXY_SERVER_SCRIPT"
}

update_pii_nlp_models() {
  local engine
  engine="$(cat "$ICODEX_PII_PROXY_VENV/pii_proxy_engine" 2>/dev/null || printf '%s\n' "${ICODEX_PII_ENGINE:-rules}")"
  [[ "$engine" == "nlp" || "${ICODEX_PII_ENGINE:-rules}" == "nlp" ]] || return 0
  [[ -d "$ICODEX_PII_PROXY_VENV" ]] || return 0
  _pii_pip_install --upgrade presidio-analyzer presidio-anonymizer spacy --prefer-binary || return 1
  _pii_spacy_download en "${ICODEX_PII_SPACY_EN_MODEL:-en_core_web_lg}" en_core_web_sm || return 1
  _pii_spacy_download ru "${ICODEX_PII_SPACY_RU_MODEL:-ru_core_news_lg}" ru_core_news_sm || return 1
  printf '%s\n' "${ICODEX_PII_SPACY_EN_MODEL:-en_core_web_lg}" > "$ICODEX_PII_PROXY_VENV/spacy_model_en"
  printf '%s\n' "${ICODEX_PII_SPACY_RU_MODEL:-ru_core_news_lg}" > "$ICODEX_PII_PROXY_VENV/spacy_model_ru"
}

#!/usr/bin/env bash
# Persistent user configuration. The config file (.codex_config) holds plain
# KEY=value lines; only ICODEX_* keys are honored. Values are parsed and
# exported — the file is NOT sourced, so it can never execute arbitrary code.

_config_key_allowed() { # <key>
  case "$1" in
    IWIKI_[A-Z0-9_]*) return 1 ;;   # raw IWIKI_* must go through the ICODEX_ wrapper
    ICODEX_[A-Z0-9_]*) return 0 ;;  # includes ICODEX_IWIKI_* (e.g. ICODEX_IWIKI_LLM_KEY)
    *) return 1 ;;
  esac
}

# load_config <file> — export allowed KEY=value lines from the file.
# Comments, blank lines, and disallowed keys are ignored. Missing file: no-op.
load_config() { # <config_file>
  local file="$1" line key val
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"                       # tolerate CRLF
    [[ "$line" =~ ^[A-Z][A-Z0-9_]*= ]] || continue
    key="${line%%=*}"
    _config_key_allowed "$key" || continue
    val="${line#*=}"
    export "$key=$val"
  done < "$file"
}

# apply_api_key — map ICODEX_API_KEY (from .codex_config) to OPENAI_API_KEY for
# codex. An OPENAI_API_KEY already present in the environment takes precedence.
apply_api_key() {
  [[ -n "${ICODEX_API_KEY:-}" ]] || return 0
  export OPENAI_API_KEY="${OPENAI_API_KEY:-$ICODEX_API_KEY}"
}

# apply_iwiki_env — map ICODEX_IWIKI_LLM_KEY (from .codex_config) to IWIKI_LLM_KEY
# for the iwiki MCP server. The config.toml [mcp_servers.iwiki] block forwards
# IWIKI_LLM_KEY via env_vars; all other iwiki settings are literal in that block.
# An IWIKI_LLM_KEY already in the environment takes precedence.
apply_iwiki_env() {
  [[ -n "${ICODEX_IWIKI_LLM_KEY:-}" ]] || return 0
  export IWIKI_LLM_KEY="${IWIKI_LLM_KEY:-$ICODEX_IWIKI_LLM_KEY}"
}

_pii_is_uint() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }

_pii_valid_upstream() {
  local url="${1:-}"
  case "$url" in
    https://*) return 0 ;;
    http://127.0.0.1:*|http://127.0.0.1/*|http://localhost:*|http://localhost/*) return 0 ;;
    http://[[]::1[]]:*|http://[[]::1[]]/*) return 0 ;;
    *) return 1 ;;
  esac
}

validate_pii_config() {
  case "${ICODEX_PII_ENGINE:-rules}" in
    rules|nlp) ;;
    *) log_error "invalid ICODEX_PII_ENGINE: ${ICODEX_PII_ENGINE:-}"; return 1 ;;
  esac
  case "${ICODEX_PII_MASKING_LEVEL:-standard}" in
    off|secrets|standard) ;;
    *) log_error "invalid ICODEX_PII_MASKING_LEVEL: ${ICODEX_PII_MASKING_LEVEL:-}"; return 1 ;;
  esac
  case "${ICODEX_PII_LOG_LEVEL:-info}" in
    info|debug) ;;
    *) log_error "invalid ICODEX_PII_LOG_LEVEL: ${ICODEX_PII_LOG_LEVEL:-}"; return 1 ;;
  esac
  _pii_is_uint "${ICODEX_PII_PROXY_PORT:-0}" || { log_error "invalid ICODEX_PII_PROXY_PORT"; return 1; }
  _pii_is_uint "${ICODEX_PII_PROXY_PORT_MIN:-20000}" || { log_error "invalid ICODEX_PII_PROXY_PORT_MIN"; return 1; }
  _pii_is_uint "${ICODEX_PII_PROXY_PORT_MAX:-40000}" || { log_error "invalid ICODEX_PII_PROXY_PORT_MAX"; return 1; }
  (( ICODEX_PII_PROXY_PORT_MIN >= 1024 && ICODEX_PII_PROXY_PORT_MIN < ICODEX_PII_PROXY_PORT_MAX && ICODEX_PII_PROXY_PORT_MAX <= 65535 )) || {
    log_error "invalid PII proxy port range"
    return 1
  }
  _pii_is_uint "${ICODEX_PII_CONNECT_TIMEOUT:-10}" || { log_error "invalid ICODEX_PII_CONNECT_TIMEOUT"; return 1; }
  _pii_is_uint "${ICODEX_PII_READ_TIMEOUT:-300}" || { log_error "invalid ICODEX_PII_READ_TIMEOUT"; return 1; }
  _pii_valid_upstream "${ICODEX_PII_UPSTREAM_URL:-https://api.openai.com/v1}" || {
    log_error "invalid ICODEX_PII_UPSTREAM_URL: ${ICODEX_PII_UPSTREAM_URL:-}"
    return 1
  }
}

map_pii_env() {
  export PII_PROXY_ENGINE="${ICODEX_PII_ENGINE:-rules}"
  export PII_PROXY_MASKING_LEVEL="${ICODEX_PII_MASKING_LEVEL:-standard}"
  export PII_PROXY_MASK_TOKEN="${ICODEX_PII_MASK_TOKEN:-REDACTED}"
  export PII_PROXY_LOG_LEVEL="${ICODEX_PII_LOG_LEVEL:-info}"
  export PII_PROXY_PORT="${ICODEX_PII_PROXY_PORT:-0}"
  export PII_PROXY_PORT_MIN="${ICODEX_PII_PROXY_PORT_MIN:-20000}"
  export PII_PROXY_PORT_MAX="${ICODEX_PII_PROXY_PORT_MAX:-40000}"
  export PII_PROXY_UPSTREAM_URL="${ICODEX_PII_UPSTREAM_URL:-https://api.openai.com/v1}"
  export PII_PROXY_CONNECT_TIMEOUT="${ICODEX_PII_CONNECT_TIMEOUT:-10}"
  export PII_PROXY_READ_TIMEOUT="${ICODEX_PII_READ_TIMEOUT:-300}"
  export PII_PROXY_SPACY_EN_MODEL="${ICODEX_PII_SPACY_EN_MODEL:-en_core_web_lg}"
  export PII_PROXY_SPACY_RU_MODEL="${ICODEX_PII_SPACY_RU_MODEL:-ru_core_news_lg}"
}

# _config_set <file> <key> <value> — upsert KEY=value, preserving other lines.
# The file is (re)written with 0600 permissions from the start (creds-safe).
_config_set() { # <config_file> <key> <value>
  local file="$1" key="$2" val="$3" tmp
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    grep -v "^${key}=" "$file" > "$tmp" 2>/dev/null || true
  fi
  printf '%s=%s\n' "$key" "$val" >> "$tmp"
  ( umask 177; cat "$tmp" > "$file" )
  chmod 600 "$file"
  rm -f "$tmp"
}

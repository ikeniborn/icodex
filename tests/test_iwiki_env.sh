#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/config/env.sh"

tmp="$(mktemp -d)"; cfg="$tmp/.codex_config"
trap 'rm -rf "$tmp"' EXIT

# --- _config_key_allowed: ICODEX_IWIKI_* wrapper allowed, raw IWIKI_* rejected ---
assert_exit "ICODEX_IWIKI_LLM_KEY allowed" 0 _config_key_allowed ICODEX_IWIKI_LLM_KEY
assert_exit "raw IWIKI_LLM_KEY rejected"   1 _config_key_allowed IWIKI_LLM_KEY
assert_exit "ICODEX_IWIKI_RERANK_MODEL allowed" 0 _config_key_allowed ICODEX_IWIKI_RERANK_MODEL
assert_exit "raw IWIKI_RERANK_MODEL rejected" 1 _config_key_allowed IWIKI_RERANK_MODEL
assert_exit "raw IWIKI_BASE_DIR rejected"  1 _config_key_allowed IWIKI_BASE_DIR
assert_exit "ICODEX_PROXY still allowed"   0 _config_key_allowed ICODEX_PROXY

# --- load_config exports the wrapper key; raw key in file is ignored ---
cat > "$cfg" <<'EOF'
ICODEX_IWIKI_LLM_KEY=sk-secret
ICODEX_IWIKI_RERANK_MODEL=rerank-test-model
IWIKI_LLM_KEY=raw-should-be-ignored
IWIKI_RERANK_MODEL=raw-rerank-should-be-ignored
EOF
unset ICODEX_IWIKI_LLM_KEY IWIKI_LLM_KEY ICODEX_IWIKI_RERANK_MODEL IWIKI_RERANK_MODEL
load_config "$cfg"
assert_eq "wrapper key loaded"         "sk-secret"         "${ICODEX_IWIKI_LLM_KEY:-}"
assert_eq "wrapper rerank loaded"      "rerank-test-model" "${ICODEX_IWIKI_RERANK_MODEL:-}"
assert_eq "raw key in file ignored"    ""                  "${IWIKI_LLM_KEY:-}"
assert_eq "raw rerank in file ignored" ""                  "${IWIKI_RERANK_MODEL:-}"

# --- apply_iwiki_env: maps wrapper -> IWIKI_LLM_KEY when target unset ---
unset IWIKI_LLM_KEY; ICODEX_IWIKI_LLM_KEY="sk-secret"
apply_iwiki_env
assert_eq "mapped to IWIKI_LLM_KEY" "sk-secret" "${IWIKI_LLM_KEY:-}"

# --- ambient IWIKI_LLM_KEY wins over the wrapper ---
unset IWIKI_LLM_KEY; export IWIKI_LLM_KEY="sk-ambient"; ICODEX_IWIKI_LLM_KEY="sk-config"
apply_iwiki_env
assert_eq "ambient IWIKI_LLM_KEY wins" "sk-ambient" "${IWIKI_LLM_KEY:-}"

# --- no wrapper -> no-op returns 0, leaves IWIKI_LLM_KEY untouched ---
unset IWIKI_LLM_KEY ICODEX_IWIKI_LLM_KEY
assert_exit "no wrapper -> noop 0" 0 apply_iwiki_env
assert_eq "IWIKI_LLM_KEY stays unset" "" "${IWIKI_LLM_KEY:-}"

# --- PostgreSQL password follows the same wrapper-only secret path ---
unset IWIKI_DB_PASSWORD; ICODEX_IWIKI_DB_PASSWORD="db-secret"
apply_iwiki_env
assert_eq "mapped to IWIKI_DB_PASSWORD" "db-secret" "${IWIKI_DB_PASSWORD:-}"

unset IWIKI_DB_PASSWORD; export IWIKI_DB_PASSWORD="db-ambient"; ICODEX_IWIKI_DB_PASSWORD="db-config"
apply_iwiki_env
assert_eq "ambient IWIKI_DB_PASSWORD wins" "db-ambient" "${IWIKI_DB_PASSWORD:-}"

# --- remote MCP token follows the wrapper-only secret path ---
unset IWIKI_REMOTE_TOKEN; ICODEX_IWIKI_REMOTE_TOKEN="remote-secret"
apply_iwiki_env
assert_eq "mapped to IWIKI_REMOTE_TOKEN" "remote-secret" "${IWIKI_REMOTE_TOKEN:-}"

unset IWIKI_REMOTE_TOKEN; export IWIKI_REMOTE_TOKEN="remote-ambient"; ICODEX_IWIKI_REMOTE_TOKEN="remote-config"
apply_iwiki_env
assert_eq "ambient IWIKI_REMOTE_TOKEN wins" "remote-ambient" "${IWIKI_REMOTE_TOKEN:-}"

finish

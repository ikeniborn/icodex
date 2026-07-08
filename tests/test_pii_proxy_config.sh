#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/core/init.sh"
source "$ROOT/lib/config/env.sh"

tmp="$(mktemp -d)"
cfg="$tmp/.codex_config"
export ICODEX_ROOT="$tmp/repo"
source "$ROOT/lib/core/init.sh"

assert_eq "pii venv path" "$tmp/repo/.codex-isolated/pii-proxy-venv" "$ICODEX_PII_PROXY_VENV"
assert_eq "pii script path" "$tmp/repo/.codex-isolated/pii-proxy-server.py" "$ICODEX_PII_PROXY_SERVER_SCRIPT"
assert_eq "pii log dir" "$tmp/repo/.codex-isolated/pii-proxy-logs" "$ICODEX_PII_PROXY_LOG_DIR"
assert_eq "default engine" "rules" "$ICODEX_PII_ENGINE"
assert_eq "default masking level" "standard" "$ICODEX_PII_MASKING_LEVEL"
assert_eq "default upstream" "https://api.openai.com/v1" "$ICODEX_PII_UPSTREAM_URL"

cat > "$cfg" <<'EOF'
ICODEX_USE_PII_PROXY=true
ICODEX_PII_ENGINE=nlp
ICODEX_PII_MASKING_LEVEL=secrets
ICODEX_PII_MASK_TOKEN=[MASKED]
ICODEX_PII_LOG_LEVEL=debug
ICODEX_PII_PROXY_PORT=0
ICODEX_PII_PROXY_PORT_MIN=21000
ICODEX_PII_PROXY_PORT_MAX=22000
ICODEX_PII_UPSTREAM_URL=https://api.openai.com/v1
ICODEX_PII_CONNECT_TIMEOUT=3
ICODEX_PII_READ_TIMEOUT=30
ICODEX_PII_SPACY_EN_MODEL=en_core_web_sm
ICODEX_PII_SPACY_RU_MODEL=ru_core_news_sm
EOF

load_config "$cfg"
assert_exit "valid pii config" 0 validate_pii_config
map_pii_env
assert_eq "engine mapped" "nlp" "$PII_PROXY_ENGINE"
assert_eq "masking mapped" "secrets" "$PII_PROXY_MASKING_LEVEL"
assert_eq "mask token mapped" "[MASKED]" "$PII_PROXY_MASK_TOKEN"
assert_eq "log mapped" "debug" "$PII_PROXY_LOG_LEVEL"
assert_eq "port min mapped" "21000" "$PII_PROXY_PORT_MIN"
assert_eq "upstream mapped" "https://api.openai.com/v1" "$PII_PROXY_UPSTREAM_URL"
assert_eq "en model mapped" "en_core_web_sm" "$PII_PROXY_SPACY_EN_MODEL"
assert_eq "ru model mapped" "ru_core_news_sm" "$PII_PROXY_SPACY_RU_MODEL"

ICODEX_PII_ENGINE=bad
assert_exit "invalid engine" 1 validate_pii_config
ICODEX_PII_ENGINE=rules
ICODEX_PII_MASKING_LEVEL=bad
assert_exit "invalid masking level" 1 validate_pii_config
ICODEX_PII_MASKING_LEVEL=standard
ICODEX_PII_LOG_LEVEL=trace
assert_exit "invalid log level" 1 validate_pii_config
ICODEX_PII_LOG_LEVEL=info
ICODEX_PII_UPSTREAM_URL=file:///tmp/x
assert_exit "invalid upstream" 1 validate_pii_config
ICODEX_PII_UPSTREAM_URL=http://example.com/v1
assert_exit "non-loopback http upstream" 1 validate_pii_config
ICODEX_PII_UPSTREAM_URL=http://127.0.0.1:9999/v1
assert_exit "loopback http upstream" 0 validate_pii_config

rm -rf "$tmp"
finish

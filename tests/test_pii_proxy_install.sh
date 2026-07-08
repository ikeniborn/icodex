#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/core/init.sh"
source "$ROOT/lib/pii-proxy/install.sh"

tmp="$(mktemp -d)"
export ICODEX_SHARED_DIR="$tmp/shared"
export ICODEX_PII_PROXY_VENV="$tmp/shared/pii-proxy-venv"
export ICODEX_PII_PROXY_SERVER_SCRIPT="$tmp/shared/pii-proxy-server.py"
export ICODEX_PII_PROXY_LOG_DIR="$tmp/shared/pii-proxy-logs"
mkdir -p "$ICODEX_SHARED_DIR"

calls="$tmp/calls.log"
_pii_python_ok() { return 0; }
_pii_venv_create() { mkdir -p "$ICODEX_PII_PROXY_VENV/bin"; touch "$ICODEX_PII_PROXY_VENV/bin/python3"; chmod +x "$ICODEX_PII_PROXY_VENV/bin/python3"; }
_pii_pip_install() { echo "pip:$*" >> "$calls"; }
_pii_spacy_download() { echo "spacy:$*" >> "$calls"; }

ICODEX_PII_ENGINE=rules
install_isolated_pii_proxy
assert_contains "rules installs requests" "$(cat "$calls")" "pip:requests"
assert_eq "rules marker" "rules" "$(cat "$ICODEX_PII_PROXY_VENV/pii_proxy_engine")"

: > "$calls"
ICODEX_PII_ENGINE=nlp
ICODEX_PII_SPACY_EN_MODEL=en_core_web_lg
ICODEX_PII_SPACY_RU_MODEL=ru_core_news_lg
install_isolated_pii_proxy
out="$(cat "$calls")"
assert_contains "nlp installs presidio" "$out" "presidio-analyzer"
assert_contains "nlp downloads en" "$out" "spacy:en en_core_web_lg en_core_web_sm"
assert_contains "nlp downloads ru" "$out" "spacy:ru ru_core_news_lg ru_core_news_sm"
assert_eq "nlp marker" "nlp" "$(cat "$ICODEX_PII_PROXY_VENV/pii_proxy_engine")"

: > "$calls"
update_pii_nlp_models
out="$(cat "$calls")"
assert_contains "update refreshes en model" "$out" "spacy:en en_core_web_lg en_core_web_sm"
assert_contains "update refreshes ru model" "$out" "spacy:ru ru_core_news_lg ru_core_news_sm"

rm -rf "$tmp"
finish

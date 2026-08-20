#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/iwiki/iwiki.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export ICODEX_HOME_DIR="$tmp/home"
mkdir -p "$ICODEX_HOME_DIR"
printf 'project instructions\n' > "$ICODEX_HOME_DIR/AGENTS.md"
export ICODEX_IWIKI_REMOTE_URL="https://iwiki.example.com/mcp"
export ICODEX_IWIKI_REMOTE_TOKEN="remote-test-token"

ensure_iwiki_remote_scope_instructions
ensure_iwiki_remote_scope_instructions
agents="$(cat "$ICODEX_HOME_DIR/AGENTS.md")"
assert_contains "remote scope region starts" "$agents" '<!-- icodex:iwiki-remote-scope:start -->'
assert_contains "remote scope normalizes domains" "$agents" 'Normalize domain names before passing them to `wiki_bind`'
assert_contains "remote scope binds before status" "$agents" 'before `wiki_status`, `wiki_search`, task-ledger, or any other wiki call'
assert_contains "remote scope includes full TOML scope" "$agents" 'full normalized `read`, `write`, and `primary` values from `.iwiki.toml`'
assert_contains "remote scope refuses fallback" "$agents" 'Do not infer, broaden, or replace that scope'
assert_contains "remote scope fails closed" "$agents" 'do not make mutating wiki calls and retain task lifecycle `completion-pending`'
assert_contains "remote scope documents PostgreSQL CAS" "$agents" 'pass its current `revision` as `expected_revision`'
assert_contains "remote scope documents section CAS" "$agents" '`expected_section_hash`'
assert_contains "remote scope keeps hosted code reads" "$agents" '`wiki_code_status`, `wiki_code_search`, and `wiki_code_context` read the published hosted snapshot'
assert_contains "remote scope rejects hosted indexing" "$agents" '`wiki_code_index` returns `source_unavailable`'
assert_eq "remote scope excludes token" "0" "$(grep -c 'remote-test-token' "$ICODEX_HOME_DIR/AGENTS.md")"
assert_eq "remote scope is idempotent" "1" "$(grep -c '<!-- icodex:iwiki-remote-scope:start -->' "$ICODEX_HOME_DIR/AGENTS.md")"

unset ICODEX_IWIKI_REMOTE_URL ICODEX_IWIKI_REMOTE_TOKEN
ensure_iwiki_remote_scope_instructions
agents="$(cat "$ICODEX_HOME_DIR/AGENTS.md")"
assert_eq "stdio removes remote scope region" "0" "$(grep -c 'icodex:iwiki-remote-scope:start' "$ICODEX_HOME_DIR/AGENTS.md")"
assert_contains "stdio retains project instructions" "$agents" 'project instructions'

finish

#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"
source "$ROOT/scripts/vendor-iwiki.sh" --lib-only

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
src="$tmp/source"
destroot="$tmp/cache"
dest="$destroot/ai-wiki/iwiki/0.6.5"

mkdir -p \
  "$src/.claude-plugin" \
  "$src/skills/iwiki-query" \
  "$src/engine/iwiki_engine" \
  "$src/hooks/__pycache__" \
  "$src/engine/.venv" \
  "$src/.git"

cat > "$src/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "iwiki",
  "version": "0.6.5",
  "description": "Semantic documentation graph for local projects.",
  "author": {
    "name": "Source Author",
    "url": "https://example.invalid/source"
  },
  "homepage": "https://github.com/ikeniborn/ai-wiki-plugin",
  "repository": "https://github.com/ikeniborn/ai-wiki-plugin",
  "keywords": ["docs", "wiki"],
  "license": "MIT"
}
JSON
printf '# iwiki query\n' > "$src/skills/iwiki-query/SKILL.md"
printf '[project]\nname = "iwiki-engine"\n' > "$src/engine/pyproject.toml"
printf 'version = 1\n' > "$src/engine/uv.lock"
printf '__version__ = "0.6.5"\n' > "$src/engine/iwiki_engine/__init__.py"
printf 'print("recall")\n' > "$src/hooks/iwiki-recall.py"
printf 'compiled\n' > "$src/hooks/__pycache__/x.pyc"
printf 'venv\n' > "$src/engine/.venv/file"
printf 'git\n' > "$src/.git/config"

out="$(_vendor_iwiki_normalize "$src" "$destroot")"

assert_eq "prints destination path" "$dest" "$out"
assert_exit "codex manifest written" 0 test -f "$dest/.codex-plugin/plugin.json"
assert_exit "skill copied" 0 test -f "$dest/skills/iwiki-query/SKILL.md"
assert_exit "engine pyproject copied" 0 test -f "$dest/engine/pyproject.toml"
assert_exit "engine lock copied" 0 test -f "$dest/engine/uv.lock"
assert_exit "engine package copied" 0 test -f "$dest/engine/iwiki_engine/__init__.py"
assert_exit "hook copied" 0 test -f "$dest/hooks/iwiki-recall.py"
assert_exit "venv stripped" 1 test -e "$dest/engine/.venv"
assert_exit "pycache stripped" 1 test -e "$dest/hooks/__pycache__"
assert_exit "git stripped" 1 test -e "$dest/.git"
assert_contains "manifest contains name" \
  "$(cat "$dest/.codex-plugin/plugin.json")" '"name": "iwiki"'
assert_contains "manifest contains skills path" \
  "$(cat "$dest/.codex-plugin/plugin.json")" '"skills": "./skills/"'

bad_src="$tmp/bad-source"
mkdir -p \
  "$bad_src/.claude-plugin" \
  "$bad_src/skills/iwiki-query" \
  "$bad_src/engine/iwiki_engine" \
  "$bad_src/hooks"

cat > "$bad_src/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "iwiki",
  "version": "../../escape",
  "description": "Bad version fixture.",
  "homepage": "https://example.invalid",
  "repository": "https://example.invalid/repo",
  "license": "MIT"
}
JSON
printf '# iwiki query\n' > "$bad_src/skills/iwiki-query/SKILL.md"
printf '[project]\nname = "iwiki-engine"\n' > "$bad_src/engine/pyproject.toml"
printf '__version__ = "bad"\n' > "$bad_src/engine/iwiki_engine/__init__.py"
printf 'print("recall")\n' > "$bad_src/hooks/iwiki-recall.py"

assert_exit "rejects unsafe manifest version" 1 _vendor_iwiki_normalize "$bad_src" "$destroot"
assert_exit "unsafe version does not create escape path" 1 test -e "$tmp/cache/escape"

finish

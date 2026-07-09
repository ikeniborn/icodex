#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
cd "$ROOT"

ci() { git check-ignore --no-index -q "$1"; }   # 0 => ignored, 1 => tracked-eligible

assert_exit "config is tracked"         1 ci .codex-isolated/config.toml
assert_exit "example is ignored"        0 ci .codex-isolated/config.toml.example
assert_exit "rules are tracked"         1 ci .codex-isolated/rules/default.rules
assert_exit "agents are tracked"       1 ci .codex-isolated/agents/chain-auditor.toml
assert_exit "user skills are tracked"   1 ci .codex-isolated/skills/context-awareness/SKILL.md
assert_exit "system skills are ignored" 0 ci .codex-isolated/skills/.system/x
assert_exit "loen plugin cache is tracked" 1 ci .codex-isolated/plugins/cache/ikeniborn/loen/0.2.0/x
assert_exit "superpowers plugin cache is tracked" 1 ci .codex-isolated/plugins/cache/openai-curated/superpowers/2f1a8948/x
assert_exit "github plugin cache is tracked" 1 ci .codex-isolated/plugins/cache/openai-curated-remote/github/0.1.8-2841cf9749ae/x
assert_exit "remote plugin install metadata is ignored" 0 ci .codex-isolated/plugins/cache/openai-curated-remote/github/.codex-remote-plugin-install.json
assert_exit "future openai remote plugin cache is ignored" 0 ci .codex-isolated/plugins/cache/openai-curated-remote/openai-developers/0.1.0/x
assert_exit "plugin staging is ignored" 0 ci .codex-isolated/plugins/.remote-plugin-install-staging/openai-developers/x
assert_exit "plugin catalog clone metadata is ignored" 0 ci .codex-isolated/plugins/catalogs/openai-curated/.git/index
assert_exit "binary stays ignored"      0 ci .codex-isolated/bin/codex

finish

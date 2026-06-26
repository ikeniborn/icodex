#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
cd "$ROOT"

ci() { git check-ignore --no-index -q "$1"; }   # 0 => ignored, 1 => tracked-eligible

assert_exit "example is tracked"        1 ci .codex-isolated/config.toml.example
assert_exit "live config is ignored"    0 ci .codex-isolated/config.toml
assert_exit "user skills are tracked"   1 ci .codex-isolated/skills/context-awareness/SKILL.md
assert_exit "system skills are ignored" 0 ci .codex-isolated/skills/.system/x
assert_exit "plugin cache is tracked"   1 ci .codex-isolated/plugins/cache/superpowers/superpowers/6.0.3/x
assert_exit "binary stays ignored"      0 ci .codex-isolated/bin/codex

finish

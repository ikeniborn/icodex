#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
base="$(cat "$ROOT/.codex-isolated/AGENTS.md")"
ledger="$(cat "$ROOT/.codex-isolated/skills/task-ledger/SKILL.md")"
context="$(cat "$ROOT/.codex-isolated/skills/context-awareness/SKILL.md")"
remote="$(cat "$ROOT/lib/iwiki/iwiki.sh")"
for body in "$base" "$ledger" "$context" "$remote"; do
  assert_contains 'reuse verified session binding' "$body" 'Reuse the verified binding'
  assert_contains 'reconnect invalidates reuse' "$body" 'reconnect'
done
assert_contains 'explanation exemption' "$base" 'Conversational explanations'
assert_contains 'batch preserves events' "$ledger" 'Batch material events'
assert_contains 'lint after write batch' "$base" 'Run `wiki_lint` after each completed write batch'
assert_eq 'startup lint removed' 0 "$(grep -cF '5. Run `wiki_lint`.' <<<"$base")"
assert_eq 'no LoEn recommendation' 0 "$(grep -cF 'Recommend **loen**' <<<"$base")"
assert_contains 'CAS retained' "$base" 'expected_revision'
assert_contains 'closure retained' "$ledger" 'empty spool'
assert_contains 'execution strategy explicit' "$base" 'Before implementation, state the execution strategy'
assert_contains 'direct delegation distinguished from SDD' "$base" 'does not prohibit separately authorized scoped delegation'
assert_contains 'chain full retains execution choice' "$base" 'preserve the checked-plan execution choice'
assert_contains 'revisions not cached' "$base" 'Never reuse cached page revisions'
finish

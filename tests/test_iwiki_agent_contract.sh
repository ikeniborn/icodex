#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

agents_body="$(cat "$ROOT/.codex-isolated/AGENTS.md")"
context_body="$(cat "$ROOT/.codex-isolated/skills/context-awareness/SKILL.md")"
context_template="$(cat "$ROOT/.codex-isolated/skills/context-awareness/templates/project-context.json")"
ledger_body="$(cat "$ROOT/.codex-isolated/skills/task-ledger/SKILL.md")"
chain_body="$(cat "$ROOT/.codex-isolated/skills/check-chain/SKILL.md")"

assert_contains "binding uses project TOML for every transport" "$agents_body" 'One binding protocol applies to local stdio and remote HTTP'
assert_contains "binding keeps complete project scope" "$agents_body" 'full normalized `read`, `write`, and `primary` scope'
assert_contains "rules include section insert" "$agents_body" '`wiki_insert_section`'
assert_contains "rules include section move" "$agents_body" '`wiki_move_section`'
assert_contains "rules include section delete" "$agents_body" '`wiki_delete_section`'
assert_contains "rules require PostgreSQL revision CAS" "$agents_body" '`expected_revision_required`'
assert_contains "rules include section hash CAS" "$agents_body" '`expected_section_hash`'
assert_contains "rules separate Git publication" "$agents_body" '`wiki_sync` is Git-only'
assert_contains "rules explain hosted domain creation" "$agents_body" '`wiki_create_domain` requires hosted creation authority'
assert_contains "rules explain PostgreSQL lint limits" "$agents_body" 'PostgreSQL lint does not compute orphan, stale-source, frontmatter, or tag-drift findings'
assert_contains "rules cover Python and TypeScript graph" "$agents_body" 'Python or TypeScript code-analysis'
assert_contains "rules use hosted graph reads" "$agents_body" 'published PostgreSQL snapshot'

assert_contains "context skill version updated" "$context_body" '# version: 1.7.1'
assert_contains "context reports graph availability" "$context_body" 'code_graph_available'
assert_contains "context reports graph domain" "$context_body" 'code_graph_domain'
assert_contains "context reports graph state" "$context_body" 'code_graph_state'
assert_contains "context checks graph read-only" "$context_body" '`wiki_code_status`'
assert_contains "context prefers graph search" "$context_body" '`wiki_code_search` / `wiki_code_context`'
assert_contains "context covers TypeScript" "$context_body" 'Python or TypeScript'
assert_contains "context template uses wiki domain" "$context_template" '"wiki_domain"'
assert_contains "context template reports graph availability" "$context_template" '"code_graph_available"'
assert_contains "context template reports graph domain" "$context_template" '"code_graph_domain"'
assert_contains "context template reports graph state" "$context_template" '"code_graph_state"'
assert_contains "context template reports task page" "$context_template" '"task_page_slug"'

assert_contains "ledger reads revision before mutation" "$ledger_body" 'Read the current page revision before every PostgreSQL page mutation'
assert_contains "ledger passes expected revision" "$ledger_body" '`expected_revision`'
assert_contains "ledger handles revision conflict" "$ledger_body" '`conflict`'
assert_contains "ledger handles section conflict" "$ledger_body" '`section_conflict`'
assert_contains "ledger records history successor" "$ledger_body" 'exactly `## Events` and `## Next`'
assert_contains "ledger understands PostgreSQL lint limits" "$ledger_body" 'PostgreSQL lint does not compute orphan or stale-source findings'

assert_contains "check-chain uses PostgreSQL CAS" "$chain_body" 'read the current page revision immediately before each task-page or documentation mutation'
assert_contains "check-chain permits section mutation tools" "$chain_body" 'relevant page or section mutation tool'
assert_contains "check-chain passes expected revision" "$chain_body" 'pass it as `expected_revision`'
assert_contains "check-chain retries only after reread" "$chain_body" 're-read after `conflict` or `section_conflict`'

finish

#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

agents_body="$(cat "$ROOT/.codex-isolated/AGENTS.md")"
flat_agents_body="$(tr '\n' ' ' < "$ROOT/.codex-isolated/AGENTS.md" | sed 's/[[:space:]][[:space:]]*/ /g')"
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
assert_contains "rules define GWT workflow" "$agents_body" '## GWT Specification Workflow'
assert_contains "GWT applies to observable behavior" "$flat_agents_body" 'new observable domain behavior, a public contract, a bug reproduction, or a business invariant'
assert_contains "GWT excludes non-behavior edits" "$flat_agents_body" 'formatting, ordinary Wiki maintenance, or mechanical refactoring with unchanged behavior'
assert_contains "GWT uses exact semantic tools" "$flat_agents_body" '`wiki_spec_search`, `wiki_spec_context`, and `wiki_spec_resolve`'
assert_contains "GWT reads context before edits" "$flat_agents_body" 'Call `wiki_spec_context` before changing an existing scenario'
assert_contains "GWT preserves scenario identity" "$flat_agents_body" 'Preserve its scenario ID while the observable contract is unchanged'
assert_contains "GWT keeps artifacts coherent" "$flat_agents_body" 'scenario, executable test, `implements` and `verifies` bindings, and verification evidence as one coherent unit'
assert_contains "GWT records executable evidence" "$flat_agents_body" 'focused and relevant regression tests and record command, exit status, and repository revision in the task ledger'
assert_contains "GWT resolves ready graphs" "$flat_agents_body" 'call `wiki_spec_resolve` after code or test changes'
assert_contains "GWT graph fallback is fail soft" "$flat_agents_body" 'preserve declared selectors, use repository search, run executable tests, and record `graph_unavailable`'
assert_contains "GWT uses bounded TOML grammar" "$flat_agents_body" 'closed `iwiki-gwt` TOML fence'
assert_contains "GWT requires all phases" "$flat_agents_body" '`given`, `when`, `then`, and `code`'
assert_contains "GWT requires implementation bindings" "$flat_agents_body" 'at least one `implements` and one `verifies` binding'
assert_contains "GWT hosted bind forwards project mode" "$flat_agents_body" 'pass `[specifications].mode` as `specification_mode` to hosted HTTP `wiki_bind`'
assert_contains "GWT local bind omits project mode" "$flat_agents_body" 'omit `specification_mode` for local stdio'
assert_contains "GWT mode mismatch fails closed" "$flat_agents_body" 'retain task lifecycle `completion-pending`'
assert_contains "GWT strict uses exact blocking findings" "$flat_agents_body" '`missing_scenario`, `invalid_scenario`, `duplicate_scenario_id`, or `incomplete_bindings`'
assert_contains "GWT strict scope is page local" "$flat_agents_body" 'only a future mutation of the reported explicit specification page'
assert_contains "GWT resolution stays advisory" "$flat_agents_body" 'Projection and resolution findings remain advisory'
assert_contains "GWT hook avoids guessing existing scenarios" "$flat_agents_body" 'Hooks never infer that an uncontextualized fence is an existing scenario'
assert_contains "GWT hook enforces contextual identity" "$flat_agents_body" 'enforce matching domain and scenario ID after `wiki_spec_context`'
assert_contains "GWT hooks never write Wiki" "$flat_agents_body" 'never write to Wiki or replace interactive MCP calls'

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

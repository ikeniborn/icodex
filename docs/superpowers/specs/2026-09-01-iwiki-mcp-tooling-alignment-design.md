---
chain:
  intent: docs/superpowers/intents/2026-09-01-iwiki-mcp-tooling-alignment-intent.md
review:
  spec_hash: ff7ce9bc2c7afc90
  last_run: 2026-09-01
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    clarity: { status: passed }
    consistency: { status: passed }
  findings: []
---

# iwiki-mcp Tooling Alignment Design

**Date:** 2026-09-01
**Status:** draft
**Intent:** `docs/superpowers/intents/2026-09-01-iwiki-mcp-tooling-alignment-intent.md`

## Acceptance (from intent)

### Desired Outcomes

- Agents select the current iwiki tool for Markdown read/write, specification,
  task-ledger, code-graph, binding, publication, discovery, and management intents.
- Agent-facing guidance uses current parameters and preserves the distinctions between
  local stdio and hosted HTTP, and between Git and PostgreSQL storage.
- Full project binding, PostgreSQL compare-and-swap, specification-mode, authorization,
  and fail-closed task lifecycle guarantees remain explicit and correct.
- Deprecated tools, parameters, assumptions, and routes are removed or marked as
  unsupported; hooks and focused tests reject mechanically detectable regressions.

### Done When

- Every affected icodex agent surface matches the live iwiki-mcp contract; deprecated
  calls and assumptions are absent; focused and full validations pass; icodex Wiki/task
  documentation is current; and `wiki_lint` has no new blocking finding.

## Scope

This design aligns only icodex agent-facing assets with the live 35-tool iwiki-mcp
registry and observed hosted behavior. It updates existing instructions, skills,
generated remote-scope text, the GWT ordering hook, focused tests, and the local modes
documentation. The live callable schemas and successful server responses remain the
authority; repository prose is a checked consumer of that contract.

The design does not modify iwiki-mcp, `.iwiki.toml`, `.codex-lockfile.json`, hosted
grants, production services, or external project repositories. It creates neither a
second machine-readable tool catalog nor a universal hook for every iwiki call. It does
not invoke grant mutations, create domains, publish snapshots, or use legacy plugin or
CLI routes.

## Requirements

### R1. Live Contract Authority

Agent guidance MUST treat the tools exposed by the active MCP session, their callable
schemas, and observed successful/error responses as the current contract. Documentation
from iwiki-mcp MAY explain semantics, but a stale tool count or stale schema statement
MUST NOT override the live registry.

Guidance MUST organize the 35 tools by intent rather than require an agent to memorize a
version-pinned flat list. It MUST state that a tool absent from the client despite being
served can indicate client-side schema rejection and MUST be diagnosed by comparing the
served schema with the client-exposed registry after an upgrade.

Acceptance:

- Focused tests assert the current contract categories and the schema-sensitive
  `wiki_update_page` forms without introducing a duplicated catalog file.
- No instruction claims that the live registry has 32 tools or that code-selector
  updates require a different mutation tool.

### R2. Binding and Hosted Provenance

Every workflow MUST load the full normalized project `read`, `write`, and `primary`
scope before the first Wiki call. Hosted HTTP MUST also carry project
`specification_mode` when the callable `wiki_bind` schema accepts it. Local stdio MUST
omit that client override. Neither path may narrow the scope to the project basename or
rebind to one inferred domain.

Hosted `wiki_bind` MUST be followed by `wiki_status`. A hosted answer is usable only
when `binding_source == "session"`, the requested primary was not substituted, and the
effective specification mode is compatible with the project request under documented
hosted precedence. `token_default`, `binding_defaulted`, `primary_substituted`,
`binding_not_selected`, a rejected bind, or an unexpected session identity MUST cause a
full rebind and repeat of the affected read; unresolved mismatch MUST stop mutations and
retain task lifecycle `completion-pending`.

Acceptance:

- Base rules, generated remote-scope text, `context-awareness`, `fix-intent`, and
  `task-ledger` use the same full-scope protocol.
- Focused tests reject the former `wiki_status`-then-single-domain rebind sequence.
- Hosted provenance fields and recovery actions are stated next to hosted binding and
  domain-free code reads.

### R3. Intent-Based Tool Routing

Instructions MUST route current tools as follows:

- Base discovery and reading: `wiki_status`, `wiki_list_domains`, `wiki_list_pages`,
  `wiki_read_page`, `wiki_search`, and `wiki_related`.
- Markdown authoring: `wiki_write_page`, `wiki_update_page`,
  `wiki_insert_section`, `wiki_move_section`, `wiki_delete_section`, and
  `wiki_delete_page`.
- Explicit rebuild and Git maintenance: `wiki_index`; plus `wiki_sync`, OKF tools, and
  `wiki_remediation_plan` only where their Git storage preconditions hold.
- Specifications: `wiki_spec_search`, `wiki_spec_context`, and `wiki_spec_resolve` only
  when the effective mode permits them.
- Code graph: status, search, context, local index, and hosted publication tools under
  their separate freshness, checkout, transport, write-scope, and server-limit rules.
- Hosted authority: `wiki_create_domain` and domain-grant tools only under their
  advertised creation or management authority.

Explicit `wiki_search(domains=...)` MUST win over scope defaults. `scope="all"` MUST be
used only for an explicit whole-base search; normal project work MUST use the bound read
scope or explicit authorized domains. `read=["all"]` MUST be documented as a literal
domain name, not a wildcard. `wiki_related` MUST consume a real section identifier from
Wiki retrieval rather than a guessed page slug.

Read-only discovery does not authorize state changes. `wiki_list_domain_grants` MUST be
limited to an explicit hosted management task. `wiki_set_domain_grant` and
`wiki_revoke_domain_grant` MUST require separate explicit user authorization and hosted
management authority; grant expansion remains human-only under the approved intent.

Acceptance:

- Base rules and mode documentation name every tool category and its preconditions.
- Tests cover discovery, whole-base search semantics, literal `all`, and management
  authority boundaries.
- No hook or skill invokes a hosted authority tool automatically.

### R4. Page and Selector Mutation Contract

`wiki_update_page` MUST be documented in its three live forms:

- Section-only: paired `heading` and `new_body`.
- Selector-only: `code`, preserving body bytes; it MUST NOT include `source`,
  `description`, `status`, `new_heading`, or `expected_section_hash`.
- Combined: paired section fields plus `code` in one atomic mutation.

On PostgreSQL every page update or delete and every section mutation MUST use the
current page `revision` as `expected_revision`. A heading-scoped operation SHOULD also
use the current `section_hash` as `expected_section_hash`. A conflict MUST trigger one
re-read and bounded merge attempt; a second conflict MUST leave the task
`completion-pending`. Git keeps its no-revision contract and automatic write indexing.

Acceptance:

- Agent-contract tests assert all three update forms and code-only exclusions.
- Existing CAS, section-CAS, one-retry, and storage-specific publication rules remain
  covered.

### R5. Code-Graph Availability and Language Coverage

Code-graph guidance MUST recognize `python`, `typescript`, `javascript`, and `bash`.
Bash MUST remain opt-in and limited to `.sh` files; its entity prefix is `sh:`.
JavaScript and TypeScript MUST remain distinct supported identities.

`context-awareness` MUST expose `code_graph_fresh` and
`code_graph_binding_source` alongside graph state and domain. Graph-assisted repository
analysis is available only when `state == "ready"` and `fresh == true`; hosted reads
also require `binding_source == "session"`. A defaulted warning, stale/missing/failed
snapshot, unavailable source, or unconfigured graph MUST fall back to repository search
without blocking ordinary Wiki work.

Local indexing requires a server with the repository checkout. Hosted HTTP reads a
published PostgreSQL snapshot and cannot run `wiki_code_index`. Hosted publication MUST
use a writable primary, start with `wiki_code_publish_begin`, respect every advertised
row/byte limit, and never add `domain` or `iwiki_id` client arguments.

Acceptance:

- The context skill and JSON template expose state, freshness, domain, and provenance.
- Availability tests require both ready state and freshness, plus session provenance on
  hosted transport.
- Mode documentation names all four languages and preserves hosted publication limits.

### R6. Effective Specification Mode in the GWT Hook

The GWT hook MUST derive effective per-domain specification modes from a successful
`wiki_status` response, never solely from project `.iwiki.toml`. The post-status hook
MUST record only recognized `disabled`, `optional`, or `strict` modes for the current
Codex session. Hosted status evidence is valid only with `binding_source == "session"`
and no primary substitution. Evidence MUST expire no later than the hosted 1800-second
idle binding lifetime and MUST remain isolated by session and domain.

Before a `wiki_update_page` containing an `iwiki-gwt` fence:

- Missing, expired, malformed, or untrusted status evidence MUST block the mutation and
  instruct the parent to bind and call `wiki_status`.
- Effective `disabled` mode MUST treat the fence as ordinary Markdown and allow the
  mutation without semantic context.
- Effective `optional` or `strict` mode MUST preserve current context-before-mutation
  behavior: unclassified scenario IDs receive a non-blocking context nudge, while a
  known domain context with missing or mismatched scenario IDs blocks the mutation.
- Successful scenario mutation MUST consume matching context evidence.

Ordinary updates without an `iwiki-gwt` fence MUST remain unaffected. The hook MUST
never call MCP or mutate Wiki content. Hook wiring MUST observe post-use `wiki_status`
and retain existing `wiki_spec_context` and `wiki_update_page` events.

Acceptance:

- Hook tests cover absent, expired, malformed, local-stdio, hosted-session,
  token-default, substituted-primary, disabled, optional, strict, ordinary-update,
  matching-context, and mismatched-context cases.
- Hook state never crosses Codex session or domain boundaries.
- Existing ordinary Wiki and GWT ordering tests remain green.

### R7. Skill and Generated-Instruction Consistency

`context-awareness`, `fix-intent`, and `task-ledger` MUST consume the binding,
provenance, specification-mode, and graph-availability contracts defined above.
`fix-intent` MUST remove the fallback sequence that calls `wiki_status` before a narrow
single-domain bind. `task-ledger` MUST fail closed for hosted binding mismatch while
preserving its parent-only write, spool, redaction, CAS, and closure rules.

The generated remote-scope block MUST include hosted provenance recovery and remain
idempotent and secret-free. Local stdio launch MUST continue removing that remote-only
block. No change may alter the active project `.iwiki.toml` or copy credentials into
generated instructions.

Acceptance:

- Contract tests assert equivalent language across base rules and affected skills.
- Remote-scope tests assert provenance, recovery, idempotence, token redaction, and
  local removal.
- Repository search finds no active instruction that narrows the project binding or
  trusts hosted code results without freshness and session provenance.

### R8. Verification and Documentation Closure

Implementation MUST begin from failing focused assertions for the demonstrated gaps,
then make the smallest changes that satisfy the approved contract. It MUST run focused
agent-contract, remote-scope, GWT-hook, and wiring tests before the complete Bash suite.
Python hook syntax and JSON wiring MUST be checked explicitly.

The icodex `iwiki-mcp-integration` page MUST be updated through PostgreSQL
compare-and-swap to describe the final agent contract. The task page and history MUST
contain verification evidence. `wiki_lint(domain="icodex")` MUST report no new blocking
finding before result closure.

Acceptance:

- Focused tests and every `tests/test_*.sh` script exit zero.
- `python3 -m py_compile` succeeds for the changed hook and hook JSON parses.
- Repository diff contains only approved icodex scope plus chain artifacts.
- Wiki documentation, task evidence, and lint agree with the verified repository state.

## Architecture

### Contract Layers

The live MCP registry is the external authority. `.codex-isolated/AGENTS.md` is the
central human-readable operation contract. A small set of existing skills projects the
parts needed at task start, intent capture, and durable task lifecycle. The generated
remote-scope block adds hosted-only preflight rules to each project home. Focused tests
bind these repeated projections to the same required phrases and behaviors.

No new catalog is introduced because it would become a second schema source. No
universal Wiki hook is introduced because binding, authorization, and mutation intent
remain interactive parent decisions. The only mechanical enforcement change stays in
the existing GWT hook, whose current local-config mode inference is unsafe under hosted
overrides.

### GWT Status Evidence

`gwt-gate.py` keeps scenario-context evidence and effective-status evidence as local
hook state under `$CODEX_HOME/state`. Status evidence stores the Codex session, domain,
recognized mode, transport/provenance trust result, and timestamp. Separate state
records keep the existing scenario-context format compatible and make status expiry
independent.

Post-use `wiki_status` parses both successful direct mappings and JSON content wrapped
in a normal MCP tool response. It replaces the current session's mode map atomically
only after validating the complete relevant response. Hosted token-default or
substituted-primary responses record no trusted evidence. Pre-update checks consult the
target domain only when an `iwiki-gwt` fence is present.

### Agent Data Flow

1. Parent loads and normalizes the complete project binding and optional project
   specification mode.
2. Parent calls `wiki_bind`, then `wiki_status`; hosted provenance must confirm the
   current session.
3. The status post-hook caches effective modes for GWT enforcement.
4. Phase 0 records Wiki, task, and graph state. Graph availability applies the ready,
   fresh, and hosted-session gates.
5. Parent selects a Markdown, specification, code-graph, discovery, publication, or
   authority tool from the requested intent and live preconditions.
6. Page mutations apply storage-specific CAS and indexing rules. GWT mutations add
   effective-mode and semantic-context gates.
7. Focused and full tests, Wiki documentation CAS, task evidence, and lint close the
   workflow.

## Components and Changes

- `.codex-isolated/AGENTS.md`: current tool routing, hosted provenance, search scope,
  selector updates, four graph languages, and explicit authority boundaries.
- `.codex-isolated/skills/context-awareness/SKILL.md` and its JSON template: full bind
  protocol, effective specification state, graph freshness, and hosted provenance.
- `.codex-isolated/skills/fix-intent/SKILL.md`: remove status-before-bind and inferred
  single-domain fallback behavior.
- `.codex-isolated/skills/task-ledger/SKILL.md`: hosted provenance fail-closed rule
  without changing durable event ownership or spool semantics.
- `.codex-isolated/hooks/gwt-gate.py` and `.codex-isolated/hooks.json`: status evidence,
  domain/mode enforcement, and post-status matcher wiring.
- `lib/iwiki/iwiki.sh`: generate the same hosted provenance and recovery rules and wire
  the updated hook matchers idempotently.
- `docs/iwiki-mcp-modes.md`: supported languages, live routing, provenance, search,
  selector, and authority semantics.
- Focused shell tests: executable assertions for every changed instruction projection,
  generated region, and hook state transition.
- `icodex:iwiki-mcp-integration`: final behavior documentation after implementation.

## Failure Boundaries

- Missing or rejected project binding: no Wiki mutation; task remains
  `completion-pending`.
- Hosted default/substituted binding: rebind and repeat; unresolved provenance blocks
  mutation and hosted graph use.
- Missing GWT status evidence: block only the GWT-bearing update and request status;
  ordinary Markdown stays available.
- Disabled specification mode: semantic tools are unavailable; ordinary Markdown,
  including a fence treated as text, remains available.
- Graph unavailable or stale: preserve selectors, use repository search and executable
  tests, and continue ordinary Wiki work.
- PostgreSQL conflict: re-read and retry once; a second conflict blocks completion.
- Unsupported storage or transport: do not route around the server error with another
  mode; choose only a contract-supported tool path.
- Missing hosted management authority or explicit user authorization: do not invoke
  domain creation or grant mutation.

## Testing Strategy

The implementation starts by adding focused failing assertions for the nine observed
contract gaps. Agent contract tests validate tool intent groups and consistent language
across instructions and skills. Remote-scope tests generate project instructions twice,
prove idempotence and secret exclusion, and validate provenance recovery text. GWT tests
drive hook events through status capture, expiry, mode branches, context matching, and
ordinary updates. Wiring tests prove the generated matcher set remains stable.

After focused tests pass, verification runs Python syntax for `gwt-gate.py`, JSON parse
for hook configuration, repository stale-pattern searches, and the complete sequential
`tests/test_*.sh` suite. Final evidence records command names, exit codes, and repository
revision without raw output or credentials.

## Risks and Mitigations

- **Instruction drift across projections:** focused phrase and behavior tests cover the
  base rules, skills, generated block, and documentation together.
- **Hook trusts stale server state:** evidence is session/domain scoped and expires no
  later than the hosted binding lifetime.
- **Hook blocks ordinary Wiki work:** the status gate runs only when `new_body` contains
  an `iwiki-gwt` fence.
- **Hosted fallback appears healthy:** graph availability and status trust require
  explicit session provenance and reject default/substituted answers.
- **Tool catalog drifts again:** no static replacement catalog is created; live schema
  remains authoritative and upgrade diagnostics compare served and exposed tools.
- **Management guidance broadens authority:** read-only discovery is separate from
  creation and grant mutation; explicit authorization and server authority remain
  mandatory.

## Human Checkpoints

- Removing a supported workflow, changing the public agent contract beyond this design,
  or weakening a hook requires proposal-first approval.
- Domain creation, grant mutation, production service changes, secret access, and grant
  expansion are outside implementation authority.
- Any live-schema/server-behavior contradiction halts implementation until the user or
  iwiki-mcp owner resolves it.

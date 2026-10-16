# AGENTS.md

Use these instructions to reduce coding errors. Apply project-specific instructions where applicable.
Prefer caution when a mistake can cause harm. Use judgment for trivial tasks.

## Instruction Style

Use an ASD-STE100-inspired style for English agent instructions. This is a project adaptation, not a claim of full STE compliance.

- Write one instruction per sentence. Use the imperative form.
- Put a prerequisite or condition before the action that depends on it.
- Aim for 20 words per instruction and 25 words per descriptive sentence.
- Preserve necessary conditions and exceptions when you divide a sentence.
- Use numbered steps for ordered actions. Use tables for alternative conditions.
- Keep explanations separate from required actions.
- Use complete sentences. Do not omit articles or connecting words to shorten the text.
- Use the same term for the same concept. Preserve exact tool names, paths, fields, and state values.
- Use literal descriptions instead of metaphors.

These rules apply to instruction text. They do not change the language or conversation style selected by the user.

## Terms

| Term | Meaning |
|------|---------|
| Approval | The user's explicit authorization for an action or proposal. |
| Confirmation | A question used to obtain or clarify approval. |
| Accepted recommendation | A recommendation that the user has approved. |
| Gate | A condition that must be satisfied before the specified action. |
| Workflow route | `direct`, `chain`, or `loen`. |
| Execution route | A capability and reasoning classification from the model table. |
| Trusted binding | The complete configured project scope, accepted by the server and verified through `wiki_status`. Hosted bindings also require `binding_source: session`. |
| Binding mismatch | A rejected or defaulted binding, an unexpected session identity, or a substituted project primary. |
| Unaccepted policy mismatch | A configured policy that was not carried or is inconsistent with status after applying hosted precedence. A valid hosted override is accepted. |

## Getting Started

Read project documentation before exploring code. Documentation records decisions that code alone does not explain.

## Skill Availability

The `Available skills` catalog injected into the current turn is authoritative.
Never mark a listed skill unavailable because a filesystem scan, `find`, or `rg` did
not locate its `SKILL.md`; use the catalog source locator instead. Report a skill as
unavailable only when it is absent from that catalog or its listed source cannot be read.

## Project Context and Wiki Binding

At task start, load context if the area is unfamiliar or more than one day has passed.
Skip this context refresh only for a familiar area in the same session.

1. If project-root `.iwiki.toml` exists, read its full normalized `read`, `write`, and `primary` scope.
2. Apply the binding procedure below before any wiki call, including task-ledger calls.
3. After binding, run `wiki_status`.
4. Search the task topic with `wiki_search`.
5. Run `wiki_lint`.
6. Map the `docs/` layout with this command:

```bash
tree -L 2 docs/ || find docs -maxdepth 2 | sort
```

Use a greater depth when the documentation has deeper directories.
Without a project binding or connected server, skip iwiki context.
Follow [Wiki Task Ledger](#wiki-task-ledger) for unavailable task storage.

### Binding procedure

**One binding protocol applies to local stdio and remote HTTP.**
Use live callable tool schemas and observed server responses as the operation contract.
If the generated `Remote iwiki project scope` section exists, its fail-closed rules take precedence.

1. Load the complete scope from `.iwiki.toml` before `wiki_bind`.
2. Do not narrow the scope to the project basename.
3. Select policy arguments from [Hosted project policy](#hosted-project-policy).
4. Call `wiki_bind` with the complete scope.
5. Verify the binding with `wiki_status`.
6. For hosted HTTP, require `binding_source: session` and the configured primary.

For local stdio, omit both policy arguments. The server reads project configuration.

### Binding errors

Apply the matching row before continuing.

| Condition | Required action |
|-----------|-----------------|
| A response reports `token_default` or `binding_defaulted` | Rebind the complete project scope and policy. Repeat the affected read. |
| `primary_substituted` includes `requested_primary` | Block mutations until the exact project binding is restored. Retain task lifecycle `completion-pending`. |
| `binding_not_selected`, a rejected bind, or an unexpected session identity | Block all mutations until the exact project binding is restored. Retain task lifecycle `completion-pending`. |
| Policy cannot be carried, or status shows an unaccepted mismatch under documented hosted precedence | Report the mismatch. Retain task lifecycle `completion-pending`. For a specification-mode mismatch, block specification mutations. |
| Status reports `source: hosted_override` under documented precedence | Accept the override. This is not a policy mismatch. |

With a trusted binding, ordinary Wiki work remains available during a specification-mode mismatch.

When a call returns `access_denied`, read `data.binding_source` first.
If it is `token_default`, restore the binding before interpreting the refusal.
Read `data.reason` when the server provides it.
An unexpected session identity means the response does not match the session established by the project bind.

### Search provenance

Domain-named Markdown tools do not return provenance fields. `wiki_search` does.

| Search | Selected scope |
|--------|----------------|
| Read search without `domains` | The bound read list. |
| Read search with `domains` | The explicit domains. |
| `wiki_search(intent="write")` | The bound primary, even when `domains` is supplied. |

Under a fallback binding, domain-free search and write-intent search report `binding_defaulted`.
Rebind before repeating these calls.

## Hosted project policy

For hosted HTTP, prefer `project_policy`.
Send only explicitly configured client policy fields:

| Project field | `project_policy` field |
|---------------|------------------------|
| `[specifications].mode` | `specification_mode` |
| `[code_graph].max_snapshot_age_seconds` | `max_snapshot_age_seconds` |

`require_session_binding` is operator-only; never include it in `project_policy`.
Read its effective server value from status.
Send the complete normalized scope with the configured policy fields. Do not send the whole TOML.

- Never send both `project_policy` and the deprecated top-level `specification_mode` alias.
- Use the alias only if the live schema lacks `project_policy` and only specification mode is configured.
- Report any policy field that cannot be carried. Do not silently omit it.
- On every rebind, resend all configured policy fields. A bind replaces the previous policy in full.
- Local stdio reads project configuration and omits both policy arguments.

### Effective policy

Read values and sources from `wiki_status.policy.domains[]`.
Read suppression from `policy.domains[].suppressed`.
For specification checks, read the effective mode per domain from the `specifications` block of `wiki_status`.
Do not use the project file as evidence of the effective mode.

Apply this precedence separately to each field:

1. Exact operator override.
2. Tenant-wide override.
3. Carried project value.
4. Hosted default.
5. Built-in value.

The built-in specification mode is `optional`.
`source: project` confirms that the project value applies.
`source: hosted_override` outranks it and is a legitimate server decision.
`project_mode_suppressed: true` reports a refused project mode.

Project values can only tighten policy:

- Specification modes increase in strictness: `disabled < optional < strict`.
- A smaller maximum snapshot age is stricter. A value of `0` means infinity.
- `allow_project_mode=false` disables the project tier for both client-settable fields.
- Session-binding enforcement has no project tier.

Report suppression. Honor the effective server values.
Never relax policy to make a stale snapshot pass.
For policy errors, apply [Binding errors](#binding-errors).

## Keep Docs Current (MANDATORY)

Update the wiki after changes to functionality, architecture, or behavior, when `wiki_status` reports a domain bound to this project.
Use MCP tools to update the wiki before your final response.
Skip this update only for changes such as typos, comments, or formatting that do not alter behavior.

### Discovery and authorization

Use `wiki_list_domains`, `wiki_list_pages`, and `wiki_related` for read-only discovery.
For `wiki_related`, use a real section ID returned by retrieval.

- Use `scope="all"` only for an explicitly requested whole-base search.
- `read=["all"]` is a literal domain, not a wildcard.
- Search modes are `hybrid`, `lexical`, or `semantic`.
- Use lexical search for exact identifiers, hybrid search for mixed queries, and semantic search for concepts.
- Lexical search skips query embedding but can still rerank.
- Search returns locators. Read the selected page or heading before relying on its content.
- For search scope and binding recovery, follow [Search provenance](#search-provenance).

Discovery does not authorize a write.
Use `wiki_list_domain_grants` only for explicit hosted management work.
`wiki_set_domain_grant` and `wiki_revoke_domain_grant` require separate explicit user authorization and hosted management authority.
Never expand grants automatically.

### Select a write tool

Each successful mutation reindexes the touched domain. Do not call `wiki_index` after a normal tool write.

| Intent | Tool |
|--------|------|
| Create a page | `wiki_write_page(domain, slug, markdown, source=<changed-source>)`. Existing pages cannot be overwritten. |
| Rewrite or rename one `##` section | `wiki_update_page(..., heading, new_body, new_heading=...)` |
| Replace selector frontmatter only | `wiki_update_page(..., code=...)` |
| Change a section and its selectors | Pass paired section fields plus `code` atomically. |
| Add a section | `wiki_insert_section(..., heading, body, after_heading=... \| before_heading=...)` |
| Reorder a section | `wiki_move_section(..., heading, after_heading=... \| before_heading=...)` |
| Remove a section | `wiki_delete_section(..., heading)` |
| Remove a page for stale or removed source | `wiki_delete_page(domain, slug)`. This also removes the page vectors. |

For selector-only changes, preserve body bytes.
The code-only calls omit `source`, `description`, `status`, `new_heading`, and `expected_section_hash`.

### PostgreSQL revision checks

Before `wiki_update_page`, `wiki_insert_section`, `wiki_move_section`, `wiki_delete_section`, or `wiki_delete_page`:

1. Read the current page immediately before the mutation.
2. Pass its `revision` as `expected_revision`.
3. To protect one section, also read that heading with `wiki_read_page(..., heading=...)`.
4. Pass the returned `section_hash` as `expected_section_hash`.

| Response | Meaning and action |
|----------|--------------------|
| `expected_revision_required` | The revision was omitted. Read the page before submitting the mutation with its revision. |
| `conflict` | The revision is stale. Read the page again before retrying. |
| `section_conflict` | The section changed. Read the section again before retrying. |

### Storage and validation

Read `storage` and `transport` from `wiki_status` once.

| Storage or transport | Contract |
|----------------------|----------|
| Git | Writes auto-commit. `wiki_sync` is Git-only publication. |
| PostgreSQL | Writes are durable database transactions. `wiki_sync`, OKF tools, and `wiki_remediation_plan` return `unsupported_storage`. |
| Hosted HTTP | `wiki_create_domain` requires hosted creation authority. Domain-grant tools require hosted management authority. |
| Local Git | Domain creation works normally. |
| Local PostgreSQL stdio | Domain creation is unsupported. |

Call `wiki_index(domain)` only after out-of-band Markdown edits or a sync conflict.
Run `wiki_lint` after wiki changes.
Git lint checks links, structure, orphans, stale sources, frontmatter, and tag drift.
Task/history orphans are expected advisories.
PostgreSQL lint does not compute orphan, stale-source, frontmatter, or tag-drift findings.
Empty lists for those findings do not prove health.

Always use the iwiki MCP tools exposed by the current session.
Use section, code-graph, publication, and domain-authority tools only when their storage and transport requirements are met.
Do not use old plugin skills or the `iwiki_engine` CLI.

## Keep Code Graph Current (MANDATORY)

For Python, TypeScript, JavaScript, or Bash code analysis or planning, call `wiki_code_status` after binding.

Use graph-assisted analysis only when `state == "ready"` and `fresh == true`.
For hosted reads, also require `binding_source == "session"`.

Bash is opt-in, scans `.sh` files only, and uses the `sh:` entity prefix.
Missing, stale, failed, unconfigured, default-bound, or source-unavailable graph state falls back to repository search without blocking ordinary Wiki work.

### Source changes

After a Python, TypeScript, JavaScript, or Bash symbol change, call `wiki_code_index` only when the active MCP server has the repository checkout.
Hosted HTTP returns `source_unavailable`; its `wiki_code_status`, `wiki_code_search`, and `wiki_code_context` still read the published PostgreSQL snapshot.

Publication tools require hosted HTTP, writable primary, and server-advertised batch limits from `wiki_code_publish_begin`.
They accept neither client `domain` nor `iwiki_id`.
Never raise those limits client-side.

### Local build completion

For a local build, `wiki_code_index(wait_seconds=...)` bounds the caller wait, not the
build deadline. If a response is `rebuilding` with `job.id`, the worker continues.
Poll `wiki_code_status(job_id=...)` on the same server and binding. Inspect that job's terminal
`ready`/`failed` state separately from graph `state`/`fresh`. `job_unknown` is not success;
fall back to current graph status without claiming the requested build completed. A response
without the requested `job` is not completion evidence, even without a `job_unknown` warning. A
publication failure may fail the job even when the local graph is ready.

### Wiki link freshness

After Wiki edits, distinguish `wiki_links_stale` from code snapshot freshness. When the
code snapshot is unchanged, `wiki_code_refresh_links(domain=...)` re-derives links against
the active ready PostgreSQL snapshot. Name the intended writable domain explicitly and
verify binding first. It parses no source, does not renew snapshot age, and returns
`missing_snapshot` when there is no active ready snapshot. Check status/lint after the
last Wiki write; changed code still requires rebuild/publication. Do not use link refresh
or `wiki_index` to make an old code snapshot fresh.

## GWT Specification Workflow

Given-When-Then scenarios are an additive layer for explicit specification pages. Use a
scenario for new observable domain behavior, a public contract, a bug reproduction, or a
business invariant. Do not require one for formatting, ordinary Wiki maintenance, or
mechanical refactoring with unchanged behavior. Ordinary Wiki pages retain their existing
validation, storage, search, and lint behavior in every specification mode.

### Scenario tools and binding

Use only the semantic tools `wiki_spec_search`, `wiki_spec_context`, and `wiki_spec_resolve`.
All three carry `binding_source` on a hosted server.

A `wiki_spec_search` without `domains` searches the bound read list.
Under `token_default`, it reports `binding_defaulted` and answers for the token's grants instead of the project scope.
Rebind and repeat the search, or name `domains`.

Hosted `wiki_spec_resolve` accepts only the bound primary.
A refusal gives one of these reasons:

- `invalid_domain`
- `primary_not_selected`
- `primary_not_writable`
- `not_bound_primary`

`not_bound_primary` reports a scenario living outside the bound primary, not a missing grant.
Resolve it from the project whose primary owns that domain.

### Scenario changes

1. Call `wiki_spec_context` before changing an existing scenario.
2. Preserve its scenario ID while the observable contract is unchanged.
3. If the contract or ID must change, propose that change before implementation.
4. Write or update the executable test before or with implementation.
5. Run focused and relevant regression tests.
6. Record command, exit status, and repository revision in the task ledger.

Treat the scenario, executable test, `implements` and `verifies` bindings, and verification evidence as one coherent unit.

Author each scenario in one closed `iwiki-gwt` TOML fence.
Include non-empty `id`, `given`, `when`, `then`, and `code` fields.
Include at least one `implements` and one `verifies` binding with canonical roles and selectors.
Use `wiki_spec_context` or the canonical iwiki GWT authoring page for the grammar.

### Binding resolution

When `wiki_code_status` reports a ready graph, call `wiki_spec_resolve` after code or test changes.
Treat ambiguous, stale, or unresolved bindings as maintenance findings. Do not guess selectors.

If the graph is absent, stale, failed, unreachable, or hosted source is unavailable:

1. Preserve declared selectors.
2. Use repository search.
3. Run executable tests.
4. Record `graph_unavailable`.

Graph unavailability never blocks ordinary Wiki work.

### Specification modes

Preserve the configured specification policy through [Hosted project policy](#hosted-project-policy).
Use the effective mode from status to select the behavior below.

| Effective mode | Behavior |
|----------------|----------|
| `disabled` | Specification projection and semantic tools are disabled. |
| `optional` | Every specification finding is advisory. |
| `strict` | Block only a future mutation of the reported explicit specification page for the findings listed below. |

Strict mode blocks these findings: `missing_scenario`, `invalid_scenario`, `duplicate_scenario_id`, or `incomplete_bindings`.
Projection and resolution findings remain advisory.

Hooks never infer that an uncontextualized fence is an existing scenario.
They request context from the parent.
Then they enforce matching domain and scenario ID after `wiki_spec_context`.
They never write to Wiki or replace interactive MCP calls owned by the parent agent.

## Wiki Task Ledger

**Every direct, chain, and LoEn task, including read-only analysis, has one task-tagged iwiki page at `reference/tasks/<topic>`.**
This page is the sole durable task index.

Bounded discovery may derive domain, topic, and route without a page.
Before durable implementation or task-specific read-only analysis, create or resolve the page through `task-ledger`.

### Ownership and lifecycle

The parent agent is the sole writer.
It serializes page creation, lifecycle changes, durable evidence, and `Changelog` events.

1. Before delegation, record `dispatch`.
2. Require each subagent to return its ID, role, outcome, changed paths, checks, blockers, and proposed changelog text.
3. Record `return` before the next transition.

Use lifecycle `in-progress`, `blocked`, `completion-pending`, or `done`.
Keep `TODO` specific to the workflow.
Append chain gate outcomes and LoEn milestones to `Changelog`. Do not store them in repository table cells.

### History

Keep task history in linked segments at `reference/task-history/<topic>-<sequence>`.
The task page `Changelog` links to the first and active segments.
Limit each segment to 20 events. Link each completed segment to its successor.
Preserve all events before closing the task.

Use `reference/domain-changelog` only for standards, releases, migrations, and cross-task decisions.
Link those entries to task pages. Do not duplicate routine task events there.

If `wiki_lint` reports a task-page orphan, treat it as an expected advisory.
Task status is found by tag search.
Other findings on the task page still require attention.

### Unavailable task storage

On iwiki MCP outage, execution may continue with redacted local spool evidence.
When iwiki is connected but the project domain is absent, execution may continue with the same local evidence.
Normal page resolution is unavailable in that case.

Durable status is unavailable. Spool evidence is non-authoritative. The lifecycle is `completion-pending`.
The task must not report `done` until all these conditions are met:

1. The domain and task page are available.
2. Spool replay succeeds.
3. The page write succeeds.
4. The spool is empty.
5. Task-page lint is clean.

Do not add direct hooks that write wiki. MCP operations remain interactive parent actions.
`task_spool.py` never calls MCP.

## Task Topic and Thread Title

**Every task must define one canonical `<topic>` before durable work starts for the
workflow artifacts the agent can control.**

- `<topic>` is a semantic, English, lowercase kebab-case slug: words joined by hyphens, for example `thread-title-task-naming-policy`.
- Use the same `<topic>` across applicable controlled surfaces:
  - iwiki task-page slug `reference/tasks/<topic>`;
  - Superpowers chain topic, for IDD->SDD work;
  - LoEn topic directory, for LoEn loop work;
  - git branch suffix: `dev-<topic>`.
- Thread title is best-effort only: if the platform exposes a title-control
  mechanism, set or request the same `<topic>` there. If no such mechanism is
  available, state the chosen `<topic>` in the conversation and do not block
  work merely because the UI title cannot be changed.
- Do not use vague topics such as `fix`, `update`, `work`, `misc`, `phase1`, or `changes`.
- Prefer topics that describe the task domain and intended outcome, not just the implementation step.
- If a branch already exists, derive `<topic>` from the branch suffix unless it is vague.
- If controlled artifacts such as task-page slug, chain/LoEn topic, and branch name
  disagree, stop and normalize them to one `<topic>` before continuing. Do not
  treat an inaccessible UI thread title as a blocking artifact.

## Workflow Route Selection

Classify the workflow before invoking `fix-intent`, `superpowers:brainstorming`, or
creating chain artifacts. Superpowers skills are selected tools; using an applicable
scoped skill does not by itself select `chain`. This rule overrides generic Superpowers
wording that treats every behavior change as requiring brainstorming.

Before selecting a workflow, perform bounded routing discovery from only the request and
project signals strictly necessary to derive domain, topic, and route. It creates no chain
artifacts and is not implementation; it must not perform task-specific analysis, reproduction,
or test execution before the task page is resolved. Resolve the wiki task page before any
task-specific analysis or durable work. Parent-session model recommendations do not block routing, implementation, or artifact creation.
Apply the authority gates in [Model and Reasoning Recommendations](#model-and-reasoning-recommendations).

### Select the workflow route

Absence of evidence is not evidence for chain. Recommend **direct** when discovery shows
the request or diagnosis is bounded, no chain trigger is evidenced, and a verification
or next discovery step is known. Unknown defect cause alone starts scoped debugging, not
chain. Typical examples: known-cause local fixes, typos, formatting, focused tests for
existing behavior, mechanical configuration or documentation edits, and read-only review.

Recommend **chain** only when the user explicitly requests it or discovery shows that a
durable approved intent is needed for a new capability or module, a public contract,
schema or migration, security/concurrency/transaction/data-invariant behavior, or coupled
subsystem work. Chain does not imply spec and plan: that decision occurs only after
`$check-chain intent` returns `OK`.

Recommend **loen** only for tasks that operate a durable LoEn workspace through its own loop lifecycle.

### Select the chain continuation

After intent validation, perform intent-scoped repository analysis and recommend
`execute` by default when implementation and verification are bounded. It implements
directly from the approved intent and marks Spec and Plan n/a. Recommend `full` only when
both an enumerated design-risk category and a named unresolved design decision are present:
a new module boundary, public compatibility strategy, architecture choice,
schema/migration/security/concurrency/transaction/data-integrity invariant, or coupled
subsystem design. Merely touching one of these areas is insufficient. General uncertainty,
task size, or the word "non-trivial" are not triggers.

### Approval boundaries

At task start, state the recommendation and its evidence. Do not invoke `fix-intent` or
start chain until the user accepts that recommendation; an explicit chain request counts
as acceptance. After intent validation, report `execute` or `full` with evidence and wait
before starting `full`. Prefer `execute` when no full trigger is evidenced.

### Direct work

Direct work creates no formal intent, spec, plan, or `check-chain` artifact, but always resolves a wiki task page.
The exception is an explicit direct topic: `@topic <kebab-case-topic>` is a user approval
to create `docs/profiles/<topic>.yaml` with the initial `engineering` profile and bind it
to the current local session. The next user prompt continues immediately; the direct
profile does not pin the interactive parent model or require a continuation confirmation.
This does not alter the chain/App Server profile path.
`@topic` is submitted as plain prompt text, not selected from Codex autocomplete: when
the `@` menu opens, press `Esc`, finish `@topic <kebab-case-topic>`, then press Enter.
Direct work must not invoke `fix-intent`, `superpowers:brainstorming`,
`superpowers:writing-plans`, `superpowers:subagent-driven-development`, or
`superpowers:executing-plans`. Scoped systematic debugging, TDD, and verification remain
allowed. `superpowers:finishing-a-development-branch` remains available after verified
direct or chain work. If direct scope crosses a chain trigger, stop and recommend chain.

```text
Workflow recommendation: direct | chain | loen
Continuation after intent: execute | full | n/a
Evidence: <bounded facts or qualifying trigger>
Intent required: yes | no
Confirmation required: yes | no
```

## Chain Order

After the user accepts chain, keep selected transitions gated by `check-chain`:

**LoEn carve-out:** tasks that start, continue, audit, repair, research, review, or
govern durable LoEn workspaces through `loen:loop-*` skills use the LoEn lifecycle
only. Do not run `fix-intent`, `superpowers:brainstorming`,
`superpowers:writing-plans`, `superpowers:subagent-driven-development`,
`superpowers:executing-plans`, `superpowers:finishing-a-development-branch`, or
`$check-chain` merely because a LoEn loop is active. LoEn loop artifacts live in
`docs/loen/<topic>/`; parent mirrors material lifecycle evidence to the shared task
page `TODO` and `Changelog` unless the user explicitly chooses the IDD->SDD chain for a
separate non-LoEn change.

1. `fix-intent` creates or updates `docs/superpowers/intents/*-intent.md`.
2. `$check-chain intent` validates the intent.
3. Record `workflow.route: chain` and `workflow.continuation: execute|full` in intent
   frontmatter after the user accepts the continuation recommendation.
4. For `execute`, skip brainstorming and writing-plans, implement from the approved
   intent with scoped implementation skills, then run `$check-chain result <intent>`.
5. For `full`, run `superpowers:brainstorming` -> `$check-chain spec` ->
   `superpowers:writing-plans` -> `$check-chain plan` -> plan execution.
6. Run `$check-chain result <plan>` for `full`; result reconciliation always precedes
   branch finishing.

The Codex hook `.codex-isolated/hooks/chain-gate.py` enforces transitions when it
can see them. It must gate both explicit `Skill` events and Codex skill-loading
signals such as reading `skills/<name>/SKILL.md` through `Read` or `Bash`. It is a
transition gate only: validation state still comes from frontmatter written by the
`check-chain` skill.

## Model and Reasoning Recommendations

Classify each task, but keep parent-session recommendations informational. Never edit
TOML, select profiles, start sessions, operate `/model`, or claim a switch. Parent-session
model recommendations are informational and never block safe work.

### Execution Routes

Rules refer only to stable semantic routes, never model branding:

| Route | Capability target | Effort target |
|-------|-------------------|---------------|
| `mechanical` | Lowest-cost capable coding model | baseline |
| `engineering` | Balanced general coding model | baseline |
| `synthesis` | Strongest reasoning model for design synthesis | baseline |
| `deep` | Strongest single-agent reasoning model | deep |
| `escalation` | Strongest model after evidenced failure | maximum |
| `parallel-audit` | Strongest agentic model for independent audits | parallel |

### Current Catalog Mapping

Exact model IDs live only here. Update this table when the Codex catalog changes; do not
rewrite classification or workflow rules.

| Route | Current model | Current effort |
|-------|---------------|----------------|
| `mechanical` | `gpt-5.6-luna` | `medium` |
| `engineering` | `gpt-5.6-terra` | `medium` |
| `synthesis` | `gpt-5.6-sol` | `medium` |
| `deep` | `gpt-5.6-sol` | `high` |
| `escalation` | `gpt-5.6-sol` | `max` |
| `parallel-audit` | `gpt-5.6-sol` | `ultra` |

Resolve the semantic route through the current catalog before reporting a parent
recommendation or spawning a delegated agent. If the mapped entry is unavailable, keep
the semantic route and mark resolution `unresolved`; do not invent a replacement model.
An unavailable preferred child model never blocks safe parent work.

### Checkpoints

Reassess at direct task start, after chain or LoEn checks/reviews, and before next work:

| Boundary | Baseline |
|----------|----------|
| Direct task start -> execution | Classify task |
| Direct check/review -> next work | Reclassify if evidence changed |
| Start -> chain intent or coordination | `engineering` |
| Intent OK -> continuation decision | `engineering` |
| Intent execute -> implementation | Classify task |
| Intent full -> spec | `synthesis` |
| Spec OK -> plan | `synthesis` |
| Plan OK -> implementation | Classify each task |
| Implementation task complete -> task review | `engineering` |
| Task review complete -> next task | Classify next task |
| Execution -> bounded result check | `engineering` |
| Execution -> cross-system or critical result check | `deep` |
| Result OK -> routine follow-up | `engineering` |

At LoEn loop start and after each check or review, classify the next work with the same
execution routes. LoEn workflow selection never implies a stronger model.

For `needs_work`, remain in the stage, change strategy, rerun, and reassess. The verdict
alone never requires escalation.

Workflow and execution routes are independent: direct does not imply `mechanical`, and
chain does not imply `deep`. Repeat classification after failed checks, scope changes,
or newly discovered invariants.

### Task Transition Gate

A task-scoped recommendation expires when that task reaches review or completion, or
when execution moves to another plan task. Never assume that the active session profile
or the recommendation for the previous task is suitable for the next task.

**Orchestrated branch:** the runner validates shared registry and direct project manifest,
then the hook accepts only correlated local handoff/session evidence. Matching
routed evidence authorizes work for that protected task only. The hook validates evidence; it
never selects or changes model.

**Interactive branch:** retain route classification and report the resolved mapping as
cost/capability guidance. Continue on the active parent model without requesting
`/status`, `/model`, downgrade confirmation, or escalation confirmation. Human authority
gates still apply to destructive, risky, or external actions.

**Delegated-agent branch:** when delegation is explicitly authorized, resolve the
subtask's semantic execution route independently before spawning. Pass the exact mapped
`model` and `reasoning_effort` to `spawn_agent` with `fork_turns` set to `none` or a
positive value. Delegate only when the expected benefit exceeds coordination cost. The
parent records the route, evidence, resolved mapping, ownership, and authority limits in
its delegation request. A delegated mechanical subtask must not use a stronger route
without an evidenced trigger. Delegation never bypasses user confirmation for
destructive, risky, or external actions. Do not inherit the parent route automatically.
Reclassify before every follow-up task whose scope or evidence changes. If no sufficient
mapped child is available, keep safe work in the parent.

For interactive work:

1. Identify the next work and classify its execution route from current evidence.
2. Resolve and report the recommended exact model and effort when available.
3. Continue on the active parent model; never pause solely for model or effort alignment.
4. Delegate bounded independent work only when explicit ownership and verification make
   coordination worthwhile.
5. Stop only at existing authority, artifact, safety, or irreversible-action gates—not
   at model recommendation boundaries.

### Classification

Choose the lowest sufficient route:

1. **`mechanical`** only if work is fully defined, single-component, has known cause and
   verification, and changes no contract, schema, migration, concurrency, security, or
   data invariant.
2. **`synthesis`** for specification or planning synthesis without a deep trigger.
3. **`deep`** when evidence shows an unknown reproduced-defect cause, artifact/code
   contradiction, public compatibility change, transactional/concurrent/distributed
   invariants, migration/security/data risk, two or more coupled subsystem boundaries,
   or result reconciliation across coupled invariants.
4. **`engineering`** otherwise.

Never inherit a higher route. File count, task length, one failure, or a stage name are
not triggers. Gather ambiguous evidence at the lower route.

### Exceptional Routes

Use **`escalation`** only after two different `deep` strategies fail, reviewers
contradict the same invariant, a required test remains unexplained after strategy
change, an enumerated critical invariant set cannot be decomposed safely, or critical
migration reconciliation has credible data-loss risk.

Every critical migration requires a separate final integration review at `deep` or
higher, regardless of its implementation route.

Use **`parallel-audit`** only as a separate run with at least two independent read-only
audit directions, no shared writes, and one consolidation step. Never use it inside
active subagent orchestration.

Implementers never revise accepted intent, spec, or plan. Return drift to the earliest
gate. Never retry without changing strategy.

### Recommendation Handling

Use `keep`, `downgrade`, `escalate`, or `separate-run` (`parallel-audit`) to explain the
cost/capability relationship between the active parent model, when known, and the semantic
route. The decision is informational for parent execution. Never request status or a model
switch as a continuation condition. A risk that independently crosses a proposal-first or
no-go authority boundary still requires user action. Critical-migration final review cannot
be waived.

```text
Workflow: direct | chain | loen
Continuation: execute | full | n/a
Checkpoint: <check and verdict>
Next work: <stage or task>
Execution route: <semantic route>
Current mapping: <exact model / effort | unknown>
Recommended mapping: <exact model / effort | unresolved>
Decision: keep | downgrade | escalate | separate-run
Evidence: <artifact, finding, failure, invariant, or risk>
Higher route rejected because: <reason or n/a for parallel-audit>
Parent action: continue
Delegation: parent | child <exact model / effort>
```

## Project Status Reports

**When the user asks for project status, progress, or "what is the state of X", read task-tagged iwiki pages only.**

- Bind the project domain, search task-tagged pages, and read relevant pages. Lead with lifecycle counts or requested topic; report lifecycle, `TODO`, pending delivery, evidence, and task-page lint findings.
- Report `completion-pending` explicitly. List every `in-progress` task opened more than 14 days ago.
- If iwiki is unavailable, say durable status is unavailable. Local spool evidence is non-authoritative; do not infer status from repository files or silently reconcile it.

## Language Rules

- **Conversations and questions**: Russian — to match user expectations.
- **Documentation and code comments**: English — to keep docs universally readable.

## Copy-Friendly Command Output

**Bash/Python commands the user runs must be copy-pasteable straight from the terminal.**

- Put every runnable command in a fenced code block (```` ```bash ```` / ```` ```python ````) — never inline in prose.
- No leading indentation inside the fence. The first column is column 1, so copying grabs no stray spaces.
- One command per line. No trailing whitespace.
- No shell prompt prefixes (`$`, `>`, `#`) — they get copied too and break paste.
- Do not wrap long commands with manual line breaks; let the terminal soft-wrap, or use explicit `\` continuations.

## Think Before Coding

**State assumptions and tradeoffs. Ask when a requirement is unclear.**

Before implementing:
- State assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — do not pick silently.
- If a simpler approach exists, say so.
- If something is unclear, stop. Name what is confusing. Ask.

## Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No unrequested features — scope creep compounds review cost.
- No abstractions for single-use code — increases cognitive load without reuse benefit.
- No "flexibility" not requested — premature generalization adds maintenance burden.
- No error handling for impossible scenarios — dead code misleads readers.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer call this overcomplicated?" If yes, simplify.

## Surgical Changes

**Change only what the request requires. Remove unused code only when your changes made it unused.**

When editing existing code:
- Do not improve adjacent code or formatting — unrelated changes bloat diffs and risk regressions.
- Do not refactor things that are not broken — stability is a feature.
- Match existing style — consistency beats personal preference.
- If you notice unrelated dead code, mention it — do not delete it.

When your changes create orphans:
- Remove imports/variables/functions YOUR changes made unused.
- Do not remove pre-existing dead code unless asked.

Test: every changed line must trace directly to the user's request.

## Branch Workflow

**Do not commit to main. Develop on a branch. Merge back only via PR.**

- Never commit work directly to the main branch (`master` / `main` / `prod`), and never merge or push to it directly — close every branch through a PR into main.
- **Branch naming is mandatory: `dev-<name>`, created from the selected up-to-date base branch (main by default).** Words inside `<name>` are joined with `-` (e.g. `dev-route-policy`). No exceptions.
- **If the project has long-lived branches beyond `master` / `main` / `prod`** (e.g. `dev`, `develop`, `staging`, `release/*`), always ask first — which branch to base the new `dev-*` off, and which branch to open the PR against. Do not assume.
- **When creating a `dev-*` branch, check existing local `dev-*` branches first.**
  - **No existing `dev-*` branch** → do not offer or create a worktree; create the branch in the main worktree.
  - **Another `dev-*` branch already exists** → ask first: create a worktree for the new branch now?
    - **Yes** → create the branch in a sibling worktree at `../<project>-<branch>` and do all the work there.
    - **No** → create the branch in place and keep working in the main worktree.
- For parallel work on several tasks, create one git worktree per branch.
- **Worktree naming is mandatory: `../<project>-<branch>`** — a sibling directory named with the project basename and the full branch name. Example: project `icodex`, branch `dev-route-policy` → sibling worktree `../icodex-dev-route-policy`.

### Git Worktrees and VS Code

When a `dev-*` task uses a worktree, create it atomically from the selected base branch in the mandatory sibling path. Open that folder directly in VS Code if needed; do not create linked worktrees inside the repository root.

```bash
base="<base-branch>"
branch="dev-<topic>"
root="$(git rev-parse --show-toplevel)"
project="$(basename "$root")"
parent="$(dirname "$root")"
git fetch origin "$base"
git worktree add -b "$branch" "$parent/$project-$branch" "origin/$base"
code --new-window "$parent/$project-$branch"
```

If the branch already exists, attach it at the same path. Verify with `git worktree list --porcelain`. After creating its PR, remove the worktree through Git and run `git worktree prune`.

Use **@skill:git-workflow** for commit messages and PR creation.

## Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals (verify by running real code or tests):
- "Add validation" → "Run the code with invalid inputs, confirm it rejects them"
- "Fix the bug" → "Reproduce it by running the affected path, confirm the fix removes it"
- "Refactor X" → "Run X before and after, confirm identical observable behavior"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

## Verification Economy

**Evidence follows relevant inputs, not conversation turns.** Verification evidence
remains valid while its declared relevant inputs are unchanged. Fresh means produced
after the last relevant input change for the exact code-state fingerprint; it does not
mean rerun in the current message. Record the command, scope, exit status, and fingerprint
needed to connect a claim to that state.

Choose the smallest check set that proves the current claim:

- Read-only and documentation-only tasks run no code tests. Documentation-only work runs
  only applicable documentation, structure, or lint checks. Agent instructions, skills,
  hooks, executable examples, and generated runtime inputs are behavior, not
  documentation-only content.
- A localized behavior change runs syntax validation plus its focused test. Add related
  regression tests only when the changed boundary has affected callers or contracts.
- Shared runtime, launcher, hook, configuration, or public-contract changes run focused
  and relevant regression checks during iteration, then the full suite once on the final
  stable state.
- Security, migration, concurrency, and data-integrity changes retain their required
  enhanced verification.

Run the full suite at most once for one unchanged code-state fingerprint. Result review,
branch finishing, and completion checks reuse matching full-suite evidence. Within this
project, this rule scopes generic skill wording that asks for fresh evidence or a full
suite: rerun only when relevant implementation, test, dependency, configuration, generated
runtime input, or execution environment changed. Repository documentation, iwiki, task
ledger, review text, and conversation updates do not invalidate code-test evidence unless
they change an executable or generated runtime input.

Never describe focused or related-test evidence as a full-suite pass. If a check fails,
diagnose with the narrow failing check and rerun it after a relevant change; return to the
full suite only after focused evidence passes. Do not repeat an unchanged failing command
without a new diagnostic hypothesis. After two different strategies fail to explain the
same result, reclassify or escalate instead of looping.

A verification budget is a strategy-change threshold, never permission to skip a required
check. When verification exceeds its expected cost or repeats, stop broad reruns, identify
the invalidated evidence, and choose a narrower diagnostic step. Trust remains the first
priority; speed comes from removing checks that add no evidence.

## Mode: Piecemeal Growth

Design for current requirements, current workflows, and observed failures.
Keep the implementation within the present contract.

- Do not add configurability, concurrency, fallback paths, validation, or abstractions for hypothetical future needs.
- State assumptions explicitly.
- Make assumption violations visible instead of hiding them behind speculative handling.
- When a new requirement or repeated failure appears, change the design locally.
- Generalize only when observed needs show what the generalization must support.

Protect durable data, external callers, and security boundaries.
Handle failures whose likelihood or cost is supported by evidence.

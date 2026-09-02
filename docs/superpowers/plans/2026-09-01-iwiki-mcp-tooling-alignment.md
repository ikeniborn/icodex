---
chain:
  intent: docs/superpowers/intents/2026-09-01-iwiki-mcp-tooling-alignment-intent.md
  spec: docs/superpowers/specs/2026-09-01-iwiki-mcp-tooling-alignment-design.md
review:
  plan_hash: 28663b7f1dbf8176
  last_run: 2026-09-01
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings: []
result_check:
  verdict: OK
  source: plan
  plan_hash: 28663b7f1dbf8176
  last_run: 2026-09-02
  reviewed: true
  docs_checked: true
---

# iwiki-mcp Tooling Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align every affected icodex agent surface with the live 35-tool iwiki-mcp contract while preserving binding, authorization, CAS, GWT, task-ledger, and storage/transport safeguards.

**Architecture:** Keep the live MCP registry authoritative and update the existing instruction projections rather than creating a second catalog. Extend the existing GWT hook with session/domain-scoped effective-mode evidence from `wiki_status`; all other binding and authorization decisions remain interactive parent responsibilities enforced by instructions and tests.

**Tech Stack:** Bash documentation/wiring, dependency-free Bash tests, Python 3 standard library hook, JSON hook configuration, iwiki MCP over hosted PostgreSQL.

---

## File Map

- `.codex-isolated/AGENTS.md`: central iwiki operation and tool-routing contract.
- `.codex-isolated/skills/context-awareness/SKILL.md`: Phase 0 binding, specification,
  and code-graph state projection.
- `.codex-isolated/skills/context-awareness/templates/project-context.json`: stable
  project-context fields.
- `.codex-isolated/skills/fix-intent/SKILL.md`: intent-stage iwiki context bootstrap.
- `.codex-isolated/skills/task-ledger/SKILL.md`: durable task binding/provenance gate.
- `.codex-isolated/hooks/gwt-gate.py`: effective specification-mode and scenario-context
  enforcement.
- `.codex-isolated/hooks.json`: tracked hook matcher projection.
- `lib/iwiki/iwiki.sh`: generated remote-scope instructions and generated hook matchers.
- `docs/iwiki-mcp-modes.md`: operator/agent storage, transport, graph, and authority guide.
- `tests/test_iwiki_agent_contract.sh`: executable base/skill/doc contract.
- `tests/test_iwiki_remote_scope.sh`: generated remote instruction and hook wiring contract.
- `tests/test_gwt_gate.sh`: status/mode/context hook state machine.
- `icodex:iwiki-mcp-integration`: final Wiki architecture page, updated through MCP CAS.

## Requirement Coverage

| Requirement | Plan tasks |
|---|---|
| R1 Live Contract Authority | 1, 3, 5 |
| R2 Binding and Hosted Provenance | 1, 2, 3, 5 |
| R3 Intent-Based Tool Routing | 1, 3, 5 |
| R4 Page and Selector Mutation Contract | 1, 3, 5 |
| R5 Code-Graph Availability and Language Coverage | 1, 2, 3, 5 |
| R6 Effective Specification Mode in the GWT Hook | 4, 5 |
| R7 Skill and Generated-Instruction Consistency | 2, 3, 5 |
| R8 Verification and Documentation Closure | 1–5 |

### Task 1: Align the Central Agent Contract

**Closes:** R1, R2, R3, R4, R5. Agents need one accurate intent-based contract for
the live registry before downstream skills can project subsets of it.

**Files:**
- Modify: `tests/test_iwiki_agent_contract.sh:7-76`
- Modify: `.codex-isolated/AGENTS.md:18-55`

- [ ] **Step 1: Add failing base-contract assertions**

Add these assertions after the existing full-scope binding assertion in
`tests/test_iwiki_agent_contract.sh`:

```bash
assert_contains "rules trust live callable schemas" "$agents_body" 'live callable tool schemas and observed server responses'
assert_contains "hosted binding requires session provenance" "$agents_body" '`binding_source: session`'
assert_contains "hosted default binding is rejected" "$agents_body" '`token_default` or `binding_defaulted`'
assert_contains "substituted primary blocks writes" "$agents_body" '`primary_substituted`'
assert_contains "rules include domain discovery" "$agents_body" '`wiki_list_domains`, `wiki_list_pages`, and `wiki_related`'
assert_contains "rules explain explicit whole-base search" "$agents_body" '`scope="all"`'
assert_contains "rules reject literal all wildcard" "$agents_body" '`read=["all"]` is a literal domain'
assert_contains "rules cover selector-only updates" "$agents_body" '`wiki_update_page(..., code=...)`'
assert_contains "rules cover combined selector updates" "$agents_body" 'section fields plus `code` atomically'
assert_contains "rules name four graph languages" "$agents_body" 'Python, TypeScript, JavaScript, or Bash'
assert_contains "rules gate graph freshness" "$agents_body" '`state == "ready"` and `fresh == true`'
assert_contains "rules gate hosted graph provenance" "$agents_body" '`binding_source == "session"`'
assert_contains "rules protect grant mutations" "$agents_body" '`wiki_set_domain_grant` and `wiki_revoke_domain_grant` require separate explicit user authorization'
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
bash tests/test_iwiki_agent_contract.sh
```

Expected: exit `1`; every new named assertion reports `FAIL`, while pre-existing
assertions remain unchanged.

- [ ] **Step 3: Add the minimal central contract text**

In `.codex-isolated/AGENTS.md`, extend the startup binding paragraph with this exact
hosted recovery rule:

```markdown
Treat live callable tool schemas and observed server responses as the operation
contract. After hosted `wiki_bind`, require `wiki_status` to report
`binding_source: session`. If an answer reports `token_default` or
`binding_defaulted`, rebind the full project scope and repeat the affected read.
`primary_substituted` with `requested_primary`, `binding_not_selected`, a rejected
bind, or an unexpected session identity blocks mutations and retains
`completion-pending` until the exact project binding is restored. Domain-named
Markdown tools carry no provenance fields.
```

Add this intent-routing paragraph under `Keep Docs Current` before the write-tool list:

```markdown
Use `wiki_list_domains`, `wiki_list_pages`, and `wiki_related` for read-only discovery;
`wiki_related` consumes a real section ID returned by retrieval. For `wiki_search`,
explicit `domains` win. Use `scope="all"` only for an explicit whole-base search;
`read=["all"]` is a literal domain, not a wildcard. Discovery does not authorize a
write. `wiki_list_domain_grants` is limited to explicit hosted management work;
`wiki_set_domain_grant` and `wiki_revoke_domain_grant` require separate explicit user
authorization and hosted management authority. Never expand grants automatically.
```

Extend the `wiki_update_page` bullet with all three live forms:

```markdown
  - **Rewrite / rename one `##` section** →
    `wiki_update_page(..., heading, new_body, new_heading=...)`.
  - **Replace selector frontmatter only** → `wiki_update_page(..., code=...)`; body
    bytes stay unchanged and code-only calls omit `source`, `description`, `status`,
    `new_heading`, and `expected_section_hash`.
  - **Change one section and selectors together** → pass paired section fields plus
    `code` atomically.
```

Replace the Python/TypeScript-only graph wording with:

```markdown
For Python, TypeScript, JavaScript, or Bash code analysis or planning, call
`wiki_code_status` after binding. Treat graph-assisted analysis as available only when
`state == "ready"` and `fresh == true`; hosted reads additionally require
`binding_source == "session"`. Bash is opt-in, scans `.sh` files only, and uses the
`sh:` entity prefix. Missing, stale, failed, unconfigured, default-bound, or
source-unavailable graph state falls back to repository search without blocking
ordinary Wiki work.
```

Keep the existing local-index and hosted-publication paragraph, but add that publication
tools accept neither client `domain` nor `iwiki_id` and must respect begin-advertised
limits.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
bash tests/test_iwiki_agent_contract.sh
```

Expected: exit `0` and final line `PASS=<positive integer> FAIL=0`.

- [ ] **Step 5: Check the diff and commit Task 1**

Run:

```bash
git diff --check
git diff -- .codex-isolated/AGENTS.md tests/test_iwiki_agent_contract.sh
git add .codex-isolated/AGENTS.md tests/test_iwiki_agent_contract.sh
git commit -m "docs(agent): align iwiki tool contract"
```

Expected: `git diff --check` exits `0`; the diff is limited to the listed files; commit
succeeds.

### Task 2: Align Phase 0, Intent, and Task-Ledger Skills

**Closes:** R2, R5, R7. All task-entry skills must use the same bind-before-status and
fresh-session graph rules without changing durable task ownership or spool behavior.

**Files:**
- Modify: `tests/test_iwiki_agent_contract.sh:7-76`
- Modify: `.codex-isolated/skills/context-awareness/SKILL.md:1-180`
- Modify: `.codex-isolated/skills/context-awareness/templates/project-context.json:14-24`
- Modify: `.codex-isolated/skills/fix-intent/SKILL.md:26-47`
- Modify: `.codex-isolated/skills/task-ledger/SKILL.md:10-23`

- [ ] **Step 1: Add failing skill-contract assertions**

Load the intent skill near the existing skill variables:

```bash
fix_body="$(cat "$ROOT/.codex-isolated/skills/fix-intent/SKILL.md")"
```

Replace the context version assertion and add these checks:

```bash
assert_contains "context skill version updated" "$context_body" '# version: 1.7.2'
assert_contains "context reports graph freshness" "$context_body" 'code_graph_fresh'
assert_contains "context reports graph binding source" "$context_body" 'code_graph_binding_source'
assert_contains "context gates ready and fresh" "$context_body" 'state == "ready" and fresh == true'
assert_contains "context gates hosted session binding" "$context_body" 'binding_source == "session"'
assert_contains "context covers four graph languages" "$context_body" 'Python, TypeScript, JavaScript, or Bash'
assert_contains "context template reports graph freshness" "$context_template" '"code_graph_fresh"'
assert_contains "context template reports graph binding source" "$context_template" '"code_graph_binding_source"'
assert_contains "intent binds before status in every transport" "$fix_body" 'call `wiki_bind` with the full normalized project scope before `wiki_status`'
assert_eq "intent removes inferred single-domain bind" "0" "$(grep -cF 'wiki_bind(read=[<domain>], write=<domain>)' <<<"$fix_body")"
assert_contains "ledger verifies hosted session provenance" "$ledger_body" '`binding_source: session`'
assert_contains "ledger retains pending on binding mismatch" "$ledger_body" 'binding mismatch retains `completion-pending`'
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
bash tests/test_iwiki_agent_contract.sh
```

Expected: exit `1`; new version/freshness/provenance assertions fail and the inferred
single-domain bind count is `1` instead of `0`.

- [ ] **Step 3: Update context-awareness fields and availability logic**

Change the skill version to `1.7.2`. Replace the iwiki binding/status and graph block
with rules equivalent to:

```text
For local stdio or remote HTTP, load the full normalized read/write/primary scope and
call wiki_bind before wiki_status. Hosted HTTP also passes project specification_mode
when accepted. Hosted status is trusted only with binding_source == "session" and no
primary substitution; otherwise rebind and repeat, or report completion-pending.

For Python, TypeScript, JavaScript, or Bash analysis, call wiki_code_status.
code_graph_available is true only when state == "ready" and fresh == true and, on
hosted HTTP, binding_source == "session".
Record code_graph_fresh and code_graph_binding_source even when availability is false.
```

Add the fields to the quick reference:

```json
"code_graph_available": true,
"code_graph_domain": "<primary>",
"code_graph_state": "ready",
"code_graph_fresh": true,
"code_graph_binding_source": "session"
```

Every unavailable/no-domain example must use `false` for freshness when known false,
otherwise `null`; binding source is `null` when no answer exists.

- [ ] **Step 4: Update the JSON template**

Insert these properties immediately after `code_graph_state`:

```json
"code_graph_fresh": "{{code_graph_fresh: boolean|null}}",
"code_graph_binding_source": "{{code_graph_binding_source: session|token_default|null}}",
```

Run:

```bash
python3 -m json.tool .codex-isolated/skills/context-awareness/templates/project-context.json >/dev/null
```

Expected: exit `0`, no output.

- [ ] **Step 5: Remove the stale fix-intent fallback**

Replace `fix-intent` Step 0 lines 28-37 with:

```markdown
Before asking questions, load and normalize the project-root `.iwiki.toml` `read`,
`write`, and `primary` scope, plus optional `[specifications].mode`. For local stdio or
remote HTTP, call `wiki_bind` with the full normalized project scope before
`wiki_status`; never infer a single-domain binding from the project name. Pass
`specification_mode` only to hosted HTTP when its callable schema accepts it. On hosted
HTTP, require `binding_source: session`; rebind and repeat after `token_default`,
`binding_defaulted`, or `binding_not_selected`, and stop mutating work after a rejected
or substituted binding. Then load `wiki_search('<topic>')` from the authorized read
scope as `wiki_context`.
```

- [ ] **Step 6: Add the hosted task-ledger provenance gate**

Extend Required Flow step 1 with:

```markdown
After hosted bind, require `wiki_status` to report `binding_source: session` and the
requested primary. Rebind and repeat on a defaulted answer. A rejected bind,
`binding_not_selected`, or unresolved primary substitution permits no task-page
mutation; binding mismatch retains `completion-pending`.
```

Do not change sections, event schemas, spool rules, CAS, or closure semantics.

- [ ] **Step 7: Run focused tests and verify GREEN**

Run:

```bash
bash tests/test_iwiki_agent_contract.sh
python3 -m json.tool .codex-isolated/skills/context-awareness/templates/project-context.json >/dev/null
```

Expected: both commands exit `0`; shell test ends with `FAIL=0`.

- [ ] **Step 8: Check the diff and commit Task 2**

Run:

```bash
git diff --check
git diff -- .codex-isolated/skills tests/test_iwiki_agent_contract.sh
git add .codex-isolated/skills/context-awareness/SKILL.md .codex-isolated/skills/context-awareness/templates/project-context.json .codex-isolated/skills/fix-intent/SKILL.md .codex-isolated/skills/task-ledger/SKILL.md tests/test_iwiki_agent_contract.sh
git commit -m "docs(skills): align iwiki session state"
```

Expected: check exits `0`; commit contains only the five listed paths.

### Task 3: Align Generated Remote Instructions and Mode Documentation

**Closes:** R1, R2, R3, R4, R5, R7. Generated project homes and operator docs must
project the same hosted recovery and tool boundaries as the base contract.

**Files:**
- Modify: `tests/test_iwiki_remote_scope.sh:16-51`
- Modify: `tests/test_iwiki_agent_contract.sh:7-76`
- Modify: `lib/iwiki/iwiki.sh:69-95`
- Modify: `docs/iwiki-mcp-modes.md:1-130`

- [ ] **Step 1: Add failing generated-scope and docs assertions**

Add to `tests/test_iwiki_remote_scope.sh` after the existing full-scope checks:

```bash
assert_contains "remote scope requires session provenance" "$agents" '`binding_source: session`'
assert_contains "remote scope repairs default binding" "$agents" '`token_default` or `binding_defaulted`'
assert_contains "remote scope blocks substituted primary" "$agents" '`primary_substituted`'
assert_contains "remote scope repeats affected reads" "$agents" 'repeat the affected domain-free read'
assert_contains "remote scope gates hosted graph freshness" "$agents" '`state == "ready"`, `fresh == true`, and `binding_source == "session"`'
assert_contains "remote scope protects grant mutations" "$agents" '`wiki_set_domain_grant` and `wiki_revoke_domain_grant` require separate explicit user authorization'
```

Load docs in `tests/test_iwiki_agent_contract.sh`:

```bash
modes_body="$(cat "$ROOT/docs/iwiki-mcp-modes.md")"
```

Add:

```bash
assert_contains "modes name four graph languages" "$modes_body" 'Python, TypeScript, JavaScript, and Bash'
assert_contains "modes explain search all" "$modes_body" '`scope="all"`'
assert_contains "modes explain selector-only update" "$modes_body" '`wiki_update_page(code=...)`'
assert_contains "modes require hosted session provenance" "$modes_body" '`binding_source: session`'
assert_contains "modes protect grant changes" "$modes_body" 'separate explicit user authorization'
```

- [ ] **Step 2: Run both focused tests and verify RED**

Run:

```bash
bash tests/test_iwiki_remote_scope.sh
bash tests/test_iwiki_agent_contract.sh
```

Expected: each exits `1` with only the newly added contract assertions failing.

- [ ] **Step 3: Extend the generated remote-scope block**

In `ensure_iwiki_remote_scope_instructions`, add this paragraph immediately after the
first bind paragraph:

```markdown
After hosted bind, require `wiki_status` to report `binding_source: session`. If status
or a domain-free code read reports `token_default` or `binding_defaulted`, call
`wiki_bind` again with the exact project scope and repeat the affected domain-free read.
Treat `primary_substituted` with `requested_primary`, `binding_not_selected`, a rejected
bind, or an unexpected session as a binding mismatch: make no mutation and retain
`completion-pending` until resolved.
```

Replace the hosted graph paragraph with:

```markdown
Use hosted code results only when `state == "ready"`, `fresh == true`, and
`binding_source == "session"`. `wiki_code_index` returns `source_unavailable` because a
hosted server has no client checkout. Hosted publication requires a writable primary,
accepts neither client `domain` nor `iwiki_id`, and must obey the limits returned by
`wiki_code_publish_begin`. PostgreSQL writes are durable, so do not call Git-only
`wiki_sync` or OKF maintenance tools. Domain-grant reads require explicit hosted
management work; `wiki_set_domain_grant` and `wiki_revoke_domain_grant` require separate
explicit user authorization and hosted management authority.
```

- [ ] **Step 4: Update the modes document with current routing**

Make these bounded changes in `docs/iwiki-mcp-modes.md`:

```markdown
- Code graph supports Python, TypeScript, JavaScript, and Bash. Bash is opt-in, scans
  `.sh` only, and uses `sh:` entities.
- A graph is usable only with `state == "ready"` and `fresh == true`; hosted reads also
  require `binding_source: session`.
- Hosted `token_default`, `binding_defaulted`, `primary_substituted`, and
  `binding_not_selected` require exact-scope rebind and repeat or fail-closed mutation.
- Explicit `wiki_search(domains=...)` wins; `scope="all"` is an intentional whole-base
  search; `read=["all"]` is literal.
- `wiki_update_page(code=...)` changes selectors only; section fields plus `code` form
  one atomic combined mutation.
- Domain discovery is read-only. Grant set/revoke requires hosted management authority
  and separate explicit user authorization.
```

Keep existing local/hosted, Git/PostgreSQL, secret, CAS, and lint sections intact.

- [ ] **Step 5: Run focused and wiring regression tests**

Run:

```bash
bash tests/test_iwiki_remote_scope.sh
bash tests/test_iwiki_agent_contract.sh
bash tests/test_iwiki_wiring.sh
```

Expected: all commands exit `0`; each shell suite ends with `FAIL=0`.

- [ ] **Step 6: Check the diff and commit Task 3**

Run:

```bash
git diff --check
git diff -- lib/iwiki/iwiki.sh docs/iwiki-mcp-modes.md tests/test_iwiki_remote_scope.sh tests/test_iwiki_agent_contract.sh
git add lib/iwiki/iwiki.sh docs/iwiki-mcp-modes.md tests/test_iwiki_remote_scope.sh tests/test_iwiki_agent_contract.sh
git commit -m "docs(iwiki): align hosted scope guidance"
```

Expected: check exits `0`; commit contains only generated guidance, docs, and their
focused tests.

### Task 4: Gate GWT Mutations on Effective Server Mode

**Closes:** R6 and the hook-enforced part of R8. Replace unsafe project-file mode
inference with trusted, expiring server-status evidence without affecting ordinary
Markdown updates.

**Files:**
- Modify: `tests/test_gwt_gate.sh:1-63`
- Modify: `.codex-isolated/hooks/gwt-gate.py:1-197`
- Modify: `.codex-isolated/hooks.json:27-48`
- Modify: `lib/iwiki/iwiki.sh:137-146`
- Modify: `tests/test_iwiki_remote_scope.sh:44-51`

- [ ] **Step 1: Rewrite hook fixtures around status evidence**

Remove the `.iwiki.toml` disabled-mode fixture. Define these status payloads after the
mutation fixture:

```bash
status_optional='{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"mcp__iwiki__wiki_status","tool_response":{"storage":"postgres","transport":"streamable-http","binding_source":"session","specifications":{"domains":[{"domain":"demo","mode":"optional","source":"project"}]}}}'
status_disabled='{"session_id":"disabled","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"storage":"postgres","transport":"stdio","specifications":{"domains":[{"domain":"demo","mode":"disabled","source":"project"}]}}}'
status_strict='{"session_id":"strict","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"storage":"postgres","transport":"streamable-http","binding_source":"session","specifications":{"domains":[{"domain":"demo","mode":"strict","source":"project"}]}}}'
status_default='{"session_id":"defaulted","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"storage":"postgres","transport":"streamable-http","binding_source":"token_default","specifications":{"domains":[{"domain":"demo","mode":"strict","source":"hosted_default"}]}}}'
status_substituted='{"session_id":"substituted","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"storage":"postgres","transport":"streamable-http","binding_source":"session","primary_substituted":true,"requested_primary":"demo","specifications":{"domains":[{"domain":"demo","mode":"strict","source":"project"}]}}}'
status_wrapped='{"session_id":"wrapped","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"content":[{"type":"text","text":"{\"storage\":\"postgres\",\"transport\":\"streamable-http\",\"binding_source\":\"session\",\"specifications\":{\"domains\":[{\"domain\":\"demo\",\"mode\":\"strict\",\"source\":\"project\"}]}}"}]}}'
status_malformed='{"session_id":"malformed-status","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"content":[{"type":"text","text":"not-json"}]}}'
```

Add assertions in this order:

```bash
assert_eq "GWT mutation without status fails closed" "2" "$(capture_code pre "${mutation//\"s1\"/\"missing\"}")"
assert_contains "missing status explains recovery" "$(run_hook pre "${mutation//\"s1\"/\"missing\"}" 2>&1)" 'wiki_status'
assert_eq "optional status records effective mode" "0" "$(capture_code post "$status_optional")"
assert_eq "optional unclassified scenario stays non-blocking" "0" "$(capture_code pre "$mutation")"
assert_contains "optional scenario nudges context" "$(run_hook pre "$mutation")" 'wiki_spec_context'
assert_eq "disabled status records mode" "0" "$(capture_code post "$status_disabled")"
assert_eq "disabled mode treats fence as ordinary" "0" "$(capture_code pre "${mutation//\"s1\"/\"disabled\"}")"
assert_eq "strict status records mode" "0" "$(capture_code post "$status_strict")"
assert_eq "strict unclassified scenario stays non-blocking" "0" "$(capture_code pre "${mutation//\"s1\"/\"strict\"}")"
assert_eq "token default status remains untrusted" "0" "$(capture_code post "$status_default")"
assert_eq "token default cannot authorize GWT update" "2" "$(capture_code pre "${mutation//\"s1\"/\"defaulted\"}")"
assert_eq "substituted primary status remains untrusted" "0" "$(capture_code post "$status_substituted")"
assert_eq "substituted primary cannot authorize GWT update" "2" "$(capture_code pre "${mutation//\"s1\"/\"substituted\"}")"
assert_eq "status is session isolated" "2" "$(capture_code pre "${mutation//\"s1\"/\"other-session\"}")"
assert_eq "wrapped status response records mode" "0" "$(capture_code post "$status_wrapped")"
assert_eq "wrapped status authorizes GWT checks" "0" "$(capture_code pre "${mutation//\"s1\"/\"wrapped\"}")"
assert_eq "malformed status response stays untrusted" "0" "$(capture_code post "$status_malformed")"
assert_eq "malformed status cannot authorize GWT update" "2" "$(capture_code pre "${mutation//\"s1\"/\"malformed-status\"}")"
```

Record an optional status for sessions `s2` and `s3` before their existing context
tests so those assertions continue exercising scenario identity rather than missing
status. Keep the ordinary update test before any status for its session; it must still
exit `0`. After every context assertion, replace the status file with an expired record
and verify expiry last:

```bash
printf '{"expired":{"demo":{"mode":"strict","timestamp":0}}}\n' > "$tmp/home/state/gwt-status.json"
assert_eq "expired status cannot authorize GWT update" "2" "$(capture_code pre "${mutation//\"s1\"/\"expired\"}")"
```

- [ ] **Step 2: Run the hook test and verify RED**

Run:

```bash
bash tests/test_gwt_gate.sh
```

Expected: exit `1`; missing/default/substituted/expired status cases incorrectly pass,
and the current local-file disabled fixture no longer supplies the new status contract.

- [ ] **Step 3: Add dependency-free status response parsing and state**

In `.codex-isolated/hooks/gwt-gate.py`, remove `tomllib`, add
`STATUS_MAX_AGE_SECONDS = 30 * 60`, and add these helpers:

```python
VALID_MODES = {"disabled", "optional", "strict"}


def _status_path():
    home = os.environ.get("CODEX_HOME")
    return os.path.join(home, "state", "gwt-status.json") if home else None


def _response_payload(data):
    response = data.get("tool_response")
    if not isinstance(response, dict) or response.get("isError") is True or response.get("error"):
        return None
    content = response.get("content")
    if content is None:
        return response
    if not isinstance(content, list):
        return None
    for item in content:
        if not isinstance(item, dict) or item.get("type") != "text":
            continue
        try:
            payload = json.loads(item.get("text", ""))
        except (TypeError, ValueError):
            continue
        if isinstance(payload, dict):
            return payload
    return None


def _load_status():
    path = _status_path()
    if not path or not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as stream:
            data = json.load(stream)
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    cutoff = time.time() - STATUS_MAX_AGE_SECONDS
    clean = {}
    for session_id, domains in data.items():
        if not isinstance(session_id, str) or not isinstance(domains, dict):
            continue
        kept = {}
        for domain, entry in domains.items():
            if not isinstance(domain, str) or not isinstance(entry, dict):
                continue
            mode = entry.get("mode")
            stamp = entry.get("timestamp")
            if mode in VALID_MODES and isinstance(stamp, (int, float)) and stamp >= cutoff:
                kept[domain] = {"mode": mode, "timestamp": stamp}
        if kept:
            clean[session_id] = kept
    return clean


def _save_status(state):
    path = _status_path()
    if not path:
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = "%s.%d.tmp" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as stream:
        json.dump(state, stream, sort_keys=True)
    os.replace(tmp, path)
```

- [ ] **Step 4: Record only trusted effective modes**

Add:

```python
def _record_status(data):
    payload = _response_payload(data)
    session_id = data.get("session_id")
    if not isinstance(session_id, str) or not session_id:
        return
    state = _load_status()
    state.pop(session_id, None)
    if not isinstance(payload, dict):
        _save_status(state)
        return
    hosted = payload.get("transport") == "streamable-http"
    if hosted and payload.get("binding_source") != "session":
        _save_status(state)
        return
    if payload.get("primary_substituted") is True:
        _save_status(state)
        return
    specifications = payload.get("specifications")
    rows = specifications.get("domains") if isinstance(specifications, dict) else None
    if not isinstance(rows, list):
        _save_status(state)
        return
    stamp = int(time.time())
    domains = {}
    for row in rows:
        if not isinstance(row, dict):
            continue
        domain = row.get("domain")
        mode = row.get("mode")
        if isinstance(domain, str) and domain and mode in VALID_MODES:
            domains[domain] = {"mode": mode, "timestamp": stamp}
    if domains:
        state[session_id] = domains
    _save_status(state)


def _effective_mode(data, domain):
    session_id = data.get("session_id")
    if not isinstance(session_id, str) or not isinstance(domain, str):
        return None
    entry = _load_status().get(session_id, {}).get(domain)
    return entry.get("mode") if isinstance(entry, dict) else None
```

- [ ] **Step 5: Replace project-file inference with the effective-mode gate**

Delete `_specification_disabled`. In `_check_context`, after confirming scenario IDs,
resolve the domain and mode before loading scenario context:

```python
    session_id = data.get("session_id")
    domain = params.get("domain") if isinstance(params, dict) else None
    mode = _effective_mode(data, domain)
    if mode is None:
        sys.stderr.write(
            "GWT gate: call wiki_bind and wiki_status for domain %r before mutating an iwiki-gwt scenario.\n"
            % domain
        )
        sys.exit(2)
    if mode == "disabled":
        return
```

Then retain the existing optional/strict context matching logic. Update `main()`:

```python
        if post and tool == "wiki_status":
            _record_status(data)
        elif post and tool == "wiki_spec_context":
            _record_context(data)
        elif post and tool == "wiki_update_page":
            _consume_context(data)
        elif not post and tool == "wiki_update_page":
            _check_context(data)
```

Keep malformed outer hook payloads fail-open. A valid GWT-bearing update with missing or
unreadable status evidence reaches the explicit mode check and fails closed.

- [ ] **Step 6: Wire post-status events in tracked and generated hooks**

Change the PostToolUse matcher in `.codex-isolated/hooks.json` and
`ensure_iwiki_gwt_hook` to:

```text
mcp__iwiki__wiki_status|wiki_status|mcp__iwiki__wiki_spec_context|wiki_spec_context|mcp__iwiki__wiki_update_page|wiki_update_page
```

Add this assertion to `tests/test_iwiki_remote_scope.sh`:

```bash
assert_contains "GWT hook matches status" "$hooks" 'wiki_status'
```

- [ ] **Step 7: Run hook, wiring, syntax, and JSON checks**

Run:

```bash
bash tests/test_gwt_gate.sh
bash tests/test_iwiki_remote_scope.sh
bash tests/test_codex_hooks.sh
python3 -m py_compile .codex-isolated/hooks/gwt-gate.py
python3 -m json.tool .codex-isolated/hooks.json >/dev/null
```

Expected: every command exits `0`; shell suites end with `FAIL=0`; syntax and JSON
checks emit no error.

- [ ] **Step 8: Check the diff and commit Task 4**

Run:

```bash
git diff --check
git diff -- .codex-isolated/hooks/gwt-gate.py .codex-isolated/hooks.json lib/iwiki/iwiki.sh tests/test_gwt_gate.sh tests/test_iwiki_remote_scope.sh
git add .codex-isolated/hooks/gwt-gate.py .codex-isolated/hooks.json lib/iwiki/iwiki.sh tests/test_gwt_gate.sh tests/test_iwiki_remote_scope.sh
git commit -m "fix(hooks): gate GWT updates on effective mode"
```

Expected: check exits `0`; commit succeeds with only hook implementation, matcher
projections, and focused tests.

### Task 5: Verify, Update Wiki Documentation, and Prepare Result Reconciliation

**Closes:** R8 and verifies R1–R7. Completion requires executable evidence, current
icodex documentation, clean lint, and a bounded branch diff.

**Files:**
- Read: every changed path from Tasks 1–4
- Update through MCP CAS: `icodex:iwiki-mcp-integration`, heading
  `Agent Operation Contract`
- Update through MCP CAS: `icodex:reference/tasks/iwiki-mcp-tooling-alignment`
- Update through MCP CAS: active task-history segment

- [ ] **Step 1: Run focused verification from a clean shell state**

Run:

```bash
bash tests/test_iwiki_agent_contract.sh
bash tests/test_iwiki_remote_scope.sh
bash tests/test_gwt_gate.sh
bash tests/test_iwiki_wiring.sh
bash tests/test_codex_hooks.sh
python3 -m py_compile .codex-isolated/hooks/gwt-gate.py
python3 -m json.tool .codex-isolated/hooks.json >/dev/null
python3 -m json.tool .codex-isolated/skills/context-awareness/templates/project-context.json >/dev/null
```

Expected: all commands exit `0`; each shell suite ends with `FAIL=0`; Python/JSON checks
emit no error.

- [ ] **Step 2: Prove stale contracts are absent**

Run:

```bash
test "$(rg -n 'wiki_bind\(read=\[<domain>\], write=<domain>\)|Python or TypeScript code-analysis|# version: 1\.7\.1' .codex-isolated docs/iwiki-mcp-modes.md || true)" = ""
rg -n 'binding_source|code_graph_fresh|wiki_update_page\(\.\.\., code|wiki_list_domain_grants|scope="all"' .codex-isolated docs/iwiki-mcp-modes.md lib/iwiki/iwiki.sh
```

Expected: first command exits `0`; second exits `0` and lists matches in each intended
instruction layer.

- [ ] **Step 3: Run the complete repository suite**

Run:

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: exit `0`; every suite reports zero failures.

- [ ] **Step 4: Verify branch scope and commit state**

Run:

```bash
git diff --check origin/master...HEAD
git status --short
git diff --name-only origin/master...HEAD
```

Expected: diff check exits `0`; status is empty; changed paths are limited to chain
artifacts plus the files listed in this plan.

- [ ] **Step 5: Refresh the exact iwiki session binding**

Using the active iwiki MCP tools, call `wiki_bind` with the full normalized project
scope and hosted `specification_mode`, then call `wiki_status`.

Expected: storage `postgres`, transport `streamable-http`, primary `icodex`,
`binding_source: session`, no primary substitution, and effective icodex mode matching
the project request. Any mismatch stops Wiki mutation and leaves lifecycle
`completion-pending`.

- [ ] **Step 6: Update the architecture page through CAS**

Read `icodex:iwiki-mcp-integration` immediately before mutation and read its `Agent
Operation Contract` section for `section_hash`. Update that section with the verified
contract: live schema authority, full bind and hosted provenance recovery, discovery
and search scope, three `wiki_update_page` forms, four graph languages plus freshness,
status-aware GWT hook behavior, and management authority boundaries. Pass the current
page revision and section hash.

Expected: `wiki_update_page` returns a new numeric revision and indexed chunks. On one
conflict, re-read and retry once; a second conflict stops closure.

- [ ] **Step 7: Persist verification and run lint**

Append redacted task verification evidence through parent-owned task-ledger CAS. Record
only command names, pass/fail status, integer exit codes, the repository revision, and
artifact hashes. Then call `wiki_lint(domain="icodex")`.

Expected: task page and history revisions advance, spool is absent, and lint reports no
new broken link, section, frontmatter, reserved-target, or specification finding. A
PostgreSQL empty orphan/stale list is not used as health proof.

- [ ] **Step 8: Run plan-backed result reconciliation**

Invoke:

```text
$check-chain result docs/superpowers/plans/2026-09-01-iwiki-mcp-tooling-alignment.md
```

Expected: plan hash matches, R1–R8 and Tasks 1–5 reconcile to actual diff/evidence,
focused review finds no unresolved bug, lifecycle becomes `done`, close event is
durable, spool is empty, and result verdict is `OK`.

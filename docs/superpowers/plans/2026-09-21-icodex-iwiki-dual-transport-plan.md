---
review:
  plan_hash: 38b040a207796f8f
  last_run: 2026-09-21
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings:
    - id: F-001
      phase: verifiability
      severity: WARNING
      section: Task 8
      section_hash: dbbc1a6a21a60c8c
      fragment: "time three launches to a usable session, recording wall clock each time"
      text: "The health-metric task named a measurement with no command that performs it, and a codex launch cannot be timed non-interactively."
      fix: "Measure what the change actually adds instead: three timed stdio initialize round-trips against the local server, including its embedding probe. The baseline is zero because no second server starts today."
      verdict: fixed
      verdict_at: 2026-09-21
    - id: F-002
      phase: coverage
      severity: WARNING
      section: Task 9b
      section_hash: c16e0023fda69b85
      fragment: "templates/CLAUDE.md.snippet, templates/AGENTS.md.snippet"
      text: "Spec requirement R9b arrived after the plan was gated, leaving it with no task."
      fix: "Added Task 9b in phase B, delivered in the same pull request as Task 9, with its own before/after measurement command."
      verdict: fixed
      verdict_at: 2026-09-21
    - id: F-003
      phase: coverage
      severity: WARNING
      section: Task 7b
      section_hash: 70807435434c0f80
      fragment: "icodex/specification/iwiki-dual-transport-wiring"
      text: "Spec requirement R8b arrived from a coverage audit after the plan was gated, leaving it with no task."
      fix: "Added Task 7b: write the scenario after the behaviour it describes is merged, verify it through wiki_spec_context and wiki_lint."
      verdict: fixed
      verdict_at: 2026-09-21
chain:
  intent: 5f9ea0d56abe70b3
  spec: 1d52a28f9e397e44
workflow:
  route: chain
  continuation: full
---

# icodex iwiki dual transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Register the local stdio iwiki server alongside the remote HTTPS one, so a code graph can be rebuilt from an icodex session and an outage no longer leaves a launch with no wiki.

**Architecture:** The two block generators in `lib/iwiki/iwiki.sh` take the server name as an argument. `ensure_iwiki_wiring` resolves the remote and local sets independently and concatenates one or two blocks into the same managed region. The remote server keeps the name `iwiki` in every mode, so hook matchers and generated instructions that reference `mcp__iwiki__*` stay correct without change.

**Tech Stack:** Bash 5 with `awk` and `printf`, the project's own `tests/helpers.sh` assertion harness, Python 3 only inside the existing hook writer.

**Spec:** `docs/superpowers/specs/2026-09-21-icodex-iwiki-dual-transport-design.md` (spec_hash `1d52a28f9e397e44`)

## Global Constraints

- The remote server is always `[mcp_servers.iwiki]`. Renaming it is forbidden.
- A launch never fails because of iwiki: an unresolved setting logs a warning and skips its block, returning 0.
- Secrets travel only through `env_vars` and `bearer_token_env_var`, never literal in TOML.
- Assertions already passing in `tests/test_iwiki_wiring.sh` are not modified — append only. The file started at 61 and stands at 86. Editing a passing test needs the user's approval first.
- One managed region, existing markers, region stays at end of file.
- Every `for` loop and trailing conditional keeps its `if`-block form: under the launcher's `set -e` a false test on the last iteration kills the launch.

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `lib/iwiki/iwiki.sh` | Wiring: block generators, region strip/rewrite, hook writer, instruction region | Modify |
| `tests/test_iwiki_wiring.sh` | Wiring assertions | Append cases only |
| `docs/iwiki-mcp-modes.md` | Operator documentation of transport modes | Modify |

Phases B through D touch other repositories and land as their own pull requests.

---

### Task 1: Parameterize the block generators

**Files:**
- Modify: `lib/iwiki/iwiki.sh` (`_iwiki_region_body`, `_iwiki_remote_region_body`, their two call sites in `ensure_iwiki_wiring`)
- Test: `tests/test_iwiki_wiring.sh` (existing cases act as the regression test)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `_iwiki_region_body <server-name> <command> <base_dir> <llm_base_url> <project_dir>` and `_iwiki_remote_region_body <server-name> <remote-url>`, both printing a block whose tables are named after `<server-name>`.

- [ ] **Step 1: Run the existing suite to record the green baseline**

Run: `env -u IWIKI_CODE_GRAPH_MCP_TOKEN -u IWIKI_CODE_GRAPH_MCP_URL bash tests/test_iwiki_wiring.sh`
Expected: `PASS=61 FAIL=0`

- [ ] **Step 2: Add the server-name argument to the local generator**

In `_iwiki_region_body`, replace the signature comment, the `local` line, and the two table headers:

```bash
_iwiki_region_body() { # <server-name> <command> <base_dir> <llm_base_url> <project_dir>
  local server="$1" cmd="$2" base="$3" url="$4" project="$5" name cfg val
  printf '[mcp_servers.%s]\n' "$server"
  printf 'command = "%s"\n' "$cmd"
  printf 'env_vars = ["IWIKI_LLM_KEY", "IWIKI_DB_PASSWORD"]\n'
  printf '[mcp_servers.%s.env]\n' "$server"
```

The rest of the function body, including the `for` loop over `_IWIKI_OPTIONAL_VARS` and its `if`-block, is unchanged.

- [ ] **Step 3: Add the server-name argument to the remote generator**

```bash
_iwiki_remote_region_body() { # <server-name> <remote-url>
  local server="$1" remote_url="$2"
  printf '[mcp_servers.%s]\n' "$server"
  printf 'url = "%s"\n' "$remote_url"
  printf 'bearer_token_env_var = "IWIKI_REMOTE_TOKEN"\n'
}
```

- [ ] **Step 4: Update both call sites in `ensure_iwiki_wiring`**

```bash
    body="$(_iwiki_remote_region_body iwiki "$remote_url")"
```

```bash
    body="$(_iwiki_region_body iwiki "$cmd" "$base" "$url" "$project")"
```

- [ ] **Step 5: Run the suite to prove behaviour is unchanged**

Run: `env -u IWIKI_CODE_GRAPH_MCP_TOKEN -u IWIKI_CODE_GRAPH_MCP_URL bash tests/test_iwiki_wiring.sh`
Expected: `PASS=61 FAIL=0` — the same number as Step 1. A drop means a call site was missed.

- [ ] **Step 6: Commit**

```bash
git add lib/iwiki/iwiki.sh
git commit -m "refactor(iwiki): name the generated mcp server through an argument"
```

---

### Task 2: Register both transports when both resolve

**Files:**
- Modify: `lib/iwiki/iwiki.sh` (`ensure_iwiki_wiring`)
- Test: `tests/test_iwiki_wiring.sh` (append)

**Interfaces:**
- Consumes: `_iwiki_region_body` and `_iwiki_remote_region_body` from Task 1.
- Produces: a region holding `[mcp_servers.iwiki]` alone, or `[mcp_servers.iwiki]` followed by `[mcp_servers.iwiki-local]`.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_iwiki_wiring.sh`, immediately before the final `finish`:

```bash
# --- dual: a resolvable remote and a resolvable local set register both servers ---
export ICODEX_HOME_DIR="$tmp/home-dual"
export ICODEX_PROJECT_ROOT="$tmp/project-dual"
export ICODEX_IWIKI_REMOTE_URL="https://iwiki.example.com/mcp"
export ICODEX_IWIKI_REMOTE_TOKEN="remote-test-token"
export ICODEX_IWIKI_COMMAND="$tmp/bin/iwiki-mcp"
export ICODEX_IWIKI_BASE_DIR="$tmp/wiki-base"
export ICODEX_IWIKI_LLM_BASE_URL="http://test-llm:1234/v1"
export ICODEX_IWIKI_LLM_KEY="test-key"
mkdir -p "$ICODEX_HOME_DIR" "$ICODEX_PROJECT_ROOT"
printf 'model = "x"\n' > "$ICODEX_HOME_DIR/config.toml"
ensure_iwiki_wiring
cfg="$(cat "$ICODEX_HOME_DIR/config.toml")"
assert_contains "dual: remote table named iwiki" "$cfg" '[mcp_servers.iwiki]'
assert_contains "dual: remote url present" "$cfg" 'url = "https://iwiki.example.com/mcp"'
assert_contains "dual: local table suffixed" "$cfg" '[mcp_servers.iwiki-local]'
assert_contains "dual: local env table suffixed" "$cfg" '[mcp_servers.iwiki-local.env]'
assert_contains "dual: local command present" "$cfg" "command = \"$tmp/bin/iwiki-mcp\""
assert_eq "dual: remote token not literal" "0" "$(grep -c 'remote-test-token' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "dual: llm key not literal" "0" "$(grep -c 'test-key' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "dual: exactly one start marker" "1" "$(grep -c '# icodex:iwiki:start' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "dual: region at end of file" "# icodex:iwiki:end" "$(tail -n1 "$ICODEX_HOME_DIR/config.toml")"

before="$(cat "$ICODEX_HOME_DIR/config.toml")"
ensure_iwiki_wiring
assert_eq "dual: idempotent second run" "$before" "$(cat "$ICODEX_HOME_DIR/config.toml")"
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `env -u IWIKI_CODE_GRAPH_MCP_TOKEN -u IWIKI_CODE_GRAPH_MCP_URL bash tests/test_iwiki_wiring.sh`
Expected: FAIL on `dual: local table suffixed` — today the remote branch returns before any local block is generated.

- [ ] **Step 3: Rewrite the resolution block in `ensure_iwiki_wiring`**

Replace the whole `if [[ -n "$remote_url" ]]; then … fi` block (the one that ends just before `ensure_iwiki_gwt_hook`) with:

```bash
  local remote_body="" local_body="" server_name="iwiki"
  if [[ -n "$remote_url" ]]; then
    if [[ -n "$remote_token" ]]; then
      remote_body="$(_iwiki_remote_region_body iwiki "$remote_url")"
    else
      log_warn "iwiki: remote URL is set but remote token is unresolved, skipping the remote server"
    fi
  fi
  if [[ -n "$project" ]] && _iwiki_project_uses_postgres "$project"; then
    postgres=1
  fi
  local local_ready=1
  if [[ -z "$cmd" || -z "$url" || -z "$key" || -z "$project" ]]; then
    local_ready=0
  elif [[ "$postgres" -eq 1 && -z "$db_password" ]]; then
    local_ready=0
  elif [[ "$postgres" -eq 0 && -z "$base" ]]; then
    local_ready=0
  fi
  if [[ "$local_ready" -eq 1 ]]; then
    if [[ -n "$remote_body" ]]; then
      server_name="iwiki-local"
    fi
    local_body="$(_iwiki_region_body "$server_name" "$cmd" "$base" "$url" "$project")"
  elif [[ -z "$remote_body" ]]; then
    log_warn "iwiki: required setting unresolved, skipping iwiki wiring"
  fi
  if [[ -z "$remote_body" && -z "$local_body" ]]; then
    return 0
  fi
  if [[ -n "$remote_body" && -n "$local_body" ]]; then
    body="$remote_body"$'\n'"$local_body"
  elif [[ -n "$remote_body" ]]; then
    body="$remote_body"
  else
    body="$local_body"
  fi
```

The `elif [[ -z "$remote_body" ]]` on the local warning is requirement R5: with a working remote, an absent local set is a deliberate configuration, not something to warn about on every launch.

- [ ] **Step 4: Run the suite**

Run: `env -u IWIKI_CODE_GRAPH_MCP_TOKEN -u IWIKI_CODE_GRAPH_MCP_URL bash tests/test_iwiki_wiring.sh`
Expected: `PASS=71 FAIL=0` — 61 existing plus the 10 new assertions.

- [ ] **Step 5: Commit**

```bash
git add lib/iwiki/iwiki.sh tests/test_iwiki_wiring.sh
git commit -m "feat(iwiki): register the local server beside the remote one"
```

---

### Task 3: Strip the suffixed table when it is no longer generated

**Files:**
- Modify: `lib/iwiki/iwiki.sh` (`_iwiki_strip_existing_wiring`)
- Test: `tests/test_iwiki_wiring.sh` (append)

**Interfaces:**
- Consumes: the dual region from Task 2.
- Produces: no new interface; the strip pattern now also matches `iwiki-local`.

- [ ] **Step 1: Write the failing test**

Append immediately after the Task 2 block:

```bash
# --- dual -> remote-only: the suffixed local table must not survive ---
unset ICODEX_IWIKI_BASE_DIR ICODEX_IWIKI_LLM_BASE_URL ICODEX_IWIKI_LLM_KEY
ensure_iwiki_wiring
assert_eq "dual->remote: local table removed" "0" "$(grep -cF '[mcp_servers.iwiki-local]' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "dual->remote: local env table removed" "0" "$(grep -cF '[mcp_servers.iwiki-local.env]' "$ICODEX_HOME_DIR/config.toml")"
assert_contains "dual->remote: remote kept" "$(cat "$ICODEX_HOME_DIR/config.toml")" 'url = "https://iwiki.example.com/mcp"'
export ICODEX_IWIKI_BASE_DIR="$tmp/wiki-base"
export ICODEX_IWIKI_LLM_BASE_URL="http://test-llm:1234/v1"
export ICODEX_IWIKI_LLM_KEY="test-key"
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `env -u IWIKI_CODE_GRAPH_MCP_TOKEN -u IWIKI_CODE_GRAPH_MCP_URL bash tests/test_iwiki_wiring.sh`
Expected: FAIL on `dual->remote: local table removed` — the current pattern `^\[mcp_servers\.iwiki(\]|\.)` does not match `[mcp_servers.iwiki-local]`, so the old block survives outside the region.

- [ ] **Step 3: Widen the strip pattern**

In `_iwiki_strip_existing_wiring`, change the stale-table line to:

```bash
    /^\[mcp_servers\.iwiki(-local)?(\]|\.)/ { in_stale=1; next }
```

- [ ] **Step 4: Run the suite**

Run: `env -u IWIKI_CODE_GRAPH_MCP_TOKEN -u IWIKI_CODE_GRAPH_MCP_URL bash tests/test_iwiki_wiring.sh`
Expected: `PASS=74 FAIL=0`

- [ ] **Step 5: Commit**

```bash
git add lib/iwiki/iwiki.sh tests/test_iwiki_wiring.sh
git commit -m "fix(iwiki): strip the suffixed local table with the managed region"
```

---

### Task 4: Keep a resolvable local half when the remote token is missing

**Files:**
- Test: `tests/test_iwiki_wiring.sh` (append)

**Interfaces:**
- Consumes: the resolution block from Task 2, which already implements this. This task proves it.
- Produces: nothing new.

- [ ] **Step 1: Write the test**

Append after the Task 3 block:

```bash
# --- remote URL without a token falls back to the local server, named iwiki ---
export ICODEX_HOME_DIR="$tmp/home-remote-untokened"
mkdir -p "$ICODEX_HOME_DIR"
printf 'model = "x"\n' > "$ICODEX_HOME_DIR/config.toml"
unset ICODEX_IWIKI_REMOTE_TOKEN IWIKI_REMOTE_TOKEN
assert_exit "untokened remote -> exit 0" 0 ensure_iwiki_wiring
cfg="$(cat "$ICODEX_HOME_DIR/config.toml")"
assert_contains "untokened remote: local server present" "$cfg" "command = \"$tmp/bin/iwiki-mcp\""
assert_eq "untokened remote: named iwiki" "1" "$(grep -cF '[mcp_servers.iwiki]' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "untokened remote: no suffixed table" "0" "$(grep -cF '[mcp_servers.iwiki-local]' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "untokened remote: no url" "0" "$(grep -c '^url =' "$ICODEX_HOME_DIR/config.toml")"
export ICODEX_IWIKI_REMOTE_TOKEN="remote-test-token"
```

- [ ] **Step 2: Run the suite**

Run: `env -u IWIKI_CODE_GRAPH_MCP_TOKEN -u IWIKI_CODE_GRAPH_MCP_URL bash tests/test_iwiki_wiring.sh`
Expected: `PASS=79 FAIL=0`. If `untokened remote: local server present` fails, Task 2's warning branch returned early instead of falling through.

- [ ] **Step 3: Commit**

```bash
git add tests/test_iwiki_wiring.sh
git commit -m "test(iwiki): cover the untokened remote falling back to local"
```

---

### Task 5: Extend the GWT hook matchers to the local server

**Files:**
- Modify: `lib/iwiki/iwiki.sh` (`ensure_iwiki_gwt_hook`, the two `replace(...)` calls)
- Test: `tests/test_iwiki_wiring.sh` (append)

**Interfaces:**
- Consumes: the hook writer as it stands.
- Produces: matchers that also name `mcp__iwiki-local__*`.

- [ ] **Step 1: Write the failing test**

```bash
# --- the GWT hook gates writes through either server ---
export ICODEX_HOME_DIR="$tmp/home-hook"
mkdir -p "$ICODEX_HOME_DIR"
printf 'model = "x"\n' > "$ICODEX_HOME_DIR/config.toml"
printf '{\n  "hooks": {}\n}\n' > "$ICODEX_HOME_DIR/hooks.json"
ensure_iwiki_wiring
hooks="$(cat "$ICODEX_HOME_DIR/hooks.json")"
assert_contains "hook: pre matches local update" "$hooks" 'mcp__iwiki-local__wiki_update_page'
assert_contains "hook: pre still matches remote update" "$hooks" 'mcp__iwiki__wiki_update_page'
assert_contains "hook: post matches local status" "$hooks" 'mcp__iwiki-local__wiki_status'
assert_contains "hook: post matches local spec context" "$hooks" 'mcp__iwiki-local__wiki_spec_context'
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `env -u IWIKI_CODE_GRAPH_MCP_TOKEN -u IWIKI_CODE_GRAPH_MCP_URL bash tests/test_iwiki_wiring.sh`
Expected: FAIL on `hook: pre matches local update`.

- [ ] **Step 3: Widen both matchers**

In the embedded Python of `ensure_iwiki_gwt_hook`:

```python
replace(
    "PreToolUse",
    gate,
    "mcp__iwiki__wiki_update_page|mcp__iwiki-local__wiki_update_page|wiki_update_page",
    "Checking GWT context ordering",
)
replace(
    "PostToolUse",
    post,
    "mcp__iwiki__wiki_status|mcp__iwiki-local__wiki_status|wiki_status|"
    "mcp__iwiki__wiki_spec_context|mcp__iwiki-local__wiki_spec_context|wiki_spec_context|"
    "mcp__iwiki__wiki_update_page|mcp__iwiki-local__wiki_update_page|wiki_update_page",
    "Recording GWT context ordering",
)
```

- [ ] **Step 4: Run the suite**

Run: `env -u IWIKI_CODE_GRAPH_MCP_TOKEN -u IWIKI_CODE_GRAPH_MCP_URL bash tests/test_iwiki_wiring.sh`
Expected: `PASS=83 FAIL=0`

- [ ] **Step 5: Run the other three iwiki suites**

```bash
for t in test_iwiki_binding.sh test_iwiki_remote_scope.sh test_iwiki_agent_contract.sh; do
  env -u IWIKI_CODE_GRAPH_MCP_TOKEN -u IWIKI_CODE_GRAPH_MCP_URL bash "tests/$t" | tail -1
done
```

Expected: `PASS=14 FAIL=0`, `PASS=44 FAIL=0`, `PASS=147 FAIL=0`

- [ ] **Step 6: Commit**

```bash
git add lib/iwiki/iwiki.sh tests/test_iwiki_wiring.sh
git commit -m "fix(iwiki): gate GWT ordering on either server's write"
```

---

### Task 6: State the role split and the outage rule — HUMAN CHECKPOINT

**Files:**
- Modify: `lib/iwiki/iwiki.sh` (the heredoc inside `ensure_iwiki_remote_scope_instructions`)
- Test: `tests/test_iwiki_remote_scope.sh` (append)

**Interfaces:**
- Consumes: the dual region from Task 2.
- Produces: an AGENTS.md paragraph naming both servers and both states.

> The intent puts the generated instruction region in the proposal-first autonomy zone. Show the exact paragraph to the user and wait for approval before writing it.

- [ ] **Step 1: Draft the paragraph and show it to the user**

Proposed text, to be appended inside the existing `icodex:iwiki-remote-scope` region:

```text
When `iwiki-local` is registered beside `iwiki`, the two servers address different stores:
`iwiki` is the hosted PostgreSQL wiki, `iwiki-local` is a local Git base. While `iwiki`
answers, use `iwiki-local` only for `wiki_code_index` and the code readers
`wiki_code_status`, `wiki_code_search`, and `wiki_code_context`; send every Markdown and
specification call to `iwiki`. A misrouted write lands in the wrong store silently.
If `iwiki` is unreachable — absent from the session, a failed `initialize`, or transport
errors on every call — `iwiki-local` becomes the full server, writes included. Record each
such write on the topic's ledger page as having landed in the local store, so it can be
reconciled with the hosted copy afterwards.
```

- [ ] **Step 2: Wait for approval**

Do not edit the file until the user approves the wording. If they revise it, use their version verbatim.

- [ ] **Step 3: Write the failing test**

```bash
# --- the generated scope instruction covers both servers ---
assert_contains "scope: names the local server" "$agents" "iwiki-local"
assert_contains "scope: names the outage rule" "$agents" "becomes the full server"
```

Place it beside the existing remote-scope assertions, reusing that file's `$agents` variable.

- [ ] **Step 4: Run it to make sure it fails**

Run: `env -u IWIKI_CODE_GRAPH_MCP_TOKEN -u IWIKI_CODE_GRAPH_MCP_URL bash tests/test_iwiki_remote_scope.sh`
Expected: FAIL on `scope: names the local server`.

- [ ] **Step 5: Append the approved paragraph to the heredoc**

Insert it before the closing `EOF` of the `icodex:iwiki-remote-scope` heredoc in `ensure_iwiki_remote_scope_instructions`.

- [ ] **Step 6: Run the suite**

Run: `env -u IWIKI_CODE_GRAPH_MCP_TOKEN -u IWIKI_CODE_GRAPH_MCP_URL bash tests/test_iwiki_remote_scope.sh`
Expected: `PASS=46 FAIL=0`

- [ ] **Step 7: Commit**

```bash
git add lib/iwiki/iwiki.sh tests/test_iwiki_remote_scope.sh
git commit -m "docs(iwiki): tell agents which server owns which call"
```

---

### Task 7: Correct the one-transport claim

**Files:**
- Modify: `docs/iwiki-mcp-modes.md`
- Modify (wiki, through MCP tools): `icodex/iwiki-mcp-integration`, section `Required Settings`

**Interfaces:**
- Consumes: the finished behaviour from Tasks 2 through 6.
- Produces: documentation that matches it.

- [ ] **Step 1: Find every claim**

Run: `grep -n "one transport\|replaces the managed local\|replaces local stdio" docs/iwiki-mcp-modes.md`
Expected: the lines stating that remote configuration replaces local stdio.

- [ ] **Step 2: Rewrite those lines**

Replace the "selects one managed transport per launch" statement with:

```markdown
A launch registers one or two managed iwiki servers, depending on what resolves.

| Condition | Registered |
|---|---|
| Remote URL and token resolve, local settings incomplete | `[mcp_servers.iwiki]` over HTTP |
| No remote URL, local settings complete | `[mcp_servers.iwiki]` over stdio |
| Both resolve | `[mcp_servers.iwiki]` over HTTP and `[mcp_servers.iwiki-local]` over stdio |

The name `iwiki` always belongs to the server that answers Markdown and specification
calls, so instructions and hook matchers that reference `mcp__iwiki__*` hold in every
mode. In the dual mode `iwiki-local` exists for `wiki_code_index` and the code readers,
because a hosted server answers `source_unavailable` to an index request; it becomes the
full server only while the remote one is unreachable.
```

- [ ] **Step 3: Update the wiki page**

Read the section first, then update it in place:

```text
wiki_read_page(domain="icodex", slug="iwiki-mcp-integration", heading="Required Settings")
wiki_update_page(domain="icodex", slug="iwiki-mcp-integration", heading="Required Settings",
                 new_body=<three modes>, expected_revision=<from the read>,
                 expected_section_hash=<from the read>, source="lib/iwiki/iwiki.sh")
```

- [ ] **Step 4: Verify the wiki is clean**

Run `wiki_lint(domain="icodex")` and confirm no new finding for that page.

- [ ] **Step 5: Commit**

```bash
git add docs/iwiki-mcp-modes.md
git commit -m "docs: describe the three iwiki transport modes"
```

---

### Task 7b: Contract the behaviour as a Given-When-Then scenario

**Files:**
- Create (wiki, through MCP tools): `icodex/specification/iwiki-dual-transport-wiring`

**Interfaces:**
- Consumes: the finished behaviour from Tasks 2 through 5, and the mode table Task 7 wrote.
- Produces: nothing other tasks read.

- [ ] **Step 1: Check no scenario already covers this**

```text
wiki_spec_search(query="iwiki transport wiring registers servers", domains=["icodex"])
```

Expected: no result describing transport registration. A hit means amend that scenario
instead of writing a new one, keeping its `id` stable.

- [ ] **Step 2: Write the page**

`wiki_write_page(domain="icodex", slug="specification/iwiki-dual-transport-wiring",
type="specification", status="stable", tags=["specification", "iwiki", "transport"],
source="lib/iwiki/iwiki.sh")` with one `##` section holding exactly this fence:

````markdown
```iwiki-gwt
id = "register-both-iwiki-transports"
title = "Register both iwiki transports for one launch"
given = [
  { role = "state", name = "RemoteUrlAndTokenResolve" },
  { role = "state", name = "LocalServerSettingsComplete" }
]
when = { role = "action", name = "EnsureIwikiWiring" }
then = [
  { role = "outcome", name = "RemoteServerRegisteredAsIwiki" },
  { role = "outcome", name = "LocalServerRegisteredAsIwikiLocal" }
]
code = [
  { relation = "implements", phase = "when", file = "lib/iwiki/iwiki.sh" },
  { relation = "verifies", file = "tests/test_iwiki_wiring.sh" }
]
```
````

Use `file` selectors, not `symbol`: the published code-graph snapshot for this domain is
stale until Task 11 deploys the rollout, so a qualified name would not resolve.

- [ ] **Step 3: Confirm the projection accepted it**

```text
wiki_spec_context(domain="icodex", scenario_id="register-both-iwiki-transports")
```

Expected: the scenario is present with both bindings. `graph_unavailable` or
`stale_graph` is acceptable and expected here; `invalid_scenario` is not.

- [ ] **Step 4: Confirm the domain lints clean**

```text
wiki_lint(domain="icodex")
```

Expected: no new finding naming this page, and the `specifications` block reports no
`invalid_scenario` or `duplicate_scenario_id`.

---

### Task 8: Measure the startup cost

**Files:** none — this is the intent's health metric.

- [ ] **Step 1: Measure what the second server actually costs**

The added cost is one more stdio server reaching the point where it answers `initialize`,
which includes its embedding probe. Measure that directly, three times:

```bash
for i in 1 2 3; do
  /usr/bin/time -f "%e" env \
    IWIKI_BASE_DIR="$ICODEX_IWIKI_BASE_DIR" \
    IWIKI_LLM_BASE_URL="$ICODEX_IWIKI_LLM_BASE_URL" \
    IWIKI_LLM_KEY="$ICODEX_IWIKI_LLM_KEY" \
    iwiki-mcp <<'JSON' > /dev/null
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"timing","version":"0"}}}
JSON
done
```

Expected: three wall-clock numbers in seconds, printed by `time` on stderr.

- [ ] **Step 2: Compare against the budget**

The baseline is zero — today no second server starts at all in this mode, so the measured
number *is* the regression. The threshold is 3 seconds.

- [ ] **Step 3: Escalate rather than absorb an overrun**

Over 3 seconds, stop and report it. The intent's stop rule names this case explicitly; do
not lower the threshold to fit the measurement.

- [ ] **Step 4: Record the numbers on the ledger page**

The three numbers and their average, on `icodex/reference/tasks/icodex-iwiki-dual-transport`, section `Evidence`.

---

## Phase B — tools reference, separate pull request in `iwiki-mcp`

### Task 9: Document every registered tool

**Files:**
- Modify: `docs/tools-reference.md`, `docs/tools-reference.ru.md` in the `iwiki-mcp` repository

- [ ] **Step 1: List the gap**

```bash
comm -13 <(grep -oE "wiki_[a-z_]+" docs/tools-reference.md | sort -u) \
         <(grep -oE "mcp\.tool\(\)\(wiki_[a-z_]+\)" src/iwiki_mcp/server.py | sed 's/.*(\(wiki_[a-z_]*\))/\1/' | sort -u)
```

Expected today: 15 tools — nine code-graph, three grant, three specification.

- [ ] **Step 2: Add a row per missing tool**

One row each, in the existing table format. A tool with a dedicated page gets a one-line summary plus a link to that page rather than a duplicated description.

- [ ] **Step 3: Mirror into the Russian sibling**

The two files carry the same information; only the language differs.

- [ ] **Step 4: Verify parity**

Re-run the Step 1 command. Expected: empty output.

- [ ] **Step 5: Commit**

```bash
git add docs/tools-reference.md docs/tools-reference.ru.md
git commit -m "docs: list every registered tool in the reference"
```

---

### Task 9b: Update the agent snippets — same pull request as Task 9

**Files:**
- Modify: `templates/CLAUDE.md.snippet`, `templates/AGENTS.md.snippet` in the `iwiki-mcp` repository

**Interfaces:**
- Consumes: the completed reference from Task 9 — the snippets summarize it.
- Produces: nothing other tasks read.

- [ ] **Step 1: Measure the gap**

```bash
comm -13 <(grep -oE "wiki_[a-z_]+" templates/AGENTS.md.snippet | sort -u) \
         <(grep -oE "mcp\.tool\(\)\(wiki_[a-z_]+\)" src/iwiki_mcp/server.py | sed 's/.*(\(wiki_[a-z_]*\))/\1/' | sort -u)
```

Expected today: 27 tools, including every code-graph tool, `wiki_read_page`,
`wiki_list_pages`, `wiki_related`, `wiki_status`, and `wiki_spec_search`.

- [ ] **Step 2: Add the missing tools to both snippets**

A snippet is a short operating guide, not a copy of the reference. Group the additions the
way the server groups them — ordinary reads, page mutations, code graph, specifications,
governance — one line each, naming what the tool is for and the one constraint that bites
in practice. Keep the two files equivalent: `CLAUDE.md.snippet` and `AGENTS.md.snippet`
differ only where the host's tool-naming differs.

- [ ] **Step 3: Verify both files carry the same tool set**

```bash
diff <(grep -oE "wiki_[a-z_]+" templates/CLAUDE.md.snippet | sort -u) \
     <(grep -oE "wiki_[a-z_]+" templates/AGENTS.md.snippet | sort -u)
```

Expected: no output.

- [ ] **Step 4: Verify nothing is left out**

Re-run Step 1's command. Expected: empty output.

- [ ] **Step 5: Commit**

```bash
git add templates/CLAUDE.md.snippet templates/AGENTS.md.snippet
git commit -m "docs(templates): describe every tool an agent can call"
```

---

## Phase C — rule surfaces, one pull request per repository

### Task 10: Teach the new tools to icodex and iclaude — HUMAN CHECKPOINT

**Files:**
- Modify: the generated instruction region in `icodex`
- Modify: the iwiki tool-semantics section of the iclaude rule file

Both are proposal-first: show the wording, wait for approval, then write.

- [ ] **Step 1: Name what is missing**

`wiki_code_refresh_links` appears nowhere in the iclaude rules and only inside icodex's generated region. Confirm with `grep -c` in each repository before writing anything.

- [ ] **Step 2: Draft one paragraph per repository and show both**

- [ ] **Step 3: Apply the approved text, one branch and pull request per repository**

---

## Phase D — rollout

### Task 11: Install locally and deploy the hosted server

- [ ] **Step 1: Wait for the merges**

Phase A's pull request and the already-merged `iwiki-mcp` 0.7.288 must both be on master.

- [ ] **Step 2: Install the new local version**

```bash
uv tool install --force /home/ikeniborn/Documents/Project/iwiki-mcp
iwiki-mcp --help | head -3
```

- [ ] **Step 3: Deploy the hosted server**

Follow `docs/deployment.md` in the iwiki-mcp repository, on the `framework` host. The deployed image reports 0.7.286 today.

- [ ] **Step 4: Verify the deployment**

```bash
ssh framework 'docker inspect --format "{{.State.Health.Status}}" iwiki-mcp-app-iwiki-1'
ssh framework 'docker exec iwiki-mcp-app-iwiki-1 /app/.venv/bin/python -c "import importlib.metadata as m;print(m.version(\"iwiki-mcp\"))"'
```

Expected: `healthy`, and a version of 0.7.288 or later.

- [ ] **Step 5: Verify the outcome that started all of this**

From an icodex session, run `wiki_code_index`, then `wiki_code_status` for the `icodex` domain.
Expected: `fresh: true`, `wiki_links_stale: false`.

- [ ] **Step 6: Record the result and close the topic**

Append the evidence to the ledger page, then run `/check-chain result` against this plan.

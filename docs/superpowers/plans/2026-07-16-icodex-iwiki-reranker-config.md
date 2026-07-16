---
review:
  plan_hash: 4390269442ae74b1
  last_run: 2026-07-16
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-07-16-icodex-iwiki-reranker-config-intent.md
  spec: docs/superpowers/specs/2026-07-16-icodex-iwiki-reranker-config-design.md
result_check:
  verdict: OK
  plan_hash: 4390269442ae74b1
  last_run: 2026-07-16
  reviewed: true
  docs_checked: true
---
# icodex iwiki reranker config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add runtime support for newer upstream `iwiki-mcp` `ICODEX_IWIKI_*` settings and generate `IWIKI_PROJECT_DIR` from the icodex project root.

**Architecture:** Keep the existing launch-time owner, `lib/iwiki/iwiki.sh`, and extend its optional-variable allowlist. Generate `IWIKI_PROJECT_DIR` from `ICODEX_PROJECT_ROOT` inside the managed `[mcp_servers.iwiki.env]` table, while keeping `IWIKI_LLM_KEY` forwarded only through `env_vars`.

**Tech Stack:** Bash, generated Codex TOML, existing Bash tests under `tests/`, iwiki MCP docs.

---

## File Structure

- Modify `tests/test_iwiki_env.sh`: add key-filtering coverage for a new wrapped iwiki variable and raw iwiki rejection.
- Modify `tests/test_iwiki_wiring.sh`: drive new optional variables and generated project root through the generated TOML region.
- Modify `lib/iwiki/iwiki.sh`: extend `_IWIKI_OPTIONAL_VARS`, require `ICODEX_PROJECT_ROOT`, pass project root into `_iwiki_region_body`, and emit `IWIKI_PROJECT_DIR`.
- Modify `.codex_config.example`: document required settings, optional command override, new optional variables, reranker support, chat/search/seed settings, and generated project-dir behavior.
- Update iwiki page `iwiki-mcp-integration` after implementation using `wiki_update_page`.

## Result Diff Baseline

Before starting Task 1, store the current branch tip outside the working tree so the result gate can reconcile implementation commits after the plan's intermediate commits:

```bash
git rev-parse HEAD > .git/icodex-iwiki-reranker-config.result-base
cat .git/icodex-iwiki-reranker-config.result-base
```

Expected: prints the commit SHA for the approved plan state. Use this stored SHA in Task 6 as the value after `--since=`.

## Coverage Matrix

- Spec 3.1 runtime variable support: Task 1 tests, Task 3 implementation.
- Spec 3.2 generated project directory: Task 2 tests, Task 3 implementation.
- Spec 3.3 required-tier guard: Task 2 tests, Task 3 implementation.
- Spec 3.4 secret handling: Task 2 preserves existing assertion, Task 3 keeps `env_vars`.
- Spec 3.5 `.codex_config.example`: Task 4 documentation.
- Spec 8 iwiki page update: Task 5 documentation and lint.

### Task 1: Add env parser coverage for new iwiki wrapper names

**Files:**
- Modify: `tests/test_iwiki_env.sh`
- Test: `tests/test_iwiki_env.sh`

- [ ] **Step 1: Add parser coverage for wrapped reranker config**

Insert this block after the existing raw-key rejection assertions near the top of `tests/test_iwiki_env.sh`:

```bash
assert_exit "ICODEX_IWIKI_RERANK_MODEL allowed" 0 _config_key_allowed ICODEX_IWIKI_RERANK_MODEL
assert_exit "raw IWIKI_RERANK_MODEL rejected" 1 _config_key_allowed IWIKI_RERANK_MODEL
```

Definition of done: the test file explicitly covers a newly supported wrapper key and confirms raw `IWIKI_RERANK_MODEL` remains rejected.

- [ ] **Step 2: Add load_config coverage for raw versus wrapped reranker config**

Extend the first temporary config block in `tests/test_iwiki_env.sh` from:

```bash
cat > "$cfg" <<'EOF'
ICODEX_IWIKI_LLM_KEY=sk-secret
IWIKI_LLM_KEY=raw-should-be-ignored
EOF
unset ICODEX_IWIKI_LLM_KEY IWIKI_LLM_KEY
load_config "$cfg"
assert_eq "wrapper key loaded"        "sk-secret" "${ICODEX_IWIKI_LLM_KEY:-}"
assert_eq "raw key in file ignored"   ""          "${IWIKI_LLM_KEY:-}"
```

to:

```bash
cat > "$cfg" <<'EOF'
ICODEX_IWIKI_LLM_KEY=sk-secret
ICODEX_IWIKI_RERANK_MODEL=rerank-test-model
IWIKI_LLM_KEY=raw-should-be-ignored
IWIKI_RERANK_MODEL=raw-rerank-should-be-ignored
EOF
unset ICODEX_IWIKI_LLM_KEY IWIKI_LLM_KEY ICODEX_IWIKI_RERANK_MODEL IWIKI_RERANK_MODEL
load_config "$cfg"
assert_eq "wrapper key loaded"        "sk-secret"          "${ICODEX_IWIKI_LLM_KEY:-}"
assert_eq "wrapper rerank loaded"     "rerank-test-model"  "${ICODEX_IWIKI_RERANK_MODEL:-}"
assert_eq "raw key in file ignored"   ""                   "${IWIKI_LLM_KEY:-}"
assert_eq "raw rerank in file ignored" ""                  "${IWIKI_RERANK_MODEL:-}"
```

Definition of done: `load_config` proves new wrapped values load and raw iwiki values do not.

- [ ] **Step 3: Run the focused env test**

Run:

```bash
bash tests/test_iwiki_env.sh
```

Expected: `PASS` for all assertions and exit code `0`.

### Task 2: Add wiring tests for new optionals and project root

**Files:**
- Modify: `tests/test_iwiki_wiring.sh`
- Test: `tests/test_iwiki_wiring.sh`

- [ ] **Step 1: Add synthetic project root to the main wiring scenario**

In `tests/test_iwiki_wiring.sh`, after `export ICODEX_IWIKI_LLM_KEY="test-key"`, add:

```bash
export ICODEX_PROJECT_ROOT="$tmp/project-root"
export ICODEX_IWIKI_PROJECT_DIR="$tmp/wrong-project"
mkdir -p "$ICODEX_PROJECT_ROOT"
```

Definition of done: the main wiring scenario has a deterministic project root available before `ensure_iwiki_wiring` runs, plus a deliberately wrong manual wrapper value to prove generated project root wins.

- [ ] **Step 2: Add new optional variables to the main wiring scenario**

After the existing optional exports:

```bash
export ICODEX_IWIKI_EMBED_MODEL="ollama-bge-m3"
export ICODEX_IWIKI_TOP_K="5"
```

add:

```bash
export ICODEX_IWIKI_SEARCH_MODE="semantic"
export ICODEX_IWIKI_RERANK_MODEL="rerank-test-model"
export ICODEX_IWIKI_SEED_TOP_K="7"
export ICODEX_IWIKI_BFS_TOP_K="11"
export ICODEX_IWIKI_SEED_THRESHOLD="0.17"
export ICODEX_IWIKI_WRITE_SEED_THRESHOLD="0.37"
export ICODEX_IWIKI_CHAT_MODEL="chat-test-model"
```

Extend the unset list that follows so these variables are absent in the negative checks:

```bash
unset ICODEX_IWIKI_EMBED_DIMENSIONS ICODEX_IWIKI_SCORE_THRESHOLD \
      ICODEX_IWIKI_GRAPH_DEPTH ICODEX_IWIKI_CHUNK_SIZE \
      ICODEX_IWIKI_CHUNK_OVERLAP ICODEX_IWIKI_SUMMARY_MAX_CHARS
```

Keep those unset variables as the intentionally absent set.

Definition of done: the main scenario includes representative new optional variables and keeps representative unset optionals.

- [ ] **Step 3: Assert generated project dir and new optional lines**

After the existing assertions for base dir and LLM URL, add:

```bash
assert_contains "resolved project dir" "$cfg" "IWIKI_PROJECT_DIR = \"$tmp/project-root\""
assert_contains "set optional search mode" "$cfg" 'IWIKI_SEARCH_MODE = "semantic"'
assert_contains "set optional rerank model" "$cfg" 'IWIKI_RERANK_MODEL = "rerank-test-model"'
assert_contains "set optional seed top k" "$cfg" 'IWIKI_SEED_TOP_K = "7"'
assert_contains "set optional bfs top k" "$cfg" 'IWIKI_BFS_TOP_K = "11"'
assert_contains "set optional seed threshold" "$cfg" 'IWIKI_SEED_THRESHOLD = "0.17"'
assert_contains "set optional write seed threshold" "$cfg" 'IWIKI_WRITE_SEED_THRESHOLD = "0.37"'
assert_contains "set optional chat model" "$cfg" 'IWIKI_CHAT_MODEL = "chat-test-model"'
assert_eq "manual project dir ignored" "0" "$(grep -cF "$tmp/wrong-project" "$ICODEX_HOME_DIR/config.toml")"
```

Definition of done: generated TOML includes the generated project root and each set representative new optional variable, and does not include the deliberately wrong `ICODEX_IWIKI_PROJECT_DIR` value.

- [ ] **Step 4: Assert unset optional lines remain absent**

After existing absent assertions, add:

```bash
assert_eq "unset optional graph absent" "0" "$(grep -c 'IWIKI_GRAPH_DEPTH' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "unset optional score absent" "0" "$(grep -c 'IWIKI_SCORE_THRESHOLD' "$ICODEX_HOME_DIR/config.toml")"
```

Definition of done: the test still proves unset optionals are not pinned into generated TOML.

- [ ] **Step 5: Add project-root guard scenario**

After the missing-key guard scenario and before the no-op home-unset scenario, add:

```bash
# --- guard: missing project root -> no region, returns 0 ---
unset ICODEX_PROJECT_ROOT
export ICODEX_HOME_DIR="$tmp/home-guard-project"
mkdir -p "$ICODEX_HOME_DIR"
printf 'model = "x"\n' > "$ICODEX_HOME_DIR/config.toml"
assert_exit "missing project root -> noop 0" 0 ensure_iwiki_wiring
assert_eq "guard project: no region" "0" "$(grep -cF '[mcp_servers.iwiki]' "$ICODEX_HOME_DIR/config.toml")"
export ICODEX_PROJECT_ROOT="$tmp/project-root"
unset ICODEX_IWIKI_PROJECT_DIR
```

Definition of done: missing project root becomes a non-failing no-region case.

- [ ] **Step 6: Add project root to the set-e regression subshell**

Inside the final `set -euo pipefail` subshell, after exporting `ICODEX_IWIKI_LLM_KEY`, add:

```bash
export ICODEX_PROJECT_ROOT="$tmp/project-root"
```

Definition of done: the regression subshell still exercises `ensure_iwiki_wiring` with all required values present.

- [ ] **Step 7: Run the focused wiring test and observe the expected failure**

Run:

```bash
bash tests/test_iwiki_wiring.sh
```

Expected before Task 3: failure that mentions missing `IWIKI_PROJECT_DIR`, the wrong manual project dir appearing, or a new optional line not found in generated TOML.

### Task 3: Extend iwiki TOML generation

**Files:**
- Modify: `lib/iwiki/iwiki.sh`
- Test: `tests/test_iwiki_wiring.sh`, `tests/test_iwiki_env.sh`, `tests/test_iwiki_binding.sh`

- [ ] **Step 1: Extend the optional variable list**

In `lib/iwiki/iwiki.sh`, replace:

```bash
_IWIKI_OPTIONAL_VARS="EMBED_MODEL EMBED_DIMENSIONS TOP_K SCORE_THRESHOLD GRAPH_DEPTH CHUNK_SIZE CHUNK_OVERLAP SUMMARY_MAX_CHARS"
```

with:

```bash
_IWIKI_OPTIONAL_VARS="EMBED_MODEL EMBED_DIMENSIONS TOP_K SCORE_THRESHOLD SEARCH_MODE RERANK_MODEL GRAPH_DEPTH SEED_TOP_K BFS_TOP_K SEED_THRESHOLD WRITE_SEED_THRESHOLD CHAT_MODEL CHUNK_SIZE CHUNK_OVERLAP SUMMARY_MAX_CHARS"
```

Definition of done: every optional variable named in spec requirement 3.1 is present exactly once in `_IWIKI_OPTIONAL_VARS`, and `PROJECT_DIR` is absent from that list.

- [ ] **Step 2: Update `_iwiki_region_body` signature and body**

Change:

```bash
_iwiki_region_body() { # <command> <base_dir> <llm_base_url>
  local cmd="$1" base="$2" url="$3" name cfg val
```

to:

```bash
_iwiki_region_body() { # <command> <base_dir> <llm_base_url> <project_dir>
  local cmd="$1" base="$2" url="$3" project="$4" name cfg val
```

After:

```bash
printf 'IWIKI_LLM_BASE_URL = "%s"\n' "$url"
```

add:

```bash
printf 'IWIKI_PROJECT_DIR = "%s"\n' "$project"
```

Definition of done: generated TOML always includes project root when the required tier resolves.

- [ ] **Step 3: Require and pass `ICODEX_PROJECT_ROOT`**

In `ensure_iwiki_wiring`, change:

```bash
local file="$ICODEX_HOME_DIR/config.toml" body tmp cmd base url key
```

to:

```bash
local file="$ICODEX_HOME_DIR/config.toml" body tmp cmd base url key project
```

After:

```bash
key="${ICODEX_IWIKI_LLM_KEY:-${IWIKI_LLM_KEY:-}}"
```

add:

```bash
project="${ICODEX_PROJECT_ROOT:-}"
```

Change the guard from:

```bash
if [[ -z "$cmd" || -z "$base" || -z "$url" || -z "$key" ]]; then
  log_warn "iwiki: required setting (command/base_dir/llm_base_url/llm_key) unresolved, skipping iwiki wiring"
  return 0
fi
body="$(_iwiki_region_body "$cmd" "$base" "$url")"
```

to:

```bash
if [[ -z "$cmd" || -z "$base" || -z "$url" || -z "$key" || -z "$project" ]]; then
  log_warn "iwiki: required setting (command/base_dir/llm_base_url/llm_key/project_root) unresolved, skipping iwiki wiring"
  return 0
fi
body="$(_iwiki_region_body "$cmd" "$base" "$url" "$project")"
```

Definition of done: missing project root skips wiring like other missing required values.

- [ ] **Step 4: Update the module comments**

In the header comment of `lib/iwiki/iwiki.sh`, update the summary so it says non-secret values include generated `IWIKI_PROJECT_DIR`, and the required guard includes project root. Keep the comment short:

```bash
# IWIKI_PROJECT_DIR is generated from ICODEX_PROJECT_ROOT so Codex-spawned
# iwiki-mcp resolves the project .iwiki.toml even when its cwd is CODEX_HOME.
```

Definition of done: comments match the runtime behavior without adding new policy.

- [ ] **Step 5: Run focused iwiki tests**

Run:

```bash
bash tests/test_iwiki_env.sh
bash tests/test_iwiki_wiring.sh
bash tests/test_iwiki_binding.sh
```

Expected: all three commands exit `0`; `tests/test_iwiki_wiring.sh` reports no missing generated project-dir or new optional lines.

- [ ] **Step 6: Commit code and tests**

Run:

```bash
git add lib/iwiki/iwiki.sh tests/test_iwiki_env.sh tests/test_iwiki_wiring.sh
git commit -m "fix(iwiki): generate project dir and expose reranker config"
```

Expected: commit succeeds and does not include `.codex_config` or `.iwiki.toml`.

### Task 4: Update `.codex_config.example`

**Files:**
- Modify: `.codex_config.example`
- Test: `.codex_config.example`

- [ ] **Step 1: Replace the iwiki example block**

In `.codex_config.example`, replace the iwiki section starting at:

```text
# iwiki MCP server (always on in every Codex home). The [mcp_servers.iwiki] block
```

through the final current iwiki example line with this block:

```text
# iwiki MCP server (always on in every Codex home). The [mcp_servers.iwiki] block
# is assembled at launch from the keys below (see lib/iwiki/iwiki.sh).
#
# Command + required tier (iwiki is NOT wired if a required value is missing):
#   ICODEX_IWIKI_COMMAND       Path to the iwiki-mcp binary. OPTIONAL:
#                              auto-detected via `command -v iwiki-mcp` when unset.
#   ICODEX_IWIKI_BASE_DIR      Personal wiki store path. REQUIRED.
#   ICODEX_IWIKI_LLM_BASE_URL  OpenAI-compatible endpoint base URL. REQUIRED.
#   ICODEX_IWIKI_LLM_KEY       Secret API key, forwarded as IWIKI_LLM_KEY via
#                              `env_vars`. REQUIRED, SECRET — never commit a real
#                              value.
#
# Project directory:
#   IWIKI_PROJECT_DIR is generated from the launched project root. Do not add
#   ICODEX_IWIKI_PROJECT_DIR here; icodex intentionally ignores that setting so
#   stale local config cannot point iwiki at the wrong project.
#
# Optional passthrough settings (written only if set; otherwise iwiki-mcp uses
# its own defaults):
#   ICODEX_IWIKI_EMBED_MODEL              (default text-embedding-3-small)
#   ICODEX_IWIKI_EMBED_DIMENSIONS         (default 1536; must match embed model)
#   ICODEX_IWIKI_TOP_K                    (default 8)
#   ICODEX_IWIKI_SCORE_THRESHOLD          (default 0.2)
#   ICODEX_IWIKI_SEARCH_MODE              (default hybrid; hybrid|lexical|semantic)
#   ICODEX_IWIKI_RERANK_MODEL             (default empty; optional reranker model)
#   ICODEX_IWIKI_GRAPH_DEPTH              (default 2)
#   ICODEX_IWIKI_SEED_TOP_K               (default 5)
#   ICODEX_IWIKI_BFS_TOP_K                (default 10)
#   ICODEX_IWIKI_SEED_THRESHOLD           (default 0.15)
#   ICODEX_IWIKI_WRITE_SEED_THRESHOLD     (default 0.35)
#   ICODEX_IWIKI_CHAT_MODEL               (default empty; optional classifier model)
#   ICODEX_IWIKI_CHUNK_SIZE               (default 512)
#   ICODEX_IWIKI_CHUNK_OVERLAP            (default 64)
#   ICODEX_IWIKI_SUMMARY_MAX_CHARS        (default 400)
#
#ICODEX_IWIKI_COMMAND=/home/you/.local/bin/iwiki-mcp
#ICODEX_IWIKI_BASE_DIR=/home/you/Documents/Project/iwiki-personal
#ICODEX_IWIKI_LLM_BASE_URL=http://localhost:11434/v1
#ICODEX_IWIKI_LLM_KEY=sk-...
#ICODEX_IWIKI_EMBED_MODEL=ollama-bge-m3
#ICODEX_IWIKI_EMBED_DIMENSIONS=1024
#ICODEX_IWIKI_SEARCH_MODE=hybrid
#ICODEX_IWIKI_RERANK_MODEL=
#ICODEX_IWIKI_SEED_TOP_K=5
#ICODEX_IWIKI_BFS_TOP_K=10
#ICODEX_IWIKI_SEED_THRESHOLD=0.15
#ICODEX_IWIKI_WRITE_SEED_THRESHOLD=0.35
#ICODEX_IWIKI_CHAT_MODEL=
```

Definition of done: example documents current supported runtime keys and explicitly says project dir is generated.

- [ ] **Step 2: Verify the example contains no real secret and no manual project-dir key**

Run:

```bash
grep -n '^[[:space:]]*ICODEX_IWIKI_PROJECT_DIR=' .codex_config.example || true
grep -n '^[[:space:]]*ICODEX_IWIKI_LLM_KEY=' .codex_config.example || true
grep -n '^#ICODEX_IWIKI_LLM_KEY=sk-\.\.\.' .codex_config.example
```

Expected: first two commands print nothing; the third command shows the commented placeholder `#ICODEX_IWIKI_LLM_KEY=sk-...`.

- [ ] **Step 3: Commit example docs**

Run:

```bash
git add .codex_config.example
git commit -m "docs(config): document iwiki reranker settings"
```

Expected: commit succeeds and does not include live `.codex_config`.

### Task 5: Update iwiki documentation and run verification

**Files:**
- Update via MCP: icodex wiki page `iwiki-mcp-integration`
- Verify: focused tests and full Bash suite

- [ ] **Step 1: Update the iwiki page section for optional variables**

Use `wiki_update_page(domain="icodex", slug="iwiki-mcp-integration", heading="Optional Server Variables", ...)` with this new body:

```markdown
The launch wrapper forwards optional server settings only when the matching `ICODEX_IWIKI_*` value is set:

- `EMBED_MODEL`
- `EMBED_DIMENSIONS`
- `TOP_K`
- `SCORE_THRESHOLD`
- `SEARCH_MODE`
- `RERANK_MODEL`
- `GRAPH_DEPTH`
- `SEED_TOP_K`
- `BFS_TOP_K`
- `SEED_THRESHOLD`
- `WRITE_SEED_THRESHOLD`
- `CHAT_MODEL`
- `CHUNK_SIZE`
- `CHUNK_OVERLAP`
- `SUMMARY_MAX_CHARS`

Unset optional values fall back to iwiki server defaults. `RERANK_MODEL` enables the upstream LiteLLM-compatible reranker; leaving it unset preserves the preliminary search order.
```

Definition of done: wiki page lists the new optionals and explains unset reranker behavior.

- [ ] **Step 2: Update the iwiki page section for project binding**

Use `wiki_update_page(domain="icodex", slug="iwiki-mcp-integration", heading="Project Binding", ...)` with this new body:

````markdown
`ensure_iwiki_binding` seeds `.iwiki.toml` in the project root when absent:

```toml
read = ["<project-basename>"]
write = "<project-basename>"
```

Existing project `.iwiki.toml` files are preserved as user truth. icodex also symlinks that file into `CODEX_HOME/.iwiki.toml` for compatibility.

The MCP server receives `IWIKI_PROJECT_DIR` generated from `ICODEX_PROJECT_ROOT`, so Codex-spawned `iwiki-mcp` resolves the project root explicitly even when its process cwd is the Codex home.

For this repository, the expected domain name is `icodex`.
````

Definition of done: wiki page states project root now comes from generated `IWIKI_PROJECT_DIR`.

- [ ] **Step 3: Run iwiki lint**

Run MCP `wiki_lint(domain="icodex")`.

Expected: no new broken references from the edited page. Pre-existing stale, missing frontmatter, or missing source findings may remain; record them as unrelated if unchanged.

- [ ] **Step 4: Run focused verification**

Run:

```bash
bash tests/test_iwiki_env.sh
bash tests/test_iwiki_wiring.sh
bash tests/test_iwiki_binding.sh
```

Expected: all commands exit `0`.

- [ ] **Step 5: Run full suite**

Run:

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: exit code `0`. If an unrelated pre-existing failure appears, capture the failing test and evidence before deciding whether to fix or report it.

- [ ] **Step 6: Commit wiki/docs evidence if repository files changed**

If only iwiki MCP pages changed, no repository commit is needed for the wiki base because iwiki tools auto-commit their base updates. If repository docs changed during this task, inspect those paths with `git status --short` and commit only the task-owned documentation paths. Expected: no live `.codex_config` or user-owned `.iwiki.toml` is staged.

### Task 6: Result reconciliation

**Files:**
- Modify: `docs/superpowers/plans/2026-07-16-icodex-iwiki-reranker-config.md`
- Verify: `git diff HEAD`, chain artifacts, final report

- [ ] **Step 1: Check working tree scope**

Run:

```bash
git status --short
```

Expected: changed files are limited to planned implementation files, chain artifacts, and allowed documentation outputs. `.codex_config` must not appear. `.iwiki.toml` may appear as a pre-existing unrelated user change and must not be staged.

- [ ] **Step 2: Run result gate**

Print the stored base SHA:

```bash
cat .git/icodex-iwiki-reranker-config.result-base
```

Expected: prints the same SHA stored before Task 1.

Invoke the result stage with `--since=` followed by the exact SHA printed above. This is a Codex skill invocation, not a shell command; the final argument must look like `--since=abc1234` with the stored full SHA value.

Expected: result reconciliation marks all plan tasks done, reports no missing required work, and records verification evidence from the full diff since the stored base SHA.

- [ ] **Step 3: Address result findings if any**

If result gate reports an open critical finding, fix the exact source file named by the finding, rerun the focused verification command named by the finding, and rerun:

```bash
cat .git/icodex-iwiki-reranker-config.result-base
```

Then rerun the result stage with `--since=` followed by the exact SHA printed above. This is a Codex skill invocation, not a shell command; the final argument must look like `--since=abc1234` with the stored full SHA value.

Expected: result verdict becomes `OK` before branch closeout.

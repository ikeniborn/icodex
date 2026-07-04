---
review:
  plan_hash: b41536e2c88bba83
  last_run: 2026-07-04
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-07-04-skill-subagents-intent.md
  spec: docs/superpowers/specs/2026-07-04-skill-subagents-design.md
result_check:
  verdict: OK
  plan_hash: b41536e2c88bba83
  last_run: 2026-07-04
---
# Skill Subagents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add tracked custom agents to the isolated icodex environment and route five existing skills through trust-first subagent guidance.

**Architecture:** `.codex-isolated/agents` becomes a tracked shared store linked into each per-project `CODEX_HOME`, matching the existing `skills` and `rules` pattern. Custom TOML agents define model and reasoning choices, while each target skill gets a concise `## Subagent Routing` section that tells the main agent when to delegate and when to keep control.

**Tech Stack:** Bash launcher modules, Bash tests, Python stdlib `tomllib` for TOML smoke checks, Codex `SKILL.md` instructions, Codex custom agent TOML files.

---

## File Structure

- Modify `.gitignore`: whitelist `.codex-isolated/agents/` and its files.
- Modify `lib/config/isolated.sh`: link the shared `agents` directory into per-project `CODEX_HOME`.
- Modify `tests/test_isolated.sh`: prove generated homes expose `agents` as a shared symlink.
- Modify `tests/test_gitignore.sh`: prove custom agent files are tracked-eligible.
- Create `tests/test_agent_configs.sh`: parse custom agent TOML files and verify required keys, model choices, reasoning effort, sandbox mode, and summary-contract wording.
- Create `.codex-isolated/agents/chain-auditor.toml`: high-trust IDD chain auditor.
- Create `.codex-isolated/agents/artifact-renderer.toml`: medium-reasoning HTML artifact reviewer.
- Create `.codex-isolated/agents/diagram-checker.toml`: medium-reasoning Mermaid/Obsidian checker.
- Create `.codex-isolated/agents/repo-safety-reviewer.toml`: high-trust git risk reviewer.
- Create `.codex-isolated/agents/project-explorer.toml`: low-reasoning read-only project scanner.
- Create `tests/test_skill_routing.sh`: verify each target skill names its intended agent and summary contract.
- Modify `.codex-isolated/skills/check-chain/SKILL.md`: add routing for `chain-auditor`.
- Modify `.codex-isolated/skills/html-report/SKILL.md`: add routing for `artifact-renderer`.
- Modify `.codex-isolated/skills/mermaid-obsidian/SKILL.md`: add routing for `diagram-checker`.
- Modify `.codex-isolated/skills/git-workflow/SKILL.md`: add routing for `repo-safety-reviewer`.
- Modify `.codex-isolated/skills/context-awareness/SKILL.md`: add routing for `project-explorer`.

## Task 1: Runtime Agent Wiring

**Files:**
- Modify: `tests/test_isolated.sh`
- Modify: `tests/test_gitignore.sh`
- Modify: `.gitignore`
- Modify: `lib/config/isolated.sh`

- [ ] **Step 1: Add failing isolated-home wiring assertions**

In `tests/test_isolated.sh`, add an agents fixture after the skills fixture:

```bash
# agents fixture: project-scoped custom agents shared into each CODEX_HOME
mkdir -p "$ICODEX_SHARED_DIR/agents"
printf 'name = "sample-agent"\n' > "$ICODEX_SHARED_DIR/agents/sample-agent.toml"
```

Then add assertions after the existing `rules` symlink assertions:

```bash
assert_exit "agents symlink"     0 test -L "$ICODEX_HOME_DIR/agents"
assert_eq  "agents -> shared"    "$ICODEX_SHARED_DIR/agents" "$(readlink "$ICODEX_HOME_DIR/agents")"
```

- [ ] **Step 2: Add failing gitignore tracking assertion**

In `tests/test_gitignore.sh`, add this assertion after the `rules are tracked` assertion:

```bash
assert_exit "agents are tracked"       1 ci .codex-isolated/agents/chain-auditor.toml
```

- [ ] **Step 3: Run the focused tests and verify the expected failures**

Run:

```bash
bash tests/test_isolated.sh
```

Expected: non-zero exit with `FAIL [agents symlink]` because `setup_codex_home` does not link `agents` yet.

Run:

```bash
bash tests/test_gitignore.sh
```

Expected: non-zero exit with `FAIL [agents are tracked]` because `.codex-isolated/agents` is still ignored by the whitelist model.

- [ ] **Step 4: Whitelist the agents directory**

In `.gitignore`, add this block after the `rules` whitelist:

```gitignore
!.codex-isolated/agents/
!.codex-isolated/agents/**
```

- [ ] **Step 5: Link shared agents into per-project homes**

In `lib/config/isolated.sh`, add `_link_shared agents` in `setup_codex_home` after `_link_shared rules`:

```bash
  _link_shared skills      # user skills -> runtime (variant A: whole-dir symlink)
  _link_shared rules       # codex execution-policy -> runtime
  _link_shared agents      # custom subagents -> runtime
```

- [ ] **Step 6: Run focused tests and verify they pass**

Run:

```bash
bash tests/test_isolated.sh
```

Expected: exit 0 with `PASS [agents symlink]` and `PASS [agents -> shared]`.

Run:

```bash
bash tests/test_gitignore.sh
```

Expected: exit 0 with `PASS [agents are tracked]`.

- [ ] **Step 7: Commit runtime wiring**

Run:

```bash
git add .gitignore lib/config/isolated.sh tests/test_isolated.sh tests/test_gitignore.sh
git commit -m "feat(isolation): wire custom agents into codex home"
```

Expected: commit succeeds on branch `dev-skill-subagents`.

## Task 2: Custom Agent Configs

**Files:**
- Create: `tests/test_agent_configs.sh`
- Create: `.codex-isolated/agents/chain-auditor.toml`
- Create: `.codex-isolated/agents/artifact-renderer.toml`
- Create: `.codex-isolated/agents/diagram-checker.toml`
- Create: `.codex-isolated/agents/repo-safety-reviewer.toml`
- Create: `.codex-isolated/agents/project-explorer.toml`

- [ ] **Step 1: Create the failing agent config smoke test**

Create `tests/test_agent_configs.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
cd "$ROOT"

assert_exit "agent configs parse and match contract" 0 python3 - <<'PY'
from pathlib import Path
import sys
import tomllib

root = Path(".codex-isolated/agents")
expected = {
    "chain-auditor.toml": {
        "name": "chain-auditor",
        "model": "gpt-5.5",
        "model_reasoning_effort": "high",
        "sandbox_mode": "read-only",
        "phrases": ["check-chain", "CRITICAL", "frontmatter", "decision", "evidence", "risks", "next_action"],
    },
    "artifact-renderer.toml": {
        "name": "artifact-renderer",
        "model": "gpt-5.4-mini",
        "model_reasoning_effort": "medium",
        "sandbox_mode": "read-only",
        "phrases": ["html-report", "zero-dependency", "chain-tab", "decision", "evidence", "risks", "next_action"],
    },
    "diagram-checker.toml": {
        "name": "diagram-checker",
        "model": "gpt-5.4-mini",
        "model_reasoning_effort": "medium",
        "sandbox_mode": "read-only",
        "phrases": ["mermaid-obsidian", "Obsidian", "syntax", "decision", "evidence", "risks", "next_action"],
    },
    "repo-safety-reviewer.toml": {
        "name": "repo-safety-reviewer",
        "model": "gpt-5.5",
        "model_reasoning_effort": "high",
        "sandbox_mode": "read-only",
        "phrases": ["git-workflow", "branch", "commit", "decision", "evidence", "risks", "next_action"],
    },
    "project-explorer.toml": {
        "name": "project-explorer",
        "model": "gpt-5.4-mini",
        "model_reasoning_effort": "low",
        "sandbox_mode": "read-only",
        "phrases": ["context-awareness", "project_context", "iwiki", "decision", "evidence", "risks", "next_action"],
    },
}

errors = []
if not root.is_dir():
    errors.append(f"missing directory: {root}")

for filename, want in expected.items():
    path = root / filename
    if not path.is_file():
        errors.append(f"missing file: {path}")
        continue
    data = tomllib.loads(path.read_text())
    for key in ("name", "description", "developer_instructions", "model", "model_reasoning_effort", "sandbox_mode"):
        if key not in data:
            errors.append(f"{path}: missing {key}")
    for key in ("name", "model", "model_reasoning_effort", "sandbox_mode"):
        if data.get(key) != want[key]:
            errors.append(f"{path}: {key}={data.get(key)!r}, want {want[key]!r}")
    instructions = data.get("developer_instructions", "")
    if "Do not modify files." not in instructions:
        errors.append(f"{path}: instructions must forbid file modification")
    for phrase in want["phrases"]:
        if phrase not in instructions:
            errors.append(f"{path}: missing phrase {phrase!r}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
PY

finish
```

- [ ] **Step 2: Run the smoke test and verify it fails**

Run:

```bash
bash tests/test_agent_configs.sh
```

Expected: non-zero exit with `FAIL [agent configs parse and match contract]` because `.codex-isolated/agents/*.toml` does not exist yet.

- [ ] **Step 3: Create `chain-auditor`**

Create `.codex-isolated/agents/chain-auditor.toml`:

```toml
name = "chain-auditor"
description = "Read-only reviewer for check-chain phase scans, hash evidence, findings, and result reconciliation drafts."
model = "gpt-5.5"
model_reasoning_effort = "high"
sandbox_mode = "read-only"
developer_instructions = """
You support the check-chain skill.
Work only as a read-only auditor. Do not modify files.
Focus on IDD/SDD trust: CRITICAL findings, canonical body hashes, frontmatter state, result reconciliation, report readiness, and task-log readiness.
Return a concise structured summary with exactly these labels:
decision: OK, needs_work, or uncertain.
evidence: file paths, hashes, phase names, findings, and diff paths that support the decision.
risks: blocking findings, uncertainty, missing artifacts, stale hashes, or unsafe assumptions.
next_action: the smallest action the main agent should take next.
The main agent owns confirmations, frontmatter writes, report merges, task-log updates, and downstream chain decisions.
"""
```

- [ ] **Step 4: Create `artifact-renderer`**

Create `.codex-isolated/agents/artifact-renderer.toml`:

```toml
name = "artifact-renderer"
description = "Read-only reviewer for html-report recipe selection, source coverage, and self-contained report validation."
model = "gpt-5.4-mini"
model_reasoning_effort = "medium"
sandbox_mode = "read-only"
developer_instructions = """
You support the html-report skill.
Work only as a read-only artifact reviewer. Do not modify files.
Focus on zero-dependency HTML, source coverage, requested data points, chain-tab marker safety, theme toggle integrity, and self-validation evidence.
Return a concise structured summary with exactly these labels:
decision: OK, needs_work, or uncertain.
evidence: source paths, selected recipe, data coverage, marker checks, and validation checks.
risks: missing data, external resource needs, tab corruption, size warnings, or ambiguity.
next_action: the smallest action the main agent should take next.
The main agent owns ambiguous source selection, final file writes, and user-facing output reporting.
"""
```

- [ ] **Step 5: Create `diagram-checker`**

Create `.codex-isolated/agents/diagram-checker.toml`:

```toml
name = "diagram-checker"
description = "Read-only reviewer for mermaid-obsidian syntax, Obsidian constraints, and render-risk notes."
model = "gpt-5.4-mini"
model_reasoning_effort = "medium"
sandbox_mode = "read-only"
developer_instructions = """
You support the mermaid-obsidian skill.
Work only as a read-only diagram reviewer. Do not modify files.
Focus on Mermaid syntax, Obsidian 11.4.1 constraints, safe node IDs, quoted labels, reserved words, theme init, color contrast, and render-risk notes.
Return a concise structured summary with exactly these labels:
decision: OK, needs_work, or uncertain.
evidence: Mermaid lines, fixed rule violations, and Obsidian-specific constraints checked.
risks: semantic ambiguity, render quirks, invalid IDs, unsupported labels, or unresolved syntax.
next_action: the smallest action the main agent should take next.
The main agent owns semantic questions, final diagram text, and file edits.
"""
```

- [ ] **Step 6: Create `repo-safety-reviewer`**

Create `.codex-isolated/agents/repo-safety-reviewer.toml`:

```toml
name = "repo-safety-reviewer"
description = "Read-only reviewer for git-workflow branch safety, staged-file scope, commit readiness, and PR readiness."
model = "gpt-5.5"
model_reasoning_effort = "high"
sandbox_mode = "read-only"
developer_instructions = """
You support the git-workflow skill.
Work only as a read-only repository safety reviewer. Do not modify files.
Focus on branch state, dirty files, unrelated changes, secrets risk, staged-file scope, validation evidence, commit message quality, and PR readiness.
Return a concise structured summary with exactly these labels:
decision: OK, needs_work, or uncertain.
evidence: branch name, changed files, staged files, relevant diffs, validation commands, and commit-message rationale.
risks: wrong branch, protected branch, unrelated dirty files, untracked secrets, missing validation, or unclear base branch.
next_action: the smallest action the main agent should take next.
The main agent owns every mutating git command: checkout, branch creation, add, commit, push, and PR creation.
"""
```

- [ ] **Step 7: Create `project-explorer`**

Create `.codex-isolated/agents/project-explorer.toml`:

```toml
name = "project-explorer"
description = "Read-only scanner for context-awareness project signals, docs layout, iwiki status, and test-command hints."
model = "gpt-5.4-mini"
model_reasoning_effort = "low"
sandbox_mode = "read-only"
developer_instructions = """
You support the context-awareness skill.
Work only as a read-only project scanner. Do not modify files.
Focus on project_context signals: language files, framework files, test files, docs layout, PRD hints, iwiki status, and candidate syntax or test commands.
Return a concise structured summary with exactly these labels:
decision: OK, needs_work, or uncertain.
evidence: file paths, detected signals, docs paths, iwiki signals, and command hints.
risks: contradictory project signals, missing docs, unavailable iwiki data, or uncertain test command choice.
next_action: the smallest action the main agent should take next.
The main agent owns final project_context synthesis, task-specific documentation interpretation, and deep semantic wiki searches.
"""
```

- [ ] **Step 8: Run the agent config smoke test**

Run:

```bash
bash tests/test_agent_configs.sh
```

Expected: exit 0 with `PASS [agent configs parse and match contract]`.

- [ ] **Step 9: Commit agent configs and smoke test**

Run:

```bash
git add tests/test_agent_configs.sh .codex-isolated/agents
git commit -m "feat(agents): add trust-first skill subagents"
```

Expected: commit succeeds and includes five TOML files plus `tests/test_agent_configs.sh`.

## Task 3: Skill Routing Sections

**Files:**
- Create: `tests/test_skill_routing.sh`
- Modify: `.codex-isolated/skills/check-chain/SKILL.md`
- Modify: `.codex-isolated/skills/html-report/SKILL.md`
- Modify: `.codex-isolated/skills/mermaid-obsidian/SKILL.md`
- Modify: `.codex-isolated/skills/git-workflow/SKILL.md`
- Modify: `.codex-isolated/skills/context-awareness/SKILL.md`

- [ ] **Step 1: Create the failing skill routing smoke test**

Create `tests/test_skill_routing.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
cd "$ROOT"

check_skill() { # <skill-path> <agent-name> <main-owned-phrase>
  local path="$1" agent="$2" owned="$3" text
  text="$(cat "$path" 2>/dev/null || true)"
  assert_contains "$path has routing section" "$text" "## Subagent Routing"
  assert_contains "$path names $agent" "$text" "Agent: \`$agent\`"
  assert_contains "$path keeps main ownership" "$text" "$owned"
  assert_contains "$path summary decision" "$text" "decision"
  assert_contains "$path summary evidence" "$text" "evidence"
  assert_contains "$path summary risks" "$text" "risks"
  assert_contains "$path summary next_action" "$text" "next_action"
}

check_skill ".codex-isolated/skills/check-chain/SKILL.md" "chain-auditor" "Main context keeps confirmations, final verdicts, frontmatter writes, report merges, task-log row updates, and downstream stop/go decisions."
check_skill ".codex-isolated/skills/html-report/SKILL.md" "artifact-renderer" "Main context keeps ambiguous source selection, final file writes, and user-facing output reporting."
check_skill ".codex-isolated/skills/mermaid-obsidian/SKILL.md" "diagram-checker" "Main context keeps semantic questions, final diagram text, and file edits."
check_skill ".codex-isolated/skills/git-workflow/SKILL.md" "repo-safety-reviewer" "Main context keeps all mutating git commands: checkout, branch creation, add, commit, push, and PR creation."
check_skill ".codex-isolated/skills/context-awareness/SKILL.md" "project-explorer" "Main context keeps final project_context synthesis, task-specific documentation interpretation, and deep semantic wiki searches."

finish
```

- [ ] **Step 2: Run the routing smoke test and verify it fails**

Run:

```bash
bash tests/test_skill_routing.sh
```

Expected: non-zero exit with missing `## Subagent Routing` failures.

- [ ] **Step 3: Add routing to `check-chain`**

In `.codex-isolated/skills/check-chain/SKILL.md`, insert this section after the introductory paragraph that ends with "former `check-intent`, `check-spec`, `check-plan`, `check-result` commands.":

```markdown
## Subagent Routing

Agent: `chain-auditor`

Use a subagent when phase scans, section-hash evidence, result diff reconciliation, or report/task-log update checks would pollute the main context with large intermediate output.

Stay in the main context for user confirmations, final verdict handling, frontmatter writes, HTML report merges, task-log row updates, and downstream chain stop/go decisions.

Return summary:
- decision: `OK`, `needs_work`, or `uncertain`
- evidence: artifact paths, hashes, phases, findings, and matched diff paths
- risks: CRITICAL findings, stale hashes, missing artifacts, unresolved verdicts, or uncertainty
- next_action: the smallest main-context action required

Stop rule: any CRITICAL finding, hash mismatch uncertainty, missing artifact, or result reconciliation uncertainty halts downstream stages until the main context resolves it. Main context keeps confirmations, final verdicts, frontmatter writes, report merges, task-log row updates, and downstream stop/go decisions.
```

- [ ] **Step 4: Add routing to `html-report`**

In `.codex-isolated/skills/html-report/SKILL.md`, insert this section after the opening paragraph that ends with "human-readable artifact.":

```markdown
## Subagent Routing

Agent: `artifact-renderer`

Use a subagent when recipe selection, data-source coverage, chain-tab marker checks, or self-validation would add noisy intermediate HTML analysis to the main context.

Stay in the main context for ambiguous source selection, final file writes, and user-facing output reporting.

Return summary:
- decision: `OK`, `needs_work`, or `uncertain`
- evidence: selected recipe, source paths, requested data coverage, marker checks, and validation checks
- risks: missing data, external resource needs, non-self-contained output, chain-tab corruption, or size warnings
- next_action: the smallest main-context action required

Stop rule: missing source data, an external resource requirement, non-self-contained output, or tab corruption uncertainty stops the write. Main context keeps ambiguous source selection, final file writes, and user-facing output reporting.
```

- [ ] **Step 5: Add routing to `mermaid-obsidian`**

In `.codex-isolated/skills/mermaid-obsidian/SKILL.md`, insert this section after "Produce correct, styled Mermaid diagrams that render reliably in Obsidian.":

```markdown
## Subagent Routing

Agent: `diagram-checker`

Use a subagent when a diagram needs syntax linting, Obsidian constraint review, corrected Mermaid drafting, or render-risk notes that would crowd the main context.

Stay in the main context for semantic questions, final diagram text, and file edits.

Return summary:
- decision: `OK`, `needs_work`, or `uncertain`
- evidence: Mermaid lines reviewed, Obsidian constraints checked, and rule violations fixed
- risks: semantic ambiguity, invalid node IDs, unsupported labels, reserved words, contrast issues, or render quirks
- next_action: the smallest main-context action required

Stop rule: if graph semantics are ambiguous, ask the user instead of inventing structure. Main context keeps semantic questions, final diagram text, and file edits.
```

- [ ] **Step 6: Add routing to `git-workflow`**

In `.codex-isolated/skills/git-workflow/SKILL.md`, insert this section after "# Git Workflow v2.2":

```markdown
## Subagent Routing

Agent: `repo-safety-reviewer`

Use a subagent when branch status, dirty-file scope, diff review, staged-file planning, commit-message drafting, or PR readiness needs isolated read-only analysis.

Stay in the main context for all mutating git commands: checkout, branch creation, add, commit, push, and PR creation.

Return summary:
- decision: `OK`, `needs_work`, or `uncertain`
- evidence: current branch, relevant changed files, staged files, validation commands, and commit-message rationale
- risks: wrong branch, protected branch, unrelated dirty files, untracked secrets, missing validation, or unclear base branch
- next_action: the smallest main-context action required

Stop rule: unrelated dirty files, wrong branch, untracked secrets, missing validation, or unclear base branch blocks mutation until resolved. Main context keeps all mutating git commands: checkout, branch creation, add, commit, push, and PR creation.
```

- [ ] **Step 7: Add routing to `context-awareness`**

In `.codex-isolated/skills/context-awareness/SKILL.md`, insert this section after "# Context Awareness":

```markdown
## Subagent Routing

Agent: `project-explorer`

Use a subagent when file layout, docs skeleton, iwiki status, language/framework hints, or candidate syntax/test command discovery can be scanned read-only and summarized.

Stay in the main context for final project_context synthesis, task-specific documentation interpretation, and deep semantic wiki searches.

Return summary:
- decision: `OK`, `needs_work`, or `uncertain`
- evidence: file paths, detected signals, docs paths, iwiki signals, and command hints
- risks: contradictory project signals, missing docs, unavailable iwiki data, or uncertain test command choice
- next_action: the smallest main-context action required

Stop rule: contradictory project signals are reported as ambiguity; the main context decides or asks. Main context keeps final project_context synthesis, task-specific documentation interpretation, and deep semantic wiki searches.
```

- [ ] **Step 8: Run routing smoke test**

Run:

```bash
bash tests/test_skill_routing.sh
```

Expected: exit 0 with every `PASS [...]` line and `FAIL=0`.

- [ ] **Step 9: Commit skill routing**

Run:

```bash
git add tests/test_skill_routing.sh .codex-isolated/skills/check-chain/SKILL.md .codex-isolated/skills/html-report/SKILL.md .codex-isolated/skills/mermaid-obsidian/SKILL.md .codex-isolated/skills/git-workflow/SKILL.md .codex-isolated/skills/context-awareness/SKILL.md
git commit -m "docs(skills): add subagent routing guidance"
```

Expected: commit succeeds and includes the routing test plus five skill edits.

## Task 4: Final Verification, Wiki, And Chain Result

**Files and systems:**
- Verify: `tests/test_agent_configs.sh`
- Verify: `tests/test_skill_routing.sh`
- Verify: `tests/test_isolated.sh`
- Verify: `tests/test_gitignore.sh`
- Verify: all `tests/test_*.sh`
- Update: iwiki domain `icodex`, page slug `skill-subagents`
- Validate: `docs/superpowers/plans/2026-07-04-skill-subagents.md`

- [ ] **Step 1: Run focused verification**

Run:

```bash
bash tests/test_isolated.sh
bash tests/test_gitignore.sh
bash tests/test_agent_configs.sh
bash tests/test_skill_routing.sh
```

Expected: every command exits 0 and ends with `FAIL=0`.

- [ ] **Step 2: Run the full suite**

Run:

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: exit 0. If a test fails, stop and fix the failing task before continuing.

- [ ] **Step 3: Inspect git diff for accidental scope**

Run:

```bash
git diff --stat HEAD
git diff --name-only HEAD
```

Expected changed paths are limited to:

```text
.gitignore
.codex-isolated/agents/chain-auditor.toml
.codex-isolated/agents/artifact-renderer.toml
.codex-isolated/agents/diagram-checker.toml
.codex-isolated/agents/repo-safety-reviewer.toml
.codex-isolated/agents/project-explorer.toml
.codex-isolated/skills/check-chain/SKILL.md
.codex-isolated/skills/html-report/SKILL.md
.codex-isolated/skills/mermaid-obsidian/SKILL.md
.codex-isolated/skills/git-workflow/SKILL.md
.codex-isolated/skills/context-awareness/SKILL.md
lib/config/isolated.sh
tests/test_agent_configs.sh
tests/test_gitignore.sh
tests/test_isolated.sh
tests/test_skill_routing.sh
```

- [ ] **Step 4: Update iwiki**

Use the iwiki MCP tools. First run `wiki_status`; if domain `icodex` is bound or available, bind it for read/write. Then write or update page slug `skill-subagents` with this body:

```markdown
# Skill Subagents

## Overview
icodex stores custom Codex agents in `.codex-isolated/agents` and links that directory into each per-project `CODEX_HOME/agents`. This keeps agent definitions inside the isolated icodex environment and makes them git-tracked with the rest of shareable Codex assets.

## Runtime Wiring
`setup_codex_home` links `.codex-isolated/agents` into the generated per-project home alongside `skills`, `rules`, `hooks`, and plugins. Tests cover both the symlink and the gitignore whitelist.

## Agent Catalog
- `chain-auditor`: `gpt-5.5`, high reasoning, read-only support for `check-chain`.
- `artifact-renderer`: `gpt-5.4-mini`, medium reasoning, read-only support for `html-report`.
- `diagram-checker`: `gpt-5.4-mini`, medium reasoning, read-only support for `mermaid-obsidian`.
- `repo-safety-reviewer`: `gpt-5.5`, high reasoning, read-only support for `git-workflow`.
- `project-explorer`: `gpt-5.4-mini`, low reasoning, read-only support for `context-awareness`.

## Trust Boundary
Subagents analyze, draft, validate, and summarize. The main agent keeps final writes, git mutations, user confirmations, IDD/SDD gate transitions, and user-facing verdicts. Every subagent summary returns `decision`, `evidence`, `risks`, and `next_action`.
```

Then run `wiki_lint` for domain `icodex`.

Expected: `wiki_lint` reports no broken refs, no stale pages, and no missing source for the new page.

- [ ] **Step 5: Commit wiki-triggering local code state if any files remain uncommitted**

Run:

```bash
git status --short
```

Expected: no uncommitted local repository files except check-chain state generated in Step 6. The iwiki MCP may maintain its own external base; do not manually edit that base from this repository.

- [ ] **Step 6: Run result reconciliation after implementation**

Run the `check-chain` skill for the result stage using:

```text
check-chain result docs/superpowers/plans/2026-07-04-skill-subagents.md
```

Expected: result verdict `OK`, report `docs/superpowers/reports/skill-subagents-results.html` has the Result tab updated, and the task-log row for `skill-subagents` is closed.

- [ ] **Step 7: Commit chain result artifacts**

Run:

```bash
git add docs/superpowers/plans/2026-07-04-skill-subagents.md docs/superpowers/reports/skill-subagents-results.html docs/[T]ODO.md
git commit -m "docs(chain): validate skill subagents result"
```

Expected: commit succeeds after result reconciliation writes plan frontmatter/report/task-log state.

# 00 LoEn Overview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `00-loen-overview` a checkable umbrella design that links every LoEn layer spec, records global TODO tracking, preserves LoEn independence, and identifies the layer that owns each runtime behavior.

**Architecture:** Keep the overview as a documentation-only contract; layer-specific implementation stays in the six layer specs and their own plans. Add one focused Bash doc test that verifies the overview links, TODO rows, repository boundaries, independence statements, and runtime behavior ownership table. Normalize only the overview document and LoEn rows in `docs/TODO.md`; do not create plugin runtime code in this plan.

**Tech Stack:** Markdown, Bash, dependency-free `tests/helpers.sh`.

Spec: `docs/superpowers/specs/2026-07-02-00-loen-overview-design.md`

---

## Scope Check

This spec is an umbrella design, not the implementation of all LoEn layers. It should produce working, testable documentation coverage for the overview only. Plugin source, runtime artifacts, hooks, agents, icodex wiring, and automation governance remain owned by layer-specific specs `01` through `06`.

## File Structure

- **Create** `tests/test_loen_overview_docs.sh` - acceptance test for the overview design contract.
- **Modify** `docs/superpowers/specs/2026-07-02-00-loen-overview-design.md` - convert layer spec names into real Markdown links and add runtime behavior ownership.
- **Modify** `docs/TODO.md` - keep exactly one row for each LoEn overview/layer topic.
- **Do not modify** `plugins/loen/`, `lib/`, `.codex-isolated/plugins/cache/`, or layer specs `01` through `06` in this plan.

## Execution Prerequisites

Use the project branch workflow before Task 1. If no suitable `dev-*` branch already exists, use `git-workflow` and `superpowers:using-git-worktrees`: ask whether to create a worktree, then create a branch such as `dev-00-loen-overview` from the intended base branch. Run all commands from the repository root.

---

### Task 1: Add Overview Contract Test

**Files:**
- Create: `tests/test_loen_overview_docs.sh`
- Read: `docs/superpowers/specs/2026-07-02-00-loen-overview-design.md`
- Read: `docs/TODO.md`

- [ ] **Step 1: Write the failing test**

Create `tests/test_loen_overview_docs.sh` with:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

overview="$ROOT/docs/superpowers/specs/2026-07-02-00-loen-overview-design.md"
todo="$ROOT/docs/TODO.md"

assert_exit "overview spec exists" 0 test -f "$overview"
assert_exit "TODO index exists" 0 test -f "$todo"

if [[ ! -f "$overview" || ! -f "$todo" ]]; then
  finish; exit $?
fi

overview_body="$(cat "$overview")"
todo_body="$(cat "$todo")"

layer_topics=(
  "01-loen-plugin-core"
  "02-loen-runtime-artifacts"
  "03-loen-enforcement-hooks"
  "04-loen-agent-isolation"
  "05-loen-icodex-integration"
  "06-loen-automation-governance"
)

layer_specs=(
  "docs/superpowers/specs/2026-07-02-01-loen-plugin-core-design.md"
  "docs/superpowers/specs/2026-07-02-02-loen-runtime-artifacts-design.md"
  "docs/superpowers/specs/2026-07-02-03-loen-enforcement-hooks-design.md"
  "docs/superpowers/specs/2026-07-02-04-loen-agent-isolation-design.md"
  "docs/superpowers/specs/2026-07-02-05-loen-icodex-integration-design.md"
  "docs/superpowers/specs/2026-07-02-06-loen-automation-governance-design.md"
)

for i in "${!layer_topics[@]}"; do
  topic="${layer_topics[$i]}"
  rel="${layer_specs[$i]}"
  base="$(basename "$rel")"
  expected_link='[`'"$topic"'`]('"$base"')'

  assert_exit "layer spec exists: $topic" 0 test -f "$ROOT/$rel"
  assert_contains "overview links $topic" "$overview_body" "$expected_link"
done

todo_topics=(
  "00-loen-overview"
  "01-loen-plugin-core"
  "02-loen-runtime-artifacts"
  "03-loen-enforcement-hooks"
  "04-loen-agent-isolation"
  "05-loen-icodex-integration"
  "06-loen-automation-governance"
)

for topic in "${todo_topics[@]}"; do
  assert_eq "TODO one row: $topic" "1" "$(grep -cF "| $topic |" "$todo")"
done

assert_contains "overview source boundary" "$overview_body" "plugins/loen/"
assert_contains "overview cache boundary" "$overview_body" ".codex-isolated/plugins/cache/<marketplace>/loen/<version>/"
assert_contains "overview task artifact boundary" "$overview_body" "docs/loen/<topic>/"
assert_contains "overview global registry boundary" "$overview_body" "docs/TODO.md remains the only global human-readable task index"

assert_contains "independent from IDD chain" "$overview_body" "LoEn is not an extension of the current IDD->SDD chain"
assert_contains "independent from Superpowers" "$overview_body" "does not depend on the Superpowers plugin"
assert_contains "legacy iwiki excluded" "$overview_body" 'Do not depend on `lib/plugin/iwiki.sh`'

assert_contains "runtime behavior section present" "$overview_body" "## Runtime Behavior Ownership"

behavior_rows=(
  '| Editable plugin source, manifest, skills, templates, inert hook assets, and agent asset names | [`01-loen-plugin-core`](2026-07-02-01-loen-plugin-core-design.md) |'
  '| Topic artifact contract, `loop.yaml`, per-topic `audit.html`, and TODO row rules | [`02-loen-runtime-artifacts`](2026-07-02-02-loen-runtime-artifacts-design.md) |'
  '| Blocking/advisory loop gates, scope guard, tool guard, permission guard, evidence gate, and audit writer behavior | [`03-loen-enforcement-hooks`](2026-07-02-03-loen-enforcement-hooks-design.md) |'
  '| Planner/worker/verifier/reviewer/researcher role separation, context capsules, Codex profile split, and WASM-first verifier model | [`04-loen-agent-isolation`](2026-07-02-04-loen-agent-isolation-design.md) |'
  '| Vendoring, launch-time marketplace wiring, `ICODEX_LOEN_MODE`, and off/advisory/enforce/strict runtime enablement in icodex | [`05-loen-icodex-integration`](2026-07-02-05-loen-icodex-integration-design.md) |'
  '| Scheduled/background loop governance, human-review counters, and no-auto-merge policy | [`06-loen-automation-governance`](2026-07-02-06-loen-automation-governance-design.md) |'
)

for row in "${behavior_rows[@]}"; do
  assert_contains "runtime behavior owner: $row" "$overview_body" "$row"
done

finish
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bash tests/test_loen_overview_docs.sh
```

Expected: FAIL. The current overview has plain text spec names instead of Markdown links and has no `## Runtime Behavior Ownership` table. Expected failing lines include:

```text
FAIL [overview links 01-loen-plugin-core]
FAIL [runtime behavior section present]
FAIL [runtime behavior owner: | Editable plugin source, manifest, skills, templates, inert hook assets, and agent asset names | [`01-loen-plugin-core`](2026-07-02-01-loen-plugin-core-design.md) |]
```

- [ ] **Step 3: Syntax-check the new test**

Run:

```bash
bash -n tests/test_loen_overview_docs.sh
```

Expected: exit code `0`.

---

### Task 2: Link Layer Specs and Add Runtime Behavior Ownership

**Files:**
- Modify: `docs/superpowers/specs/2026-07-02-00-loen-overview-design.md`
- Test: `tests/test_loen_overview_docs.sh`

- [ ] **Step 1: Replace the Layered Scope section**

In `docs/superpowers/specs/2026-07-02-00-loen-overview-design.md`, replace the whole `## Layered Scope` section, from `## Layered Scope` through the paragraph ending with `implementation plan.`, with:

```markdown
## Layered Scope

LoEn is split into sequential layer specs. Each linked layer owns its own
acceptance criteria and implementation plan.

| Order | Topic | Spec | Scope |
|---|---|---|---|
| 1 | [`01-loen-plugin-core`](2026-07-02-01-loen-plugin-core-design.md) | Plugin source tree, manifest, skills, templates | Editable source and inert assets |
| 2 | [`02-loen-runtime-artifacts`](2026-07-02-02-loen-runtime-artifacts-design.md) | `docs/loen/<topic>/` artifacts and `audit.html` | Durable task state |
| 3 | [`03-loen-enforcement-hooks`](2026-07-02-03-loen-enforcement-hooks-design.md) | Loop gates, scope guard, tool guard, permission guard, evidence gate | Deterministic enforcement |
| 4 | [`04-loen-agent-isolation`](2026-07-02-04-loen-agent-isolation-design.md) | Agent roles, context capsules, Codex profile split, WASM verifier | Worker/verifier separation |
| 5 | [`05-loen-icodex-integration`](2026-07-02-05-loen-icodex-integration-design.md) | Vendoring, launch-time wiring, config/cache integration | icodex adapter |
| 6 | [`06-loen-automation-governance`](2026-07-02-06-loen-automation-governance-design.md) | Later L3 automations and governance loops | Scheduled/background governance |

The overview only defines shared boundaries and sequencing. Each layer owns its
own acceptance criteria and implementation plan.
```

- [ ] **Step 2: Insert runtime behavior ownership before Repository Boundaries**

In the same file, insert this section between the Layered Scope section and `## Repository Boundaries`:

```markdown
## Runtime Behavior Ownership

Each runtime behavior is introduced by one layer. Later layers may consume that
behavior, but should not redefine its contract.

| Runtime behavior | Owning layer |
|---|---|
| Editable plugin source, manifest, skills, templates, inert hook assets, and agent asset names | [`01-loen-plugin-core`](2026-07-02-01-loen-plugin-core-design.md) |
| Topic artifact contract, `loop.yaml`, per-topic `audit.html`, and TODO row rules | [`02-loen-runtime-artifacts`](2026-07-02-02-loen-runtime-artifacts-design.md) |
| Blocking/advisory loop gates, scope guard, tool guard, permission guard, evidence gate, and audit writer behavior | [`03-loen-enforcement-hooks`](2026-07-02-03-loen-enforcement-hooks-design.md) |
| Planner/worker/verifier/reviewer/researcher role separation, context capsules, Codex profile split, and WASM-first verifier model | [`04-loen-agent-isolation`](2026-07-02-04-loen-agent-isolation-design.md) |
| Vendoring, launch-time marketplace wiring, `ICODEX_LOEN_MODE`, and off/advisory/enforce/strict runtime enablement in icodex | [`05-loen-icodex-integration`](2026-07-02-05-loen-icodex-integration-design.md) |
| Scheduled/background loop governance, human-review counters, and no-auto-merge policy | [`06-loen-automation-governance`](2026-07-02-06-loen-automation-governance-design.md) |
```

- [ ] **Step 3: Run the overview test**

Run:

```bash
bash tests/test_loen_overview_docs.sh
```

Expected: PASS if `docs/TODO.md` already has exactly one row for each LoEn topic. If the only failures are `TODO one row: ...`, complete Task 3 before committing.

- [ ] **Step 4: Commit the passing overview docs and test**

Run:

```bash
git add docs/superpowers/specs/2026-07-02-00-loen-overview-design.md tests/test_loen_overview_docs.sh
git commit -m "docs(loen): validate overview design contract"
```

Expected: commit succeeds on a `dev-*` branch after the test passes.

---

### Task 3: Normalize LoEn TODO Rows

**Files:**
- Modify: `docs/TODO.md`
- Test: `tests/test_loen_overview_docs.sh`

- [ ] **Step 1: Replace the LoEn TODO row block**

In `docs/TODO.md`, replace the contiguous rows from `00-loen-overview` through `06-loen-automation-governance` with:

```markdown
| 00-loen-overview | in-progress | n/a | – | – | – | 2026-07-02 |  | Umbrella design for standalone LoEn loop-engineering plugin and layer sequencing |
| 01-loen-plugin-core | in-progress | n/a | – | – | – | 2026-07-02 |  | LoEn plugin source tree, manifest, skills, hooks, agents, and templates |
| 02-loen-runtime-artifacts | in-progress | n/a | – | – | – | 2026-07-02 |  | Topic artifacts under docs/loen/<topic>/ with numbered stages and audit.html |
| 03-loen-enforcement-hooks | in-progress | n/a | – | – | – | 2026-07-02 |  | Independent LoEn loop gates, scope guard, tool guard, permission guard, and evidence gate |
| 04-loen-agent-isolation | in-progress | n/a | – | – | – | 2026-07-02 |  | Role-specific agents, context capsules, Codex profile split, and WASM-first verifier isolation |
| 05-loen-icodex-integration | in-progress | n/a | – | – | – | 2026-07-02 |  | Vendor and launch-time wiring for LoEn as a standalone Codex plugin in icodex |
| 06-loen-automation-governance | in-progress | n/a | – | – | – | 2026-07-02 |  | Later L3 automation and governance rules after manual loops prove stable |
```

- [ ] **Step 2: Run the overview test**

Run:

```bash
bash tests/test_loen_overview_docs.sh
```

Expected: PASS with `FAIL=0`.

- [ ] **Step 3: Commit TODO normalization if it changed**

Run:

```bash
git status --short docs/TODO.md
```

Expected: output is empty if the rows already matched. If `docs/TODO.md` is listed, run:

```bash
git add docs/TODO.md
git commit -m "docs(loen): normalize overview TODO rows"
```

Expected: commit succeeds only when `docs/TODO.md` changed.

---

### Task 4: Final Verification

**Files:**
- Test: `tests/test_loen_overview_docs.sh`
- Test: all `tests/test_*.sh`

- [ ] **Step 1: Run syntax checks for the new test**

Run:

```bash
bash -n tests/test_loen_overview_docs.sh
```

Expected: exit code `0`.

- [ ] **Step 2: Run the focused overview test**

Run:

```bash
bash tests/test_loen_overview_docs.sh
```

Expected: output ends with:

```text
---
PASS=<number> FAIL=0
```

and the command exits `0`.

- [ ] **Step 3: Run the full Bash test suite**

Run:

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: every test file exits `0`; no command stops the loop.

- [ ] **Step 4: Check whitespace damage**

Run:

```bash
git diff --check
```

Expected: no output and exit code `0`.

- [ ] **Step 5: Review final diff scope**

Run:

```bash
git status --short
git diff -- docs/superpowers/specs/2026-07-02-00-loen-overview-design.md docs/TODO.md tests/test_loen_overview_docs.sh
```

Expected: only the overview spec, `docs/TODO.md` if Task 3 changed it, and the new overview test appear. No `plugins/loen/`, `lib/`, cache, or layer spec files are changed by this overview implementation.

## Self-Review Notes

- Spec coverage: layer spec links are covered by Task 1 and Task 2; TODO rows by Task 1 and Task 3; independence from IDD/Superpowers by Task 1 assertions; runtime behavior ownership by Task 2 table and Task 1 assertions.
- Placeholder scan: no unspecified implementation steps remain; each file edit has exact content and each command has expected output.
- Type/name consistency: topic slugs match the overview spec, layer spec filenames, and `docs/TODO.md` rows.

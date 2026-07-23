---
review:
  plan_hash: 8ccbfcc2f31e6f74
  last_run: 2026-07-23
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-07-23-loen-start-mode-gates-intent.md
  spec: docs/superpowers/specs/2026-07-23-loen-start-mode-gates-design.md
---

# LoEn Start Mode Gates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce four ordered LoEn checkpoints so topic planning is deliberate and runner execution requires a separate, current human launch confirmation.

**Architecture:** `loop.yaml` stores structured current checkpoint authority while `attempts.jsonl` stores append-only checkpoint events. Shared Python helpers parse artifacts, compute a canonical authority-policy hash, and validate ordered freshness; `loop-start`, standalone `loop-plan`, and `loop-run` own distinct human checkpoints. Existing safety checks remain downstream of checkpoint validation.

**Tech Stack:** Bash contract tests, Python 3 standard library LoEn hook helpers, Markdown skill instructions and templates, YAML-like deterministic parser, iwiki MCP documentation.

---

## File Map

- Modify `plugins/loen/hooks/loen_common.py`: parse structured `checkpoints` from `loop.yaml`.
- Modify `plugins/loen/hooks/loen_artifacts.py`: hash artifacts and canonical policy, validate checkpoint order/freshness, append checkpoint events, and render checkpoint audit state.
- Modify `plugins/loen/assets/templates/loop.yaml`: replace legacy execution authority with unconfirmed structured checkpoints.
- Modify `plugins/loen/assets/templates/1_goal.md`: require objective, observable outcome, and success criteria.
- Modify `plugins/loen/assets/templates/2_context.md`: require constraints, scopes, verifier, budget, rollback, and unresolved assumptions.
- Modify `plugins/loen/assets/templates/3_plan.md`: map bounded steps to criteria, evidence, risks, and recovery.
- Modify `plugins/loen/skills/loop-start/SKILL.md`: integrate topic development and planning through three human gates, then stop with the exact runner command.
- Modify `plugins/loen/skills/loop-plan/SKILL.md`: retain only standalone replan semantics and reset downstream authority.
- Modify `plugins/loen/skills/loop-run/SKILL.md`: separate invocation from launch confirmation and repeat preflight after confirmation.
- Modify `tests/test_loen_loop_run_contract.sh`: cover parser, hashes, checkpoint validation, invalidation, audit events, skill order, legacy refusal, and no-execution scenarios.
- Modify `tests/test_loen_runtime_artifacts.sh`: cover generated checkpoint defaults and audit rendering.
- Modify `tests/test_loen_workflow_transitions.sh`: require explicit valid timestamps in executable transition evidence.
- Create `vendor/superpowers/pin`: identify the exact runtime cache path.
- Create `vendor/superpowers/patches/*.patch`: store ordered icodex validation-first deltas outside generated cache state.
- Modify `scripts/vendor-superpowers.sh`: apply patches with zero fuzz in staging and publish cache/pin atomically.
- Modify `lib/plugin/superpowers.sh`: resolve exactly the pinned cache and fail before runtime mutations on invalid state.
- Modify `tests/test_vendor.sh`: cover overlay replay, conflict rollback, unique discovery, and atomic publication.
- Modify `tests/test_plugin.sh`: cover exact pin selection and pre-mutation failure.
- Modify `tests/test_idd_skills.sh` and `tests/test_chain_result_report_contract.sh`: resolve the shared pin and strengthen workflow semantics.
- Modify `.codex-isolated/plugins/cache/openai-curated/superpowers/11c74d6b/skills/brainstorming/SKILL.md` and `writing-plans/SKILL.md`: materialized validation-first overlay output.
- Modify `.codex-isolated/config.toml`: update pin-maintenance guidance without adding private TOML keys.
- Modify `plugins/loen/docs/architecture.md`: final verified architecture flow.
- Modify `plugins/loen/README.md`: final English user workflow and migration break.
- Modify `plugins/loen/README.ru.md`: final Russian user workflow and migration break.
- Update iwiki pages `loen-overview.md` and `loen-runtime-artifacts.md`: final documented behavior after source and tests stabilize.

### Task 1: Parse Checkpoints and Generate Safe Defaults

**Closes:** R6, R7; intent outcomes for current machine-readable confirmations and legacy refusal.

**Files:**
- Modify: `tests/test_loen_loop_run_contract.sh`
- Modify: `tests/test_loen_runtime_artifacts.sh`
- Modify: `plugins/loen/hooks/loen_common.py`
- Modify: `plugins/loen/hooks/loen_artifacts.py`
- Modify: `plugins/loen/assets/templates/loop.yaml`

- [ ] **Step 1: Replace template keyword assertions with failing structured-checkpoint assertions**

Add assertions for the four checkpoint blocks and false/null defaults:

```bash
assert_contains "template has checkpoints block" "$template_text" "checkpoints:"
assert_contains "template has goal context checkpoint" "$template_text" "goal_context:"
assert_contains "template has mode checkpoint" "$template_text" "  mode:"
assert_contains "template has plan checkpoint" "$template_text" "  plan:"
assert_contains "template has launch checkpoint" "$template_text" "launch:"
assert_eq "template has four unconfirmed checkpoints" "4" "$(grep -cF '    confirmed: false' "$template")"
```

Extend the generated-artifact test to assert the same defaults in a scaffolded topic.

- [ ] **Step 2: Add a failing parser fixture for nested checkpoints**

Use a complete fixture with current hashes:

```yaml
checkpoints:
  goal_context:
    confirmed: true
    goal_hash: "goal-hash"
    context_hash: "context-hash"
  mode:
    confirmed: true
    mode: governance
    subtype: merge-release
  plan:
    confirmed: true
    plan_hash: "plan-hash"
    policy_hash: "policy-hash"
  launch:
    confirmed: false
    goal_hash: null
    context_hash: null
    plan_hash: null
    policy_hash: null
```

Assert `parse_loop_yaml()` returns a `checkpoints` map containing all four nested maps and typed booleans.

- [ ] **Step 3: Run focused tests and verify the new assertions fail**

```bash
bash tests/test_loen_loop_run_contract.sh
bash tests/test_loen_runtime_artifacts.sh
```

Expected: failures identify missing `checkpoints` template/parser state; no unrelated crash.

- [ ] **Step 4: Add deterministic nested checkpoint parsing**

Initialize checkpoint state in `parse_loop_yaml()`:

```python
"checkpoints": {
  "goal_context": {"confirmed": False, "goal_hash": "", "context_hash": ""},
  "mode": {"confirmed": False, "mode": "", "subtype": ""},
  "plan": {"confirmed": False, "plan_hash": "", "policy_hash": ""},
  "launch": {"confirmed": False, "goal_hash": "", "context_hash": "", "plan_hash": "", "policy_hash": ""},
},
```

Track the indent-two checkpoint name and parse indent-four scalar values with `_parse_scalar()`. Unknown checkpoint names must not become executable authority.

- [ ] **Step 5: Replace generated and asset template authority with safe checkpoint defaults**

Keep runner progress fields under `run`, but move mode and approval authority under `checkpoints`:

```yaml
checkpoints:
  goal_context:
    confirmed: false
    goal_hash: ""
    context_hash: ""
  mode:
    confirmed: false
    mode: ""
    subtype: null
  plan:
    confirmed: false
    plan_hash: ""
    policy_hash: ""
  launch:
    confirmed: false
    goal_hash: ""
    context_hash: ""
    plan_hash: ""
    policy_hash: ""
run:
  state: prepare
  max_passes: 3
  current_pass: 0
```

Remove `run.plan_approved`, `run.plan_hash`, `run.mode`, `run.subtype`, `approval_source`, and `approved_at` from both template sources so legacy fields cannot be mistaken for current authority.

- [ ] **Step 6: Run focused tests and verify parser/default behavior passes**

```bash
bash tests/test_loen_loop_run_contract.sh
bash tests/test_loen_runtime_artifacts.sh
```

Expected: new parser/default assertions pass, including `policy_hash` defaults on plan and launch; old validator fixture failures are allowed until Task 2 only if assertions label them as expected legacy refusal.

- [ ] **Step 7: Commit parser and template schema**

```bash
git add plugins/loen/hooks/loen_common.py plugins/loen/hooks/loen_artifacts.py plugins/loen/assets/templates/loop.yaml tests/test_loen_loop_run_contract.sh tests/test_loen_runtime_artifacts.sh
git commit -m "feat(loen): add structured checkpoint contract"
```

### Task 2: Enforce Hash Freshness, Ordering, and Legacy Refusal

**Closes:** R2, R3, R5, R7, compatibility constraints, and the four-gate runtime guarantee.

**Files:**
- Modify: `tests/test_loen_loop_run_contract.sh`
- Modify: `plugins/loen/hooks/loen_artifacts.py`

- [ ] **Step 1: Add failing fixtures for every checkpoint transition**

Create a fixture helper that writes `1_goal.md`, `2_context.md`, `3_plan.md`, and a valid policy. Add independent assertions for:

```text
legacy run.plan_approved only -> legacy checkpoint contract
goal_context.confirmed false -> goal/context confirmation missing
goal hash mismatch -> goal hash mismatch
context hash mismatch -> context hash mismatch
mode.confirmed false -> mode selection missing
invalid delivery/governance subtype -> existing precise mode error
plan.confirmed false -> plan approval missing
plan hash mismatch -> plan hash mismatch
launch.confirmed false with require_launch=True -> launch confirmation missing
launch hashes stale -> launch goal/context/plan hash mismatch
plan policy hash stale with current plan hash -> plan policy hash mismatch
launch policy hash stale with current artifact hashes -> launch policy hash mismatch
same contract with require_launch=False -> prelaunch contract valid
```

For every negative case, assert no runner action artifact gains content.

- [ ] **Step 2: Run the contract test and verify checkpoint cases fail**

```bash
bash tests/test_loen_loop_run_contract.sh
```

Expected: FAIL because `validate_run_contract()` still trusts legacy `run.*` approval.

- [ ] **Step 3: Generalize artifact hashing**

Replace plan-only hash use with one helper while retaining the old import as a compatibility alias for existing callers:

```python
def artifact_body_hash(path: Path) -> str:
  return hashlib.sha256(_read(path).encode("utf-8")).hexdigest()[:16]


def plan_body_hash(path: Path) -> str:
  return artifact_body_hash(path)
```

Use `artifact_body_hash()` for `1_goal.md`, `2_context.md`, and `3_plan.md` checks. Add `policy_hash(contract)` as SHA-256 first 16 over UTF-8 canonical JSON (`sort_keys=True`, `separators=(",", ":")`) containing exactly `mode`, `subtype`, `mutable_scope`, `protected_scope`, `quality_gates`, `verifier`, `budget`, `stop_conditions`, `handoff_conditions`, `rollback_policy`, `governance`, and `release_policy` from parsed contract values.

- [ ] **Step 4: Refactor validation into ordered prelaunch and launch phases**

Keep one public validator with an explicit phase switch:

```python
def validate_run_contract(base: Path, *, require_launch: bool = True) -> dict[str, object]:
  checkpoint_error = _validate_checkpoints(base, require_launch=require_launch)
  if checkpoint_error:
    return {"ok": False, "reason": checkpoint_error}
  policy_error = _validate_run_policy(base)
  if policy_error:
    return {"ok": False, "reason": policy_error}
  return {"ok": True, "reason": "approved run contract"}
```

`_validate_checkpoints()` must check in this exact order: contract shape, goal/context confirmation and hashes, mode confirmation and subtype, plan confirmation, plan hash, plan policy hash, then launch confirmation, all three artifact hashes, and launch policy hash. Policy comparisons recompute the current canonical hash. Exact mismatch reasons are `plan policy hash mismatch` and `launch policy hash mismatch`. `_validate_run_policy()` retains mutable scope, verifier, budget, rollback, auto-fix, and merge-release checks.

Add table-driven mutations for mode, subtype, mutable/protected scope, quality gates, verifier, budget, stop/handoff conditions, rollback policy, governance, and release policy. Keep `3_plan.md` and artifact hashes unchanged. Assert plan validation rejects each mutation until reapproval updates plan+policy hashes; then assert launch validation rejects a mutation after launch confirmation until a new launch decision updates all four launch hashes.

- [ ] **Step 5: Run focused contract tests**

```bash
bash tests/test_loen_loop_run_contract.sh
```

Expected: all positive, stale-state, ordering, canonical-policy mutation, exact-reason, and legacy assertions pass with `FAIL=0`; no action artifact changes in any rejection case.

- [ ] **Step 6: Commit checkpoint enforcement**

```bash
git add plugins/loen/hooks/loen_artifacts.py tests/test_loen_loop_run_contract.sh
git commit -m "feat(loen): enforce ordered runtime checkpoints"
```

### Task 3: Record Checkpoint Decisions and Render Current Authority

**Closes:** R5, R6, R7 audit evidence and failed-post-confirmation behavior.

**Files:**
- Modify: `tests/test_loen_loop_run_contract.sh`
- Modify: `tests/test_loen_runtime_artifacts.sh`
- Modify: `plugins/loen/hooks/loen_artifacts.py`

- [ ] **Step 1: Add failing tests for confirm, reset, and refusal events**

Call a new helper three times and parse each JSONL line:

```python
append_checkpoint_event(
  base=base,
  checkpoint="launch",
  decision="confirmed",
  hashes={"goal_hash": "g", "context_hash": "c", "plan_hash": "p"},
  mode="delivery",
  subtype="",
  created_at="2026-07-23T12:00:00Z",
)
```

Assert records contain `event: checkpoint`, checkpoint name, `decision` in `confirmed|reset|refused`, hashes, mode/subtype, and timestamp. Confirmed hash requirements are exact: `goal_context` has goal+context, `plan` has plan+policy, and `launch` has goal+context+plan+policy. Assert a confirmed event with missing or extra required hashes, malformed checkpoint, or malformed decision raises `ValueError` without appending a line.

- [ ] **Step 2: Add a failing audit renderer assertion**

Require `audit.html` and runner summary to show all four checkpoint names, current confirmed state, hashes including policy hashes, and latest checkpoint decision count while retaining existing runner/governance sections. Seed contradictory removed `run.mode`, `run.subtype`, `run.plan_approved`, and `run.plan_hash` fixture values and assert summaries render checkpoint authority only.

- [ ] **Step 3: Run focused tests and verify failures**

```bash
bash tests/test_loen_loop_run_contract.sh
bash tests/test_loen_runtime_artifacts.sh
```

Expected: FAIL for missing `append_checkpoint_event()` and checkpoint audit section.

- [ ] **Step 4: Implement the constrained append-only event helper**

Add:

```python
CHECKPOINT_NAMES = {"goal_context", "mode", "plan", "launch"}
CHECKPOINT_DECISIONS = {"confirmed", "reset", "refused"}


def append_checkpoint_event(*, base: Path, checkpoint: str, decision: str,
                            hashes: dict[str, str], mode: str = "",
                            subtype: str = "", created_at: str = "") -> dict[str, object]:
  if checkpoint not in CHECKPOINT_NAMES:
    raise ValueError("invalid checkpoint name")
  if decision not in CHECKPOINT_DECISIONS:
    raise ValueError("invalid checkpoint decision")
  required_confirmed_hashes = {
    "goal_context": {"goal_hash", "context_hash"},
    "plan": {"plan_hash", "policy_hash"},
    "launch": {"goal_hash", "context_hash", "plan_hash", "policy_hash"},
  }
  if decision == "confirmed" and set(hashes) != required_confirmed_hashes.get(checkpoint, set()):
    raise ValueError("invalid confirmed checkpoint hashes")
  record = {
    "event": "checkpoint",
    "checkpoint": checkpoint,
    "decision": decision,
    "hashes": dict(hashes),
    "mode": mode,
    "subtype": subtype,
    "created_at": created_at,
  }
  with (base / "attempts.jsonl").open("a", encoding="utf-8") as handle:
    handle.write(json.dumps(record, sort_keys=True) + "\n")
  return record
```

- [ ] **Step 5: Extend runner summary and audit rendering**

Render current `checkpoints` separately from historical events. Runner summary and audit rendering must read mode, subtype, approvals, and hashes from `checkpoints`, never removed `run.*` authority fields or attempts. Preserve the existing attempt count and governance event rendering for mixed JSONL records.

- [ ] **Step 6: Run focused tests**

```bash
bash tests/test_loen_loop_run_contract.sh
bash tests/test_loen_runtime_artifacts.sh
```

Expected: checkpoint hash-shape events and checkpoint-authority summary/audit assertions pass; contradictory removed `run.*` fixture values are ignored; existing automation-attempt assertions remain green.

- [ ] **Step 7: Commit audit support**

```bash
git add plugins/loen/hooks/loen_artifacts.py tests/test_loen_loop_run_contract.sh tests/test_loen_runtime_artifacts.sh
git commit -m "feat(loen): audit checkpoint decisions"
```

### Task 4: Strengthen Topic Templates and Skill Gates

**Closes:** R1-R5, R8, exact continuation instruction, adaptive topic development, integrated planning, and human-only launch.

**Files:**
- Modify: `tests/test_loen_loop_run_contract.sh`
- Modify: `plugins/loen/assets/templates/1_goal.md`
- Modify: `plugins/loen/assets/templates/2_context.md`
- Modify: `plugins/loen/assets/templates/3_plan.md`
- Modify: `plugins/loen/skills/loop-start/SKILL.md`
- Modify: `plugins/loen/skills/loop-plan/SKILL.md`
- Modify: `plugins/loen/skills/loop-run/SKILL.md`

- [ ] **Step 1: Add failing structural workflow assertions**

Extract line numbers with `grep -n` and assert strict ordering in `loop-start`:

```text
resolve assumptions < confirm goal/context < select mode/subtype < write plan < approve plan < continuation command
```

Also assert:

```bash
assert_contains "loop-start resolves handoff topic" "$loop_start_text" 'Replace `{resolved_topic}` with the validated topic slug before emitting the final line.'
assert_contains "loop-start emits ready command last" "$loop_start_text" "The response's last line must be the ready-to-run command below after substitution"
assert_eq "loop-start has no immediate launch" "0" "$(grep -cF 'start immediately' "$loop_start" || true)"
assert_contains "loop-run invocation is not approval" "$loop_run_text" "Invocation is not launch confirmation"
assert_contains "loop-run repeats preflight" "$loop_run_text" "Repeat the complete preflight"
assert_contains "loop-plan is replan only" "$loop_plan_text" "existing topic"
```

Add template assertions for `Observable Outcome`, `Unresolved Assumptions`, mutable/protected scope, verifier, budget, rollback/recovery, risks, evidence, and success-criterion mapping.

Scaffold a real topic and scan generated `1_goal.md`, `2_context.md`, and `3_plan.md` with `rg -n '\{\{[^}]+\}\}'`. The assertion must fail if any unresolved placeholder remains; generated artifacts must contain concrete safe defaults or collected values.

- [ ] **Step 2: Run the contract test and verify skill/template assertions fail**

```bash
bash tests/test_loen_loop_run_contract.sh
```

Expected: FAIL on old shallow templates, immediate-launch wording, and missing gate order.

- [ ] **Step 3: Expand the three planning templates**

Use fixed headings that make completeness testable:

```markdown
# Goal
## User Request
## Objective
## Observable Outcome
## Success Criteria
```

```markdown
# Context
## Facts
## Constraints
## Mutable Scope
## Protected Scope
## Verifier
## Budget
## Rollback or Recovery
## Unresolved Assumptions
```

```markdown
# Plan
## Preconditions
## Steps
## Success-Criterion Mapping
## Checks and Evidence
## Risks
## Rollback or Recovery
## Terminal Condition
```

- [ ] **Step 4: Rewrite `loop-start` as the three-gate planning orchestrator**

Specify adaptive one-question-at-a-time topic development, explicit empty-assumption requirement, confirmation hashes, explicit mode/subtype selection, integrated plan generation, separate plan approval, downstream invalidation, audit events, and unconditional stop with this command template after substituting the validated topic slug:

```text
loen:loop-run {resolved_topic}
```

Require the command as the response's final line and forbid angle-bracket notation or unresolved placeholders in emitted output.

Remove all immediate-run offers and any wording that treats plan approval as execution authority.

- [ ] **Step 5: Rewrite standalone `loop-plan` for replan only**

Require a current goal/context checkpoint and mode checkpoint, regenerate the bounded plan, reset `plan` and `launch`, append reset events, request new plan approval, and never launch execution.

- [ ] **Step 6: Rewrite `loop-run` launch procedure**

Before state-machine execution, require:

```text
1. Validate with require_launch=false.
2. Present mode, subtype, scopes, verifier, budget, rollback/recovery, and goal/context/plan/policy hashes.
3. State that invocation is not launch confirmation.
4. Ask one explicit launch question.
5. On refusal or ambiguity, append a refused event and stop.
6. On approval, write launch.confirmed=true with goal/context/plan/policy hashes and append a confirmed event with exactly those four hashes.
7. Repeat the complete preflight with require_launch=true.
8. On failure, reset launch, append a reset event, and stop before prepare/act/check/reflect.
```

Update merge-release text: start-time plan approval is no longer sufficient; the universal `loop-run` launch checkpoint is required before mode policy applies.

- [ ] **Step 7: Run focused workflow tests**

```bash
bash tests/test_loen_loop_run_contract.sh
bash tests/test_loen_runtime_artifacts.sh
```

Expected: all gate-order, exact-command, topic-quality, placeholder-completeness, replan, launch, contract, and audit assertions pass with `FAIL=0`.

- [ ] **Step 8: Commit skills and planning templates**

```bash
git add plugins/loen/assets/templates/1_goal.md plugins/loen/assets/templates/2_context.md plugins/loen/assets/templates/3_plan.md plugins/loen/skills/loop-start/SKILL.md plugins/loen/skills/loop-plan/SKILL.md plugins/loen/skills/loop-run/SKILL.md tests/test_loen_loop_run_contract.sh
git commit -m "feat(loen): gate start planning and runner launch"
```

### Task 5: Stabilize Contract and Regression Coverage

**Closes:** Testing section and health metrics requiring retained safety policy.

**Files:**
- Modify: `tests/test_loen_loop_run_contract.sh`
- Modify: `tests/test_loen_runtime_artifacts.sh`
- Add or modify: `tests/test_loen_workflow_transitions.sh`
- Modify only if a regression is found: `plugins/loen/hooks/loen_common.py`
- Modify only if a regression is found: `plugins/loen/hooks/loen_artifacts.py`

- [ ] **Step 1: Run Python syntax checks**

```bash
python3 -m py_compile plugins/loen/hooks/loen_common.py plugins/loen/hooks/loen_artifacts.py plugins/loen/hooks/audit-writer.py
```

Expected: exit 0 and no output.

- [ ] **Step 2: Add deterministic executable workflow-transition coverage**

Use real scaffolded `1_goal.md`, `2_context.md`, `3_plan.md`, `loop.yaml`, the production validator, and persisted checkpoint events. Drive this exact sequence in one isolated temporary topic:

```text
current goal/context + mode + plan/policy -> prelaunch valid
loop-run invocation -> no action
explicit refusal -> refusal event + no action
explicit confirmation -> launch event with goal/context/plan/policy hashes
repeated require_launch=true preflight -> valid
mode or canonical policy mutation -> exact policy-hash rejection + no action
renew current plan/policy and launch authority -> repeated full validation valid
runner action -> occurs only now
```

Assert event order and contents, exact `plan policy hash mismatch` / `launch policy hash mismatch` reasons at their respective gates, unchanged action evidence for every invocation/refusal/rejection step, and one action only after current full validation.

- [ ] **Step 3: Run all focused LoEn tests**

```bash
for t in tests/test_loen_*.sh; do bash "$t" || exit 1; done
```

Expected: every LoEn test exits 0; no `FAIL` count is nonzero.

- [ ] **Step 4: Run the full Bash suite**

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: every test exits 0. Any unrelated pre-existing failure must be reproduced on `origin/master` and recorded before proceeding.

- [ ] **Step 5: Fix only confirmed checkpoint regressions and rerun their smallest failing test**

Use the failure message to make the smallest source or fixture correction. Do not weaken missing/stale/legacy rejection. Rerun the exact failing test, then Steps 1-4.

- [ ] **Step 6: Commit any stabilization changes**

```bash
git add plugins/loen/hooks/loen_common.py plugins/loen/hooks/loen_artifacts.py tests/test_loen_loop_run_contract.sh tests/test_loen_runtime_artifacts.sh tests/test_loen_workflow_transitions.sh
git diff --cached --quiet || git commit -m "test(loen): cover checkpoint state transitions"
```

### Task 6: Complete Documentation Closeout

**Closes:** R9 and mandatory documentation consistency. This is the final implementation step.

**Files:**
- Modify: `plugins/loen/docs/architecture.md`
- Modify: `plugins/loen/README.md`
- Modify: `plugins/loen/README.ru.md`
- Update through iwiki MCP: `icodex/loen-overview.md`
- Update through iwiki MCP: `icodex/loen-runtime-artifacts.md`

- [ ] **Step 1: Update architecture after verified behavior is stable**

Replace the old `plan approval -> immediate runner` sequence and legacy `run.*` authority with the four-checkpoint flow, structured checkpoint contract, invalidation table, standalone replan boundary, repeated preflight, audit-event boundary, and legacy refusal.

- [ ] **Step 2: Update English README user workflow**

Document:

```text
loen:loop-start
  -> confirm goal/context
  -> select mode/subtype
  -> approve integrated plan
  -> run loen:loop-run <topic>
  -> confirm launch
  -> repeated preflight
  -> result or handoff
```

State that `loop-start` never launches automatically and `loop-plan` is standalone replan only.

- [ ] **Step 3: Update Russian README with equivalent behavior**

Keep commands and checkpoint keys exact. Ensure Russian prose does not retain statements that plan approval alone enables execution or that governance can run immediately after start.

- [ ] **Step 4: Update bound iwiki pages from final source behavior**

Use `wiki_update_page` for relevant sections in `loen-overview.md` and `loen-runtime-artifacts.md`, with changed plugin files as `source`. Include four gates, hash invalidation, audit history versus current authority, replan role, exact continuation command, and breaking legacy refusal.

- [ ] **Step 5: Verify repository docs and wiki contain no stale contract**

```bash
rg -n "run\.plan_approved|start immediately|immediate launch|plan approval.*sufficient|can run immediately after" plugins/loen/docs/architecture.md plugins/loen/README.md plugins/loen/README.ru.md
```

Expected: no stale behavioral claim; any match is an explicit historical/migration warning.

Run `wiki_lint(domain="icodex")`.

Expected: no broken, orphan, stale, missing-source, or tag-drift findings.

- [ ] **Step 6: Re-run documentation-sensitive focused tests**

```bash
bash tests/test_loen_loop_run_contract.sh
bash tests/test_loen_runtime_artifacts.sh
```

Expected: both exit 0 with `FAIL=0`.

- [ ] **Step 7: Commit final documentation**

```bash
git add plugins/loen/docs/architecture.md plugins/loen/README.md plugins/loen/README.ru.md
git commit -m "docs(loen): document checkpointed start workflow"
```

### Task 7: Pre-Hardening Verification Baseline

**Closes:** R1-R9 verification before review-discovered R10-R13 blockers; no implementation files change in this task.

**Files:**
- Verify: all files listed above
- Update through `$check-chain result`: this plan frontmatter and `docs/TODO.md`

- [ ] **Step 1: Run final syntax and focused verification**

```bash
python3 -m py_compile plugins/loen/hooks/loen_common.py plugins/loen/hooks/loen_artifacts.py plugins/loen/hooks/audit-writer.py
for t in tests/test_loen_*.sh; do bash "$t" || exit 1; done
```

Expected: exit 0; all LoEn tests pass, including executable transition coverage proving no action before current goal/context/plan/policy launch authority and repeated full validation.

- [ ] **Step 2: Run final full suite**

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: exit 0 for every test.

- [ ] **Step 3: Inspect diff scope and stale legacy wording**

```bash
git diff --check origin/master...HEAD
git diff --stat origin/master...HEAD
rg -n "run\.plan_approved|run\.plan_hash|run\.mode|run\.subtype" plugins/loen tests
rg -n '\{\{[^}]+\}\}' docs/loen/*/1_goal.md docs/loen/*/2_context.md docs/loen/*/3_plan.md
```

Expected: clean diff; changed paths map to Tasks 1-6; remaining legacy-key matches exist only in explicit rejection/summary-authority tests or migration documentation; generated planning artifacts contain no unresolved placeholders. Evidence explicitly maps review corrections to `loen_artifacts.py`, `loop.yaml`, the three planning templates, `test_loen_loop_run_contract.sh`, `test_loen_runtime_artifacts.sh`, and `test_loen_workflow_transitions.sh`, with passing exact-reason, event-hash, summary-authority, scaffold-completeness, and action-timing assertions.

- [ ] **Step 4: Validate chain result and close TODO**

Run `$check-chain result docs/superpowers/plans/2026-07-23-loen-start-mode-gates.md`.

Expected: review may reopen the topic when confirmed blockers remain; final closure moves to Task 11.

### Task 8: Harden Canonical Parsing and Audit Events

**Closes:** R10, R11; canonical null, duplicate authority refusal, and timestamped audit outcomes.

**Files:**
- Modify: `plugins/loen/hooks/loen_common.py`
- Modify: `plugins/loen/hooks/loen_artifacts.py`
- Modify: `tests/test_loen_loop_run_contract.sh`
- Modify: `tests/test_loen_runtime_artifacts.sh`
- Modify: `tests/test_loen_workflow_transitions.sh`
- Modify: `plugins/loen/skills/loop-start/SKILL.md`
- Modify: `plugins/loen/skills/loop-plan/SKILL.md`
- Modify: `plugins/loen/skills/loop-run/SKILL.md`

- [ ] **Step 1: Add failing semantic-null and independent hash-vector tests**

Test bare null variants, quoted null, and expected SHA-256 prefixes computed directly from literal canonical JSON rather than `run_policy_hash()`.

```bash
bash tests/test_loen_loop_run_contract.sh
```

Expected: FAIL because bare null is currently parsed as textual `"null"`.

- [ ] **Step 2: Add failing canonical duplicate matrix**

Cover every top-level policy field, verifier/budget/governance/release-policy member, checkpoint name/field, and quality-gate item key. Include comments, unrelated nested keys, and quoted `#` controls that must remain valid.

```bash
bash tests/test_loen_loop_run_contract.sh
```

Expected: FAIL because non-checkpoint duplicates currently use last-value wins.

- [ ] **Step 3: Implement semantic scalar parsing and checked diagnostics**

Keep `parse_loop_yaml(text) -> dict`. Add a quote-aware checked parser path returning diagnostics to `validate_run_contract()`. Normalize delivery null subtype before validation/hash input and return the stable reason `invalid canonical authority` for duplicate authority paths.

```bash
bash tests/test_loen_loop_run_contract.sh
```

Expected: all contract tests pass, including independent vectors and duplicate matrix.

- [ ] **Step 4: Add failing timestamp schema and no-write tests**

Cover valid second/fractional `Z`, and reject empty, offset, lowercase, date-only, invalid date/time. Assert invalid append leaves JSONL unchanged and malformed history is excluded.

```bash
bash tests/test_loen_runtime_artifacts.sh
```

Expected: FAIL because empty `created_at` is currently accepted.

- [ ] **Step 5: Implement shared timestamp validation**

Use one strict validator in writer and reader. Preserve call signature but require callers to pass canonical timestamps; update skill examples and workflow fixtures.

```bash
bash tests/test_loen_runtime_artifacts.sh
bash tests/test_loen_workflow_transitions.sh
```

Expected: all timestamp and executable-transition tests pass.

- [ ] **Step 6: Commit runtime hardening**

```bash
git add plugins/loen/hooks/loen_common.py plugins/loen/hooks/loen_artifacts.py tests/test_loen_loop_run_contract.sh tests/test_loen_runtime_artifacts.sh tests/test_loen_workflow_transitions.sh plugins/loen/skills/loop-start/SKILL.md plugins/loen/skills/loop-plan/SKILL.md plugins/loen/skills/loop-run/SKILL.md
git commit -m "fix(loen): harden policy parsing and audit events"
```

### Task 9: Make Superpowers Overlay Durable and Cache Selection Deterministic

**Closes:** R12; re-vendor durability, atomic publication, and exact runtime cache selection.

**Files:**
- Create: `vendor/superpowers/pin`
- Create: `vendor/superpowers/patches/0001-brainstorming-check-chain.patch`
- Create: `vendor/superpowers/patches/0002-writing-plans-check-chain.patch`
- Modify: `scripts/vendor-superpowers.sh`
- Modify: `lib/plugin/superpowers.sh`
- Modify: `.codex-isolated/config.toml`
- Modify: `tests/test_vendor.sh`
- Modify: `tests/test_plugin.sh`

- [ ] **Step 1: Add failing vendor-overlay tests**

Fixtures must prove ordered zero-fuzz application, required markers, rejection of zero/multiple source caches, conflict rollback, and atomic cache/pin publication.

```bash
bash tests/test_vendor.sh
```

Expected: FAIL because no pin/patch staging API exists.

- [ ] **Step 2: Implement staged fail-closed vendoring**

Normalize the unique source into a sibling staging directory, apply every ordered patch with `patch --batch --forward --fuzz=0 -p1`, validate output, then replace destination and pin only after success. Any failure preserves previous destination and pin.

```bash
bash tests/test_vendor.sh
```

Expected: all refresh, drift, ambiguity, and rollback tests pass.

- [ ] **Step 3: Add failing exact-pin runtime tests**

Cover valid pin, malformed/missing pin, missing target, extra unpinned cache, marketplace mismatch, and proof that failure does not alter config, marketplace root, or skill links.

```bash
bash tests/test_plugin.sh
```

Expected: FAIL because runtime currently chooses first glob match and tolerates missing cache.

- [ ] **Step 4: Implement deterministic pre-mutation resolution**

Read and validate the dedicated pin, enumerate cache directories, require one exact match and configured marketplace identity, then wire only after all checks pass.

```bash
bash tests/test_plugin.sh
```

Expected: exact-pin and existing idempotence/CWD tests pass.

- [ ] **Step 5: Materialize and verify overlay patches**

Generate unified patches from clean pinned upstream to the reviewed skill outputs. Reapply them to a clean fixture and compare the resulting two `SKILL.md` files byte-for-byte with committed cache files.

```bash
bash tests/test_vendor.sh
bash tests/test_idd_skills.sh
```

Expected: committed cache is reproducible from pin plus ordered patches.

- [ ] **Step 6: Commit durable vendoring**

```bash
git add vendor/superpowers/pin vendor/superpowers/patches/0001-brainstorming-check-chain.patch vendor/superpowers/patches/0002-writing-plans-check-chain.patch scripts/vendor-superpowers.sh lib/plugin/superpowers.sh .codex-isolated/config.toml .codex-isolated/plugins/cache/openai-curated/superpowers/11c74d6b/skills/brainstorming/SKILL.md .codex-isolated/plugins/cache/openai-curated/superpowers/11c74d6b/skills/writing-plans/SKILL.md tests/test_vendor.sh tests/test_plugin.sh
git commit -m "fix(plugin): pin and replay Superpowers overlay"
```

### Task 10: Strengthen IDD Workflow Contracts and Documentation

**Closes:** R12 documentation/workflow acceptance and R9 expanded documentation impact.

**Files:**
- Modify: `.codex-isolated/plugins/cache/openai-curated/superpowers/11c74d6b/skills/brainstorming/SKILL.md`
- Modify: `.codex-isolated/plugins/cache/openai-curated/superpowers/11c74d6b/skills/writing-plans/SKILL.md`
- Modify: `tests/test_idd_skills.sh`
- Modify: `tests/test_chain_result_report_contract.sh`
- Modify: `plugins/loen/docs/architecture.md`
- Modify: `plugins/loen/README.md`
- Modify: `plugins/loen/README.ru.md`
- Update through iwiki MCP: `icodex/loen-runtime-artifacts.md`
- Update through iwiki MCP: `icodex/plugin-and-hook-wiring.md`

- [ ] **Step 1: Add semantic workflow and shared-pin tests**

Require one shared pin resolver in repository tests. Assert provisional design-section feedback is not final spec approval; cover `needs_work -> fix -> OK -> approval -> commit` and plan `needs_work -> fix -> OK -> approval -> execution handoff` order. Continue forbidding intermediate HTML requirements.

```bash
bash tests/test_idd_skills.sh
bash tests/test_chain_result_report_contract.sh
```

Expected: FAIL on current first-glob selection and incomplete approval distinction.

- [ ] **Step 2: Clarify skill approval and commit semantics**

Preserve upstream brainstorming feedback while explicitly distinguishing it from checked-artifact approval. Require spec and plan artifact commits after approval and before downstream handoff where machine state changed.

```bash
bash tests/test_idd_skills.sh
bash tests/test_chain_result_report_contract.sh
```

Expected: all IDD skill/report contracts pass without intermediate HTML coupling.

- [ ] **Step 3: Update repository docs and iwiki**

Document semantic null, duplicate refusal, required timestamps, pin/patch maintenance, atomic refresh, deterministic selection, and recovery from overlay conflict. Run `wiki_lint` after MCP updates.

```bash
bash tests/test_loen_plugin_core.sh
bash tests/test_loen_runtime_artifacts.sh
```

Expected: repository docs match verified runtime behavior; wiki has no stale or broken pages.

- [ ] **Step 4: Commit workflow and docs**

```bash
git add .codex-isolated/plugins/cache/openai-curated/superpowers/11c74d6b/skills/brainstorming/SKILL.md .codex-isolated/plugins/cache/openai-curated/superpowers/11c74d6b/skills/writing-plans/SKILL.md tests/test_idd_skills.sh tests/test_chain_result_report_contract.sh plugins/loen/docs/architecture.md plugins/loen/README.md plugins/loen/README.ru.md
git commit -m "docs(workflow): harden checked approval contracts"
```

### Task 11: Final Verification and Consistent Result State

**Closes:** R13 and every expanded intent outcome.

**Files:**
- Verify: every path in the expanded File Map
- Update through `$check-chain result`: this plan frontmatter and `docs/TODO.md`

- [ ] **Step 1: Run focused and full verification**

```bash
python3 -m py_compile plugins/loen/hooks/*.py
for t in tests/test_loen_*.sh; do bash "$t" || exit 1; done
for t in tests/test_*.sh; do bash "$t" || exit 1; done
git diff --check origin/master...HEAD
```

Expected: every command exits 0.

- [ ] **Step 2: Run independent reviews**

Review runtime correctness, overlay durability, workflow semantics, diff scope, and docs/wiki consistency. Fix every confirmed finding and rerun focused checks.

Expected: no open critical or important findings.

- [ ] **Step 3: Reconcile result and close state atomically**

Run `$check-chain result docs/superpowers/plans/2026-07-23-loen-start-mode-gates.md`. Decline or accept optional HTML independently of machine state. Write matching `result_check.plan_hash`, `result_check.verdict: OK`, and `docs/TODO.md` `done/Result: OK/Closed` only after verdict `OK`.

Expected: no missing/excess paths, plan hash matches, TODO and plan state agree.

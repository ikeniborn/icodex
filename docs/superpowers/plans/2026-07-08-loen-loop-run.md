---
review:
  plan_hash: db1cd4a8d3aa97ae
  last_run: 2026-07-08
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: docs/superpowers/intents/2026-07-08-loen-loop-run-intent.md
  spec: docs/superpowers/specs/2026-07-08-loen-loop-run-design.md
result_check:
  verdict: OK
  plan_hash: db1cd4a8d3aa97ae
  last_run: 2026-07-08
  reviewed: true
  docs_checked: true
---
# LoEn Loop Run Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a guided LoEn start-and-run contract where `loop-start` collects mode and plan approval, then `loop-run <topic>` drives delivery or governance topics to `7_result.md` or `handoff.md`.

**Architecture:** Extend existing LoEn runtime artifacts instead of adding a second state store. `loop.yaml` gets a `run:` contract and optional `release_policy:` block; `loop-start` writes approved policy, while new `loop-run` consumes it as an explicit state machine. Existing manual LoEn skills remain usable over the same artifacts.

**Tech Stack:** Bash fixture tests, Python 3 standard library helpers, Markdown skill contracts, existing LoEn templates and audit writer, iwiki MCP documentation updates.

---

Spec: `docs/superpowers/specs/2026-07-08-loen-loop-run-design.md`

## Scope Check

This plan implements one subsystem: LoEn guided runner orchestration. It does not add a scheduler daemon, GitHub API client, remote release publisher, or background process. Merge/release automation is supported as a governed LoEn mode through recorded policy and skill instructions; actual commands remain part of the approved topic plan and must pass runner policy, verifier, evidence, scope, and recovery checks.

## File Structure

- **Create** `tests/test_loen_loop_run_contract.sh` — focused fixture for run contract, launch mode selection, governance subtypes, runner refusal rules, audit visibility, and docs coverage.
- **Create** `plugins/loen/skills/loop-run/SKILL.md` — new runner skill with state machine and policy checks.
- **Modify** `plugins/loen/assets/templates/loop.yaml` — add `run:` defaults and `release_policy:` placeholders.
- **Modify** `plugins/loen/hooks/loen_common.py` — parse `run:` and `release_policy:` sections into typed-ish dictionaries.
- **Modify** `plugins/loen/hooks/loen_artifacts.py` — render run contract text, validate approved run contracts, write handoff, and show runner state in audit.
- **Modify** `plugins/loen/skills/loop-start/SKILL.md` — make start the intake, launch-mode, mode-parameter, and plan-approval gate.
- **Modify** `plugins/loen/skills/loop-governance/SKILL.md` — align governance subtype wording with report-only, auto-fix, and merge-release.
- **Modify** `plugins/loen/README.md` and `plugins/loen/README.ru.md` — document guided start/run path and manual compatibility.
- **Modify** `plugins/loen/docs/architecture.md` — document `loop-run` state machine and policy boundaries.
- **Update via iwiki MCP** existing `loen-overview`, `loen-runtime-artifacts`, and `loen-automation-governance` pages after tests pass.
- **Do not modify** `lib/plugin/loen.sh`, `icodex.sh`, or vendored `.codex-isolated/plugins/cache/.../loen/` in this plan. Vendoring is a later sync task.

## Task 1: Add Failing Contract Coverage

**Files:**
- Create: `tests/test_loen_loop_run_contract.sh`
- Read: `tests/helpers.sh`
- Read: `plugins/loen/hooks/loen_common.py`
- Read: `plugins/loen/hooks/loen_artifacts.py`

- [ ] **Step 1: Write the focused failing test**

Create `tests/test_loen_loop_run_contract.sh` with:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

plugin_root="$ROOT/plugins/loen"
hook_root="$plugin_root/hooks"
template="$plugin_root/assets/templates/loop.yaml"
loop_start="$plugin_root/skills/loop-start/SKILL.md"
loop_run="$plugin_root/skills/loop-run/SKILL.md"
loop_governance="$plugin_root/skills/loop-governance/SKILL.md"
readme="$plugin_root/README.md"
readme_ru="$plugin_root/README.ru.md"
architecture="$plugin_root/docs/architecture.md"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
topic_dir="$tmp/docs/loen/sample-runner"
mkdir -p "$topic_dir/evidence"

cat > "$topic_dir/3_plan.md" <<'PLAN'
# Plan

Topic: `sample-runner`

## Steps

1. Write the governed report -> verify: bash tests/test_loen_loop_run_contract.sh

## Checks

```bash
bash tests/test_loen_loop_run_contract.sh
```
PLAN

plan_hash="$(PYTHONPATH="$hook_root" python3 - "$topic_dir/3_plan.md" <<'PY'
import sys
from pathlib import Path
from loen_artifacts import plan_body_hash
print(plan_body_hash(Path(sys.argv[1])))
PY
)"

cat > "$topic_dir/loop.yaml" <<YAML
topic: sample-runner
mode: governance
status: active
objective: "Run governed merge release safely"
current_stage: plan
stage: plan
mutable_scope:
  - plugins/loen/**
  - tests/**
protected_scope:
  - secrets/**
quality_gates:
  - command: bash tests/test_loen_loop_run_contract.sh
    evidence: evidence/latest-test.json
verifier:
  type: test
  command: bash tests/test_loen_loop_run_contract.sh
budget:
  max_iterations: 2
stop_conditions:
  - verifier passes
handoff_conditions:
  - policy missing
rollback_policy: "Stop and write handoff"
run:
  mode: governance
  subtype: merge-release
  plan_approved: true
  plan_hash: "$plan_hash"
  state: prepare
  max_passes: 2
  current_pass: 0
  approval_source: loop-start
  approved_at: "2026-07-08T00:00:00Z"
governance:
  automation_type: release-governance
  owner: maintainer
  schedule: manual
  auto_fix: true
  auto_merge: true
  report_only_on_no_findings: false
  alert_on:
    - protected_scope_attempt
    - verifier_failure
release_policy:
  target_branch: master
  merge_strategy: pr
  verifier_required: true
  evidence_required: true
  recovery_policy: "Stop, record handoff, and leave branch inspectable."
YAML

touch "$topic_dir/1_goal.md" "$topic_dir/2_context.md" "$topic_dir/4_act.md" \
  "$topic_dir/5_check.md" "$topic_dir/6_reflect.md" "$topic_dir/7_result.md" \
  "$topic_dir/handoff.md" "$topic_dir/attempts.jsonl"

assert_exit "loop-run skill exists" 0 test -f "$loop_run"

template_text="$(cat "$template")"
assert_contains "template has run block" "$template_text" "run:"
assert_contains "template has delivery mode default" "$template_text" "mode: delivery"
assert_contains "template has plan approved false default" "$template_text" "plan_approved: false"
assert_contains "template has plan hash field" "$template_text" "plan_hash:"
assert_contains "template has release policy block" "$template_text" "release_policy:"

parse_status="$(PYTHONPATH="$hook_root" python3 - "$topic_dir/loop.yaml" <<'PY'
import sys
from pathlib import Path
from loen_common import parse_loop_yaml

data = parse_loop_yaml(Path(sys.argv[1]).read_text(encoding="utf-8"))
run = data.get("run", {})
release = data.get("release_policy", {})
checks = [
    run.get("mode") == "governance",
    run.get("subtype") == "merge-release",
    run.get("plan_approved") is True,
    run.get("state") == "prepare",
    run.get("max_passes") == 2,
    run.get("current_pass") == 0,
    release.get("target_branch") == "master",
    release.get("merge_strategy") == "pr",
    release.get("verifier_required") is True,
    release.get("evidence_required") is True,
]
print("OK" if all(checks) else {"run": run, "release": release})
PY
)"
assert_eq "parser reads run and release policy" "OK" "$parse_status"

validation_status="$(PYTHONPATH="$hook_root" python3 - "$topic_dir" <<'PY'
import sys
from pathlib import Path
from loen_artifacts import validate_run_contract

result = validate_run_contract(Path(sys.argv[1]))
print("OK" if result["ok"] else result)
PY
)"
assert_eq "approved merge-release contract validates" "OK" "$validation_status"

cat > "$topic_dir/loop.yaml.bad" <<'YAML'
topic: bad-runner
mode: governance
run:
  mode: governance
  subtype: merge-release
  plan_approved: false
  plan_hash: "bad"
YAML
bad_status="$(PYTHONPATH="$hook_root" python3 - "$topic_dir" <<'PY'
import sys
from pathlib import Path
from loen_artifacts import validate_run_contract

base = Path(sys.argv[1])
(base / "loop.yaml").write_text((base / "loop.yaml.bad").read_text(encoding="utf-8"), encoding="utf-8")
result = validate_run_contract(base)
print("OK" if not result["ok"] and "plan approval" in result["reason"] else result)
PY
)"
assert_eq "runner refuses missing approval" "OK" "$bad_status"

cat > "$topic_dir/loop.yaml" <<YAML
topic: sample-runner
mode: governance
run:
  mode: governance
  subtype: report-only
  plan_approved: true
  plan_hash: "$plan_hash"
  state: prepare
  max_passes: 1
  current_pass: 0
governance:
  auto_fix: false
  auto_merge: false
release_policy:
  target_branch: ""
YAML
report_status="$(PYTHONPATH="$hook_root" python3 - "$topic_dir" <<'PY'
import sys
from pathlib import Path
from loen_artifacts import validate_run_contract
result = validate_run_contract(Path(sys.argv[1]))
print("OK" if result["ok"] else result)
PY
)"
assert_eq "report-only contract validates without release policy" "OK" "$report_status"

printf '# Check\n\n## Result\n\nPASS\n' > "$topic_dir/5_check.md"
printf '# Result\n\n## Outcome\n\nDone\n' > "$topic_dir/7_result.md"
printf '{"status":"pass"}\n' > "$topic_dir/evidence/latest-test.json"
audit_status="$(PYTHONPATH="$hook_root" python3 - "$topic_dir" <<'PY'
import sys
from pathlib import Path
from loen_artifacts import render_audit
base = Path(sys.argv[1])
text = render_audit(base, "sample-runner")
checks = [
    "Runner" in text,
    "report-only" in text,
    "plan_approved: true" in text,
    "Final verdict:</strong> Done" in text,
]
print("OK" if all(checks) else text[:500])
PY
)"
assert_eq "audit renders runner state" "OK" "$audit_status"

loop_start_text="$(cat "$loop_start")"
loop_run_text="$(cat "$loop_run")"
loop_governance_text="$(cat "$loop_governance")"
assert_contains "loop-start asks delivery or governance" "$loop_start_text" "delivery` or `governance"
assert_contains "loop-start asks governance subtype" "$loop_start_text" "report-only`, `auto-fix`, or `merge-release"
assert_contains "loop-start records plan approval" "$loop_start_text" "run.plan_approved"
assert_contains "loop-run documents state machine" "$loop_run_text" "prepare -> act -> check -> reflect"
assert_contains "loop-run refuses missing approval" "$loop_run_text" "plan approval"
assert_contains "loop-run supports merge release" "$loop_run_text" "merge-release"
assert_contains "governance skill names subtypes" "$loop_governance_text" "report-only"
assert_contains "README documents loop-run" "$(cat "$readme")" "loen:loop-run"
assert_contains "Russian README documents loop-run" "$(cat "$readme_ru")" "loen:loop-run"
assert_contains "architecture documents loop-run" "$(cat "$architecture")" "loop-run"

finish
```

- [ ] **Step 2: Run the failing test**

```bash
bash tests/test_loen_loop_run_contract.sh
```

Expected: failures mention missing `plugins/loen/skills/loop-run/SKILL.md`, missing `run:` template fields, missing parser data, or missing helper functions.

## Task 2: Implement Run Contract Parsing and Validation Helpers

**Files:**
- Modify: `plugins/loen/hooks/loen_common.py`
- Modify: `plugins/loen/hooks/loen_artifacts.py`
- Test: `tests/test_loen_loop_run_contract.sh`

- [ ] **Step 1: Extend YAML parsing for `run:` and `release_policy:`**

In `plugins/loen/hooks/loen_common.py`, initialize defaults in `parse_loop_yaml()`:

```python
"run": {
  "mode": "",
  "subtype": "",
  "plan_approved": False,
  "plan_hash": "",
  "state": "",
  "max_passes": 0,
  "current_pass": 0,
  "approval_source": "",
  "approved_at": "",
},
"release_policy": {
  "target_branch": "",
  "merge_strategy": "",
  "verifier_required": False,
  "evidence_required": False,
  "recovery_policy": "",
},
```

Add scalar parsing for integer fields:

```python
def _parse_run_scalar(key: str, value: str) -> Any:
  parsed = _parse_scalar(value)
  if key in {"max_passes", "current_pass"} and isinstance(parsed, str) and re.fullmatch(r"-?[0-9]+", parsed):
    return int(parsed)
  return parsed
```

Add a generic branch in the main loop before the `permissions` branch:

```python
if section in {"run", "release_policy"}:
  target = data[section]
  if ":" in stripped:
    key, value = stripped.split(":", 1)
    key = key.strip()
    parsed = _parse_inline_list(value)
    if parsed or value.strip() == "[]":
      target[key] = parsed
      list_target = None
    elif value.strip():
      target[key] = _parse_run_scalar(key, value)
      list_target = None
    else:
      target.setdefault(key, [])
      list_target = target[key]
  elif stripped.startswith("- ") and list_target is not None:
    list_target.append(stripped[2:].strip())
  continue
```

- [ ] **Step 2: Add hash, contract, and handoff helpers**

In `plugins/loen/hooks/loen_artifacts.py`, add imports:

```python
import hashlib
```

Add helpers near `governance_policy()`:

```python
def plan_body_hash(plan_path: Path) -> str:
  text = _read(plan_path)
  return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def _section_map(loop_text: str, section: str) -> dict[str, object]:
  from loen_common import parse_loop_yaml

  parsed = parse_loop_yaml(loop_text)
  value = parsed.get(section, {})
  return value if isinstance(value, dict) else {}


def run_contract(loop_text: str) -> dict[str, object]:
  return _section_map(loop_text, "run")


def release_policy(loop_text: str) -> dict[str, object]:
  return _section_map(loop_text, "release_policy")


def write_handoff(base: Path, reason: str, next_action: str) -> None:
  text = "\n".join([
    "# Handoff",
    "",
    "## Reason",
    "",
    reason,
    "",
    "## Next Action",
    "",
    next_action,
    "",
  ])
  (base / "handoff.md").write_text(text, encoding="utf-8")
```

Add validation:

```python
def validate_run_contract(base: Path) -> dict[str, object]:
  loop_text = _read(base / "loop.yaml")
  run = run_contract(loop_text)
  governance = governance_policy(loop_text)
  release = release_policy(loop_text)

  if run.get("plan_approved") is not True:
    return {"ok": False, "reason": "missing plan approval"}
  expected_hash = str(run.get("plan_hash", ""))
  actual_hash = plan_body_hash(base / "3_plan.md")
  if not expected_hash or expected_hash != actual_hash:
    return {"ok": False, "reason": "plan hash mismatch"}
  mode = str(run.get("mode", ""))
  subtype = str(run.get("subtype", "") or "")
  if mode not in {"delivery", "governance"}:
    return {"ok": False, "reason": "missing or unknown run mode"}
  if mode == "delivery" and subtype not in {"", "none", "null"}:
    return {"ok": False, "reason": "delivery run must not declare governance subtype"}
  if mode == "governance" and subtype not in {"report-only", "auto-fix", "merge-release"}:
    return {"ok": False, "reason": "missing or unknown governance subtype"}
  if mode == "governance" and subtype == "auto-fix" and governance.get("auto_fix") is not True:
    return {"ok": False, "reason": "auto-fix requires auto_fix: true"}
  if mode == "governance" and subtype == "merge-release":
    checks = [
      governance.get("auto_merge") is True,
      bool(release.get("target_branch")),
      bool(release.get("merge_strategy")),
      release.get("verifier_required") is True,
      release.get("evidence_required") is True,
      bool(release.get("recovery_policy")),
    ]
    if not all(checks):
      return {"ok": False, "reason": "merge-release policy incomplete"}
  return {"ok": True, "reason": "approved run contract"}
```

- [ ] **Step 3: Run contract test**

```bash
bash tests/test_loen_loop_run_contract.sh
```

Expected: parser and validation assertions pass; failures remain only for missing template/docs/skill text.

## Task 3: Extend Runtime Template and Audit Output

**Files:**
- Modify: `plugins/loen/assets/templates/loop.yaml`
- Modify: `plugins/loen/hooks/loen_artifacts.py`
- Test: `tests/test_loen_loop_run_contract.sh`
- Test: `tests/test_loen_runtime_artifacts.sh`

- [ ] **Step 1: Add `run:` and `release_policy:` blocks to template**

Insert after `rollback_policy` in `plugins/loen/assets/templates/loop.yaml`:

```yaml
run:
  mode: delivery
  subtype: null
  plan_approved: false
  plan_hash: ""
  state: prepare
  max_passes: 3
  current_pass: 0
  approval_source: ""
  approved_at: ""
```

Insert after `governance:` block:

```yaml
release_policy:
  target_branch: ""
  merge_strategy: ""
  verifier_required: true
  evidence_required: true
  recovery_policy: ""
```

- [ ] **Step 2: Add the same blocks to generated scaffold text**

In `loop_yaml_text()` inside `plugins/loen/hooks/loen_artifacts.py`, add the same `run:` and `release_policy:` lines. Keep defaults conservative:

```python
"run:",
"  mode: delivery",
"  subtype: null",
"  plan_approved: false",
'  plan_hash: ""',
"  state: prepare",
"  max_passes: 3",
"  current_pass: 0",
'  approval_source: ""',
'  approved_at: ""',
```

and:

```python
"release_policy:",
'  target_branch: ""',
'  merge_strategy: ""',
"  verifier_required: true",
"  evidence_required: true",
'  recovery_policy: ""',
```

- [ ] **Step 3: Render runner state in audit**

In `render_audit()`, compute:

```python
run = run_contract(loop_text)
release = release_policy(loop_text)
```

Add an HTML section after Current Status:

```python
"    <section>",
"      <h2>Runner</h2>",
f"      <p><strong>Mode:</strong> {html.escape(str(run.get('mode', '')))}</p>",
f"      <p><strong>Subtype:</strong> {html.escape(str(run.get('subtype', '')))}</p>",
f"      <p>plan_approved: {str(run.get('plan_approved') is True).lower()}</p>",
f"      <p><strong>Plan hash:</strong> {html.escape(str(run.get('plan_hash', '')))}</p>",
f"      <p><strong>State:</strong> {html.escape(str(run.get('state', '')))}</p>",
f"      <p><strong>Pass:</strong> {html.escape(str(run.get('current_pass', 0)))} / {html.escape(str(run.get('max_passes', 0)))}</p>",
f"      <p><strong>Release target:</strong> {html.escape(str(release.get('target_branch', '')))}</p>",
"    </section>",
```

- [ ] **Step 4: Run focused tests**

```bash
bash tests/test_loen_loop_run_contract.sh
bash tests/test_loen_runtime_artifacts.sh
```

Expected: both finish with `FAIL=0`.

## Task 4: Add `loen:loop-run` Skill Contract

**Files:**
- Create: `plugins/loen/skills/loop-run/SKILL.md`
- Modify: `plugins/loen/.codex-plugin/plugin.json`
- Test: `tests/test_loen_loop_run_contract.sh`
- Test: `tests/test_loen_plugin_core.sh`

- [ ] **Step 1: Create the runner skill**

Create `plugins/loen/skills/loop-run/SKILL.md`:

```markdown
---
name: loop-run
description: LoEn skill for running an approved topic state machine to 7_result.md or handoff.md.
---

# LoEn Loop Run

Use this skill when `docs/loen/<topic>/loop.yaml` contains an approved `run:` contract from `loen:loop-start` and the user asks to run that topic.

## Required Input

The user must name a topic slug, for example:

```text
loen:loop-run sample-topic
```

## Preflight

1. Read `docs/loen/<topic>/loop.yaml` and `docs/loen/<topic>/3_plan.md`.
2. Verify `run.plan_approved: true`.
3. Verify `run.plan_hash` matches the current `3_plan.md`.
4. Verify `run.mode` is `delivery` or `governance`.
5. For governance, verify `run.subtype` is `report-only`, `auto-fix`, or `merge-release`.
6. Verify scope, verifier, budget, rollback or recovery policy, and mode policy are present.
7. If any preflight fails, write `handoff.md` with the reason and stop.

## State Machine

Run this state machine:

```text
prepare -> act -> check -> reflect -> retry/fix -> result | handoff
```

Do not ask the user for manual `loop-act`, `loop-check`, or `loop-reflect` calls on the approved happy path.

## Mode Policy

### Delivery

Run inside approved `mutable_scope`, budget, verifier, and rollback policy. Write `4_act.md`, `5_check.md`, `6_reflect.md`, evidence, and either `7_result.md` or `handoff.md`.

### Governance report-only

Run checks, collect evidence, append `attempts.jsonl`, regenerate `audit.html`, and write `7_result.md` or `handoff.md`. Do not edit code.

### Governance auto-fix

Proceed only when `governance.auto_fix: true` is recorded by `loop-start` with mutable scope, verifier, budget, and rollback policy. Edits must stay inside approved scope.

### Governance merge-release

Proceed only when `governance.auto_merge: true` and `release_policy:` are recorded by `loop-start`. The policy must include target branch or release target, merge strategy, verifier requirement, evidence requirement, scope limits, and recovery policy. A second human approval immediately before merge or release is not required when the start-time approval and policy pass.

## Stop Rules

Write `handoff.md` and stop when plan approval is missing, plan hash mismatches, mode policy is incomplete, verifier fails without a bounded fix, protected scope is required, budget is exhausted, a forbidden tool is needed, or merge-release policy is incomplete.

## Output

Report the topic, final state, changed artifacts, evidence path, and whether the terminal artifact is `7_result.md` or `handoff.md`.
```

- [ ] **Step 2: Ensure plugin manifest discovers the skill**

Inspect `plugins/loen/.codex-plugin/plugin.json`. If skills are auto-discovered by directory and existing manifest has no explicit skill list, leave it unchanged. If the manifest lists skills explicitly, add `loop-run` using the same shape as existing entries.

Run:

```bash
python3 -m json.tool plugins/loen/.codex-plugin/plugin.json >/dev/null
```

Expected: exit `0`.

- [ ] **Step 3: Run plugin tests**

```bash
bash tests/test_loen_loop_run_contract.sh
bash tests/test_loen_plugin_core.sh
```

Expected: both finish with `FAIL=0`.

## Task 5: Update Existing Skill Contracts and User Docs

**Files:**
- Modify: `plugins/loen/skills/loop-start/SKILL.md`
- Modify: `plugins/loen/skills/loop-governance/SKILL.md`
- Modify: `plugins/loen/README.md`
- Modify: `plugins/loen/README.ru.md`
- Modify: `plugins/loen/docs/architecture.md`
- Test: `tests/test_loen_loop_run_contract.sh`
- Test: `tests/test_loen_overview_docs.sh`

- [ ] **Step 1: Update `loop-start` procedure**

Replace the existing procedure in `plugins/loen/skills/loop-start/SKILL.md` with a procedure that includes:

```markdown
1. Choose or validate a safe topic slug.
2. Create or reuse `docs/loen/<topic>/`.
3. Collect the user's objective, success criteria, constraints, mutable scope, protected scope, verifier command, budget, and rollback policy.
4. Ask the launch principle: `delivery` or `governance`.
5. If `governance`, ask the subtype: `report-only`, `auto-fix`, or `merge-release`.
6. Collect mode-specific parameters:
   - delivery: mutable scope, verifier, budget, rollback policy;
   - governance report-only: trigger or schedule, owner, verifier, evidence/report rules;
   - governance auto-fix: report-only fields plus mutable scope, rollback policy, fix budget, and explicit `auto_fix: true`;
   - governance merge-release: target branch or release target, merge strategy, verifier requirements, evidence requirements, scope limits, and recovery policy.
7. Create the standard topic files and evidence directory.
8. Write `3_plan.md` and present it for user approval before any automated run begins.
9. After approval, write `run.plan_approved: true`, `run.plan_hash`, `run.mode`, `run.subtype`, and policy fields in `loop.yaml`.
10. Offer to start `loen:loop-run <topic>` immediately, or report that exact command for later.
```

- [ ] **Step 2: Update `loop-governance` language**

Add a section to `plugins/loen/skills/loop-governance/SKILL.md`:

```markdown
## Governance Subtypes

- `report-only`: default; run checks, evidence, attempts, and audit without code edits.
- `auto-fix`: allowed only when `loop-start` recorded `auto_fix: true`, mutable scope, verifier, budget, and rollback policy.
- `merge-release`: allowed only when `loop-start` recorded `auto_merge: true` plus `release_policy:` with target, strategy, verifier requirement, evidence requirement, scope limits, and recovery policy.
```

- [ ] **Step 3: Update README docs**

In `plugins/loen/README.md` and `plugins/loen/README.ru.md`, update the "Работа с loop" / loop workflow sections to include:

```text
loen:loop-start
  -> choose delivery or governance
  -> approve plan
  -> loen:loop-run <topic>
  -> 7_result.md or handoff.md
```

Also state that manual `loop-plan`, `loop-act`, `loop-check`, and `loop-reflect` remain supported.

- [ ] **Step 4: Update architecture docs**

In `plugins/loen/docs/architecture.md`, add a `Loop Runner` section that documents:

```text
loop-start -> run contract in loop.yaml -> loop-run state machine -> result/handoff
```

Mention `run:`, `release_policy:`, governance subtypes, audit visibility, and manual compatibility.

- [ ] **Step 5: Run docs tests**

```bash
bash tests/test_loen_loop_run_contract.sh
bash tests/test_loen_overview_docs.sh
```

Expected: both finish with `FAIL=0`.

## Task 6: Update iwiki and Run Full Verification

**Files:**
- Modify via MCP: iwiki pages `loen-overview`, `loen-runtime-artifacts`, `loen-automation-governance`
- Read: `docs/superpowers/specs/2026-07-08-loen-loop-run-design.md`
- Test: focused and full Bash suites

- [ ] **Step 1: Run focused LoEn verification**

```bash
bash tests/test_loen_loop_run_contract.sh
bash tests/test_loen_runtime_artifacts.sh
bash tests/test_loen_automation_governance.sh
bash tests/test_loen_plugin_core.sh
bash tests/test_loen_overview_docs.sh
python3 -m py_compile plugins/loen/hooks/*.py
```

Expected: every Bash test ends with `FAIL=0`; `py_compile` exits `0`.

- [ ] **Step 2: Run full Bash suite**

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: command exits `0`.

- [ ] **Step 3: Update iwiki pages**

Use iwiki MCP tools:

```text
wiki_update_page(domain="icodex", slug="loen-overview", heading="Layer Sequence", new_body=...)
wiki_update_page(domain="icodex", slug="loen-runtime-artifacts", heading="Loop Contract", new_body=...)
wiki_update_page(domain="icodex", slug="loen-automation-governance", heading="Governance Policy", new_body=...)
wiki_lint(domain="icodex")
```

Expected: wiki reflects `loop-start` intake, `loop-run` state machine, `run:` contract, governance subtypes, and merge-release policy. `wiki_lint` has no broken refs or stale pages caused by this change.

- [ ] **Step 4: Inspect git diff for scope**

```bash
git diff --stat
git diff -- plugins/loen tests docs/superpowers/plans/2026-07-08-loen-loop-run.md
```

Expected: changes are limited to LoEn plugin source, focused tests, docs, iwiki through MCP, and chain artifacts.

- [ ] **Step 5: Run result chain gate after implementation**

```text
/check-chain result docs/superpowers/plans/2026-07-08-loen-loop-run.md
```

Expected: `OK` only after implementation, tests, docs, and iwiki are consistent.

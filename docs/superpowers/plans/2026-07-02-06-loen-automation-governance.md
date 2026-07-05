---
review:
  plan_hash: 97025827d6f37f89
  last_run: 2026-07-05
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: null
  spec: docs/superpowers/specs/2026-07-02-06-loen-automation-governance-design.md
---

# 06 LoEn Automation Governance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the later LoEn automation-governance layer so scheduled or background runs remain review-gated, artifact-backed, and bound by existing LoEn modes and safety hooks.

**Architecture:** Keep governance behavior inside the LoEn plugin source tree under `plugins/loen/`. Parse optional `loop.yaml` governance fields through the existing dependency-free YAML parser, add artifact helpers that append automated attempts and expose review-required state, extend `audit.html` with governance status, and prove existing hooks still enforce `LOEN_MODE`, evidence gates, and protected-scope rules for scheduled runs.

**Tech Stack:** Bash fixture tests, Python 3 standard library, existing LoEn hook scripts, existing LoEn runtime artifacts, iwiki MCP docs updates after implementation.

Spec: `docs/superpowers/specs/2026-07-02-06-loen-automation-governance-design.md`

---

## Scope Check

This spec covers one subsystem: optional LoEn automation governance for already-established LoEn topic artifacts. It does not add a scheduler daemon, background process manager, CI integration, dependency scanner, evaluator, notification transport, auto-merge behavior, or new icodex launch wiring. The deliverable is a deterministic local governance contract that later schedulers can call safely.

Automated runs must reuse `docs/loen/<topic>/` artifacts, append to `attempts.jsonl`, regenerate `audit.html`, and obey existing hooks. Risky unattended behavior stays disabled by default: `auto_merge: false`, `auto_fix: false`, first-run human review counters, protected-scope blocking, evidence blocking, and `LOEN_MODE` enforcement.

## File Structure

- **Create** `tests/test_loen_automation_governance.sh` - focused fixture suite for governance defaults, first-run review counters, automated attempt persistence, audit regeneration, hook enforcement, and skill/docs coverage.
- **Modify** `plugins/loen/assets/templates/loop.yaml` - add optional governance defaults and automation type metadata to the runtime contract template.
- **Modify** `plugins/loen/hooks/loen_common.py` - parse `governance:` maps, nested `automation:` metadata, booleans, integers, and list fields without external dependencies.
- **Modify** `plugins/loen/hooks/loen_artifacts.py` - add governance policy defaults, automated attempt append helpers, audit governance summary rendering, and review-required counter logic.
- **Modify** `plugins/loen/hooks/audit-writer.py` - continue delegating to `render_audit`; no new side effects beyond regenerated audit output and task-log upsert.
- **Modify** `plugins/loen/skills/loop-governance/SKILL.md` - document exact procedure and output for recurring or scheduled governance topics.
- **Modify** `plugins/loen/docs/README.md` and `plugins/loen/docs/architecture.md` - document automation-governance boundaries, defaults, artifacts, and non-goals.
- **Update via iwiki MCP** `loen-overview` and create `loen-automation-governance` after code passes.
- **Do not modify** `icodex.sh`, `lib/plugin/loen.sh`, `scripts/vendor-loen.sh`, or `.codex-isolated/plugins/cache/` in implementation tasks. Regenerate the vendored cache only in a follow-up integration sync if the project explicitly asks.

## Execution Prerequisites

Use the project branch workflow before Task 1. The current task row already exists in `docs/TODO.md` as `06-loen-automation-governance`. Run every command from the repository root.

The spec gate is recorded in `docs/superpowers/specs/2026-07-02-06-loen-automation-governance-design.md` with hash `b57a4a435ec38bb5`. If the spec body changes, rerun:

```text
/check-chain spec docs/superpowers/specs/2026-07-02-06-loen-automation-governance-design.md
```

Expected: `OK` or `OK (cached, hash match)`.

---

### Task 1: Add Automation Governance Fixture Coverage

**Files:**
- Create: `tests/test_loen_automation_governance.sh`
- Read: `tests/helpers.sh`
- Read: `docs/superpowers/specs/2026-07-02-06-loen-automation-governance-design.md`

- [ ] **Step 1: Write the failing governance fixture suite**

Create `tests/test_loen_automation_governance.sh` with this content:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

plugin_root="$ROOT/plugins/loen"
hook_root="$plugin_root/hooks"
artifact_module="$hook_root/loen_artifacts.py"
common_module="$hook_root/loen_common.py"
audit_writer="$hook_root/audit-writer.py"
loop_template="$plugin_root/assets/templates/loop.yaml"
governance_skill="$plugin_root/skills/loop-governance/SKILL.md"
readme="$plugin_root/docs/README.md"
architecture="$plugin_root/docs/architecture.md"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

artifact_root="$tmp/docs/loen"
topic="governance-topic"
topic_dir="$artifact_root/$topic"
mkdir -p "$topic_dir/evidence"

cat > "$topic_dir/loop.yaml" <<'YAML'
topic: governance-topic
mode: delivery
status: active
objective: "Run dependency audit governance safely"
current_stage: check
stage: check
mutable_scope:
  - plugins/loen/**
  - tests/**
protected_scope:
  - .codex-isolated/auth/**
  - secrets/**
quality_gates:
  - command: bash tests/test_loen_automation_governance.sh
    evidence: evidence/governance-check.json
verifier:
  type: test
  command: bash tests/test_loen_automation_governance.sh
budget:
  max_iterations: 3
stop_conditions:
  - quality gates pass
handoff_conditions:
  - protected scope requested
rollback_policy: "Stop automation and hand off to a human"
governance:
  automation_type: dependency-audit
  schedule: "weekday 09:00"
  owner: "maintainer"
  first_runs_require_human_review: 2
  reviewed_runs: 0
  auto_fix: false
  auto_merge: false
  report_only_on_no_findings: true
  alert_on:
    - protected_scope_attempt
    - verifier_failure
    - budget_exhausted
    - metric_regression
YAML

touch "$topic_dir/1_goal.md" "$topic_dir/2_context.md" "$topic_dir/3_plan.md" "$topic_dir/4_act.md" "$topic_dir/5_check.md" "$topic_dir/6_reflect.md"
printf '# Result\n\n## Outcome\n\nPending\n' > "$topic_dir/7_result.md"

assert_exit "artifact module exists" 0 test -f "$artifact_module"
assert_exit "common module exists" 0 test -f "$common_module"
assert_exit "audit writer exists" 0 test -f "$audit_writer"

template_text="$(cat "$loop_template" 2>/dev/null || true)"
assert_contains "loop template includes governance section" "$template_text" "governance:"
assert_contains "loop template defaults auto fix off" "$template_text" "auto_fix: false"
assert_contains "loop template defaults auto merge off" "$template_text" "auto_merge: false"
assert_contains "loop template requires first-run review" "$template_text" "first_runs_require_human_review:"
assert_contains "loop template lists protected scope alert" "$template_text" "protected_scope_attempt"
assert_contains "loop template lists verifier failure alert" "$template_text" "verifier_failure"

parse_status="$(PYTHONPATH="$hook_root" python3 - "$topic_dir/loop.yaml" <<'PY'
import sys
from pathlib import Path

from loen_common import parse_loop_yaml

data = parse_loop_yaml(Path(sys.argv[1]).read_text(encoding="utf-8"))
governance = data.get("governance", {})
checks = [
    governance.get("automation_type") == "dependency-audit",
    governance.get("schedule") == "weekday 09:00",
    governance.get("owner") == "maintainer",
    governance.get("first_runs_require_human_review") == 2,
    governance.get("reviewed_runs") == 0,
    governance.get("auto_fix") is False,
    governance.get("auto_merge") is False,
    governance.get("report_only_on_no_findings") is True,
    "protected_scope_attempt" in governance.get("alert_on", []),
    "metric_regression" in governance.get("alert_on", []),
]
print("OK" if all(checks) else governance)
PY
)"
assert_eq "governance yaml parses typed fields" "OK" "$parse_status"

defaults_status="$(PYTHONPATH="$hook_root" python3 - <<'PY'
from loen_artifacts import governance_policy

policy = governance_policy("topic: plain\nstatus: active\n")
checks = [
    policy["schedule"] == "",
    policy["first_runs_require_human_review"] == 0,
    policy["reviewed_runs"] == 0,
    policy["auto_fix"] is False,
    policy["auto_merge"] is False,
    policy["report_only_on_no_findings"] is True,
    "protected_scope_attempt" in policy["alert_on"],
    "verifier_failure" in policy["alert_on"],
    "budget_exhausted" in policy["alert_on"],
    "metric_regression" in policy["alert_on"],
]
print("OK" if all(checks) else policy)
PY
)"
assert_eq "governance defaults are safe" "OK" "$defaults_status"

attempt_status="$(PYTHONPATH="$hook_root" python3 - "$topic_dir" <<'PY'
import json
import sys
from pathlib import Path

from loen_artifacts import append_automation_attempt, governance_policy

base = Path(sys.argv[1])
first = append_automation_attempt(
    base=base,
    run_type="dependency-audit",
    status="pass",
    summary="No vulnerable dependencies found.",
    evidence_path="evidence/governance-check.json",
    reviewed=False,
    created_at="2026-07-05T09:00:00Z",
)
second = append_automation_attempt(
    base=base,
    run_type="dependency-audit",
    status="pass",
    summary="No vulnerable dependencies found on second run.",
    evidence_path="evidence/governance-check-2.json",
    reviewed=True,
    created_at="2026-07-06T09:00:00Z",
)
lines = [json.loads(line) for line in (base / "attempts.jsonl").read_text(encoding="utf-8").splitlines()]
policy = governance_policy((base / "loop.yaml").read_text(encoding="utf-8"))
checks = [
    first["review_required"] is True,
    first["effective_status"] == "review_required",
    second["review_required"] is True,
    second["effective_status"] == "pass",
    len(lines) == 2,
    lines[0]["automation"] is True,
    lines[0]["run_type"] == "dependency-audit",
    lines[0]["review_required"] is True,
    lines[1]["reviewed"] is True,
    policy["auto_merge"] is False,
]
print("OK" if all(checks) else {"first": first, "second": second, "lines": lines, "policy": policy})
PY
)"
assert_eq "first automated runs require human review" "OK" "$attempt_status"

printf '{"status":"pass","command":"bash tests/test_loen_automation_governance.sh"}\n' > "$topic_dir/evidence/governance-check.json"
assert_exit "audit writer runs for governance topic" 0 env LOEN_TOPIC="$topic" LOEN_ARTIFACT_ROOT="$artifact_root" LOEN_TODO_PATH="$tmp/TODO.md" python3 "$audit_writer"
audit_text="$(cat "$topic_dir/audit.html" 2>/dev/null || true)"
assert_contains "audit shows governance section" "$audit_text" "Governance"
assert_contains "audit shows automation type" "$audit_text" "dependency-audit"
assert_contains "audit shows schedule" "$audit_text" "weekday 09:00"
assert_contains "audit shows review requirement" "$audit_text" "Human review required"
assert_contains "audit shows automated attempts section" "$audit_text" "Automated Attempts"
assert_contains "audit shows automated attempt summary" "$audit_text" "No vulnerable dependencies found"
assert_contains "audit shows no auto merge" "$audit_text" "auto_merge: false"

run_hook() {
  local hook="$1" mode="$2" topic_value="$3" payload="$4"
  env LOEN_MODE="$mode" LOEN_TOPIC="$topic_value" LOEN_ARTIFACT_ROOT="$artifact_root" LOEN_TODO_PATH="$tmp/TODO.md" \
    python3 "$hook_root/$hook" <<<"$payload" >/dev/null 2>&1
}

assert_hook_exit() {
  local desc="$1" expected="$2" hook="$3" mode="$4" topic_value="$5" payload="$6" code=0
  run_hook "$hook" "$mode" "$topic_value" "$payload" || code=$?
  assert_eq "$desc" "$expected" "$code"
}

protected_automation_patch='{"automation":true,"run_type":"dependency-audit","tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Update File: secrets/token.txt\n@@\n-old\n+new\n*** End Patch\n"}}'
allowed_automation_patch='{"automation":true,"run_type":"dependency-audit","tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Update File: tests/test_loen_automation_governance.sh\n@@\n-old\n+new\n*** End Patch\n"}}'
automation_done='{"automation":true,"run_type":"dependency-audit","verdict":"done","agent_role":"verifier","worker_role":"worker-agent","verifier_role":"verifier-agent"}'

missing_topic="missing-loop"
assert_hook_exit "scheduled mode does not bypass off mode" 0 "loop-gate.py" "off" "$missing_topic" "$allowed_automation_patch"
assert_hook_exit "scheduled mode does not bypass enforce loop requirement" 2 "loop-gate.py" "enforce" "$missing_topic" "$allowed_automation_patch"
assert_hook_exit "scheduled mode allows active loop edit in enforce" 0 "loop-gate.py" "enforce" "$topic" "$allowed_automation_patch"
assert_hook_exit "scheduled mode does not bypass protected scope" 2 "scope-guard.py" "enforce" "$topic" "$protected_automation_patch"

rm -f "$topic_dir/7_result.md" "$topic_dir/verifier-verdict.md"
rm -rf "$topic_dir/evidence"
assert_hook_exit "scheduled mode does not bypass evidence gate" 2 "evidence-gate.py" "enforce" "$topic" "$automation_done"
mkdir -p "$topic_dir/evidence"
touch "$topic_dir/7_result.md" "$topic_dir/verifier-verdict.md" "$topic_dir/evidence/governance-check.json"
assert_hook_exit "scheduled mode passes evidence gate with artifacts" 0 "evidence-gate.py" "strict" "$topic" "$automation_done"

assert_contains "governance skill documents recurrence" "$(cat "$governance_skill" 2>/dev/null)" "Record recurrence, owner, and review requirement"
assert_contains "governance skill forbids auto merge" "$(cat "$governance_skill" 2>/dev/null)" "auto-merge"
assert_contains "README documents automation governance" "$(cat "$readme" 2>/dev/null)" "Automation Governance"
assert_contains "architecture documents automation governance" "$(cat "$architecture" 2>/dev/null)" "Automation Governance"

finish
```

- [ ] **Step 2: Run the new test to verify it fails**

Run:

```bash
bash tests/test_loen_automation_governance.sh
```

Expected: FAIL. The current tree has no parsed `governance` map, no `governance_policy` or `append_automation_attempt` helpers, and no governance section in the audit output. Expected failing lines include:

```text
FAIL [loop template includes governance section]: 'governance:' not found
FAIL [governance yaml parses typed fields]: ...
FAIL [governance defaults are safe]: ...
FAIL [audit shows governance section]: 'Governance' not found
```

- [ ] **Step 3: Syntax-check the test**

Run:

```bash
bash -n tests/test_loen_automation_governance.sh
```

Expected: exit code `0`.

- [ ] **Step 4: Commit the failing test**

Run:

```bash
git add tests/test_loen_automation_governance.sh
git commit -m "test(loen): add automation governance contract"
```

Expected: commit succeeds. Do not stage unrelated files.

---

### Task 2: Parse Governance Fields and Template Defaults

**Files:**
- Modify: `plugins/loen/hooks/loen_common.py`
- Modify: `plugins/loen/assets/templates/loop.yaml`
- Test: `tests/test_loen_automation_governance.sh`

- [ ] **Step 1: Extend `parse_loop_yaml` with governance defaults**

In `plugins/loen/hooks/loen_common.py`, add this key to the initial `data` dictionary inside `parse_loop_yaml`:

```python
    "governance": {
      "automation_type": "",
      "schedule": "",
      "owner": "",
      "first_runs_require_human_review": 0,
      "reviewed_runs": 0,
      "auto_fix": False,
      "auto_merge": False,
      "report_only_on_no_findings": True,
      "alert_on": [],
    },
```

In the same file, replace `_parse_scalar` with this implementation:

```python
def _parse_scalar(value: str) -> Any:
  value = value.strip().strip('"').strip("'")
  lowered = value.lower()
  if lowered == "true":
    return True
  if lowered == "false":
    return False
  if re.fullmatch(r"-?[0-9]+", value):
    return int(value)
  return value
```

Still in `parse_loop_yaml`, add this section handler before the final `if section == "permissions":` block:

```python
    if section == "governance":
      target = data["governance"]
      if ":" in stripped:
        key, value = stripped.split(":", 1)
        key = key.strip()
        parsed = _parse_inline_list(value)
        if parsed or value.strip() == "[]":
          target[key] = parsed
          list_target = None
        elif value.strip():
          target[key] = _parse_scalar(value)
          list_target = None
        else:
          target.setdefault(key, [])
          list_target = target[key]
      elif stripped.startswith("- ") and list_target is not None:
        list_target.append(stripped[2:].strip())
      continue
```

- [ ] **Step 2: Add governance defaults to the loop template**

In `plugins/loen/assets/templates/loop.yaml`, add this block after `rollback_policy: "Revert unsafe changes"`:

```yaml
governance:
  automation_type: manual
  schedule: ""
  owner: ""
  first_runs_require_human_review: 3
  reviewed_runs: 0
  auto_fix: false
  auto_merge: false
  report_only_on_no_findings: true
  alert_on:
    - protected_scope_attempt
    - verifier_failure
    - budget_exhausted
    - metric_regression
```

- [ ] **Step 3: Run the focused test and inspect the remaining failures**

Run:

```bash
bash tests/test_loen_automation_governance.sh
```

Expected: FAIL remains only for missing artifact helpers, audit governance rendering, and docs text. The parsing assertions should pass:

```text
PASS [loop template includes governance section]
PASS [governance yaml parses typed fields]
```

- [ ] **Step 4: Run syntax checks for changed Python**

Run:

```bash
python3 -m py_compile plugins/loen/hooks/loen_common.py
```

Expected: exit code `0`.

- [ ] **Step 5: Commit parser and template changes**

Run:

```bash
git add plugins/loen/hooks/loen_common.py plugins/loen/assets/templates/loop.yaml
git commit -m "feat(loen): parse automation governance policy"
```

Expected: commit succeeds.

---

### Task 3: Add Governance Artifact Helpers and Audit Rendering

**Files:**
- Modify: `plugins/loen/hooks/loen_artifacts.py`
- Modify: `plugins/loen/hooks/audit-writer.py`
- Test: `tests/test_loen_automation_governance.sh`

- [ ] **Step 1: Add JSON import and governance dataclass**

In `plugins/loen/hooks/loen_artifacts.py`, add `import json` beside the existing imports, then add this dataclass after `LoopSummary`:

```python
@dataclass(frozen=True)
class GovernanceSummary:
  automation_type: str
  schedule: str
  owner: str
  first_runs_require_human_review: int
  reviewed_runs: int
  auto_fix: bool
  auto_merge: bool
  report_only_on_no_findings: bool
  alert_on: list[str]
  automated_attempts: list[dict[str, object]]
```

- [ ] **Step 2: Add governance parsing and attempt helpers**

In `plugins/loen/hooks/loen_artifacts.py`, add these functions after `_yaml_section_list`:

```python
def _parse_bool(value: str, default: bool) -> bool:
  lowered = value.strip().strip('"').strip("'").lower()
  if lowered == "true":
    return True
  if lowered == "false":
    return False
  return default


def _parse_int(value: str, default: int) -> int:
  try:
    return int(value.strip().strip('"').strip("'"))
  except ValueError:
    return default


def governance_policy(loop_text: str) -> dict[str, object]:
  policy: dict[str, object] = {
    "automation_type": "",
    "schedule": "",
    "owner": "",
    "first_runs_require_human_review": 0,
    "reviewed_runs": 0,
    "auto_fix": False,
    "auto_merge": False,
    "report_only_on_no_findings": True,
    "alert_on": [
      "protected_scope_attempt",
      "verifier_failure",
      "budget_exhausted",
      "metric_regression",
    ],
  }
  in_governance = False
  list_key = ""
  for raw in loop_text.splitlines():
    if raw == "governance:":
      in_governance = True
      list_key = ""
      continue
    if in_governance and raw and not raw.startswith(" "):
      break
    if not in_governance:
      continue
    stripped = raw.strip()
    if not stripped:
      continue
    if stripped.startswith("- ") and list_key:
      values = policy.setdefault(list_key, [])
      if isinstance(values, list):
        values.append(stripped[2:].strip().strip('"'))
      continue
    if ":" not in stripped:
      continue
    key, value = stripped.split(":", 1)
    key = key.strip()
    value = value.strip()
    if not value:
      policy.setdefault(key, [])
      list_key = key
      continue
    list_key = ""
    if key in {"auto_fix", "auto_merge", "report_only_on_no_findings"}:
      policy[key] = _parse_bool(value, bool(policy[key]))
    elif key in {"first_runs_require_human_review", "reviewed_runs"}:
      policy[key] = _parse_int(value, int(policy[key]))
    else:
      policy[key] = value.strip('"').strip("'")
  return policy


def _automation_attempts(base: Path) -> list[dict[str, object]]:
  attempts: list[dict[str, object]] = []
  for line in _read(base / "attempts.jsonl").splitlines():
    if not line.strip():
      continue
    try:
      data = json.loads(line)
    except json.JSONDecodeError:
      continue
    if isinstance(data, dict) and data.get("automation") is True:
      attempts.append(data)
  return attempts


def _governance_summary(base: Path, loop_text: str) -> GovernanceSummary:
  policy = governance_policy(loop_text)
  attempts = _automation_attempts(base)
  return GovernanceSummary(
    automation_type=str(policy["automation_type"]),
    schedule=str(policy["schedule"]),
    owner=str(policy["owner"]),
    first_runs_require_human_review=int(policy["first_runs_require_human_review"]),
    reviewed_runs=int(policy["reviewed_runs"]),
    auto_fix=bool(policy["auto_fix"]),
    auto_merge=bool(policy["auto_merge"]),
    report_only_on_no_findings=bool(policy["report_only_on_no_findings"]),
    alert_on=list(policy["alert_on"]) if isinstance(policy["alert_on"], list) else [],
    automated_attempts=attempts,
  )


def append_automation_attempt(
  *,
  base: Path,
  run_type: str,
  status: str,
  summary: str,
  evidence_path: str = "",
  reviewed: bool = False,
  created_at: str = "",
) -> dict[str, object]:
  loop_text = _read(base / "loop.yaml")
  policy = governance_policy(loop_text)
  previous = _automation_attempts(base)
  review_limit = int(policy["first_runs_require_human_review"])
  reviewed_runs = int(policy["reviewed_runs"]) + len([item for item in previous if item.get("reviewed") is True])
  review_required = len(previous) < review_limit and reviewed_runs < review_limit
  effective_status = status if reviewed or not review_required else "review_required"
  record: dict[str, object] = {
    "automation": True,
    "run_type": run_type,
    "status": status,
    "effective_status": effective_status,
    "summary": summary,
    "evidence": evidence_path,
    "review_required": review_required,
    "reviewed": reviewed,
    "created_at": created_at,
  }
  attempts_path = base / "attempts.jsonl"
  attempts_path.parent.mkdir(parents=True, exist_ok=True)
  with attempts_path.open("a", encoding="utf-8") as handle:
    handle.write(json.dumps(record, sort_keys=True) + "\n")
  return record
```

- [ ] **Step 3: Render governance sections in `audit.html`**

In `plugins/loen/hooks/loen_artifacts.py`, inside `render_audit`, add this assignment after `summary = _summary_from_loop(loop_text, topic)`:

```python
  governance = _governance_summary(base, loop_text)
```

Then add these local values before `sections = [`:

```python
  review_required = len(governance.automated_attempts) < governance.first_runs_require_human_review
  review_text = "Human review required" if review_required else "Human review window complete"
  alert_html = "\n".join(f"<li>{html.escape(value)}</li>" for value in governance.alert_on) or "<li>No alerts configured.</li>"
  attempt_html = "\n".join(
    "<li>"
    f"{html.escape(str(item.get('created_at', '')))} "
    f"{html.escape(str(item.get('run_type', '')))} "
    f"{html.escape(str(item.get('effective_status', item.get('status', ''))))}: "
    f"{html.escape(str(item.get('summary', '')))}"
    "</li>"
    for item in governance.automated_attempts
  ) or "<li>No automated attempts recorded.</li>"
```

Add these two sections in the returned HTML after the `Budget and Stop/Handoff State` section and before `Protected Scope Findings`:

```python
    "    <section>",
    "      <h2>Governance</h2>",
    f"      <p><strong>Automation type:</strong> {html.escape(governance.automation_type or 'manual')}</p>",
    f"      <p><strong>Schedule:</strong> {html.escape(governance.schedule or 'none')}</p>",
    f"      <p><strong>Owner:</strong> {html.escape(governance.owner or 'none')}</p>",
    f"      <p><strong>Review:</strong> {html.escape(review_text)}</p>",
    f"      <p><strong>auto_fix:</strong> {str(governance.auto_fix).lower()}</p>",
    f"      <p><strong>auto_merge:</strong> {str(governance.auto_merge).lower()}</p>",
    f"      <p><strong>report_only_on_no_findings:</strong> {str(governance.report_only_on_no_findings).lower()}</p>",
    f"      <ul>{alert_html}</ul>",
    "    </section>",
    "    <section>",
    "      <h2>Automated Attempts</h2>",
    f"      <ul>{attempt_html}</ul>",
    "    </section>",
```

- [ ] **Step 4: Keep `audit-writer.py` unchanged except import health**

Run:

```bash
python3 -m py_compile plugins/loen/hooks/audit-writer.py
```

Expected: exit code `0`. If this fails because `loen_artifacts.py` has a syntax error, fix `loen_artifacts.py`; do not add logic to `audit-writer.py`.

- [ ] **Step 5: Run the focused governance suite**

Run:

```bash
bash tests/test_loen_automation_governance.sh
```

Expected: FAIL remains only for skill and docs text if Task 4 has not run. Governance parser, helper, audit, and hook assertions should pass.

- [ ] **Step 6: Run artifact syntax checks**

Run:

```bash
python3 -m py_compile plugins/loen/hooks/loen_artifacts.py plugins/loen/hooks/audit-writer.py
```

Expected: exit code `0`.

- [ ] **Step 7: Commit artifact helper changes**

Run:

```bash
git add plugins/loen/hooks/loen_artifacts.py plugins/loen/hooks/audit-writer.py
git commit -m "feat(loen): record automation governance attempts"
```

Expected: commit succeeds. If `audit-writer.py` has no diff, omit it from `git add`.

---

### Task 4: Document Governance Skill and Plugin Boundaries

**Files:**
- Modify: `plugins/loen/skills/loop-governance/SKILL.md`
- Modify: `plugins/loen/docs/README.md`
- Modify: `plugins/loen/docs/architecture.md`
- Test: `tests/test_loen_automation_governance.sh`

- [ ] **Step 1: Replace `loop-governance` procedure with exact governance contract**

Replace `plugins/loen/skills/loop-governance/SKILL.md` with:

```markdown
---
name: loop-governance
description: LoEn skill for scheduled or recurring checks with governance artifacts under docs/loen/<topic>/.
---

# LoEn Loop Governance

Use this skill when a LoEn topic represents a recurring check, scheduled governance pass, dependency audit, CI triage report, eval drift check, or cost/latency comparison.

## Procedure

1. Record recurrence, owner, and review requirement in `docs/loen/<topic>/loop.yaml` under `governance:`.
2. Keep scheduled activity advisory unless the repository owner explicitly enables stricter `LOEN_MODE`.
3. Record every run in `attempts.jsonl` with `automation: true`, `run_type`, status, summary, evidence path, review flags, and timestamp.
4. Require human review before any merge, release, destructive operation, protected-scope edit, or first-run completion within `first_runs_require_human_review`.
5. Keep `auto_merge: false` and `auto_fix: false` unless a later integration layer adds explicit reviewed support.
6. Run the topic verifier and regenerate `audit.html` after each scheduled attempt.

## Output

Report schedule, owner, latest evidence, whether human review is still required, alert reasons, and next run condition.
```

- [ ] **Step 2: Add README automation governance section**

Append this section to `plugins/loen/docs/README.md`:

```markdown
## Automation Governance

LoEn supports optional governance metadata for later scheduled or background runs. The source layer records the policy in `docs/loen/<topic>/loop.yaml`, appends automated run records to `attempts.jsonl`, and renders governance state in the per-topic `audit.html`.

Governance defaults are conservative: `auto_fix: false`, `auto_merge: false`, `report_only_on_no_findings: true`, and first scheduled runs require human review when `first_runs_require_human_review` is greater than zero. Automation does not bypass `LOEN_MODE`, protected-scope checks, evidence gates, or worker/verifier separation.
```

- [ ] **Step 3: Add architecture automation governance section**

Append this section to `plugins/loen/docs/architecture.md`:

```markdown
## Automation Governance

The automation-governance layer is a contract, not a scheduler. Future CI triage, PR babysitting, dependency audit, eval governance, and cost/latency governance integrations can call the same topic artifact APIs, but this repository only stores deterministic policy and evidence.

Scheduled runs reuse `docs/loen/<topic>/`, append JSON records to `attempts.jsonl`, preserve verifier evidence under `evidence/`, and regenerate `audit.html`. Existing hooks still enforce active-loop state, protected scope, shell/network policy, evidence requirements, and `LOEN_MODE`; automation payloads are treated as ordinary tool events with extra metadata.
```

- [ ] **Step 4: Run the focused governance suite**

Run:

```bash
bash tests/test_loen_automation_governance.sh
```

Expected: PASS summary from `tests/helpers.sh`, with zero failures.

- [ ] **Step 5: Commit docs and skill changes**

Run:

```bash
git add plugins/loen/skills/loop-governance/SKILL.md plugins/loen/docs/README.md plugins/loen/docs/architecture.md
git commit -m "docs(loen): describe automation governance boundaries"
```

Expected: commit succeeds.

---

### Task 5: Verify, Update Wiki, and Close Chain

**Files:**
- Test: `tests/test_loen_automation_governance.sh`
- Test: `tests/test_loen_runtime_artifacts.sh`
- Test: `tests/test_loen_enforcement_hooks.sh`
- Test: `tests/test_loen_agent_isolation.sh`
- Test: full Bash suite
- Update via iwiki MCP: `loen-overview`
- Create via iwiki MCP: `loen-automation-governance`
- Validate: `docs/superpowers/plans/2026-07-02-06-loen-automation-governance.md`

- [ ] **Step 1: Run focused LoEn suites**

Run:

```bash
bash tests/test_loen_automation_governance.sh
bash tests/test_loen_runtime_artifacts.sh
bash tests/test_loen_enforcement_hooks.sh
bash tests/test_loen_agent_isolation.sh
```

Expected: every command exits `0`.

- [ ] **Step 2: Run Python syntax checks for LoEn hooks**

Run:

```bash
python3 -m py_compile plugins/loen/hooks/*.py
```

Expected: exit code `0`.

- [ ] **Step 3: Run full Bash suite**

Run:

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: exit code `0`.

- [ ] **Step 4: Update iwiki overview**

Use iwiki MCP tools, not local markdown edits:

```text
wiki_update_page(domain="icodex", slug="loen-overview", heading="Layer Sequence", new_body=<updated layer table that marks 06 automation governance as implemented and links [[loen-automation-governance]]>, source="plugins/loen/hooks/loen_artifacts.py")
```

Expected: tool succeeds and reindexes the domain.

- [ ] **Step 5: Create automation governance wiki page**

Use iwiki MCP tools:

```text
wiki_write_page(domain="icodex", slug="loen-automation-governance", markdown=<page documenting governance defaults, artifact flow, review counters, hook enforcement, and validation commands>, source="plugins/loen/hooks/loen_artifacts.py")
```

Expected: tool succeeds and reindexes the domain.

- [ ] **Step 6: Run iwiki lint**

Use iwiki MCP:

```text
wiki_lint(domain="icodex")
```

Expected: no broken refs, no orphans, no stale pages. Existing advisory style warnings may remain.

- [ ] **Step 7: Run result reconciliation**

Run:

```text
/check-chain result docs/superpowers/plans/2026-07-02-06-loen-automation-governance.md
```

Expected: `OK`; report `docs/superpowers/reports/06-loen-automation-governance-results.html` has result tab updated; `docs/TODO.md` row `06-loen-automation-governance` is `done`.

- [ ] **Step 8: Commit verification/doc state**

Run:

```bash
git add docs/superpowers/plans/2026-07-02-06-loen-automation-governance.md docs/superpowers/reports/06-loen-automation-governance-results.html docs/TODO.md
git commit -m "chore(loen): close automation governance chain"
```

Expected: commit succeeds if chain artifacts changed. If chain artifacts are already staged in a previous commit workflow, commit only the remaining changed files.

---

## Self-Review

- Spec coverage: Purpose is covered by Tasks 1-4; Automation Types are represented by `automation_type` and `run_type`; Preconditions are covered by review counters, evidence gate assertions, and docs; Runtime Model is covered by append-only `attempts.jsonl`, evidence files, and audit regeneration; Governance Fields are covered by parser, template, defaults, and tests; Tests and Acceptance are covered by Task 1 and Task 5.
- Placeholder scan: no implementation placeholders are present. The only `TODO` occurrence is the repository task-log filename from project conventions.
- Type consistency: `governance_policy`, `append_automation_attempt`, `GovernanceSummary`, `parse_loop_yaml`, `render_audit`, `auto_fix`, `auto_merge`, `first_runs_require_human_review`, `reviewed_runs`, and `alert_on` are named consistently across tasks.

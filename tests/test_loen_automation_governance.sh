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

touch "$topic_dir/1_goal.md" "$topic_dir/2_context.md" "$topic_dir/3_plan.md" \
  "$topic_dir/4_act.md" "$topic_dir/5_check.md" "$topic_dir/6_reflect.md"
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

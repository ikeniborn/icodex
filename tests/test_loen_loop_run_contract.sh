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

tmp="$(mktemp -d)" || exit 1
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

plan_hash=""
plan_hash_output="$(PYTHONPATH="$hook_root" python3 - "$topic_dir/3_plan.md" 2>/dev/null <<'PY'
import sys
from pathlib import Path
from loen_artifacts import plan_body_hash
print(plan_body_hash(Path(sys.argv[1])))
PY
)"
plan_hash_code="$?"
assert_eq "plan hash helper computes" "0" "$plan_hash_code"
plan_hash="$plan_hash_output"

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

parse_status_output="$(PYTHONPATH="$hook_root" python3 - "$topic_dir/loop.yaml" 2>/dev/null <<'PY'
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
parse_status_code="$?"
assert_eq "parser helper runs" "0" "$parse_status_code"
assert_eq "parser reads run and release policy" "OK" "$parse_status_output"

validation_status_output="$(PYTHONPATH="$hook_root" python3 - "$topic_dir" 2>/dev/null <<'PY'
import sys
from pathlib import Path
from loen_artifacts import validate_run_contract

result = validate_run_contract(Path(sys.argv[1]))
print("OK" if result["ok"] else result)
PY
)"
validation_status_code="$?"
assert_eq "run contract validator helper runs" "0" "$validation_status_code"
assert_eq "approved merge-release contract validates" "OK" "$validation_status_output"

cat > "$topic_dir/loop.yaml.bad" <<YAML
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
  plan_approved: false
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
bad_status_output="$(PYTHONPATH="$hook_root" python3 - "$topic_dir" 2>/dev/null <<'PY'
import sys
from pathlib import Path
from loen_artifacts import validate_run_contract

base = Path(sys.argv[1])
(base / "loop.yaml").write_text((base / "loop.yaml.bad").read_text(encoding="utf-8"), encoding="utf-8")
result = validate_run_contract(base)
print("OK" if not result["ok"] and "plan approval" in result["reason"] else result)
PY
)"
bad_status_code="$?"
assert_eq "missing approval validator helper runs" "0" "$bad_status_code"
assert_eq "runner refuses missing approval" "OK" "$bad_status_output"

cat > "$topic_dir/loop.yaml" <<YAML
topic: sample-runner
mode: governance
mutable_scope:
  - plugins/loen/**
verifier:
  type: test
  command: bash tests/test_loen_loop_run_contract.sh
budget:
  max_iterations: 1
rollback_policy: "Stop and write handoff"
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
report_status_output="$(PYTHONPATH="$hook_root" python3 - "$topic_dir" 2>/dev/null <<'PY'
import sys
from pathlib import Path
from loen_artifacts import validate_run_contract
result = validate_run_contract(Path(sys.argv[1]))
print("OK" if result["ok"] else result)
PY
)"
report_status_code="$?"
assert_eq "report-only validator helper runs" "0" "$report_status_code"
assert_eq "report-only contract validates without release policy" "OK" "$report_status_output"

negative_dir="$tmp/docs/loen/missing-verifier"
mkdir -p "$negative_dir"
cp "$topic_dir/3_plan.md" "$negative_dir/3_plan.md"
negative_plan_hash="$(PYTHONPATH="$hook_root" python3 - "$negative_dir/3_plan.md" 2>/dev/null <<'PY'
import sys
from pathlib import Path
from loen_artifacts import plan_body_hash
print(plan_body_hash(Path(sys.argv[1])))
PY
)"

cat > "$negative_dir/loop.yaml" <<YAML
topic: missing-verifier
mode: governance
mutable_scope:
  - plugins/loen/**
budget:
  max_iterations: 1
rollback_policy: "Stop and write handoff"
run:
  mode: governance
  subtype: report-only
  plan_approved: true
  plan_hash: "$negative_plan_hash"
  state: prepare
  max_passes: 1
  current_pass: 0
governance:
  auto_fix: false
  auto_merge: false
release_policy:
  target_branch: ""
YAML
missing_verifier_output="$(PYTHONPATH="$hook_root" python3 - "$negative_dir" 2>/dev/null <<'PY'
import sys
from pathlib import Path
from loen_artifacts import validate_run_contract
result = validate_run_contract(Path(sys.argv[1]))
print("OK" if not result["ok"] and "verifier" in result["reason"] else result)
PY
)"
missing_verifier_code="$?"
assert_eq "missing verifier validator helper runs" "0" "$missing_verifier_code"
assert_eq "report-only refuses missing verifier" "OK" "$missing_verifier_output"

zero_budget_dir="$tmp/docs/loen/zero-budget"
mkdir -p "$zero_budget_dir"
cp "$topic_dir/3_plan.md" "$zero_budget_dir/3_plan.md"
zero_budget_plan_hash="$(PYTHONPATH="$hook_root" python3 - "$zero_budget_dir/3_plan.md" 2>/dev/null <<'PY'
import sys
from pathlib import Path
from loen_artifacts import plan_body_hash
print(plan_body_hash(Path(sys.argv[1])))
PY
)"

cat > "$zero_budget_dir/loop.yaml" <<YAML
topic: zero-budget
mode: governance
mutable_scope:
  - plugins/loen/**
verifier:
  type: test
  command: bash tests/test_loen_loop_run_contract.sh
budget:
  max_iterations: 0
rollback_policy: "Stop and write handoff"
run:
  mode: governance
  subtype: report-only
  plan_approved: true
  plan_hash: "$zero_budget_plan_hash"
  state: prepare
  max_passes: 1
  current_pass: 0
governance:
  auto_fix: false
  auto_merge: false
release_policy:
  target_branch: ""
YAML
zero_budget_output="$(PYTHONPATH="$hook_root" python3 - "$zero_budget_dir" 2>/dev/null <<'PY'
import sys
from pathlib import Path
from loen_artifacts import validate_run_contract
result = validate_run_contract(Path(sys.argv[1]))
print("OK" if not result["ok"] and "budget" in result["reason"] else result)
PY
)"
zero_budget_code="$?"
assert_eq "zero budget validator helper runs" "0" "$zero_budget_code"
assert_eq "report-only refuses zero budget" "OK" "$zero_budget_output"

printf '# Check\n\n## Result\n\nPASS\n' > "$topic_dir/5_check.md"
printf '# Result\n\n## Outcome\n\nDone\n' > "$topic_dir/7_result.md"
printf '{"status":"pass"}\n' > "$topic_dir/evidence/latest-test.json"
audit_status_output="$(PYTHONPATH="$hook_root" python3 - "$topic_dir" 2>/dev/null <<'PY'
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
audit_status_code="$?"
assert_eq "audit renderer helper runs" "0" "$audit_status_code"
assert_eq "audit renders runner state" "OK" "$audit_status_output"

loop_start_text="$(cat "$loop_start")"
loop_run_text="$(cat "$loop_run")"
loop_governance_text="$(cat "$loop_governance")"
assert_contains "loop-start asks delivery or governance" "$loop_start_text" 'delivery` or `governance'
assert_contains "loop-start asks governance subtype" "$loop_start_text" 'report-only`, `auto-fix`, or `merge-release'
assert_contains "loop-start records plan approval" "$loop_start_text" "run.plan_approved"
assert_contains "loop-run documents state machine" "$loop_run_text" "prepare -> act -> check -> reflect"
assert_contains "loop-run refuses missing approval" "$loop_run_text" "plan approval"
assert_contains "loop-run supports merge release" "$loop_run_text" "merge-release"
assert_contains "governance skill names subtypes" "$loop_governance_text" "report-only"
assert_contains "README documents loop-run" "$(cat "$readme")" "loen:loop-run"
assert_contains "Russian README documents loop-run" "$(cat "$readme_ru")" "loen:loop-run"
assert_contains "architecture documents loop-run" "$(cat "$architecture")" "loop-run"

finish

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
assert_eq "artifact hash length" "16" "${#plan_hash}"
assert_exit "artifact hash format" 0 bash -c '[[ "$1" =~ ^[0-9a-f]{16}$ ]]' _ "$plan_hash"
artifact_plan_hash="$(PYTHONPATH="$hook_root" python3 - "$topic_dir/3_plan.md" 2>/dev/null <<'PY'
import sys
from pathlib import Path
from loen_artifacts import artifact_body_hash
print(artifact_body_hash(Path(sys.argv[1])))
PY
)"
assert_eq "plan hash compatibility alias" "$artifact_plan_hash" "$plan_hash"

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
    plan_hash: "$plan_hash"
  launch:
    confirmed: true
    goal_hash: "goal-hash"
    context_hash: "context-hash"
    plan_hash: "$plan_hash"
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
  scope_limit: "Configured mutable scope only"
  recovery_policy: "Stop, record handoff, and leave branch inspectable."
YAML

touch "$topic_dir/1_goal.md" "$topic_dir/2_context.md" "$topic_dir/4_act.md" \
  "$topic_dir/5_check.md" "$topic_dir/6_reflect.md" "$topic_dir/7_result.md" \
  "$topic_dir/handoff.md" "$topic_dir/attempts.jsonl"

assert_exit "loop-run skill exists" 0 test -f "$loop_run"

template_text="$(cat "$template")"
assert_contains "template has run block" "$template_text" "run:"
assert_contains "template has checkpoints block" "$template_text" "checkpoints:"
for checkpoint in goal_context mode plan launch; do
  assert_contains "template has $checkpoint checkpoint" "$template_text" "  $checkpoint:"
done
assert_eq "template checkpoints default unconfirmed" "4" "$(grep -cF '    confirmed: false' "$template")"
assert_eq "template omits legacy plan approval" "0" "$(grep -cF 'plan_approved:' "$template" || true)"
assert_contains "template mode subtype defaults to textual null" "$template_text" "    subtype: null"
assert_contains "template has release policy block" "$template_text" "release_policy:"
assert_contains "template has release scope limit" "$template_text" "scope_limit:"

parse_status_output="$(PYTHONPATH="$hook_root" python3 - "$topic_dir/loop.yaml" 2>/dev/null <<'PY'
import sys
from pathlib import Path
from loen_common import parse_loop_yaml

data = parse_loop_yaml(Path(sys.argv[1]).read_text(encoding="utf-8"))
run = data.get("run", {})
checkpoints = data.get("checkpoints", {})
release = data.get("release_policy", {})
checks = [
    run.get("mode") == "governance",
    run.get("subtype") == "merge-release",
    run.get("plan_approved") is True,
    run.get("state") == "prepare",
    run.get("max_passes") == 2,
    run.get("current_pass") == 0,
    checkpoints == {
        "goal_context": {"confirmed": True, "goal_hash": "goal-hash", "context_hash": "context-hash"},
        "mode": {"confirmed": True, "mode": "governance", "subtype": "merge-release"},
        "plan": {"confirmed": True, "plan_hash": run.get("plan_hash")},
        "launch": {
            "confirmed": True,
            "goal_hash": "goal-hash",
            "context_hash": "context-hash",
            "plan_hash": run.get("plan_hash"),
        },
    },
    release.get("target_branch") == "master",
    release.get("merge_strategy") == "pr",
    release.get("verifier_required") is True,
    release.get("evidence_required") is True,
    release.get("scope_limit") == "Configured mutable scope only",
]
print("OK" if all(checks) else {"run": run, "release": release})
PY
)"
parse_status_code="$?"
assert_eq "parser helper runs" "0" "$parse_status_code"
assert_eq "parser reads run and release policy" "OK" "$parse_status_output"

parser_fixture_output="$(PYTHONPATH="$hook_root" python3 - 2>/dev/null <<'PY'
from loen_common import parse_loop_yaml

data = parse_loop_yaml("""checkpoints:
  goal_context:
    confirmed: false
    goal_hash: goal-123
    context_hash: context-456
    injected: authority
  mode:
    confirmed: true
    mode: governance
    subtype: report-only
  plan:
    confirmed: false
    plan_hash: plan-789
  launch:
    confirmed: true
    goal_hash: goal-123
    context_hash: context-456
    plan_hash: plan-789
  unknown:
    confirmed: true
    injected: authority
""")
expected = {
    "goal_context": {"confirmed": False, "goal_hash": "goal-123", "context_hash": "context-456"},
    "mode": {"confirmed": True, "mode": "governance", "subtype": "report-only"},
    "plan": {"confirmed": False, "plan_hash": "plan-789"},
    "launch": {
        "confirmed": True,
        "goal_hash": "goal-123",
        "context_hash": "context-456",
        "plan_hash": "plan-789",
    },
}
print("OK" if data.get("checkpoints") == expected else data.get("checkpoints"))
PY
)"
assert_eq "parser reads known structured checkpoints" "OK" "$parser_fixture_output"

duplicate_checkpoint_output="$(PYTHONPATH="$hook_root" python3 - 2>/dev/null <<'PY'
from loen_common import parse_loop_yaml

data = parse_loop_yaml("""checkpoints:
  goal_context:
    confirmed: true
    goal_hash: stale-goal
    context_hash: stale-context
  goal_context:
    confirmed: true
    goal_hash: replacement-goal
    context_hash: replacement-context
""")
expected = {"confirmed": False, "goal_hash": "", "context_hash": ""}
print("OK" if data["checkpoints"]["goal_context"] == expected else data["checkpoints"]["goal_context"])
PY
)"
assert_eq "duplicate checkpoint fails closed" "OK" "$duplicate_checkpoint_output"

malformed_checkpoint_output="$(PYTHONPATH="$hook_root" python3 - 2>/dev/null <<'PY'
from loen_common import parse_loop_yaml

data = parse_loop_yaml("""checkpoints:
  goal_context:
    confirmed: true
    goal_hash: stale-goal
    context_hash: stale-context
  malformed sibling
    confirmed: true
    goal_hash: stitched-goal
    context_hash: stitched-context
""")
expected = {"confirmed": False, "goal_hash": "", "context_hash": ""}
print("OK" if data["checkpoints"]["goal_context"] == expected else data["checkpoints"]["goal_context"])
PY
)"
assert_eq "malformed checkpoint sibling fails closed" "OK" "$malformed_checkpoint_output"

invalid_indent_output="$(PYTHONPATH="$hook_root" python3 - 2>/dev/null <<'PY'
from loen_common import parse_loop_yaml

data = parse_loop_yaml("""checkpoints:
  goal_context:
    confirmed: true
    goal_hash: stale-goal
   malformed: indentation
    context_hash: stitched-context
""")
expected = {"confirmed": False, "goal_hash": "", "context_hash": ""}
print("OK" if data["checkpoints"]["goal_context"] == expected else data["checkpoints"]["goal_context"])
PY
)"
assert_eq "invalid checkpoint indentation fails closed" "OK" "$invalid_indent_output"

tab_indent_output="$(PYTHONPATH="$hook_root" python3 - 2>/dev/null <<'PY'
from loen_common import parse_loop_yaml

data = parse_loop_yaml("""checkpoints:
  goal_context:
    confirmed: true
    goal_hash: stale-goal
\tmalformed: tab-indentation
    context_hash: stitched-context
""")
expected = {"confirmed": False, "goal_hash": "", "context_hash": ""}
print("OK" if data["checkpoints"]["goal_context"] == expected else data["checkpoints"]["goal_context"])
PY
)"
assert_eq "tab-indented checkpoint line fails closed" "OK" "$tab_indent_output"

duplicate_confirmed_output="$(PYTHONPATH="$hook_root" python3 - 2>/dev/null <<'PY'
from loen_common import parse_loop_yaml

data = parse_loop_yaml("""checkpoints:
  goal_context:
    confirmed: true
    confirmed: false
    goal_hash: stitched-goal
    context_hash: stitched-context
""")
expected = {"confirmed": False, "goal_hash": "", "context_hash": ""}
print("OK" if data["checkpoints"]["goal_context"] == expected else data["checkpoints"]["goal_context"])
PY
)"
assert_eq "duplicate confirmed field fails closed" "OK" "$duplicate_confirmed_output"

duplicate_hash_output="$(PYTHONPATH="$hook_root" python3 - 2>/dev/null <<'PY'
from loen_common import parse_loop_yaml

data = parse_loop_yaml("""checkpoints:
  goal_context:
    confirmed: true
    goal_hash: first-goal
    goal_hash: second-goal
    context_hash: stitched-context
""")
expected = {"confirmed": False, "goal_hash": "", "context_hash": ""}
print("OK" if data["checkpoints"]["goal_context"] == expected else data["checkpoints"]["goal_context"])
PY
)"
assert_eq "duplicate checkpoint hash fails closed" "OK" "$duplicate_hash_output"

fixture_driver="$tmp/run-contract-fixture.py"
cat > "$fixture_driver" <<'PY'
import sys
from pathlib import Path

from loen_artifacts import artifact_body_hash, validate_run_contract

root = Path(sys.argv[1])
scenario = sys.argv[2]


def contract_text(hashes, *, mode="governance", subtype="report-only", overrides=None):
  values = {
    "goal_confirmed": "true",
    "goal_hash": hashes["goal"],
    "context_hash": hashes["context"],
    "mode_confirmed": "true",
    "mode": mode,
    "subtype": subtype,
    "plan_confirmed": "true",
    "plan_hash": hashes["plan"],
    "launch_confirmed": "true",
    "launch_goal_hash": hashes["goal"],
    "launch_context_hash": hashes["context"],
    "launch_plan_hash": hashes["plan"],
  }
  values.update(overrides or {})
  auto_merge = "true" if subtype == "merge-release" else "false"
  return f"""topic: checkpoint-fixture
mutable_scope:
  - plugins/loen/**
verifier:
  command: bash tests/test_loen_loop_run_contract.sh
budget:
  max_iterations: 1
rollback_policy: Stop and write handoff
run:
  mode: delivery
  subtype: stale-legacy-value
  plan_approved: false
  plan_hash: stale-legacy-value
  state: prepare
  max_passes: 1
  current_pass: 0
checkpoints:
  goal_context:
    confirmed: {values['goal_confirmed']}
    goal_hash: {values['goal_hash']}
    context_hash: {values['context_hash']}
  mode:
    confirmed: {values['mode_confirmed']}
    mode: {values['mode']}
    subtype: {values['subtype']}
  plan:
    confirmed: {values['plan_confirmed']}
    plan_hash: {values['plan_hash']}
  launch:
    confirmed: {values['launch_confirmed']}
    goal_hash: {values['launch_goal_hash']}
    context_hash: {values['launch_context_hash']}
    plan_hash: {values['launch_plan_hash']}
governance:
  auto_fix: true
  auto_merge: {auto_merge}
release_policy:
  target_branch: master
  merge_strategy: pr
  verifier_required: true
  evidence_required: true
  scope_limit: Configured mutable scope only
  recovery_policy: Stop and write handoff
"""


def fixture(name, *, mode="governance", subtype="report-only", overrides=None):
  base = root / name
  base.mkdir(parents=True)
  (base / "1_goal.md").write_text("# Goal\n\nShip safely.\n", encoding="utf-8")
  (base / "2_context.md").write_text("# Context\n\nRepository state.\n", encoding="utf-8")
  (base / "3_plan.md").write_text("# Plan\n\n1. Verify contract.\n", encoding="utf-8")
  (base / "4_act.md").write_text("", encoding="utf-8")
  hashes = {
    "goal": artifact_body_hash(base / "1_goal.md"),
    "context": artifact_body_hash(base / "2_context.md"),
    "plan": artifact_body_hash(base / "3_plan.md"),
  }
  text = contract_text(hashes, mode=mode, subtype=subtype, overrides=overrides)
  (base / "loop.yaml").write_text(text, encoding="utf-8")
  return base


def replace(base, old, new):
  loop_path = base / "loop.yaml"
  loop_path.write_text(loop_path.read_text(encoding="utf-8").replace(old, new), encoding="utf-8")


options = {}
require_launch = True
if scenario == "legacy":
  base = fixture(scenario)
  (base / "loop.yaml").write_text("""topic: legacy
run:
  mode: governance
  subtype: report-only
  plan_approved: true
  plan_hash: legacy
""", encoding="utf-8")
elif scenario == "goal-unconfirmed":
  base = fixture(scenario, overrides={"goal_confirmed": "false"})
elif scenario == "goal-stale":
  base = fixture(scenario, overrides={"goal_hash": "stale"})
elif scenario == "context-stale":
  base = fixture(scenario, overrides={"context_hash": "stale"})
elif scenario == "mode-unconfirmed":
  base = fixture(scenario, overrides={"mode_confirmed": "false"})
elif scenario == "delivery-subtype":
  base = fixture(scenario, mode="delivery", subtype="auto-fix")
elif scenario == "governance-subtype":
  base = fixture(scenario, subtype="invalid")
elif scenario == "plan-unconfirmed":
  base = fixture(scenario, overrides={"plan_confirmed": "false"})
elif scenario == "plan-stale":
  base = fixture(scenario, overrides={"plan_hash": "stale"})
elif scenario == "launch-unconfirmed":
  base = fixture(scenario, overrides={"launch_confirmed": "false"})
elif scenario == "launch-goal-stale":
  base = fixture(scenario, overrides={"launch_goal_hash": "stale"})
elif scenario == "launch-context-stale":
  base = fixture(scenario, overrides={"launch_context_hash": "stale"})
elif scenario == "launch-plan-stale":
  base = fixture(scenario, overrides={"launch_plan_hash": "stale"})
elif scenario == "missing-goal":
  base = fixture(scenario)
  (base / "1_goal.md").unlink()
elif scenario == "missing-context":
  base = fixture(scenario)
  (base / "2_context.md").unlink()
elif scenario == "missing-plan":
  base = fixture(scenario)
  (base / "3_plan.md").unlink()
elif scenario == "duplicate-checkpoints":
  base = fixture(scenario)
  loop_path = base / "loop.yaml"
  text = loop_path.read_text(encoding="utf-8")
  text = text.replace(
    "checkpoints:\n  goal_context:",
    """checkpoints:
  goal_context:
    confirmed: true
    goal_hash: split-authority
    context_hash: split-authority
checkpoints:
  goal_context:""",
  )
  loop_path.write_text(text, encoding="utf-8")
elif scenario == "unreadable-goal":
  base = fixture(scenario)
  (base / "1_goal.md").write_bytes(b"\xff\xfe")
elif scenario == "unreadable-context":
  base = fixture(scenario)
  (base / "2_context.md").write_bytes(b"\xff\xfe")
elif scenario == "unreadable-plan":
  base = fixture(scenario)
  (base / "3_plan.md").write_bytes(b"\xff\xfe")
elif scenario == "scope-missing":
  base = fixture(scenario)
  replace(base, "  - plugins/loen/**", "  - none")
elif scenario == "verifier-missing":
  base = fixture(scenario)
  replace(base, "  command: bash tests/test_loen_loop_run_contract.sh", '  command: ""')
elif scenario == "budget-missing":
  base = fixture(scenario)
  replace(base, "  max_iterations: 1", "  max_iterations: 0")
elif scenario == "rollback-missing":
  base = fixture(scenario)
  replace(base, "rollback_policy: Stop and write handoff", 'rollback_policy: ""')
elif scenario == "auto-fix-disabled":
  base = fixture(scenario, subtype="auto-fix")
  replace(base, "  auto_fix: true", "  auto_fix: false")
elif scenario == "merge-policy-incomplete":
  base = fixture(scenario, subtype="merge-release")
  replace(base, "  scope_limit: Configured mutable scope only", '  scope_limit: ""')
elif scenario == "merge-release":
  base = fixture(scenario, subtype="merge-release")
elif scenario == "prelaunch":
  base = fixture(scenario, overrides={"launch_confirmed": "false"})
  require_launch = False
else:
  base = fixture(scenario)

result = validate_run_contract(base, require_launch=require_launch)
action = "EMPTY" if (base / "4_act.md").read_text(encoding="utf-8") == "" else "CHANGED"
print(f"{result['reason']}|{action}")
PY

run_contract_case() {
  local label="$1"
  local scenario="$2"
  local expected="$3"
  local output code
  output="$(PYTHONPATH="$hook_root" python3 "$fixture_driver" "$tmp/independent-fixtures" "$scenario" 2>&1)"
  code="$?"
  assert_eq "$label helper runs" "0" "$code"
  assert_eq "$label" "$expected|EMPTY" "$output"
}

run_contract_case "legacy contract rejected" "legacy" "legacy checkpoint contract"
run_contract_case "goal/context confirmation required" "goal-unconfirmed" "goal/context confirmation missing"
run_contract_case "stale goal rejected" "goal-stale" "goal hash mismatch"
run_contract_case "stale context rejected" "context-stale" "context hash mismatch"
run_contract_case "mode selection required" "mode-unconfirmed" "mode selection missing"
run_contract_case "delivery subtype rejected precisely" "delivery-subtype" "invalid delivery subtype"
run_contract_case "governance subtype rejected precisely" "governance-subtype" "invalid governance subtype"
run_contract_case "plan approval required" "plan-unconfirmed" "plan approval missing"
run_contract_case "stale plan rejected" "plan-stale" "plan hash mismatch"
run_contract_case "launch confirmation required" "launch-unconfirmed" "launch confirmation missing"
run_contract_case "stale launch goal rejected" "launch-goal-stale" "launch goal hash mismatch"
run_contract_case "stale launch context rejected" "launch-context-stale" "launch context hash mismatch"
run_contract_case "stale launch plan rejected" "launch-plan-stale" "launch plan hash mismatch"
run_contract_case "missing goal artifact rejected" "missing-goal" "goal hash mismatch"
run_contract_case "missing context artifact rejected" "missing-context" "context hash mismatch"
run_contract_case "missing plan artifact rejected" "missing-plan" "plan hash mismatch"
run_contract_case "duplicate checkpoint contract rejected" "duplicate-checkpoints" "invalid checkpoint contract"
run_contract_case "unreadable goal artifact rejected" "unreadable-goal" "unreadable goal artifact"
run_contract_case "unreadable context artifact rejected" "unreadable-context" "unreadable context artifact"
run_contract_case "unreadable plan artifact rejected" "unreadable-plan" "unreadable plan artifact"
run_contract_case "report-only contract validates" "current" "approved run contract"
run_contract_case "full merge-release contract validates" "merge-release" "approved run contract"
run_contract_case "prelaunch contract validates" "prelaunch" "approved run contract"
run_contract_case "missing verifier rejected" "verifier-missing" "missing verifier command"
run_contract_case "zero budget rejected" "budget-missing" "missing budget max_iterations"
run_contract_case "placeholder mutable scope rejected" "scope-missing" "missing mutable scope"
run_contract_case "missing rollback rejected" "rollback-missing" "missing rollback policy"
run_contract_case "disabled auto-fix rejected" "auto-fix-disabled" "auto-fix requires governance auto_fix"
run_contract_case "incomplete merge-release policy rejected" "merge-policy-incomplete" "merge-release policy incomplete"

sed -i '0,/subtype: merge-release/s//subtype: report-only/' "$topic_dir/loop.yaml"
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

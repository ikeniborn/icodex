#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

plugin_root="$ROOT/plugins/loen"
hook_root="$plugin_root/hooks"
template="$plugin_root/assets/templates/loop.yaml"
loop_start="$plugin_root/skills/loop-start/SKILL.md"
loop_plan="$plugin_root/skills/loop-plan/SKILL.md"
loop_run="$plugin_root/skills/loop-run/SKILL.md"
goal_template="$plugin_root/assets/templates/1_goal.md"
context_template="$plugin_root/assets/templates/2_context.md"
plan_template="$plugin_root/assets/templates/3_plan.md"
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

unicode_policy_status="$(PYTHONPATH="$hook_root" python3 - <<'PY'
import hashlib
import json

from loen_artifacts import run_policy_hash

parsed = {
    "mutable_scope": ["данные/**"],
    "protected_scope": ["секреты/**"],
    "quality_gates": [{"command": "проверить"}],
    "verifier": {"command": "тест"},
    "budget": {"max_iterations": 1},
    "stop_conditions": ["готово"],
    "handoff_conditions": ["нужен человек"],
    "rollback_policy": "откатить",
    "governance": {"owner": "Ирина"},
    "release_policy": {"target_branch": "основная"},
}
payload = {
    "mode": "delivery",
    "subtype": "",
    **parsed,
}
canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
expected = hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:16]
actual = run_policy_hash(parsed, "delivery", "")
print("OK" if actual == expected else f"expected={expected} actual={actual}")
PY
)"
assert_eq "policy hash uses canonical UTF-8 JSON" "OK" "$unicode_policy_status"

semantic_null_status="$(PYTHONPATH="$hook_root" python3 - <<'PY'
import hashlib
import json

from loen_artifacts import run_policy_hash
from loen_common import parse_loop_yaml

for spelling in ("null", "Null", "NULL", "~", ""):
    parsed = parse_loop_yaml(f"""checkpoints:
  mode:
    confirmed: true
    mode: delivery
    subtype: {spelling}
rollback_policy: null
""")
    if parsed["checkpoints"]["mode"]["subtype"] is not None:
        raise SystemExit(f"non-semantic null: {spelling!r}")
    if parsed["rollback_policy"] is not None:
        raise SystemExit(f"top-level null stayed textual: {spelling!r}")

quoted = parse_loop_yaml('''checkpoints:
  mode:
    confirmed: true
    mode: delivery
    subtype: "null"
rollback_policy: "null"
''')
if quoted["checkpoints"]["mode"]["subtype"] != "null" or quoted["rollback_policy"] != "null":
    raise SystemExit("quoted null lost string semantics")

parsed = {
    "mutable_scope": ["plugins/loen/**"],
    "protected_scope": [],
    "quality_gates": [{"command": "bash tests/test_loen_loop_run_contract.sh", "evidence": None}],
    "verifier": {"command": "bash tests/test_loen_loop_run_contract.sh"},
    "budget": {"max_iterations": "1"},
    "stop_conditions": [],
    "handoff_conditions": [],
    "rollback_policy": None,
    "governance": {"owner": None},
    "release_policy": {"target_branch": None},
}
payload = {"mode": "delivery", "subtype": "", **parsed}
literal = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
expected = hashlib.sha256(literal.encode("utf-8")).hexdigest()[:16]
if run_policy_hash(parsed, "delivery", None) != expected:
    raise SystemExit("independent null JSON vector mismatch")
print("OK")
PY
)"
assert_eq "semantic nulls and independent null JSON vector" "OK" "$semantic_null_status"

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
    policy_hash: "POLICY_HASH"
  launch:
    confirmed: true
    goal_hash: "goal-hash"
    context_hash: "context-hash"
    plan_hash: "$plan_hash"
    policy_hash: "POLICY_HASH"
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

policy_hash="$(PYTHONPATH="$hook_root" python3 - "$topic_dir/loop.yaml" <<'PY'
import sys
from pathlib import Path
from loen_artifacts import run_policy_hash
from loen_common import parse_loop_yaml
parsed = parse_loop_yaml(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(run_policy_hash(parsed, "governance", "merge-release"))
PY
)"
sed -i "s/POLICY_HASH/$policy_hash/g" "$topic_dir/loop.yaml"

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
        "plan": {"confirmed": True, "plan_hash": run.get("plan_hash"), "policy_hash": checkpoints.get("plan", {}).get("policy_hash")},
        "launch": {
            "confirmed": True,
            "goal_hash": "goal-hash",
            "context_hash": "context-hash",
            "plan_hash": run.get("plan_hash"),
            "policy_hash": checkpoints.get("plan", {}).get("policy_hash"),
        },
    },
    release.get("target_branch") == "master",
    release.get("merge_strategy") == "pr",
    release.get("verifier_required") is True,
    release.get("evidence_required") is True,
    release.get("scope_limit") == "Configured mutable scope only",
]
checks.append(checkpoints["plan"]["policy_hash"] == checkpoints["launch"]["policy_hash"] and len(checkpoints["plan"]["policy_hash"]) == 16)
print("OK" if all(checks) else {"run": run, "release": release, "checkpoints": checkpoints})
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
    policy_hash: policy-000
  launch:
    confirmed: true
    goal_hash: goal-123
    context_hash: context-456
    plan_hash: plan-789
    policy_hash: policy-000
  unknown:
    confirmed: true
    injected: authority
""")
expected = {
    "goal_context": {"confirmed": False, "goal_hash": "goal-123", "context_hash": "context-456"},
    "mode": {"confirmed": True, "mode": "governance", "subtype": "report-only"},
    "plan": {"confirmed": False, "plan_hash": "plan-789", "policy_hash": "policy-000"},
    "launch": {
        "confirmed": True,
        "goal_hash": "goal-123",
        "context_hash": "context-456",
        "plan_hash": "plan-789",
        "policy_hash": "policy-000",
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

from loen_artifacts import artifact_body_hash, run_policy_hash, validate_run_contract
from loen_common import parse_loop_yaml

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
    "plan_policy_hash": "POLICY_HASH",
    "launch_confirmed": "true",
    "launch_goal_hash": hashes["goal"],
    "launch_context_hash": hashes["context"],
    "launch_plan_hash": hashes["plan"],
    "launch_policy_hash": "POLICY_HASH",
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
    policy_hash: {values['plan_policy_hash']}
  launch:
    confirmed: {values['launch_confirmed']}
    goal_hash: {values['launch_goal_hash']}
    context_hash: {values['launch_context_hash']}
    plan_hash: {values['launch_plan_hash']}
    policy_hash: {values['launch_policy_hash']}
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
  policy_hash = run_policy_hash(parse_loop_yaml(text), mode, subtype)
  text = text.replace("POLICY_HASH", policy_hash)
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
elif scenario == "non-top-level-checkpoints":
  base = fixture(scenario)
  (base / "loop.yaml").write_text("""topic: non-top-level
# checkpoints:
run:
  checkpoints:
    confirmed: true
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
elif scenario in {"duplicate-checkpoints-comment", "duplicate-checkpoints-spaces"}:
  base = fixture(scenario)
  loop_path = base / "loop.yaml"
  duplicate_header = "checkpoints: # duplicate" if scenario.endswith("comment") else "checkpoints:   "
  text = loop_path.read_text(encoding="utf-8")
  text = text.replace(
    "checkpoints:\n  goal_context:",
    f"""checkpoints:
  goal_context:
    confirmed: true
    goal_hash: split-authority
    context_hash: split-authority
{duplicate_header}
  goal_context:""",
  )
  loop_path.write_text(text, encoding="utf-8")
elif scenario.startswith("duplicate-authority-"):
  base = fixture(scenario)
  authority = scenario.removeprefix("duplicate-authority-")
  duplicate_lines = {
    "mutable_scope": ("mutable_scope:\n", "mutable_scope:\n  - split/**\nmutable_scope:\n"),
    "protected_scope": ("verifier:\n", "protected_scope:\n  - first/**\nprotected_scope:\n  - second/**\nverifier:\n"),
    "quality_gates": ("verifier:\n", "quality_gates:\n  - command: first\nquality_gates:\n  - command: second\nverifier:\n"),
    "verifier": ("verifier:\n", "verifier:\n  command: split\nverifier:\n"),
    "budget": ("budget:\n", "budget:\n  max_iterations: 7\nbudget:\n"),
    "stop_conditions": ("rollback_policy:", "stop_conditions:\n  - first\nstop_conditions:\n  - second\nrollback_policy:"),
    "handoff_conditions": ("rollback_policy:", "handoff_conditions:\n  - first\nhandoff_conditions:\n  - second\nrollback_policy:"),
    "rollback_policy": ("rollback_policy: Stop and write handoff", "rollback_policy: split\nrollback_policy: Stop and write handoff"),
    "governance": ("governance:\n", "governance:\n  owner: split\ngovernance:\n"),
    "release_policy": ("release_policy:\n", "release_policy:\n  target_branch: split\nrelease_policy:\n"),
    "verifier.command": ("  command: bash tests/test_loen_loop_run_contract.sh", "  command: split\n  command: bash tests/test_loen_loop_run_contract.sh"),
    "verifier.type": ("verifier:\n", "verifier:\n  type: first\n  type: second\n"),
    "budget.max_iterations": ("  max_iterations: 1", "  max_iterations: 7\n  max_iterations: 1"),
    "governance.automation_type": ("governance:\n", "governance:\n  automation_type: first\n  automation_type: second\n"),
    "governance.schedule": ("governance:\n", "governance:\n  schedule: first\n  schedule: second\n"),
    "governance.owner": ("governance:\n", "governance:\n  owner: first\n  owner: second\n"),
    "governance.first_runs_require_human_review": ("governance:\n", "governance:\n  first_runs_require_human_review: 1\n  first_runs_require_human_review: 2\n"),
    "governance.reviewed_runs": ("governance:\n", "governance:\n  reviewed_runs: 1\n  reviewed_runs: 2\n"),
    "governance.auto_fix": ("  auto_fix: true", "  auto_fix: false\n  auto_fix: true"),
    "governance.auto_merge": ("  auto_merge: false", "  auto_merge: true\n  auto_merge: false"),
    "governance.report_only_on_no_findings": ("governance:\n", "governance:\n  report_only_on_no_findings: true\n  report_only_on_no_findings: false\n"),
    "governance.alert_on": ("governance:\n", "governance:\n  alert_on: []\n  alert_on: []\n"),
    "release_policy.target_branch": ("  target_branch: master", "  target_branch: split\n  target_branch: master"),
    "release_policy.merge_strategy": ("  merge_strategy: pr", "  merge_strategy: split\n  merge_strategy: pr"),
    "release_policy.verifier_required": ("  verifier_required: true", "  verifier_required: false\n  verifier_required: true"),
    "release_policy.evidence_required": ("  evidence_required: true", "  evidence_required: false\n  evidence_required: true"),
    "release_policy.scope_limit": ("  scope_limit: Configured mutable scope only", "  scope_limit: split\n  scope_limit: Configured mutable scope only"),
    "release_policy.recovery_policy": ("  recovery_policy: Stop and write handoff", "  recovery_policy: split\n  recovery_policy: Stop and write handoff"),
    "quality_gates.command": ("mutable_scope:\n", "quality_gates:\n  - command: first\n    command: second\nmutable_scope:\n"),
    "quality_gates.evidence": ("mutable_scope:\n", "quality_gates:\n  - evidence: first\n    evidence: second\nmutable_scope:\n"),
    "checkpoint.goal_context": ("  goal_context:\n", "  goal_context:\n    confirmed: false\n  goal_context:\n"),
    "checkpoint.mode": ("  mode:\n", "  mode:\n    confirmed: false\n  mode:\n"),
    "checkpoint.plan": ("  plan:\n", "  plan:\n    confirmed: false\n  plan:\n"),
    "checkpoint.launch": ("  launch:\n", "  launch:\n    confirmed: false\n  launch:\n"),
    "goal_context.confirmed": ("    confirmed: true\n    goal_hash:", "    confirmed: false\n    confirmed: true\n    goal_hash:"),
    "goal_context.goal_hash": ("    goal_hash: ", "    goal_hash: split\n    goal_hash: "),
    "goal_context.context_hash": ("    context_hash: ", "    context_hash: split\n    context_hash: "),
    "mode.confirmed": ("  mode:\n    confirmed: true", "  mode:\n    confirmed: false\n    confirmed: true"),
    "mode.mode": ("    mode: governance", "    mode: delivery\n    mode: governance"),
    "mode.subtype": ("    subtype: report-only", "    subtype: split\n    subtype: report-only"),
    "plan.confirmed": ("  plan:\n    confirmed: true", "  plan:\n    confirmed: false\n    confirmed: true"),
    "plan.plan_hash": ("    plan_hash: ", "    plan_hash: split\n    plan_hash: "),
    "plan.policy_hash": ("    policy_hash: ", "    policy_hash: split\n    policy_hash: "),
    "launch.confirmed": ("  launch:\n    confirmed: true", "  launch:\n    confirmed: false\n    confirmed: true"),
    "launch.goal_hash": ("    goal_hash: ", "    goal_hash: split\n    goal_hash: "),
    "launch.context_hash": ("    context_hash: ", "    context_hash: split\n    context_hash: "),
    "launch.plan_hash": ("    plan_hash: ", "    plan_hash: split\n    plan_hash: "),
    "launch.policy_hash": ("    policy_hash: ", "    policy_hash: split\n    policy_hash: "),
  }
  old, new = duplicate_lines[authority]
  replace(base, old, new)
elif scenario == "authority-controls":
  base = fixture(scenario)
  replace(base, "rollback_policy: Stop and write handoff", 'rollback_policy: "keep # checkpoints: and verifier: literal" # checkpoints:')
  replace(base, "governance:\n", "unrelated:\n  owner: first\n  owner: second\ngovernance:\n")
  loop_path = base / "loop.yaml"
  text = loop_path.read_text(encoding="utf-8")
  current_hash = run_policy_hash(parse_loop_yaml(text), "governance", "report-only")
  old_hash = parse_loop_yaml(text)["checkpoints"]["plan"]["policy_hash"]
  loop_path.write_text(text.replace(str(old_hash), current_hash), encoding="utf-8")
elif scenario.startswith("malformed-indent-"):
  base = fixture(scenario)
  section = scenario.removeprefix("malformed-indent-")
  insertions = {
    "verifier": ("  command: bash tests/test_loen_loop_run_contract.sh", "   command: split\n  command: bash tests/test_loen_loop_run_contract.sh"),
    "governance": ("  auto_fix: true", "   auto_fix: false\n  auto_fix: true"),
    "quality_gates": ("mutable_scope:\n", "quality_gates:\n  - command: first\n     command: second\nmutable_scope:\n"),
  }
  replace(base, *insertions[section])
elif scenario.startswith("quoted-authority-"):
  base = fixture(scenario)
  section = scenario.removeprefix("quoted-authority-")
  insertions = {
    "verifier": ("  command: bash tests/test_loen_loop_run_contract.sh", '  "command": split\n  command: bash tests/test_loen_loop_run_contract.sh'),
    "governance": ("  auto_fix: true", "  'auto_fix': false\n  auto_fix: true"),
    "quality_gates": ("mutable_scope:\n", 'quality_gates:\n  - "command": first\n    command: second\nmutable_scope:\n'),
  }
  replace(base, *insertions[section])
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
run_contract_case "commented and nested checkpoints ignored" "non-top-level-checkpoints" "legacy checkpoint contract"
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
run_contract_case "duplicate checkpoint contract rejected" "duplicate-checkpoints" "invalid canonical authority"
run_contract_case "commented duplicate checkpoint contract rejected" "duplicate-checkpoints-comment" "invalid canonical authority"
run_contract_case "spaced duplicate checkpoint contract rejected" "duplicate-checkpoints-spaces" "invalid canonical authority"
for authority in mutable_scope protected_scope quality_gates verifier budget stop_conditions handoff_conditions rollback_policy governance release_policy verifier.type verifier.command budget.max_iterations governance.automation_type governance.schedule governance.owner governance.first_runs_require_human_review governance.reviewed_runs governance.auto_fix governance.auto_merge governance.report_only_on_no_findings governance.alert_on release_policy.target_branch release_policy.merge_strategy release_policy.verifier_required release_policy.evidence_required release_policy.scope_limit release_policy.recovery_policy quality_gates.command quality_gates.evidence checkpoint.goal_context checkpoint.mode checkpoint.plan checkpoint.launch goal_context.confirmed goal_context.goal_hash goal_context.context_hash mode.confirmed mode.mode mode.subtype plan.confirmed plan.plan_hash plan.policy_hash launch.confirmed launch.goal_hash launch.context_hash launch.plan_hash launch.policy_hash; do
  run_contract_case "duplicate canonical authority $authority rejected" "duplicate-authority-$authority" "invalid canonical authority"
done
run_contract_case "quoted comments and unrelated duplicates stay valid" "authority-controls" "approved run contract"
for section in verifier governance quality_gates; do
  run_contract_case "malformed indentation cannot bypass $section duplicate detection" "malformed-indent-$section" "invalid canonical authority"
  run_contract_case "quoted canonical key cannot bypass $section duplicate detection" "quoted-authority-$section" "invalid canonical authority"
done
run_contract_case "unreadable goal artifact rejected" "unreadable-goal" "unreadable goal artifact"
run_contract_case "unreadable context artifact rejected" "unreadable-context" "unreadable context artifact"
run_contract_case "unreadable plan artifact rejected" "unreadable-plan" "unreadable plan artifact"
run_contract_case "report-only contract validates" "current" "approved run contract"
run_contract_case "full merge-release contract validates" "merge-release" "approved run contract"
run_contract_case "prelaunch contract validates" "prelaunch" "approved run contract"
run_contract_case "verifier mutation invalidates approval" "verifier-missing" "plan policy hash mismatch"
run_contract_case "budget mutation invalidates approval" "budget-missing" "plan policy hash mismatch"
run_contract_case "mutable scope mutation invalidates approval" "scope-missing" "plan policy hash mismatch"
run_contract_case "rollback mutation invalidates approval" "rollback-missing" "plan policy hash mismatch"
run_contract_case "governance mutation invalidates approval" "auto-fix-disabled" "plan policy hash mismatch"
run_contract_case "release policy mutation invalidates approval" "merge-policy-incomplete" "plan policy hash mismatch"

sed -i '0,/subtype: merge-release/s//subtype: report-only/' "$topic_dir/loop.yaml"
sed -i '/^  launch:/,/^governance:/ s/^    confirmed: true$/    confirmed: false/' "$topic_dir/loop.yaml"
printf '# Check\n\n## Result\n\nPASS\n' > "$topic_dir/5_check.md"
printf '# Result\n\n## Outcome\n\nDone\n' > "$topic_dir/7_result.md"
printf '{"status":"pass"}\n' > "$topic_dir/evidence/latest-test.json"
cat > "$topic_dir/attempts.jsonl" <<'JSONL'
legacy plain attempt
{"status":"pass","summary":"legacy JSON survives"}
{"automation":true,"created_at":"2026-07-23T09:00:00Z","effective_status":"pass","run_type":"governance","summary":"mixed automation survives"}
not-json {
{"checkpoint":"goal_context","created_at":"2026-07-23T10:00:00Z","decision":"reset","event":"checkpoint","hashes":{"context_hash":"historical-context","goal_hash":"historical-goal"},"mode":"<script>alert(1)</script>","outcome":"<img src=x onerror=alert(1)>","subtype":""}
{"checkpoint":"launch","created_at":"2026-07-23T11:00:00Z","decision":"confirmed","event":"checkpoint","hashes":{"context_hash":"context-hash","goal_hash":"goal-hash","plan_hash":"PLAN_HASH","policy_hash":"POLICY_HASH"},"mode":"governance","outcome":"confirmed","subtype":"report-only"}
{"checkpoint":"unknown","created_at":"2026-07-23T12:00:00Z","decision":"confirmed","event":"checkpoint","hashes":{},"mode":"delivery","outcome":"confirmed","subtype":""}
{"checkpoint":"plan","created_at":"2026-07-23T12:01:00Z","decision":"ignored","event":"checkpoint","hashes":{},"mode":"delivery","outcome":"ignored","subtype":""}
{"checkpoint":"plan","created_at":"2026-07-23T12:02:00Z","decision":"confirmed","event":"checkpoint","hashes":[],"mode":"delivery","outcome":"confirmed","subtype":""}
{"checkpoint":"plan","created_at":"2026-07-23T12:03:00Z","decision":"confirmed","event":"checkpoint","hashes":{"plan_hash":7},"mode":"delivery","outcome":"confirmed","subtype":""}
{"checkpoint":"plan","created_at":7,"decision":"confirmed","event":"checkpoint","hashes":{"plan_hash":"valid"},"mode":"delivery","outcome":"confirmed","subtype":""}
{"checkpoint":"plan","created_at":"2026-07-23T12:04:00Z","decision":"confirmed","event":"checkpoint","hashes":{"plan_hash":"valid"},"mode":7,"outcome":"confirmed","subtype":""}
{"checkpoint":"plan","created_at":"2026-07-23T12:05:00Z","decision":"confirmed","event":"checkpoint","hashes":{"plan_hash":"valid"},"mode":"delivery","outcome":"confirmed","subtype":7}
{"checkpoint":"plan","created_at":"2026-07-23T12:06:00Z","decision":"confirmed","event":"checkpoint","hashes":{"plan_hash":"valid"},"mode":"delivery","outcome":7,"subtype":""}
JSONL
sed -i "s/PLAN_HASH/$plan_hash/" "$topic_dir/attempts.jsonl"
sed -i "s/POLICY_HASH/$policy_hash/" "$topic_dir/attempts.jsonl"
audit_status_output="$(PYTHONPATH="$hook_root" python3 - "$topic_dir" "$plan_hash" 2>/dev/null <<'PY'
import sys
from pathlib import Path
from loen_artifacts import render_audit
base = Path(sys.argv[1])
text = render_audit(base, "sample-runner")
checkpoint_section = text.split("<h2>Checkpoints</h2>", 1)[1].split("</section>", 1)[0]
history_section = text.split("<h2>Checkpoint History</h2>", 1)[1].split("</section>", 1)[0]
checks = {
    "runner section retained": "Runner" in text and "merge-release" in text and "plan_approved: true" in text and sys.argv[2] in text,
    "governance section retained": "Governance" in text and "mixed automation survives" in text,
    "goal_context current authority": (
        "<strong>goal_context</strong>: confirmed: true, goal_hash: goal-hash, context_hash: context-hash"
        in checkpoint_section
    ),
    "mode current authority": (
        "<strong>mode</strong>: confirmed: true, mode: governance, subtype: merge-release"
        in checkpoint_section
    ),
    "plan current authority": (
        f"<strong>plan</strong>: confirmed: true, plan_hash: {sys.argv[2]}" in checkpoint_section
    ),
    "launch current authority": (
        f"<strong>launch</strong>: confirmed: false, goal_hash: goal-hash, context_hash: context-hash, plan_hash: {sys.argv[2]}"
        in checkpoint_section
    ),
    "history excluded from current authority": "historical-goal" not in checkpoint_section and "reset" not in checkpoint_section,
    "checkpoint history count": "2 checkpoint event(s)" in history_section,
    "checkpoint reset event rendered": "goal_context reset" in history_section and "historical-goal" in history_section,
    "checkpoint confirmed event rendered": "launch confirmed" in history_section,
    "hostile checkpoint values escaped": (
        "&lt;script&gt;alert(1)&lt;/script&gt;" in history_section
        and "&lt;img src=x onerror=alert(1)&gt;" in history_section
        and "<script>" not in history_section
        and "<img " not in history_section
    ),
    "invalid semantic events excluded": "unknown confirmed" not in history_section and "plan ignored" not in history_section,
    "legacy JSON excluded from checkpoint history": "legacy JSON survives" not in history_section,
    "automation excluded from checkpoint history": "mixed automation survives" not in history_section,
    "final verdict retained": "Final verdict:</strong> Done" in text,
}
failures = [label for label, passed in checks.items() if not passed]
print("OK" if not failures else "FAILED: " + "; ".join(failures))
PY
)"
audit_status_code="$?"
assert_eq "audit renderer helper runs" "0" "$audit_status_code"
assert_eq "audit renders runner state" "OK" "$audit_status_output"

loop_start_text="$(cat "$loop_start")"
loop_plan_text="$(cat "$loop_plan")"
loop_run_text="$(cat "$loop_run")"
loop_governance_text="$(cat "$loop_governance")"

assert_ordered_lines() {
  local label="$1"
  local file="$2"
  shift 2
  local previous=0 marker line count result=OK
  for marker in "$@"; do
    count="$(grep -cF -- "$marker" "$file" || true)"
    line="$(grep -nF -m1 -- "$marker" "$file" | cut -d: -f1)"
    if [[ "$count" != "1" ]]; then
      result="expected one '$marker', found $count"
      break
    fi
    if [[ -z "$line" || "$line" -le "$previous" ]]; then
      result="expected '$marker' after line $previous"
      break
    fi
    previous="$line"
  done
  assert_eq "$label" "OK" "$result"
}

assert_ordered_lines "loop-start preserves confirmation and planning gate order" "$loop_start" \
  "Resolve every unresolved assumption adaptively, one question at a time." \
  "Obtain explicit confirmation of the complete goal and context." \
  'Ask the user to select `delivery` or `governance`; never infer mode or subtype.' \
  "Write the integrated plan from the confirmed goal, context, mode, and subtype." \
  "Obtain separate explicit approval of the complete plan." \
  '`loen:loop-run {resolved_topic}`'

loop_start_output="$(awk '/^## Output$/ {capture=1} capture {print}' "$loop_start")"
assert_contains "loop-start gives resolved continuation template" "$loop_start_output" '`loen:loop-run {resolved_topic}`'
assert_contains "loop-start requires slug substitution" "$loop_start_output" 'Replace `{resolved_topic}` with the validated topic slug before emitting the final line.'
assert_eq "loop-start forbids literal topic continuation output" "0" "$(grep -cF 'loen:loop-run <topic>' <<<"$loop_start_output" || true)"
assert_eq "loop-start resolved continuation template appears once" "1" "$(grep -cF '`loen:loop-run {resolved_topic}`' "$loop_start")"
assert_eq "loop-start does not offer immediate run" "0" "$(grep -Eic 'offer.*(start|run).*immediately|start.*immediately' "$loop_start" || true)"
assert_contains "loop-start requires empty unresolved assumptions" "$loop_start_text" 'Unresolved Assumptions` must be explicitly empty'
assert_contains "loop-start hashes confirmed goal and context" "$loop_start_text" 'Hash the current confirmed `1_goal.md` and `2_context.md`'
assert_contains "loop-start invalidates downstream checkpoints" "$loop_start_text" "deterministic invalidation"
assert_contains "loop-start appends checkpoint audit events" "$loop_start_text" "append checkpoint reset and confirmation events"
assert_contains "loop-start writes checkpoint mode key" "$loop_start_text" '`checkpoints.mode.mode`'
assert_contains "loop-start writes checkpoint subtype key" "$loop_start_text" '`checkpoints.mode.subtype`'
for legacy_authority in "run.mode" "run.subtype" "run.plan_approved" "run.plan_hash"; do
  assert_eq "loop-start omits $legacy_authority authority" "0" "$(grep -cF "$legacy_authority" "$loop_start" || true)"
done
assert_contains "goal/context changes reset all checkpoints" "$loop_start_text" 'INVALIDATE-GOAL-CONTEXT: Any content change to `1_goal.md` or `2_context.md` resets goal_context, mode, plan, and launch.'
assert_contains "mode changes reset mode plan launch" "$loop_start_text" 'INVALIDATE-MODE: Any mode or subtype change resets mode, plan, and launch.'
assert_contains "plan changes reset plan launch" "$loop_start_text" 'INVALIDATE-PLAN: Any content change to `3_plan.md` resets plan and launch.'
assert_contains "plan reapproval restores plan only" "$loop_start_text" 'RESTORE-PLAN: Reapproval restores plan only; launch remains unconfirmed.'
assert_contains "post-confirmation failure resets launch only" "$loop_start_text" 'INVALIDATE-FAILED-PREFLIGHT: Failed post-confirmation preflight resets launch only.'
assert_contains "every reset has reset event" "$loop_start_text" 'RESET-AUDIT: Every reset appends one reset event; never infer confirmation or approval.'
assert_contains "loop-start must not write launch true" "$loop_start_text" 'PROHIBITION: MUST NOT write `checkpoints.launch.confirmed: true`.'
assert_contains "loop-start must not invoke runner" "$loop_start_text" 'PROHIBITION: MUST NOT invoke `loen:loop-run`.'

for heading in "User Request" "Objective" "Observable Outcome" "Success Criteria"; do
  assert_contains "goal template has $heading heading" "$(cat "$goal_template")" "## $heading"
done
for heading in "Facts" "Constraints" "Mutable Scope" "Protected Scope" "Verifier" "Budget" "Rollback or Recovery" "Unresolved Assumptions"; do
  assert_contains "context template has $heading heading" "$(cat "$context_template")" "## $heading"
done
for heading in "Preconditions" "Steps" "Success-Criterion Mapping" "Checks and Evidence" "Risks" "Rollback or Recovery" "Terminal Condition"; do
  assert_contains "plan template has $heading heading" "$(cat "$plan_template")" "## $heading"
done

assert_contains "loop-plan is existing-topic replan only" "$loop_plan_text" "existing topic replan only"
assert_contains "loop-plan keeps topic-scoped state under topic root" "$loop_plan_text" 'All topic-scoped loop state remains under `docs/loen/<topic>/`.'
assert_contains "loop-plan validates upstream checkpoints" "$loop_plan_text" "Validate the goal/context and mode checkpoints"
assert_contains "loop-plan resets plan checkpoint" "$loop_plan_text" "Reset the plan checkpoint"
assert_contains "loop-plan resets launch checkpoint" "$loop_plan_text" "reset the launch checkpoint"
assert_contains "loop-plan appends reset events" "$loop_plan_text" "Append a reset event for each reset checkpoint"
assert_contains "loop-plan separately approves plan" "$loop_plan_text" "Obtain separate explicit plan approval"
assert_contains "loop-plan exact upstream validation" "$loop_plan_text" 'UPSTREAM VALIDATION: Validate confirmed goal_context hashes against current `1_goal.md` and `2_context.md`, then validate confirmed explicit mode and subtype.'
assert_contains "loop-plan plan change reset mapping" "$loop_plan_text" 'PLAN INVALIDATION: Before writing changed `3_plan.md`, reset plan and launch and append one reset event for each.'
assert_contains "loop-plan approval restores only plan" "$loop_plan_text" 'Explicit approval restores plan only; launch remains unconfirmed.'
assert_contains "loop-plan restoration writes plan policy checkpoint" "$loop_plan_text" 'PLAN RESTORATION: After explicit plan approval, write only `checkpoints.plan.confirmed: true`, its current `plan_hash`, and the current `policy_hash` computed with `run_policy_hash`, then append the confirmed plan event with both hashes.'
assert_contains "loop-plan restoration leaves launch false" "$loop_plan_text" 'Keep `checkpoints.launch.confirmed: false`.'
assert_ordered_lines "loop-plan preserves replan gate order" "$loop_plan" \
  'UPSTREAM VALIDATION:' \
  'PLAN REGENERATION:' \
  'PLAN INVALIDATION:' \
  'PLAN APPROVAL REQUEST:' \
  'PLAN RESTORATION:' \
  '## Output'
assert_contains "loop-plan must not write launch true" "$loop_plan_text" 'PROHIBITION: MUST NOT write `checkpoints.launch.confirmed: true`.'
assert_contains "loop-plan must not invoke runner" "$loop_plan_text" 'PROHIBITION: MUST NOT invoke `loen:loop-run`.'

loop_start_filtered="$(grep -vF 'MUST NOT' "$loop_start" | grep -vF 'To continue, run `loen:loop-run <topic>`.' || true)"
loop_plan_filtered="$(grep -vF 'MUST NOT' "$loop_plan" || true)"
runner_action_pattern='((^|[^[:alnum:]_])(run|launch|call|start|invoke|execute)([^[:alnum:]_]|$).*(loen:loop-run|loop-run|runner))|((loen:loop-run|loop-run|runner).*(^|[^[:alnum:]_])(run|launch|call|start|invoke|execute)([^[:alnum:]_]|$))'
launch_confirmed_true_pattern='launch.*confirmed[[:space:]:]*true'
launch_write_true_pattern='((write|set|mark|confirm).*launch.*true)|((write|set|mark|confirm).*true.*launch)|(launch.*(write|set|mark|confirm).*true)|(launch.*true.*(write|set|mark|confirm))|(true.*(write|set|mark|confirm).*launch)|(true.*launch.*(write|set|mark|confirm))'
assert_eq "runner guard detects direct run" "1" "$(printf '%s\n' 'Run loen:loop-run <topic> now.' | grep -Eic "$runner_action_pattern" || true)"
assert_eq "runner guard detects immediate call" "1" "$(printf '%s\n' 'Call the runner immediately.' | grep -Eic "$runner_action_pattern" || true)"
assert_eq "launch guard detects dotted checkpoint write" "1" "$(printf '%s\n' 'Write checkpoints.launch.confirmed: true.' | grep -Eic "$launch_write_true_pattern" || true)"
assert_eq "launch guard detects confirmed true set" "1" "$(printf '%s\n' 'Set launch to confirmed true.' | grep -Eic "$launch_confirmed_true_pattern" || true)"
for skill_name in loop-start loop-plan; do
  if [[ "$skill_name" == "loop-start" ]]; then
    filtered_text="$loop_start_filtered"
  else
    filtered_text="$loop_plan_filtered"
  fi
  assert_eq "$skill_name has no runner action path outside prohibition" "0" "$(printf '%s\n' "$filtered_text" | grep -Eic "$runner_action_pattern" || true)"
  assert_eq "$skill_name has no launch confirmed true path outside prohibition" "0" "$(printf '%s\n' "$filtered_text" | grep -Eic "$launch_confirmed_true_pattern" || true)"
  assert_eq "$skill_name has no launch write true path outside prohibition" "0" "$(printf '%s\n' "$filtered_text" | grep -Eic "$launch_write_true_pattern" || true)"
done
assert_eq "loop-start exact resolved continuation output appears once" "1" "$(grep -cF '`loen:loop-run {resolved_topic}`' "$loop_start")"
assert_eq "loop-plan has no continuation output" "0" "$(grep -cF '`loen:loop-run {resolved_topic}`' "$loop_plan" || true)"

checkpoint_event_contract='append_checkpoint_event('
for event_skill in "$loop_start" "$loop_plan" "$loop_run"; do
  event_skill_name="$(basename "$(dirname "$event_skill")")"
  event_skill_text="$(cat "$event_skill")"
  case "$event_skill_name" in
    loop-start)
      expected_checkpoint="goal_context"
      expected_decision="confirmed"
      expected_hashes='{"context_hash":"example-context-hash","goal_hash":"example-goal-hash"}'
      expected_hash_keys="goal_hash context_hash"
      ;;
    loop-plan)
      expected_checkpoint="plan"
      expected_decision="confirmed"
      expected_hashes='{"plan_hash":"example-plan-hash","policy_hash":"example-policy-hash"}'
      expected_hash_keys="plan_hash policy_hash"
      ;;
    loop-run)
      expected_checkpoint="launch"
      expected_decision="confirmed"
      expected_hashes='{"context_hash":"example-context-hash","goal_hash":"example-goal-hash","plan_hash":"example-plan-hash","policy_hash":"example-policy-hash"}'
      expected_hash_keys="goal_hash context_hash plan_hash policy_hash"
      ;;
  esac
  assert_contains "$event_skill_name names checkpoint event API call" "$event_skill_text" "$checkpoint_event_contract"
  for event_key in base checkpoint decision hashes mode subtype outcome created_at; do
    assert_contains "$event_skill_name checkpoint event instruction has $event_key" "$event_skill_text" "$event_key"
  done
  for event_hash_key in $expected_hash_keys; do
    assert_contains "$event_skill_name checkpoint event has relevant $event_hash_key" "$event_skill_text" "\"$event_hash_key\":"
  done
  assert_contains "$event_skill_name imports Path source" "$event_skill_text" '`Path` comes from `pathlib`.'
  assert_contains "$event_skill_name imports pathlib Path" "$event_skill_text" 'from pathlib import Path'
  assert_contains "$event_skill_name imports checkpoint event helper" "$event_skill_text" 'from loen_artifacts import append_checkpoint_event'
  assert_contains "$event_skill_name checkpoint event uses concrete Path base" "$event_skill_text" 'base=Path("docs/loen/example-topic")'
  assert_contains "$event_skill_name checkpoint event uses concrete checkpoint" "$event_skill_text" "checkpoint=\"$expected_checkpoint\""
  assert_contains "$event_skill_name checkpoint event uses concrete decision" "$event_skill_text" "decision=\"$expected_decision\""
  assert_contains "$event_skill_name checkpoint event uses literal hash mapping" "$event_skill_text" 'hashes={'
  assert_contains "$event_skill_name replaces example values instruction" "$event_skill_text" 'Replace the example values with the current topic and artifact values.'
  assert_contains "$event_skill_name allows relevant hash subset mapping" "$event_skill_text" 'For an event with fewer relevant hashes, pass a dictionary containing only the relevant exact key/value pairs; never pass a set.'
  assert_eq "$event_skill_name rejects bare base example" "0" "$(grep -cF 'base=docs/loen/<topic>' "$event_skill" || true)"
  assert_eq "$event_skill_name rejects set-like hashes example" "0" "$(grep -cF 'hashes={goal_hash' "$event_skill" || true)"
  assert_eq "$event_skill_name has no standalone timestamp field" "0" "$(printf '%s\n' "$event_skill_text" | grep -Eic '(^|[^[:alnum:]_])timestamp([^[:alnum:]_]|$)' || true)"

  event_example_dir="$tmp/checkpoint-event-$event_skill_name"
  mkdir -p "$event_example_dir"
  event_example="$(awk '/^```python$/ { capture=1; next } capture && /^```$/ { exit } capture { print }' "$event_skill")"
  event_output="$(cd "$event_example_dir" && PYTHONPATH="$hook_root" python3 - <<<"$event_example" 2>&1)"
  event_code="$?"
  assert_eq "$event_skill_name checkpoint event example runs" "0" "$event_code"
  event_path="$event_example_dir/docs/loen/example-topic/attempts.jsonl"
  assert_exit "$event_skill_name checkpoint event example appends one valid event" 0 python3 - "$event_path" "$expected_checkpoint" "$expected_decision" "$expected_hashes" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines() if path.is_file() else []
record = json.loads(lines[0]) if len(lines) == 1 else {}
expected_hashes = json.loads(sys.argv[4])
valid = record == {
    "event": "checkpoint",
    "checkpoint": sys.argv[2],
    "decision": sys.argv[3],
    "hashes": expected_hashes,
    "mode": "delivery",
    "subtype": "",
    "outcome": sys.argv[3],
    "created_at": "2026-07-23T00:00:00Z",
}
raise SystemExit(0 if valid else 1)
PY
done

assert_contains "loop-run invocation is not confirmation" "$loop_run_text" "Invocation is not launch confirmation."
assert_contains "loop-run validates prelaunch without launch" "$loop_run_text" "require_launch=false"
assert_contains "loop-run attributes helper checks precisely" "$loop_run_text" '`validate_run_contract(require_launch=false)` checks runtime-enforced checkpoints and mode policy.'
assert_contains "loop-run separately inspects supplemental fields" "$loop_run_text" 'SUPPLEMENTAL CONTRACT CHECK: Separately require and inspect `protected_scope`, `stop_conditions`, and `handoff_conditions` before summary or action.'
assert_contains "loop-run presents final contract fields" "$loop_run_text" "Present the final contract fields"
assert_contains "loop-run asks one launch question" "$loop_run_text" "Ask exactly one explicit launch question."
assert_contains "loop-run records refusal and stops" "$loop_run_text" 'append a `refused` launch event and stop'
assert_contains "loop-run records approval hashes" "$loop_run_text" "write the current goal, context, plan, and computed policy hashes into the launch checkpoint"
assert_contains "loop-run computes launch policy with production helper" "$loop_run_text" 'compute the current policy hash with `run_policy_hash(parsed, run_mode, subtype)` over its exact canonical field set before writing the launch checkpoint or confirmed event'
assert_contains "loop-run writes explicit launch confirmation before event" "$loop_run_text" 'write `checkpoints.launch.confirmed: true`, `checkpoints.launch.goal_hash`, `checkpoints.launch.context_hash`, `checkpoints.launch.plan_hash`, and `checkpoints.launch.policy_hash` before appending the confirmed event.'
for launch_field in goal_hash context_hash plan_hash policy_hash; do
  launch_key="checkpoints.launch.$launch_field"
  assert_contains "loop-run names launch $launch_field field" "$loop_run_text" "\`$launch_key\`"
done
assert_contains "loop-run repeats full launch preflight" "$loop_run_text" 'Repeat the complete preflight with `require_launch=true`.'
assert_contains "loop-run resets failed launch" "$loop_run_text" "reset the launch checkpoint, append a reset event, and stop before the state machine"
assert_ordered_lines "loop-run preserves launch gate order" "$loop_run" \
  'PRELAUNCH VALIDATION:' \
  'SUPPLEMENTAL CONTRACT CHECK:' \
  'FINAL CONTRACT SUMMARY:' \
  'LAUNCH QUESTION:' \
  'REFUSAL PATH:' \
  'LAUNCH APPROVAL WRITE:' \
  'POST-APPROVAL PREFLIGHT:' \
  'POST-CONFIRMATION FAILURE:' \
  '## State Machine' \
  '`prepare`:'
assert_contains "loop-run documents state machine" "$loop_run_text" "prepare -> act -> check -> reflect"
assert_contains "loop-run refuses missing approval" "$loop_run_text" "plan approval"
assert_contains "loop-run supports merge release" "$loop_run_text" "merge-release"
assert_contains "merge-release requires universal launch checkpoint" "$loop_run_text" "universal launch checkpoint is required"
assert_contains "merge-release says plan approval is insufficient" "$loop_run_text" "Plan approval alone is insufficient"

assert_contains "governance skill names subtypes" "$loop_governance_text" "report-only"
assert_contains "README documents loop-run" "$(cat "$readme")" "loen:loop-run"
assert_contains "Russian README documents loop-run" "$(cat "$readme_ru")" "loen:loop-run"
assert_contains "architecture documents loop-run" "$(cat "$architecture")" "loop-run"

finish

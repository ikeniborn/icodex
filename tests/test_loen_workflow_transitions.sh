#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

plugin_root="$ROOT/plugins/loen"
hook_root="$plugin_root/hooks"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

transition_status="$(PYTHONPATH="$hook_root" python3 - "$workdir/artifacts" "$plugin_root/assets/templates" <<'PY'
import json
import re
import sys
from pathlib import Path

from loen_artifacts import append_checkpoint_event, artifact_body_hash, run_policy_hash, scaffold_topic, validate_run_contract
from loen_common import parse_loop_yaml

root = Path(sys.argv[1])
base = scaffold_topic(
    artifact_root=root,
    template_dir=Path(sys.argv[2]),
    topic="transition",
    objective="Execute approved transition.",
    mutable_scope=["plugins/loen/**"],
    protected_scope=["README.md"],
    verifier_command="bash tests/test_loen_workflow_transitions.sh",
    quality_gate_command="bash tests/test_loen_workflow_transitions.sh",
    created_date="2026-07-23",
)
required = {"1_goal.md", "2_context.md", "3_plan.md", "4_act.md", "5_check.md", "6_reflect.md", "7_result.md", "loop.yaml", "attempts.jsonl", "handoff.md", "audit.html"}
if not required <= {path.name for path in base.iterdir()}:
    raise SystemExit("production scaffold incomplete")
states = ["scaffold"]
scaffold_artifacts = {name: (base / name).read_text(encoding="utf-8") for name in ("1_goal.md", "2_context.md", "3_plan.md")}
scaffold_action = (base / "4_act.md").read_text(encoding="utf-8")
hashes = {name: artifact_body_hash(base / filename) for name, filename in (("goal_hash", "1_goal.md"), ("context_hash", "2_context.md"), ("plan_hash", "3_plan.md"))}

def set_checkpoint(name, body):
    path = base / "loop.yaml"
    text = path.read_text(encoding="utf-8")
    updated, count = re.subn(rf"(  {name}:\n)(?:    .*\n)+", rf"\g<1>{body}", text, count=1)
    if count != 1:
        raise SystemExit(f"checkpoint not found: {name}")
    path.write_text(updated, encoding="utf-8")

set_checkpoint("goal_context", f"    confirmed: true\n    goal_hash: {hashes['goal_hash']}\n    context_hash: {hashes['context_hash']}\n")
append_checkpoint_event(base=base, checkpoint="goal_context", decision="confirmed", hashes={"goal_hash": hashes["goal_hash"], "context_hash": hashes["context_hash"]})
states.append("goal-context-confirmed")
set_checkpoint("mode", "    confirmed: true\n    mode: delivery\n    subtype: \"\"\n")
append_checkpoint_event(base=base, checkpoint="mode", decision="confirmed", hashes={}, mode="delivery")
states.append("mode-confirmed")
policy = run_policy_hash(parse_loop_yaml((base / "loop.yaml").read_text(encoding="utf-8")), "delivery", "")
set_checkpoint("plan", f"    confirmed: true\n    plan_hash: {hashes['plan_hash']}\n    policy_hash: {policy}\n")
append_checkpoint_event(base=base, checkpoint="plan", decision="confirmed", hashes={"plan_hash": hashes["plan_hash"], "policy_hash": policy}, mode="delivery")
states.append("plan-confirmed")
if validate_run_contract(base, require_launch=False)["ok"] is not True:
    raise SystemExit("prelaunch rejected")
states.append("prelaunch")
if (base / "4_act.md").read_text(encoding="utf-8") != scaffold_action:
    raise SystemExit("invocation acted")
append_checkpoint_event(base=base, checkpoint="launch", decision="refused", hashes={})
states.append("refused")
if (base / "4_act.md").read_text(encoding="utf-8") != scaffold_action:
    raise SystemExit("refusal acted")
set_checkpoint("launch", f"    confirmed: true\n    goal_hash: {hashes['goal_hash']}\n    context_hash: {hashes['context_hash']}\n    plan_hash: {hashes['plan_hash']}\n    policy_hash: {policy}\n")
append_checkpoint_event(base=base, checkpoint="launch", decision="confirmed", hashes=hashes | {"policy_hash": policy})
if validate_run_contract(base)["ok"] is not True:
    raise SystemExit("launch rejected")
if any((base / name).read_text(encoding="utf-8") != text for name, text in scaffold_artifacts.items()):
    raise SystemExit("transition rewrote scaffold stage artifacts")
states.append("launched")
original = (base / "loop.yaml").read_text(encoding="utf-8")
mutations = {
    "mode": lambda value: value.replace("    mode: delivery\n    subtype: \"\"", "    mode: governance\n    subtype: report-only"),
    "subtype": lambda value: value.replace('    subtype: ""', "    subtype: none", 1),
    "mutable-scope": lambda value: value.replace("  - plugins/loen/**", "  - tests/**", 1),
    "protected-scope": lambda value: value.replace("  - README.md", "  - docs/**", 1),
    "quality-gates": lambda value: value.replace("evidence/latest-test.json", "evidence/other.json"),
    "verifier": lambda value: value.replace("  type: test", "  type: review"),
    "budget": lambda value: value.replace("  max_iterations: 3", "  max_iterations: 2"),
    "stop-conditions": lambda value: value.replace("  - quality gates pass", "  - verified", 1),
    "handoff-conditions": lambda value: value.replace("  - schema change required", "  - exhausted", 1),
    "rollback": lambda value: value.replace('rollback_policy: "Revert unsafe changes"', "rollback_policy: Stop"),
    "governance": lambda value: value.replace("  automation_type: manual", "  automation_type: scheduled"),
    "release": lambda value: value.replace('  target_branch: ""', "  target_branch: master"),
}
expected_canonical_inputs = {
    "mode", "subtype", "mutable-scope", "protected-scope", "quality-gates", "verifier",
    "budget", "stop-conditions", "handoff-conditions", "rollback", "governance", "release",
}
if set(mutations) != expected_canonical_inputs:
    missing = sorted(expected_canonical_inputs - set(mutations))
    extra = sorted(set(mutations) - expected_canonical_inputs)
    raise SystemExit(f"incomplete canonical mutation matrix: missing={missing} extra={extra}")
for label, mutate in mutations.items():
    (base / "loop.yaml").write_text(mutate(original), encoding="utf-8")
    if validate_run_contract(base)["reason"] != "plan policy hash mismatch":
        raise SystemExit(f"{label} mutation accepted")
    if (base / "4_act.md").read_text(encoding="utf-8") != scaffold_action:
        raise SystemExit(f"{label} mutation acted")
states.append("policy-rejected")
mutated = mutations["mutable-scope"](original)
current_policy = run_policy_hash(parse_loop_yaml(mutated), "delivery", "")
mutated = re.sub(r"(  plan:\n(?:    .*\n)*?    policy_hash: )[^\n]+", rf"\g<1>{current_policy}", mutated)
(base / "loop.yaml").write_text(mutated, encoding="utf-8")
if validate_run_contract(base)["reason"] != "launch policy hash mismatch":
    raise SystemExit("stale launch policy accepted")
append_checkpoint_event(base=base, checkpoint="plan", decision="confirmed", hashes={"plan_hash": hashes["plan_hash"], "policy_hash": current_policy})
mutated = re.sub(r"(  launch:\n(?:    .*\n)*?    policy_hash: )[^\n]+", rf"\g<1>{current_policy}", mutated)
(base / "loop.yaml").write_text(mutated, encoding="utf-8")
append_checkpoint_event(base=base, checkpoint="launch", decision="confirmed", hashes=hashes | {"policy_hash": current_policy})
if validate_run_contract(base)["ok"] is not True:
    raise SystemExit("reconfirmed current policy rejected")
states.append("reconfirmed")
(base / "4_act.md").write_text("validated action\n", encoding="utf-8")
states.append("acted")
events = [json.loads(line) for line in (base / "attempts.jsonl").read_text(encoding="utf-8").splitlines()]
event_sequence = [(event.get("checkpoint"), event.get("decision")) for event in events]
expected_event_sequence = [
    ("goal_context", "confirmed"),
    ("mode", "confirmed"),
    ("plan", "confirmed"),
    ("launch", "refused"),
    ("launch", "confirmed"),
    ("plan", "confirmed"),
    ("launch", "confirmed"),
]
if event_sequence != expected_event_sequence:
    raise SystemExit(f"event order mismatch: {event_sequence}")
expected = ["scaffold", "goal-context-confirmed", "mode-confirmed", "plan-confirmed", "prelaunch", "refused", "launched", "policy-rejected", "reconfirmed", "acted"]
if states != expected:
    raise SystemExit(f"state order mismatch: {states}")
print("OK")
PY
)"
assert_eq "production scaffold workflow transitions in order" "OK" "$transition_status"

finish

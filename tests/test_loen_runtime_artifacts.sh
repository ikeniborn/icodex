#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

plugin_root="$ROOT/plugins/loen"
artifact_module="$plugin_root/hooks/loen_artifacts.py"
common_module="$plugin_root/hooks/loen_common.py"
audit_writer="$plugin_root/hooks/audit-writer.py"
template_dir="$plugin_root/assets/templates"
workdir="$(mktemp -d)"
artifact_root="$workdir/docs/loen"
todo_path="$workdir/docs/TODO.md"
topic="sample-runtime-topic"
opened_date="$(date +%F)"

cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

assert_exit "artifact module exists" 0 test -f "$artifact_module"
assert_exit "common module exists" 0 test -f "$common_module"
assert_exit "audit writer exists" 0 test -f "$audit_writer"

if [[ -f "$artifact_module" ]]; then
  PYTHONPATH="$plugin_root/hooks" python3 - "$artifact_root" "$template_dir" "$topic" <<'PY'
import sys
from pathlib import Path

from loen_artifacts import scaffold_topic

artifact_root = Path(sys.argv[1])
template_dir = Path(sys.argv[2])
topic = sys.argv[3]

scaffold_topic(
    artifact_root=artifact_root,
    template_dir=template_dir,
    topic=topic,
    objective="Ship durable LoEn runtime artifacts",
    mutable_scope=["plugins/loen/**", "tests/test_loen_runtime_artifacts.sh", "docs/loen/**"],
    protected_scope=["secrets/**", ".codex-isolated/auth/**"],
    verifier_command="bash tests/test_loen_runtime_artifacts.sh",
    quality_gate_command="bash tests/test_loen_runtime_artifacts.sh",
    created_date="2026-07-02",
)
PY
else
  mkdir -p "$artifact_root/$topic"
fi

topic_dir="$artifact_root/$topic"
expected_files=(
  "1_goal.md"
  "2_context.md"
  "3_plan.md"
  "4_act.md"
  "5_check.md"
  "6_reflect.md"
  "7_result.md"
  "loop.yaml"
  "attempts.jsonl"
  "handoff.md"
  "audit.html"
)

for file in "${expected_files[@]}"; do
  assert_exit "scaffold file exists: $file" 0 test -f "$topic_dir/$file"
done

assert_exit "evidence directory exists" 0 test -d "$topic_dir/evidence"
assert_eq "attempts log starts empty" "" "$(cat "$topic_dir/attempts.jsonl" 2>/dev/null)"

loop_text="$(cat "$topic_dir/loop.yaml" 2>/dev/null || true)"
audit_text="$(cat "$topic_dir/audit.html" 2>/dev/null || true)"

assert_contains "loop topic field" "$loop_text" "topic: $topic"
assert_contains "loop mode field" "$loop_text" "mode: delivery"
assert_contains "loop objective field" "$loop_text" 'objective: "Ship durable LoEn runtime artifacts"'
assert_contains "loop current stage field" "$loop_text" "current_stage: goal"
assert_contains "loop mutable scope" "$loop_text" "plugins/loen/**"
assert_contains "loop protected scope" "$loop_text" ".codex-isolated/auth/**"
assert_contains "loop quality gate command" "$loop_text" "command: bash tests/test_loen_runtime_artifacts.sh"
assert_contains "loop quality gate evidence" "$loop_text" "evidence: evidence/latest-test.json"
assert_contains "loop verifier type" "$loop_text" "type: test"
assert_contains "loop verifier command" "$loop_text" "command: bash tests/test_loen_runtime_artifacts.sh"
assert_contains "loop budget" "$loop_text" "max_iterations: 3"
assert_contains "loop stop condition" "$loop_text" "quality gates pass"
assert_contains "loop handoff condition" "$loop_text" "schema change required"
assert_contains "loop rollback policy" "$loop_text" 'rollback_policy: "Revert unsafe changes"'

assert_contains "audit topic" "$audit_text" "LoEn Audit: sample-runtime-topic"
assert_contains "audit status section" "$audit_text" "Current Status"
assert_contains "audit goal section" "$audit_text" "Goal"
assert_contains "audit context section" "$audit_text" "Context"
assert_contains "audit plan section" "$audit_text" "Plan"
assert_contains "audit act section" "$audit_text" "Act"
assert_contains "audit check section" "$audit_text" "Check"
assert_contains "audit reflect section" "$audit_text" "Reflect"
assert_contains "audit result section" "$audit_text" "Result"
assert_contains "audit attempts section" "$audit_text" "Attempts"
assert_contains "audit evidence section" "$audit_text" "Evidence"
assert_contains "audit verdict" "$audit_text" "Not done"

if [[ -f "$artifact_module" ]]; then
  slug_status="$(PYTHONPATH="$plugin_root/hooks" python3 - <<'PY'
from loen_artifacts import validate_topic_slug

valid = ["a", "sample-runtime-topic", "topic-2026-07-02"]
invalid = ["", "../escape", "bad/topic", "BadCase", "-leading", "trailing-", "two--dash", "space topic"]
for slug in valid:
    validate_topic_slug(slug)
for slug in invalid:
    try:
        validate_topic_slug(slug)
    except ValueError:
        continue
    raise SystemExit(f"accepted invalid slug: {slug!r}")
print("OK")
PY
)"
else
  slug_status="missing"
fi
assert_eq "slug validation rejects unsafe names" "OK" "$slug_status"

if [[ -f "$common_module" && -f "$topic_dir/loop.yaml" ]]; then
  parse_status="$(PYTHONPATH="$plugin_root/hooks" python3 - "$topic_dir/loop.yaml" <<'PY'
import sys
from pathlib import Path

from loen_common import parse_loop_yaml

data = parse_loop_yaml(Path(sys.argv[1]).read_text(encoding="utf-8"))
checks = [
    data.get("topic") == "sample-runtime-topic",
    data.get("mode") == "delivery",
    data.get("current_stage") == "goal",
    data.get("stage") == "goal",
    "plugins/loen/**" in data.get("mutable_scope", []),
    ".codex-isolated/auth/**" in data.get("protected_scope", []),
    data.get("quality_gates", [{}])[0].get("command") == "bash tests/test_loen_runtime_artifacts.sh",
    data.get("quality_gates", [{}])[0].get("evidence") == "evidence/latest-test.json",
    data.get("verifier", {}).get("type") == "test",
    data.get("verifier", {}).get("command") == "bash tests/test_loen_runtime_artifacts.sh",
    data.get("budget", {}).get("max_iterations") == "3",
    "quality gates pass" in data.get("stop_conditions", []),
    "schema change required" in data.get("handoff_conditions", []),
    data.get("rollback_policy") == "Revert unsafe changes",
]
print("OK" if all(checks) else "BAD")
PY
)"
else
  parse_status="missing"
fi
assert_eq "loop yaml parses into contract" "OK" "$parse_status"

printf '{"status":"pass","command":"bash tests/test_loen_runtime_artifacts.sh"}\n' > "$topic_dir/evidence/latest-test.json"
printf '# Check\n\n## Result\n\nBYPASS\n' > "$topic_dir/5_check.md"
printf '# Result\n\n## Outcome\n\nNot Done\n' > "$topic_dir/7_result.md"

assert_exit "audit writer runs for negative verdict" 0 env LOEN_MODE=advisory LOEN_TOPIC="$topic" LOEN_ARTIFACT_ROOT="$artifact_root" LOEN_TODO_PATH="$todo_path" python3 "$audit_writer"
negative_audit="$(cat "$topic_dir/audit.html" 2>/dev/null || true)"
assert_contains "audit negative verdict stays not done" "$negative_audit" "Not done"
assert_eq "audit negative verdict is not done" "0" "$(grep -cF "Final verdict:</strong> Done" <<<"$negative_audit" || true)"

if [[ -f "$artifact_module" ]]; then
  opened_default_status="$(PYTHONPATH="$plugin_root/hooks" python3 - <<'PY'
import inspect
from loen_artifacts import upsert_todo_row

default = inspect.signature(upsert_todo_row).parameters["opened"].default
print("OK" if default is None else repr(default))
PY
)"
else
  opened_default_status="missing"
fi
assert_eq "TODO opened date defaults dynamically" "OK" "$opened_default_status"

printf '{"status":"pass","command":"bash tests/test_loen_runtime_artifacts.sh"}\n' > "$topic_dir/evidence/latest-test.json"
printf 'first attempt\nsecond attempt\n' > "$topic_dir/attempts.jsonl"
printf '# Check\n\n## Result\n\nPASS\n' > "$topic_dir/5_check.md"
printf '# Result\n\n## Outcome\n\nDone\n' > "$topic_dir/7_result.md"

assert_exit "audit writer runs first time" 0 env LOEN_MODE=advisory LOEN_TOPIC="$topic" LOEN_ARTIFACT_ROOT="$artifact_root" LOEN_TODO_PATH="$todo_path" python3 "$audit_writer"
assert_exit "audit writer runs second time" 0 env LOEN_MODE=advisory LOEN_TOPIC="$topic" LOEN_ARTIFACT_ROOT="$artifact_root" LOEN_TODO_PATH="$todo_path" python3 "$audit_writer"

updated_audit="$(cat "$topic_dir/audit.html" 2>/dev/null || true)"
updated_todo="$(cat "$todo_path" 2>/dev/null || true)"

assert_contains "audit regenerated with evidence file" "$updated_audit" "evidence/latest-test.json"
assert_contains "audit regenerated with attempts count" "$updated_audit" "2 attempt(s)"
assert_contains "audit regenerated done verdict" "$updated_audit" "Done"
assert_contains "task log row exists" "$updated_todo" "| sample-runtime-topic | in-progress | n/a | n/a | n/a | - | $opened_date |  | LoEn loop |"
assert_eq "task log has one topic row" "1" "$(grep -cF "| sample-runtime-topic |" "$todo_path" 2>/dev/null || true)"

finish

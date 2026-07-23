#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

plugin_root="$ROOT/plugins/loen"
agent_dir="$plugin_root/agents"
template="$plugin_root/assets/templates/loop.yaml"
capsule_script="$plugin_root/hooks/loen_capsules.py"
readme="$plugin_root/README.md"
architecture="$plugin_root/docs/architecture.md"

assert_exit "capsule generator exists" 0 test -f "$capsule_script"

agent_report="$(python3 - "$agent_dir" <<'PY'
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    tomllib = None

agent_dir = Path(sys.argv[1])

def parse_flat_toml(path):
    text = path.read_text(encoding="utf-8")
    if tomllib is not None:
        return tomllib.loads(text)
    data = {}
    for raw_line in text.splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if value == "true":
            data[key] = True
        elif value == "false":
            data[key] = False
        elif value.startswith('"') and value.endswith('"'):
            data[key] = value[1:-1]
        elif value.startswith("[") and value.endswith("]"):
            data[key] = [item.strip().strip('"') for item in value[1:-1].split(",") if item.strip()]
        else:
            data[key] = value
    return data

expected = {
    "loen-planner.toml": {
        "role": "planner",
        "read_only_default": True,
        "capsule_required": True,
        "isolation_level": "L1",
        "execution_isolation": "codex-subagent",
        "codex_profile": "loen-planner",
    },
    "loen-worker.toml": {
        "role": "worker",
        "read_only_default": False,
        "capsule_required": True,
        "mutable_scope_required": True,
        "isolation_level": "L2",
        "execution_isolation": "worktree",
        "codex_profile": "loen-worker",
    },
    "loen-verifier.toml": {
        "role": "verifier",
        "read_only_default": True,
        "capsule_required": True,
        "isolation_level": "L3",
        "execution_isolation": "wasm",
        "executor": "wasmtime",
        "network_default": "off",
    },
    "loen-reviewer.toml": {
        "role": "reviewer",
        "read_only_default": True,
        "capsule_required": True,
        "isolation_level": "L1",
        "execution_isolation": "codex-subagent",
        "codex_profile": "loen-reviewer",
    },
    "loen-researcher.toml": {
        "role": "researcher",
        "read_only_default": True,
        "capsule_required": True,
        "experiment_scope_required": True,
        "isolation_level": "L1",
        "execution_isolation": "codex-subagent",
        "codex_profile": "loen-researcher",
    },
}

failures = []
for filename, checks in expected.items():
    path = agent_dir / filename
    if not path.is_file():
        failures.append(f"{filename}:missing")
        continue
    data = parse_flat_toml(path)
    for key, expected_value in checks.items():
        actual = data.get(key)
        if actual != expected_value:
            failures.append(f"{filename}:{key}={actual!r}")

print("OK" if not failures else "\n".join(failures))
PY
)"
assert_eq "agent isolation metadata" "OK" "$agent_report"

template_body="$(cat "$template" 2>/dev/null || true)"
assert_contains "loop template defines context capsule contract" "$template_body" "context_capsule:"
assert_contains "loop template lists required capsule fields" "$template_body" "Specific question or task for the agent"
assert_contains "loop template includes researcher role policy" "$template_body" "researcher:"
assert_contains "loop template includes profile split contract" "$template_body" "profiles:"
assert_contains "loop template declares WASM execution" "$template_body" "isolation: wasm"
assert_contains "loop template defaults verifier network off" "$template_body" "network: off"
forbidden_runtime="$(grep -En 'isolation: (microvm|container)|executor: (microvm|container)' "$template" 2>/dev/null || true)"
assert_eq "loop template does not make microVM or container core default" "" "$forbidden_runtime"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
topic_dir="$tmp/docs/loen/demo-topic"
mkdir -p "$topic_dir/evidence"

cat > "$topic_dir/loop.yaml" <<'YAML'
topic: demo-topic
mode: delivery
status: active
objective: "Ship isolated verifier capsule"
current_stage: check
mutable_scope:
  - plugins/loen/**
protected_scope:
  - .codex-isolated/**
quality_gates:
  - command: bash tests/test_loen_agent_isolation.sh
    evidence: evidence/agent-isolation.txt
execution:
  isolation: wasm
  executor: wasmtime
  network: off
  mounts:
    - path: .
      mode: read-only
    - path: /tmp/loen
      mode: write
YAML

cat > "$topic_dir/2_context.md" <<'MD'
# Context

## Relevant Files
- plugins/loen/agents/loen-verifier.toml
- plugins/loen/hooks/loen_capsules.py

## Transcript
UNRELATED_TRANSCRIPT_SHOULD_NOT_LEAK
MD

cat > "$topic_dir/5_check.md" <<'MD'
# Check

## Last Evidence Summary
Focused agent isolation fixture has not passed yet.
MD

if [[ -f "$capsule_script" ]]; then
  capsule="$(python3 "$capsule_script" "$topic_dir" verifier "Run the verifier gate and report evidence." 2>/dev/null || true)"
else
  capsule=""
fi
assert_contains "capsule includes topic" "$capsule" "Topic"
assert_contains "capsule includes topic value" "$capsule" "demo-topic"
assert_contains "capsule includes objective" "$capsule" "Ship isolated verifier capsule"
assert_contains "capsule includes loop mode" "$capsule" "delivery"
assert_contains "capsule includes current stage" "$capsule" "check"
assert_contains "capsule includes mutable scope" "$capsule" "plugins/loen/**"

cp "$topic_dir/loop.yaml" "$topic_dir/loop.yaml.valid"
python3 - "$topic_dir/loop.yaml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(text.replace("  - plugins/loen/**", "  - plugins/loen/**\n  \t- outside/**"), encoding="utf-8")
PY
capsule_stderr="$tmp/capsule-malformed.stderr"
capsule_code=0
python3 "$capsule_script" "$topic_dir" verifier "Run malformed authority." >/dev/null 2>"$capsule_stderr" || capsule_code=$?
assert_eq "capsule rejects malformed canonical authority" "1" "$([[ "$capsule_code" -ne 0 ]] && echo 1 || echo 0)"
assert_contains "capsule explains malformed canonical authority" "$(cat "$capsule_stderr")" "invalid canonical authority"
mv "$topic_dir/loop.yaml.valid" "$topic_dir/loop.yaml"

cp "$topic_dir/loop.yaml" "$topic_dir/loop.yaml.valid"
python3 - "$topic_dir/loop.yaml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(text.replace("    mode: read-only", "    mode: read-only\n    metadata:\n      mode: write", 1), encoding="utf-8")
PY
capsule_stderr="$tmp/capsule-nested-execution.stderr"
capsule_code=0
python3 "$capsule_script" "$topic_dir" verifier "Run nested execution authority." >/dev/null 2>"$capsule_stderr" || capsule_code=$?
assert_eq "capsule rejects nested execution mount overwrite" "1" "$([[ "$capsule_code" -ne 0 ]] && echo 1 || echo 0)"
assert_contains "capsule diagnoses nested execution mount overwrite" "$(cat "$capsule_stderr")" "invalid canonical authority"
mv "$topic_dir/loop.yaml.valid" "$topic_dir/loop.yaml"

cp "$topic_dir/loop.yaml" "$topic_dir/loop.yaml.valid"
python3 - "$topic_dir/loop.yaml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(text.replace("      mode: read-only", "       metadata:\n      mode: write", 1), encoding="utf-8")
PY
capsule_stderr="$tmp/capsule-odd-execution.stderr"
capsule_code=0
python3 "$capsule_script" "$topic_dir" verifier "Run odd-indent execution authority." >/dev/null 2>"$capsule_stderr" || capsule_code=$?
assert_eq "capsule rejects odd-indent execution mapping" "1" "$([[ "$capsule_code" -ne 0 ]] && echo 1 || echo 0)"
assert_contains "capsule diagnoses odd-indent execution mapping" "$(cat "$capsule_stderr")" "invalid canonical authority"
mv "$topic_dir/loop.yaml.valid" "$topic_dir/loop.yaml"
assert_contains "capsule includes protected scope" "$capsule" ".codex-isolated/**"
assert_contains "capsule includes quality gate" "$capsule" "bash tests/test_loen_agent_isolation.sh"
assert_contains "capsule includes relevant files" "$capsule" "plugins/loen/hooks/loen_capsules.py"
assert_contains "capsule includes evidence summary" "$capsule" "Focused agent isolation fixture has not passed yet."
assert_contains "capsule includes role question" "$capsule" "Run the verifier gate and report evidence."
leak_count="$(grep -c 'UNRELATED_TRANSCRIPT_SHOULD_NOT_LEAK' <<<"$capsule" || true)"
assert_eq "capsule excludes unrelated transcript text" "0" "$leak_count"

unsafe_dir="$tmp/docs/loen/unsafe-topic"
mkdir -p "$unsafe_dir"
cat > "$unsafe_dir/loop.yaml" <<'YAML'
topic: unsafe-topic
mode: delivery
status: active
objective: "Unsafe verifier"
current_stage: check
execution:
  isolation: wasm
  executor: wasmtime
  network: on
YAML

unsafe_code=0
unsafe_output="$(python3 "$capsule_script" "$unsafe_dir" verifier "Run checks." 2>&1 >/dev/null)" || unsafe_code=$?
assert_eq "capsule generator rejects network-enabled WASM verifier" "2" "$unsafe_code"
assert_contains "unsafe verifier rejection explains network" "$unsafe_output" "network must be off"

assert_contains "README documents context capsules" "$(cat "$readme" 2>/dev/null)" "context capsules"
assert_contains "architecture documents L0" "$(cat "$architecture" 2>/dev/null)" "L0"
assert_contains "architecture documents L4 external adapter" "$(cat "$architecture" 2>/dev/null)" "L4"
assert_contains "architecture documents WASM-first verifier" "$(cat "$architecture" 2>/dev/null)" "WASM-first verifier"

finish

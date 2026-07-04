---
review:
  plan_hash: 286612209abf9eba
  last_run: 2026-07-04
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings: []
chain:
  intent: null
  spec: docs/superpowers/specs/2026-07-02-04-loen-agent-isolation-design.md
result_check:
  verdict: OK
  plan_hash: 286612209abf9eba
  last_run: 2026-07-04
---

# 04 LoEn Agent Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make LoEn role separation concrete through bounded context capsules, explicit role isolation metadata, and a WASM-first verifier safety check.

**Architecture:** Keep layer 4 inside the editable LoEn plugin source tree under `plugins/loen/`. A small standard-library capsule renderer reads only `docs/loen/<topic>/` artifacts, agent TOML files declare role defaults, and the loop template carries the WASM-first execution contract. This layer does not install LoEn, change icodex launch wiring, vendor cache files, add containers, or add microVM runtime code.

**Tech Stack:** Bash fixture tests, Python 3 standard library, flat TOML agent metadata, lightweight YAML parsing already used by LoEn hook assets.

Spec: `docs/superpowers/specs/2026-07-02-04-loen-agent-isolation-design.md`

---

## Scope Check

This spec covers one subsystem: LoEn agent isolation source assets and local validation. It builds role metadata, context capsule generation, L0-L4 documentation, and a WASM-first verifier config check. It does not implement icodex launch-time profile wiring, cache vendoring, background automation, external containers, or microVM adapters; those are owned by later LoEn layers.

The workspace may already contain LoEn agent files and hook helpers from layers 1-3. Execute this as a reconciliation plan: preserve matching behavior, add only missing layer 4 behavior, then verify the result with `/check-chain result`.

## File Structure

- **Create** `tests/test_loen_agent_isolation.sh` - focused Bash fixture suite for role metadata, context capsule rendering, transcript exclusion, WASM verifier network rejection, and template/documentation boundaries.
- **Create** `plugins/loen/hooks/loen_capsules.py` - deterministic context capsule renderer used by tests and future LoEn skills; reads topic artifacts, emits only required capsule fields, rejects unsafe verifier WASM defaults.
- **Modify** `plugins/loen/agents/loen-planner.toml` - marks planner as read-only by default with capsule and Codex profile metadata.
- **Modify** `plugins/loen/agents/loen-worker.toml` - binds worker to mutable scope and worktree/profile isolation metadata.
- **Modify** `plugins/loen/agents/loen-verifier.toml` - marks verifier as read-only with WASM-first executor and network-off defaults.
- **Modify** `plugins/loen/agents/loen-reviewer.toml` - marks reviewer as read-only with review-only capsule metadata.
- **Modify** `plugins/loen/agents/loen-researcher.toml` - marks researcher as experiment-scope bound and read-only by default.
- **Modify** `plugins/loen/assets/templates/loop.yaml` - adds `context_capsule`, `profiles`, `execution`, and researcher policy defaults while keeping existing hook policy sections.
- **Modify** `plugins/loen/docs/README.md` - documents agent isolation assets and capsule boundary.
- **Modify** `plugins/loen/docs/architecture.md` - documents L0-L4 isolation levels and WASM-first verifier boundary.
- **Update via iwiki MCP** page `loen-overview` and create page `loen-agent-isolation` after implementation.
- **Do not modify** `icodex.sh`, `lib/`, `.codex-isolated/plugins/cache/`, plugin installation wiring, or external runtime adapters in this plan.

## Execution Prerequisites

Use the project branch workflow before Task 1. If no suitable `dev-*` branch already exists, use `git-workflow` and `superpowers:using-git-worktrees`: ask whether to create a worktree, then create a branch such as `dev-04-loen-agent-isolation` from the intended base branch. Run every command from the repository root.

Before implementation, validate the spec gate if it is not already cached:

```text
/check-chain spec docs/superpowers/specs/2026-07-02-04-loen-agent-isolation-design.md
```

Expected: `OK` or `OK (cached, hash match)`. If the spec gate reports open CRITICAL findings, fix the spec first and rerun the gate before editing code.

---

### Task 1: Add Agent Isolation Fixture Coverage

**Files:**
- Create: `tests/test_loen_agent_isolation.sh`
- Read: `tests/helpers.sh`
- Read: `docs/superpowers/specs/2026-07-02-04-loen-agent-isolation-design.md`

- [ ] **Step 1: Write the failing fixture suite**

Create `tests/test_loen_agent_isolation.sh` with this content:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

plugin_root="$ROOT/plugins/loen"
agent_dir="$plugin_root/agents"
template="$plugin_root/assets/templates/loop.yaml"
capsule_script="$plugin_root/hooks/loen_capsules.py"
readme="$plugin_root/docs/README.md"
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
```

- [ ] **Step 2: Run the new test to verify it fails**

Run:

```bash
bash tests/test_loen_agent_isolation.sh
```

Expected: exits `1`. Output contains at least:

```text
FAIL [capsule generator exists]
FAIL [agent isolation metadata]
FAIL [loop template defines context capsule contract]
```

- [ ] **Step 3: Commit the failing test**

```bash
git add tests/test_loen_agent_isolation.sh
git commit -m "test(loen): cover agent isolation contract"
```

---

### Task 2: Add Context Capsule Renderer

**Files:**
- Create: `plugins/loen/hooks/loen_capsules.py`
- Test: `tests/test_loen_agent_isolation.sh`

- [ ] **Step 1: Write the minimal capsule renderer**

Create `plugins/loen/hooks/loen_capsules.py` with this content:

```python
#!/usr/bin/env python3
"""Render bounded LoEn context capsules from topic artifacts."""
from __future__ import annotations

from pathlib import Path
import sys
from typing import Any

from loen_common import parse_loop_yaml

BLOCK = 2


def read_text(path: Path) -> str:
  try:
    return path.read_text(encoding="utf-8")
  except (OSError, UnicodeDecodeError):
    return ""


def normalize_heading(line: str) -> str:
  return line.lstrip("#").strip().lower().replace("_", "-").replace(" ", "-")


def extract_section(text: str, *headings: str) -> str:
  wanted = {heading.lower().replace("_", "-").replace(" ", "-") for heading in headings}
  lines = text.splitlines()
  collecting = False
  collected: list[str] = []
  for line in lines:
    stripped = line.strip()
    if stripped.startswith("#"):
      if collecting:
        break
      collecting = normalize_heading(stripped) in wanted
      continue
    if collecting:
      collected.append(line.rstrip())
  return "\n".join(line for line in collected if line.strip()).strip()


def parse_execution(text: str) -> dict[str, Any]:
  execution: dict[str, Any] = {"mounts": []}
  in_execution = False
  in_mounts = False
  current_mount: dict[str, str] | None = None

  for raw_line in text.splitlines():
    line = raw_line.split("#", 1)[0].rstrip()
    if not line.strip():
      continue
    indent = len(line) - len(line.lstrip(" "))
    stripped = line.strip()

    if indent == 0:
      in_execution = stripped == "execution:"
      in_mounts = False
      current_mount = None
      continue
    if not in_execution:
      continue

    if indent == 2 and stripped == "mounts:":
      in_mounts = True
      continue
    if in_mounts and stripped.startswith("- "):
      current_mount = {}
      execution["mounts"].append(current_mount)
      item = stripped[2:].strip()
      if ":" in item:
        key, value = item.split(":", 1)
        current_mount[key.strip()] = value.strip().strip('"').strip("'")
      continue
    if in_mounts and current_mount is not None and ":" in stripped:
      key, value = stripped.split(":", 1)
      current_mount[key.strip()] = value.strip().strip('"').strip("'")
      continue
    if indent == 2 and ":" in stripped:
      key, value = stripped.split(":", 1)
      execution[key.strip()] = value.strip().strip('"').strip("'")

  return execution


def bullet_list(values: Any) -> str:
  if isinstance(values, list) and values:
    return "\n".join(f"- {value}" for value in values)
  if isinstance(values, str) and values:
    return f"- {values}"
  return "- none"


def quality_gates(policy: dict[str, Any]) -> str:
  gates = policy.get("quality_gates", [])
  if not isinstance(gates, list) or not gates:
    return "- none"
  rendered = []
  for gate in gates:
    if not isinstance(gate, dict):
      continue
    command = gate.get("command", "")
    evidence = gate.get("evidence", "")
    rendered.append(f"- {command} -> {evidence}" if evidence else f"- {command}")
  return "\n".join(rendered) if rendered else "- none"


def validate_verifier_execution(role: str, execution: dict[str, Any]) -> str:
  if role != "verifier":
    return ""
  if execution.get("isolation") != "wasm":
    return ""
  if execution.get("network", "off") != "off":
    return "LoEn verifier WASM execution network must be off"
  for mount in execution.get("mounts", []):
    if not isinstance(mount, dict):
      continue
    path = mount.get("path", "")
    mode = mount.get("mode", "")
    if path == "." and mode != "read-only":
      return "LoEn verifier project mount must be read-only"
    if mode == "write" and path != "/tmp/loen":
      return "LoEn verifier write mount must be /tmp/loen"
  return ""


def render_capsule(topic_dir: Path, role: str, question: str) -> str:
  loop_text = read_text(topic_dir / "loop.yaml")
  policy = parse_loop_yaml(loop_text)
  execution = parse_execution(loop_text)
  rejection = validate_verifier_execution(role, execution)
  if rejection:
    raise ValueError(rejection)

  context_text = read_text(topic_dir / "2_context.md")
  check_text = read_text(topic_dir / "5_check.md")
  relevant_files = extract_section(context_text, "Relevant Files", "Relevant files")
  last_evidence = extract_section(check_text, "Last Evidence Summary", "Last evidence summary")

  topic = str(policy.get("topic") or topic_dir.name)
  objective = str(policy.get("objective") or "")
  mode = str(policy.get("mode") or "")
  current_stage = str(policy.get("current_stage") or policy.get("stage") or "")

  return "\n".join([
    "Topic",
    topic,
    "",
    "Objective",
    objective,
    "",
    "Loop mode",
    mode,
    "",
    "Current stage",
    current_stage,
    "",
    "Mutable scope",
    bullet_list(policy.get("mutable_scope", [])),
    "",
    "Protected scope",
    bullet_list(policy.get("protected_scope", [])),
    "",
    "Quality gates",
    quality_gates(policy),
    "",
    "Relevant files",
    relevant_files or "- none",
    "",
    "Last evidence summary",
    last_evidence or "none",
    "",
    "Specific question or task for the agent",
    question,
    "",
  ])


def main(argv: list[str]) -> int:
  if len(argv) < 4:
    print("usage: loen_capsules.py <topic-dir> <role> <question>", file=sys.stderr)
    return BLOCK
  topic_dir = Path(argv[1])
  role = argv[2]
  question = argv[3]
  try:
    print(render_capsule(topic_dir, role, question), end="")
  except ValueError as exc:
    print(str(exc), file=sys.stderr)
    return BLOCK
  return 0


if __name__ == "__main__":
  raise SystemExit(main(sys.argv))
```

- [ ] **Step 2: Run the focused test and verify remaining failures**

Run:

```bash
bash tests/test_loen_agent_isolation.sh
```

Expected: exits `1`. Capsule-related assertions pass; remaining failures mention agent metadata, template fields, or docs text.

- [ ] **Step 3: Run Python syntax check**

Run:

```bash
python3 -m py_compile plugins/loen/hooks/loen_capsules.py
```

Expected: exits `0` with no output.

- [ ] **Step 4: Commit the capsule renderer**

```bash
git add plugins/loen/hooks/loen_capsules.py tests/test_loen_agent_isolation.sh
git commit -m "feat(loen): render bounded context capsules"
```

---

### Task 3: Add Role Isolation Metadata and Loop Defaults

**Files:**
- Modify: `plugins/loen/agents/loen-planner.toml`
- Modify: `plugins/loen/agents/loen-worker.toml`
- Modify: `plugins/loen/agents/loen-verifier.toml`
- Modify: `plugins/loen/agents/loen-reviewer.toml`
- Modify: `plugins/loen/agents/loen-researcher.toml`
- Modify: `plugins/loen/assets/templates/loop.yaml`
- Test: `tests/test_loen_agent_isolation.sh`
- Test: `tests/test_loen_plugin_core.sh`

- [ ] **Step 1: Replace planner role metadata**

Replace `plugins/loen/agents/loen-planner.toml` with:

```toml
name = "loen-planner"
role = "planner"
summary = "Creates bounded LoEn plans from goal and context artifacts."
read_only_default = true
artifact_root = "docs/loen"
allowed_outputs = ["3_plan.md"]
capsule_required = true
isolation_level = "L1"
execution_isolation = "codex-subagent"
codex_profile = "loen-planner"
```

- [ ] **Step 2: Replace worker role metadata**

Replace `plugins/loen/agents/loen-worker.toml` with:

```toml
name = "loen-worker"
role = "worker"
summary = "Executes one bounded LoEn action step and records action evidence."
read_only_default = false
artifact_root = "docs/loen"
allowed_outputs = ["4_act.md"]
capsule_required = true
mutable_scope_required = true
protected_scope_required = true
isolation_level = "L2"
execution_isolation = "worktree"
codex_profile = "loen-worker"
```

- [ ] **Step 3: Replace verifier role metadata**

Replace `plugins/loen/agents/loen-verifier.toml` with:

```toml
name = "loen-verifier"
role = "verifier"
summary = "Runs or inspects checks and records verification evidence."
read_only_default = true
artifact_root = "docs/loen"
allowed_outputs = ["5_check.md"]
capsule_required = true
isolation_level = "L3"
execution_isolation = "wasm"
executor = "wasmtime"
network_default = "off"
allowed_checks = ["quality_gates", "verifier.command"]
```

- [ ] **Step 4: Replace reviewer role metadata**

Replace `plugins/loen/agents/loen-reviewer.toml` with:

```toml
name = "loen-reviewer"
role = "reviewer"
summary = "Reviews diffs and evidence before a LoEn loop is accepted."
read_only_default = true
artifact_root = "docs/loen"
allowed_outputs = ["5_check.md", "6_reflect.md"]
capsule_required = true
isolation_level = "L1"
execution_isolation = "codex-subagent"
codex_profile = "loen-reviewer"
```

- [ ] **Step 5: Replace researcher role metadata**

Replace `plugins/loen/agents/loen-researcher.toml` with:

```toml
name = "loen-researcher"
role = "researcher"
summary = "Frames metric-driven LoEn experiments and records observations."
read_only_default = true
artifact_root = "docs/loen"
allowed_outputs = ["2_context.md", "5_check.md"]
capsule_required = true
experiment_scope_required = true
isolation_level = "L1"
execution_isolation = "codex-subagent"
codex_profile = "loen-researcher"
```

- [ ] **Step 6: Replace loop template with capsule and execution defaults**

Replace `plugins/loen/assets/templates/loop.yaml` with:

```yaml
topic: {{topic}}
mode: delivery
status: active
objective: "{{objective}}"
current_stage: goal
stage: goal
created: "{{created_date}}"
updated: "{{updated_date}}"
mutable_scope:
  - {{mutable_scope}}
protected_scope:
  - {{protected_scope}}
quality_gates:
  - command: {{quality_gate_command}}
    evidence: evidence/latest-test.json
verifier:
  type: test
  command: {{verifier_command}}
budget:
  max_iterations: 3
stop_conditions:
  - quality gates pass
handoff_conditions:
  - schema change required
rollback_policy: "Revert unsafe changes"
context_capsule:
  required_fields:
    - Topic
    - Objective
    - Loop mode
    - Current stage
    - Mutable scope
    - Protected scope
    - Quality gates
    - Relevant files
    - Last evidence summary
    - Specific question or task for the agent
profiles:
  planner: loen-planner
  worker: loen-worker
  verifier: loen-verifier
  reviewer: loen-reviewer
  researcher: loen-researcher
execution:
  isolation: wasm
  executor: wasmtime
  network: off
  mounts:
    - path: .
      mode: read-only
    - path: /tmp/loen
      mode: write
agents:
  planner:
    tools: [read, search]
    sandbox: read-only
  worker:
    tools: [read, search, edit, shell]
    sandbox: workspace-write
  verifier:
    tools: [read, search, shell]
    sandbox: read-only
    must_not_edit: true
  reviewer:
    tools: [read, search, shell]
    sandbox: read-only
    must_not_edit: true
  researcher:
    tools: [read, search, shell]
    sandbox: read-only
    experiment_scope_required: true
stages:
  goal:
    roles: [planner, worker]
  context:
    roles: [planner, worker, researcher]
  plan:
    roles: [planner]
  act:
    roles: [worker]
  check:
    roles: [verifier]
  reflect:
    roles: [planner, verifier, reviewer]
  result:
    roles: [planner, verifier, reviewer]
tools:
  allowed:
    - read
    - search
    - apply_patch
    - shell
  denied:
    - network
    - secrets
    - destructive_git
    - external_write
permissions:
  filesystem:
    mutable_scope:
      - src/**
      - tests/**
    protected_scope:
      - migrations/**
      - secrets/**
  network:
    mode: off
    allowlist: []
  shell:
    allow:
      - pytest tests/auth
      - ruff check .
    deny_patterns:
      - rm -rf
      - git reset --hard
      - curl *|sh
```

- [ ] **Step 7: Run focused tests**

Run:

```bash
bash tests/test_loen_agent_isolation.sh
bash tests/test_loen_plugin_core.sh
```

Expected:

```text
PASS=... FAIL=0
PASS=... FAIL=0
```

The exact PASS count may change as assertions are added; both commands must exit `0`.

- [ ] **Step 8: Commit role metadata and template defaults**

```bash
git add plugins/loen/agents/loen-planner.toml plugins/loen/agents/loen-worker.toml plugins/loen/agents/loen-verifier.toml plugins/loen/agents/loen-reviewer.toml plugins/loen/agents/loen-researcher.toml plugins/loen/assets/templates/loop.yaml tests/test_loen_agent_isolation.sh
git commit -m "feat(loen): define agent isolation defaults"
```

---

### Task 4: Document Agent Isolation Boundary

**Files:**
- Modify: `plugins/loen/docs/README.md`
- Modify: `plugins/loen/docs/architecture.md`
- Test: `tests/test_loen_agent_isolation.sh`

- [ ] **Step 1: Add README section**

Append this section to `plugins/loen/docs/README.md`:

```markdown
## Agent Isolation

LoEn role agents receive context capsules instead of the full main-thread
transcript. A capsule is generated from `docs/loen/<topic>/` artifacts and
contains only the topic, objective, loop mode, current stage, mutable scope,
protected scope, quality gates, relevant files, last evidence summary, and the
specific question or task for that agent.

Planner, verifier, reviewer, and researcher roles are read-only by default.
The worker role is the only default mutating role and must be bound to the
configured mutable scope. The verifier uses a WASM-first execution contract with
network off by default; external container and microVM adapters are outside this
source-layer plugin boundary.
```

- [ ] **Step 2: Add architecture section**

Append this section to `plugins/loen/docs/architecture.md`:

```markdown
## Agent Isolation Levels

LoEn separates role context and execution through five documented levels:

| Level | Mechanism | Purpose |
|---|---|---|
| L0 | Same session | Simple advisory use. |
| L1 | Codex subagent with context capsule | Context isolation and role separation. |
| L2 | Separate `CODEX_HOME`, worktree, and Codex profile | Stronger local split for worker and verifier runs. |
| L3 | WASM executor for deterministic tools and evals | Lightweight verifier execution isolation. |
| L4 | External heavy adapter | Future container or microVM adapter for workloads WASM cannot cover. |

The source plugin implements L1 capsule assets, L2 metadata, and a WASM-first
L3 verifier contract. It does not run container or microVM workloads in core.

## WASM-first Verifier

Verifier capsules reject WASM execution configs that enable network access.
The default execution contract uses `isolation: wasm`, `executor: wasmtime`,
`network: off`, a read-only project mount, and a writable `/tmp/loen` mount for
ephemeral verifier output.
```

- [ ] **Step 3: Run focused doc assertions**

Run:

```bash
bash tests/test_loen_agent_isolation.sh
```

Expected:

```text
PASS=... FAIL=0
```

- [ ] **Step 4: Commit documentation**

```bash
git add plugins/loen/docs/README.md plugins/loen/docs/architecture.md tests/test_loen_agent_isolation.sh
git commit -m "docs(loen): describe agent isolation boundary"
```

---

### Task 5: Update Wiki and Validate Full Layer

**Files:**
- Source for wiki page: `plugins/loen/docs/architecture.md`
- Source for wiki overview update: `docs/superpowers/specs/2026-07-02-04-loen-agent-isolation-design.md`
- Test: `tests/test_loen_agent_isolation.sh`
- Test: `tests/test_loen_plugin_core.sh`
- Test: `tests/test_loen_enforcement_hooks.sh`

- [ ] **Step 1: Update iwiki page `loen-agent-isolation`**

Use the iwiki MCP write tool with domain `icodex`, slug `loen-agent-isolation`, source `plugins/loen/docs/architecture.md`, and this markdown body:

```markdown
# LoEn Agent Isolation

## Summary

Layer 4 makes LoEn role separation concrete through role metadata, bounded
context capsules, documented isolation levels, and a WASM-first verifier safety
check. The layer remains inside the editable plugin source tree and does not
install LoEn or add external runtime adapters.

## Role Defaults

Planner, verifier, reviewer, and researcher roles are read-only by default.
The worker role may mutate only within configured mutable scope. All roles
require context capsules, and each role file declares the intended isolation
level and Codex profile name.

## Context Capsules

`plugins/loen/hooks/loen_capsules.py` renders capsules from
`docs/loen/<topic>/` artifacts. A capsule contains Topic, Objective, Loop mode,
Current stage, Mutable scope, Protected scope, Quality gates, Relevant files,
Last evidence summary, and Specific question or task for the agent. It does not
copy unrelated transcript text.

## Isolation Levels

LoEn documents L0 same-session use, L1 Codex subagent capsules, L2 separate
`CODEX_HOME` plus worktree plus Codex profile metadata, L3 WASM verifier
execution, and L4 external heavy adapters. L4 remains a future adapter boundary,
not core plugin code.

## WASM-first Verifier

Verifier capsules reject WASM execution configs that enable network access. The
default contract is `isolation: wasm`, `executor: wasmtime`, `network: off`, a
read-only project mount, and a writable `/tmp/loen` mount.

## Validation

`tests/test_loen_agent_isolation.sh` validates role metadata, capsule content,
transcript exclusion, unsafe verifier network rejection, and documentation
coverage. The existing plugin core and enforcement hook fixture suites remain
compatible with the added source assets.
```

Expected: wiki write succeeds. If the page already exists, use `wiki_update_page` to replace the relevant `##` sections with the same text rather than creating a duplicate page.

- [ ] **Step 2: Update iwiki page `loen-overview` layer table**

Use `wiki_update_page` on domain `icodex`, slug `loen-overview`, heading `Layer Sequence`, source `docs/superpowers/specs/2026-07-02-04-loen-agent-isolation-design.md`, and replace the layer 4 row with:

```markdown
| 4 | `04-loen-agent-isolation` | [[loen-agent-isolation]] | Planner/worker/verifier/reviewer/researcher role separation, context capsules, Codex profile split metadata, and WASM-first verifier model |
```

Expected: wiki update succeeds and reindexes the domain automatically.

- [ ] **Step 3: Run iwiki lint**

Use `wiki_lint(domain="icodex")`.

Expected: no broken refs, no orphan pages, no stale pages. Advisory section-length warnings may remain if they predate this layer.

- [ ] **Step 4: Run focused LoEn tests**

Run:

```bash
bash tests/test_loen_agent_isolation.sh
bash tests/test_loen_plugin_core.sh
bash tests/test_loen_enforcement_hooks.sh
python3 -m py_compile plugins/loen/hooks/*.py
```

Expected:

```text
PASS=... FAIL=0
PASS=... FAIL=0
PASS=... FAIL=0
```

The `py_compile` command exits `0` with no output.

- [ ] **Step 5: Run the full Bash suite**

Run:

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: exits `0`. Every test file ends with `FAIL=0`.

- [ ] **Step 6: Run plan/result gates**

Run:

```text
/check-chain plan docs/superpowers/plans/2026-07-02-04-loen-agent-isolation.md
/check-chain result docs/superpowers/plans/2026-07-02-04-loen-agent-isolation.md
```

Expected: plan gate returns `OK` or `OK (cached, hash match)`. Result gate returns `OK` after implementation diff is present and all plan steps reconcile.

- [ ] **Step 7: Commit validation artifacts**

```bash
git add plugins/loen/docs/README.md plugins/loen/docs/architecture.md docs/superpowers/plans/2026-07-02-04-loen-agent-isolation.md docs/superpowers/reports/04-loen-agent-isolation-results.html
git add -u docs
git commit -m "docs(loen): record agent isolation validation"
```

---

## Self-Review

Spec coverage:
- Agent roles are explicit: Task 3 updates all five role TOML files and Task 1 validates each role.
- Context capsules are available through generated capsules and custom agents: Task 2 adds the renderer, Task 1 validates required fields and transcript exclusion, Task 3 requires capsules in agent metadata.
- Isolation levels are documented: Task 4 adds L0-L4 docs, Task 1 validates doc coverage.
- WASM-first verifier starts with WASM, not container or microVM core code: Task 3 sets the template and verifier metadata, Task 2 rejects network-enabled WASM verifier configs, Task 1 checks that microVM/container are not defaults.
- Tests named in the spec are covered by Task 1 and Task 5.

Placeholder scan: no unresolved placeholder markers are present in this plan body. Template variables in `plugins/loen/assets/templates/loop.yaml` are intentional source-template fields.

Type and name consistency:
- `loen_capsules.py` defines `render_capsule()`, `parse_execution()`, and `validate_verifier_execution()` before any test invokes the CLI.
- Agent metadata keys used by tests match the TOML keys in Task 3.
- The plan uses the same file name `tests/test_loen_agent_isolation.sh` in every command and commit step.

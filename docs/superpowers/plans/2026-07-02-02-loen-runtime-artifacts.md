# 02 LoEn Runtime Artifacts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make LoEn create and maintain durable per-topic runtime artifacts under `docs/loen/<topic>/`, with a concrete `loop.yaml` contract, regenerated per-topic `audit.html`, evidence storage, and duplicate-free `docs/TODO.md` rows.

**Architecture:** Keep runtime artifact behavior inside the editable LoEn plugin source under `plugins/loen/`; do not add launcher wiring or installed-cache mutation in this layer. Add a small dependency-free Python artifact module that both skills and hooks can rely on, then make `audit-writer.py` use that module for audit rendering and task-log upserts. Keep tests as Bash entrypoints with Python standard-library assertions, matching existing repository style.

**Tech Stack:** Bash tests, Python 3 standard library, Markdown templates, lightweight YAML parsing already present in `plugins/loen/hooks/loen_common.py`.

Spec: `docs/superpowers/specs/2026-07-02-02-loen-runtime-artifacts-design.md`

---

## Scope Check

This spec covers one subsystem: durable LoEn topic artifacts under `docs/loen/<topic>/`. It does not install LoEn into `.codex-isolated/`, wire `icodex.sh`, enforce hook blocking semantics, or introduce role isolation beyond data stored in `loop.yaml`. Those behaviors remain owned by later LoEn layer specs.

## File Structure

- **Create** `tests/test_loen_runtime_artifacts.sh` - contract test for scaffold creation, slug validation, loop contract parsing, audit regeneration, and duplicate-free task-log rows.
- **Create** `plugins/loen/hooks/loen_artifacts.py` - dependency-free artifact helper module for topic slug validation, scaffold creation, audit rendering, and `docs/TODO.md` upserts.
- **Modify** `plugins/loen/hooks/loen_common.py` - parse the layer-2 `loop.yaml` shape while preserving existing hook callers.
- **Modify** `plugins/loen/hooks/audit-writer.py` - delegate audit rendering and task-log updates to `loen_artifacts.py`.
- **Modify** `plugins/loen/assets/templates/loop.yaml` - replace layer-1 placeholder policy with the required runtime contract fields.
- **Modify** `plugins/loen/assets/templates/audit.html` - make the template match the generated audit sections.
- **Modify** `plugins/loen/skills/loop-start/SKILL.md` - document exact artifact scaffold and slug rules for workers.
- **Modify** `plugins/loen/docs/README.md` and `plugins/loen/docs/architecture.md` - document runtime artifact ownership and boundaries.
- **Update via iwiki MCP** `loen-runtime-artifacts` and `loen-overview` - document the implemented layer and update the overview layer table from "Not implemented yet" to `[[loen-runtime-artifacts]]`.
- **Modify** `docs/TODO.md` only during check-chain result closure, not during ordinary implementation steps in this plan.
- **Do not modify** `lib/`, `icodex.sh`, `.codex-isolated/plugins/cache/`, or global LoEn integration wiring in this plan.

## Execution Prerequisites

Use the project branch workflow before Task 1. If no suitable `dev-*` branch already exists, use `git-workflow` and `superpowers:using-git-worktrees`: ask whether to create a worktree, then create a branch such as `dev-02-loen-runtime-artifacts` from the intended base branch. Run all commands from the repository root.

---

### Task 1: Add Runtime Artifact Contract Test

**Files:**
- Create: `tests/test_loen_runtime_artifacts.sh`
- Read: `docs/superpowers/specs/2026-07-02-02-loen-runtime-artifacts-design.md`
- Read: `tests/helpers.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_loen_runtime_artifacts.sh` with:

```bash
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
printf 'first attempt\nsecond attempt\n' > "$topic_dir/attempts.jsonl"
printf '# Check\n\n## Result\n\nPASS\n' > "$topic_dir/5_check.md"
printf '# Result\n\n## Outcome\n\nDone\n' > "$topic_dir/7_result.md"

assert_exit "audit writer runs first time" 0 env LOEN_TOPIC="$topic" LOEN_ARTIFACT_ROOT="$artifact_root" LOEN_TODO_PATH="$todo_path" python3 "$audit_writer"
assert_exit "audit writer runs second time" 0 env LOEN_TOPIC="$topic" LOEN_ARTIFACT_ROOT="$artifact_root" LOEN_TODO_PATH="$todo_path" python3 "$audit_writer"

updated_audit="$(cat "$topic_dir/audit.html" 2>/dev/null || true)"
updated_todo="$(cat "$todo_path" 2>/dev/null || true)"

assert_contains "audit regenerated with evidence file" "$updated_audit" "evidence/latest-test.json"
assert_contains "audit regenerated with attempts count" "$updated_audit" "2 attempt(s)"
assert_contains "audit regenerated done verdict" "$updated_audit" "Done"
assert_contains "task log row exists" "$updated_todo" "| sample-runtime-topic | in-progress | n/a | n/a | n/a | - | 2026-07-02 |  | LoEn loop |"
assert_eq "task log has one topic row" "1" "$(grep -cF "| sample-runtime-topic |" "$todo_path" 2>/dev/null || true)"

finish
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bash tests/test_loen_runtime_artifacts.sh
```

Expected: FAIL. The current tree has no `plugins/loen/hooks/loen_artifacts.py`, the current `loop.yaml` template does not expose the required layer-2 fields, and the generated audit page does not include all required sections. Expected failing lines include:

```text
FAIL [artifact module exists]: exit 1 want 0
FAIL [loop current stage field]: 'current_stage: goal' not found
FAIL [audit status section]: 'Current Status' not found
```

- [ ] **Step 3: Syntax-check the new test**

Run:

```bash
bash -n tests/test_loen_runtime_artifacts.sh
```

Expected: exit code `0`.

- [ ] **Step 4: Commit the failing test**

```bash
git add tests/test_loen_runtime_artifacts.sh
git commit -m "test(loen): cover runtime artifact contract"
```

Expected: commit succeeds with only `tests/test_loen_runtime_artifacts.sh` staged.

---

### Task 2: Add Artifact Helper Module

**Files:**
- Create: `plugins/loen/hooks/loen_artifacts.py`
- Test: `tests/test_loen_runtime_artifacts.sh`

- [ ] **Step 1: Create the artifact helper**

Create `plugins/loen/hooks/loen_artifacts.py` with:

```python
#!/usr/bin/env python3
"""LoEn runtime artifact helpers."""
from __future__ import annotations

from dataclasses import dataclass
import html
import re
from pathlib import Path


STAGE_FILES = (
  "1_goal.md",
  "2_context.md",
  "3_plan.md",
  "4_act.md",
  "5_check.md",
  "6_reflect.md",
  "7_result.md",
)

RUNTIME_FILES = STAGE_FILES + (
  "loop.yaml",
  "attempts.jsonl",
  "handoff.md",
  "audit.html",
)

SLUG_RE = re.compile(r"^[a-z0-9](?:[a-z0-9]|-(?=[a-z0-9])){0,78}[a-z0-9]?$")


@dataclass(frozen=True)
class LoopSummary:
  topic: str
  mode: str
  objective: str
  current_stage: str
  verifier_type: str
  verifier_command: str
  max_iterations: str
  rollback_policy: str


def validate_topic_slug(topic: str) -> str:
  value = topic.strip()
  if not value or "/" in value or "\\" in value or ".." in value:
    raise ValueError("LoEn topic must be a safe kebab-case slug")
  if not SLUG_RE.match(value):
    raise ValueError("LoEn topic must use lowercase letters, numbers, and single dashes")
  if "--" in value:
    raise ValueError("LoEn topic must not contain repeated dashes")
  return value


def _quote(value: str) -> str:
  escaped = value.replace("\\", "\\\\").replace('"', '\\"')
  return f'"{escaped}"'


def _yaml_list(values: list[str], indent: str = "  ") -> str:
  if not values:
    return f"{indent}- none"
  return "\n".join(f"{indent}- {value}" for value in values)


def _template(path: Path, fallback: str) -> str:
  try:
    return path.read_text(encoding="utf-8")
  except OSError:
    return fallback


def _render_stage_template(template_dir: Path, filename: str, topic: str, objective: str) -> str:
  fallback = f"# {filename}\n\nTopic: `{{{{topic}}}}`\n"
  text = _template(template_dir / filename, fallback)
  replacements = {
    "{{topic}}": topic,
    "{{user_request}}": objective,
    "{{success_criterion}}": "Loop artifacts exist and audit can be regenerated from repository state.",
    "{{fact}}": "Runtime state lives in this directory, not in chat history.",
    "{{constraint}}": "Do not create a global LoEn audit index.",
    "{{step}}": "Create or update the current LoEn stage artifact",
    "{{verification}}": "Run the loop quality gate command",
    "{{check_command}}": "bash tests/test_loen_runtime_artifacts.sh",
    "{{action_summary}}": "No action recorded yet.",
    "{{path}}": f"docs/loen/{topic}",
    "{{command}}": "bash tests/test_loen_runtime_artifacts.sh",
    "{{evidence}}": "No evidence recorded yet.",
    "{{result}}": "pending",
    "{{decision}}": "continue",
    "{{reason}}": "Initial scaffold.",
    "{{next_step}}": "Run the planned action and check stages.",
    "{{outcome}}": "pending",
    "{{evidence_file}}": "evidence/latest-test.json",
  }
  for old, new in replacements.items():
    text = text.replace(old, new)
  return text


def loop_yaml_text(
  *,
  topic: str,
  objective: str,
  mutable_scope: list[str],
  protected_scope: list[str],
  verifier_command: str,
  quality_gate_command: str,
  created_date: str,
) -> str:
  return "\n".join([
    f"topic: {topic}",
    "mode: delivery",
    "status: active",
    f"objective: {_quote(objective)}",
    "current_stage: goal",
    "stage: goal",
    f"created: {_quote(created_date)}",
    f"updated: {_quote(created_date)}",
    "mutable_scope:",
    _yaml_list(mutable_scope),
    "protected_scope:",
    _yaml_list(protected_scope),
    "quality_gates:",
    f"  - command: {quality_gate_command}",
    "    evidence: evidence/latest-test.json",
    "verifier:",
    "  type: test",
    f"  command: {verifier_command}",
    "budget:",
    "  max_iterations: 3",
    "stop_conditions:",
    "  - quality gates pass",
    "handoff_conditions:",
    "  - schema change required",
    'rollback_policy: "Revert unsafe changes"',
    "",
  ])


def scaffold_topic(
  *,
  artifact_root: Path,
  template_dir: Path,
  topic: str,
  objective: str,
  mutable_scope: list[str],
  protected_scope: list[str],
  verifier_command: str,
  quality_gate_command: str,
  created_date: str,
) -> Path:
  topic_name = validate_topic_slug(topic)
  base = artifact_root / topic_name
  base.mkdir(parents=True, exist_ok=True)
  (base / "evidence").mkdir(parents=True, exist_ok=True)

  for filename in STAGE_FILES:
    path = base / filename
    if not path.exists():
      path.write_text(_render_stage_template(template_dir, filename, topic_name, objective), encoding="utf-8")

  handoff = base / "handoff.md"
  if not handoff.exists():
    text = _template(template_dir / "handoff.md", "# Handoff\n\nTopic: `{{topic}}`\n")
    text = text.replace("{{topic}}", topic_name)
    text = text.replace("{{current_state}}", "Initial scaffold.")
    text = text.replace("{{required_decision}}", "None.")
    handoff.write_text(text, encoding="utf-8")

  attempts = base / "attempts.jsonl"
  if not attempts.exists():
    attempts.write_text("", encoding="utf-8")

  (base / "loop.yaml").write_text(
    loop_yaml_text(
      topic=topic_name,
      objective=objective,
      mutable_scope=mutable_scope,
      protected_scope=protected_scope,
      verifier_command=verifier_command,
      quality_gate_command=quality_gate_command,
      created_date=created_date,
    ),
    encoding="utf-8",
  )
  (base / "audit.html").write_text(render_audit(base, topic_name), encoding="utf-8")
  return base


def _read(path: Path) -> str:
  try:
    return path.read_text(encoding="utf-8")
  except (OSError, UnicodeDecodeError):
    return ""


def _first_heading_body(text: str) -> str:
  lines = [line for line in text.splitlines() if not line.startswith("# ")]
  body = "\n".join(lines).strip()
  return body if body else "No content recorded."


def _attempt_count(base: Path) -> int:
  text = _read(base / "attempts.jsonl")
  return len([line for line in text.splitlines() if line.strip()])


def _evidence_files(base: Path) -> list[str]:
  evidence_dir = base / "evidence"
  if not evidence_dir.is_dir():
    return []
  return [f"evidence/{path.name}" for path in sorted(evidence_dir.iterdir()) if path.is_file()]


def _summary_from_loop(loop_text: str, topic: str) -> LoopSummary:
  values: dict[str, str] = {}
  for raw in loop_text.splitlines():
    if ":" not in raw or raw.startswith(" ") or raw.startswith("-"):
      continue
    key, value = raw.split(":", 1)
    values[key.strip()] = value.strip().strip('"')
  verifier_command = ""
  verifier_type = ""
  budget_value = ""
  lines = loop_text.splitlines()
  for index, raw in enumerate(lines):
    if raw.strip() == "verifier:":
      for child in lines[index + 1:index + 4]:
        stripped = child.strip()
        if stripped.startswith("type:"):
          verifier_type = stripped.split(":", 1)[1].strip().strip('"')
        if stripped.startswith("command:"):
          verifier_command = stripped.split(":", 1)[1].strip().strip('"')
    if raw.strip() == "budget:":
      for child in lines[index + 1:index + 3]:
        stripped = child.strip()
        if stripped.startswith("max_iterations:"):
          budget_value = stripped.split(":", 1)[1].strip().strip('"')
  return LoopSummary(
    topic=values.get("topic", topic),
    mode=values.get("mode", ""),
    objective=values.get("objective", ""),
    current_stage=values.get("current_stage", values.get("stage", "")),
    verifier_type=verifier_type,
    verifier_command=verifier_command,
    max_iterations=budget_value,
    rollback_policy=values.get("rollback_policy", ""),
  )


def render_audit(base: Path, topic: str) -> str:
  loop_text = _read(base / "loop.yaml")
  summary = _summary_from_loop(loop_text, topic)
  evidence_files = _evidence_files(base)
  has_result = "Done" in _read(base / "7_result.md")
  has_check = "PASS" in _read(base / "5_check.md")
  verdict = "Done" if has_result and has_check and evidence_files else "Not done"
  evidence_html = "\n".join(f"<li>{html.escape(path)}</li>" for path in evidence_files) or "<li>No evidence files.</li>"

  sections = [
    ("Goal", _read(base / "1_goal.md")),
    ("Context", _read(base / "2_context.md")),
    ("Plan", _read(base / "3_plan.md")),
    ("Act", _read(base / "4_act.md")),
    ("Check", _read(base / "5_check.md")),
    ("Reflect", _read(base / "6_reflect.md")),
    ("Result", _read(base / "7_result.md")),
  ]
  stage_html = "\n".join(
    f"<section><h2>{html.escape(title)}</h2><pre>{html.escape(_first_heading_body(text))}</pre></section>"
    for title, text in sections
  )

  return "\n".join([
    "<!doctype html>",
    "<html lang=\"en\">",
    "<head>",
    "  <meta charset=\"utf-8\">",
    "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
    f"  <title>LoEn Audit: {html.escape(topic)}</title>",
    "</head>",
    "<body>",
    "  <main>",
    f"    <h1>LoEn Audit: {html.escape(topic)}</h1>",
    "    <section>",
    "      <h2>Current Status</h2>",
    f"      <p><strong>Mode:</strong> {html.escape(summary.mode)}</p>",
    f"      <p><strong>Stage:</strong> {html.escape(summary.current_stage)}</p>",
    f"      <p><strong>Objective:</strong> {html.escape(summary.objective)}</p>",
    f"      <p><strong>Verifier:</strong> {html.escape(summary.verifier_type)} - {html.escape(summary.verifier_command)}</p>",
    f"      <p><strong>Budget:</strong> {html.escape(summary.max_iterations)} iteration(s)</p>",
    f"      <p><strong>Rollback:</strong> {html.escape(summary.rollback_policy)}</p>",
    f"      <p><strong>Final verdict:</strong> {verdict}</p>",
    "    </section>",
    stage_html,
    "    <section>",
    "      <h2>Attempts</h2>",
    f"      <p>{_attempt_count(base)} attempt(s)</p>",
    "    </section>",
    "    <section>",
    "      <h2>Evidence</h2>",
    f"      <ul>{evidence_html}</ul>",
    "    </section>",
    "  </main>",
    "</body>",
    "</html>",
    "",
  ])


def upsert_todo_row(todo_path: Path, topic: str, opened: str = "2026-07-02") -> None:
  topic_name = validate_topic_slug(topic)
  header = "| Topic | Status | Intent | Spec | Plan | Result | Opened | Closed | Notes |\n"
  separator = "|-------|--------|--------|------|------|--------|--------|--------|-------|\n"
  row = f"| {topic_name} | in-progress | n/a | n/a | n/a | - | {opened} |  | LoEn loop |\n"
  todo_path.parent.mkdir(parents=True, exist_ok=True)
  lines = todo_path.read_text(encoding="utf-8").splitlines(keepends=True) if todo_path.is_file() else [header, separator]
  needle = f"| {topic_name} |"
  for index, line in enumerate(lines):
    if line.startswith(needle):
      cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
      if len(cells) == 9:
        if cells[1] != "done":
          cells[1] = "in-progress"
        if not cells[6]:
          cells[6] = opened
        lines[index] = "| " + " | ".join(cells) + " |\n"
      else:
        lines[index] = row
      break
  else:
    lines.append(row)
  todo_path.write_text("".join(lines), encoding="utf-8")
```

- [ ] **Step 2: Run the contract test**

Run:

```bash
bash tests/test_loen_runtime_artifacts.sh
```

Expected: FAIL. The helper exists and slug checks pass, but `parse_loop_yaml()` does not yet parse top-level lists, and `audit-writer.py` still renders the old compact audit.

- [ ] **Step 3: Syntax-check the helper**

Run:

```bash
python3 -m py_compile plugins/loen/hooks/loen_artifacts.py
```

Expected: exit code `0`.

- [ ] **Step 4: Commit the helper**

```bash
git add plugins/loen/hooks/loen_artifacts.py
git commit -m "feat(loen): add runtime artifact helpers"
```

Expected: commit succeeds with only `plugins/loen/hooks/loen_artifacts.py` staged.

---

### Task 3: Parse Layer-2 Loop Contract

**Files:**
- Modify: `plugins/loen/hooks/loen_common.py`
- Test: `tests/test_loen_runtime_artifacts.sh`

- [ ] **Step 1: Replace `parse_loop_yaml()` with a parser that supports the runtime contract**

In `plugins/loen/hooks/loen_common.py`, replace the whole `parse_loop_yaml` function with:

```python
def parse_loop_yaml(text: str) -> dict[str, Any]:
  data: dict[str, Any] = {
    "agents": {},
    "stages": {},
    "tools": {"allowed": [], "denied": []},
    "permissions": {
      "filesystem": {"mutable_scope": [], "protected_scope": []},
      "network": {"mode": "off", "allowlist": []},
      "shell": {"allow": [], "deny_patterns": []},
    },
    "mutable_scope": [],
    "protected_scope": [],
    "quality_gates": [],
    "verifier": {},
    "budget": {},
    "stop_conditions": [],
    "handoff_conditions": [],
  }
  section = ""
  subsection = ""
  current_agent = ""
  current_list_item: dict[str, Any] | None = None
  list_target: list[Any] | None = None

  for raw_line in text.splitlines():
    line = raw_line.split("#", 1)[0].rstrip()
    if not line.strip():
      continue
    indent = len(line) - len(line.lstrip(" "))
    stripped = line.strip()

    if indent == 0:
      subsection = ""
      current_agent = ""
      current_list_item = None
      list_target = None
      if stripped.endswith(":"):
        section = stripped[:-1]
        if section in {"mutable_scope", "protected_scope", "stop_conditions", "handoff_conditions"}:
          list_target = data[section]
        continue
      section = ""
      if ":" in stripped:
        key, value = stripped.split(":", 1)
        parsed = _parse_scalar(value)
        data[key.strip()] = parsed
        if key.strip() == "current_stage":
          data["stage"] = parsed
      continue

    if section in {"mutable_scope", "protected_scope", "stop_conditions", "handoff_conditions"}:
      if stripped.startswith("- "):
        data[section].append(stripped[2:].strip())
      continue

    if section == "quality_gates":
      if stripped.startswith("- "):
        current_list_item = {}
        data["quality_gates"].append(current_list_item)
        item = stripped[2:].strip()
        if ":" in item:
          key, value = item.split(":", 1)
          current_list_item[key.strip()] = _parse_scalar(value)
      elif current_list_item is not None and ":" in stripped:
        key, value = stripped.split(":", 1)
        current_list_item[key.strip()] = _parse_scalar(value)
      continue

    if section in {"verifier", "budget"}:
      if ":" in stripped:
        key, value = stripped.split(":", 1)
        data[section][key.strip()] = _parse_scalar(value)
      continue

    if section == "agents":
      if indent == 2 and stripped.endswith(":"):
        current_agent = stripped[:-1]
        data["agents"].setdefault(current_agent, {})
        list_target = None
        continue
      if current_agent and ":" in stripped:
        key, value = stripped.split(":", 1)
        key = key.strip()
        value = value.strip()
        data["agents"][current_agent][key] = _parse_inline_list(value) or _parse_scalar(value)
      continue

    if section == "stages":
      if indent == 2 and stripped.endswith(":"):
        current_agent = stripped[:-1]
        data["stages"].setdefault(current_agent, {})
        list_target = None
        continue
      if current_agent and ":" in stripped:
        key, value = stripped.split(":", 1)
        key = key.strip()
        value = value.strip()
        data["stages"][current_agent][key] = _parse_inline_list(value) or _parse_scalar(value)
      continue

    if section == "tools":
      if ":" in stripped:
        key, value = stripped.split(":", 1)
        key = key.strip()
        parsed = _parse_inline_list(value)
        data["tools"].setdefault(key, [])
        if parsed or value.strip() == "[]":
          data["tools"][key] = parsed
          list_target = None
        else:
          list_target = data["tools"][key]
      elif stripped.startswith("- ") and list_target is not None:
        list_target.append(stripped[2:].strip())
      continue

    if section == "permissions":
      if indent == 2 and stripped.endswith(":"):
        subsection = stripped[:-1]
        list_target = None
        continue
      target = data["permissions"].setdefault(subsection, {})
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

  if data["mutable_scope"] and not data["permissions"]["filesystem"]["mutable_scope"]:
    data["permissions"]["filesystem"]["mutable_scope"] = list(data["mutable_scope"])
  if data["protected_scope"] and not data["permissions"]["filesystem"]["protected_scope"]:
    data["permissions"]["filesystem"]["protected_scope"] = list(data["protected_scope"])
  if "current_stage" not in data and "stage" in data:
    data["current_stage"] = data["stage"]
  return data
```

- [ ] **Step 2: Run the contract test**

Run:

```bash
bash tests/test_loen_runtime_artifacts.sh
```

Expected: FAIL. The parser assertion now passes, but `audit-writer.py` still writes the old audit and task-log row shape.

- [ ] **Step 3: Run existing LoEn hook tests**

Run:

```bash
bash tests/test_loen_plugin_core.sh
bash tests/test_loen_enforcement_hooks.sh
```

Expected: both commands exit `0`. Existing hook behavior still accepts the old template shape and the new layer-2 fields.

- [ ] **Step 4: Syntax-check the changed hook helper**

Run:

```bash
python3 -m py_compile plugins/loen/hooks/loen_common.py
```

Expected: exit code `0`.

- [ ] **Step 5: Commit parser support**

```bash
git add plugins/loen/hooks/loen_common.py
git commit -m "feat(loen): parse runtime loop contract"
```

Expected: commit succeeds with only `plugins/loen/hooks/loen_common.py` staged.

---

### Task 4: Delegate Audit Writer to Runtime Artifact Helpers

**Files:**
- Modify: `plugins/loen/hooks/audit-writer.py`
- Test: `tests/test_loen_runtime_artifacts.sh`

- [ ] **Step 1: Replace `audit-writer.py`**

Replace `plugins/loen/hooks/audit-writer.py` with:

```python
#!/usr/bin/env python3
"""LoEn audit artifact writer; reads LOEN_ARTIFACT_ROOT through loen_common."""
import os
from pathlib import Path

from loen_artifacts import render_audit, upsert_todo_row, validate_topic_slug
from loen_common import is_off, read_loop_artifact, topic, topic_dir

SCRIPT_NAME = "audit-writer"


def main() -> int:
  if is_off():
    return 0
  topic_name = topic()
  if not topic_name or not read_loop_artifact(topic_name):
    return 0
  try:
    validate_topic_slug(topic_name)
  except ValueError:
    return 0
  base = topic_dir(topic_name)
  try:
    base.mkdir(parents=True, exist_ok=True)
    (base / "audit.html").write_text(render_audit(base, topic_name), encoding="utf-8")
    upsert_todo_row(Path(os.environ.get("LOEN_TODO_PATH", "docs/TODO.md")), topic_name)
  except OSError:
    return 0
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
```

- [ ] **Step 2: Run the contract test**

Run:

```bash
bash tests/test_loen_runtime_artifacts.sh
```

Expected: PASS. Final line:

```text
PASS=45 FAIL=0
```

- [ ] **Step 3: Run existing LoEn hook tests**

Run:

```bash
bash tests/test_loen_plugin_core.sh
bash tests/test_loen_enforcement_hooks.sh
```

Expected: both commands exit `0`.

- [ ] **Step 4: Syntax-check changed Python files**

Run:

```bash
python3 -m py_compile plugins/loen/hooks/loen_artifacts.py plugins/loen/hooks/loen_common.py plugins/loen/hooks/audit-writer.py
```

Expected: exit code `0`.

- [ ] **Step 5: Commit audit writer integration**

```bash
git add plugins/loen/hooks/audit-writer.py
git commit -m "feat(loen): regenerate topic audit artifacts"
```

Expected: commit succeeds with only `plugins/loen/hooks/audit-writer.py` staged.

---

### Task 5: Update Templates and Loop-Start Skill

**Files:**
- Modify: `plugins/loen/assets/templates/loop.yaml`
- Modify: `plugins/loen/assets/templates/audit.html`
- Modify: `plugins/loen/skills/loop-start/SKILL.md`
- Test: `tests/test_loen_runtime_artifacts.sh`

- [ ] **Step 1: Replace `loop.yaml` template**

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
```

- [ ] **Step 2: Replace `audit.html` template**

Replace `plugins/loen/assets/templates/audit.html` with:

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>LoEn Audit: {{topic}}</title>
</head>
<body>
  <main>
    <h1>LoEn Audit: {{topic}}</h1>
    <section>
      <h2>Current Status</h2>
      <p><strong>Mode:</strong> {{mode}}</p>
      <p><strong>Stage:</strong> {{current_stage}}</p>
      <p><strong>Objective:</strong> {{objective}}</p>
      <p><strong>Final verdict:</strong> {{verdict}}</p>
    </section>
    <section><h2>Goal</h2>{{goal}}</section>
    <section><h2>Context</h2>{{context}}</section>
    <section><h2>Plan</h2>{{plan}}</section>
    <section><h2>Act</h2>{{act}}</section>
    <section><h2>Check</h2>{{check}}</section>
    <section><h2>Reflect</h2>{{reflect}}</section>
    <section><h2>Result</h2>{{result}}</section>
    <section><h2>Attempts</h2>{{attempts}}</section>
    <section><h2>Evidence</h2>{{evidence}}</section>
  </main>
</body>
</html>
```

- [ ] **Step 3: Replace loop-start procedure**

In `plugins/loen/skills/loop-start/SKILL.md`, replace the `## Procedure` section with:

```markdown
## Procedure

1. Choose a topic slug that matches `^[a-z0-9](?:[a-z0-9]|-(?=[a-z0-9])){0,78}[a-z0-9]?$`.
2. Reject empty slugs, path traversal, slashes, uppercase letters, spaces, leading dashes, trailing dashes, and repeated dashes.
3. Create or reuse `docs/loen/<topic>/`.
4. Create these files directly in the topic directory: `1_goal.md`, `2_context.md`, `3_plan.md`, `4_act.md`, `5_check.md`, `6_reflect.md`, `7_result.md`, `loop.yaml`, `attempts.jsonl`, `handoff.md`, and `audit.html`.
5. Create `docs/loen/<topic>/evidence/` for run evidence files such as `latest-test.json` and `latest-test.log`.
6. Write `loop.yaml` with `topic`, `mode`, `objective`, `current_stage`, `mutable_scope`, `protected_scope`, `quality_gates`, `verifier`, `budget`, `stop_conditions`, `handoff_conditions`, and `rollback_policy`.
7. Keep `docs/TODO.md` as the only global task registry; do not create a global LoEn audit index.
8. Record durable task facts in `docs/loen/<topic>/`; do not use chat history as the source of truth.
```

- [ ] **Step 4: Run runtime artifact test**

Run:

```bash
bash tests/test_loen_runtime_artifacts.sh
```

Expected: PASS. Final line:

```text
PASS=45 FAIL=0
```

- [ ] **Step 5: Run plugin core fixture test**

Run:

```bash
bash tests/test_loen_plugin_core.sh
```

Expected: exit code `0`.

- [ ] **Step 6: Commit templates and skill docs**

```bash
git add plugins/loen/assets/templates/loop.yaml plugins/loen/assets/templates/audit.html plugins/loen/skills/loop-start/SKILL.md
git commit -m "docs(loen): define runtime artifact templates"
```

Expected: commit succeeds with only the three listed files staged.

---

### Task 6: Document Runtime Artifact Layer

**Files:**
- Modify: `plugins/loen/docs/README.md`
- Modify: `plugins/loen/docs/architecture.md`
- Update via iwiki MCP: `loen-runtime-artifacts`
- Update via iwiki MCP: `loen-overview`

- [ ] **Step 1: Add README runtime section**

Append this section to `plugins/loen/docs/README.md`:

```markdown
## Runtime Artifacts

Each LoEn topic stores durable runtime state under `docs/loen/<topic>/`.
The topic directory contains numbered stage files from `1_goal.md` through
`7_result.md`, a machine-readable `loop.yaml`, append-only `attempts.jsonl`,
an `evidence/` directory, `handoff.md`, and a regenerated per-topic
`audit.html`.

`docs/TODO.md` remains the only global task registry. LoEn does not create a
global audit index.
```

- [ ] **Step 2: Add architecture runtime boundary**

Append this section to `plugins/loen/docs/architecture.md`:

```markdown
## Runtime Artifact Boundary

Runtime topic artifacts are repository-local and live under
`docs/loen/<topic>/`. Hooks and skills read that directory as durable loop
state so the loop can continue across context compaction, new threads,
subagents, reviews, and later automation.

`loop.yaml` is the machine-readable contract for one topic. The audit writer
regenerates `audit.html` from repository artifacts and updates the matching
`docs/TODO.md` row without creating duplicate rows.
```

- [ ] **Step 3: Update iwiki runtime page**

Use `wiki_write_page` if the page does not exist, or `wiki_update_page` if it already exists, for slug `loen-runtime-artifacts` with this Markdown:

```markdown
# LoEn Runtime Artifacts

## Summary

Layer 2 defines durable LoEn topic artifacts under `docs/loen/<topic>/`.
The directory is the source of truth for loop state across context compaction,
new threads, subagents, review, and later automation.

## Topic Layout

Each topic directory contains `1_goal.md`, `2_context.md`, `3_plan.md`,
`4_act.md`, `5_check.md`, `6_reflect.md`, `7_result.md`, `loop.yaml`,
`attempts.jsonl`, `evidence/`, `handoff.md`, and `audit.html`.

## Loop Contract

`loop.yaml` records the topic, mode, objective, current stage, mutable scope,
protected scope, quality gates, verifier command, iteration budget,
stop conditions, handoff conditions, and rollback policy.

## Audit and Task Log

`audit.html` is per topic and is regenerated from repository artifacts.
LoEn does not create a global audit index. `docs/TODO.md` remains the only
global human-readable task registry, and LoEn updates the matching topic row
without creating duplicates.
```

- [ ] **Step 4: Update iwiki overview page**

Use `wiki_update_page(domain="icodex", slug="loen-overview", heading="Layer Sequence", ...)` so the layer table row for order `2` reads:

```markdown
| 2 | `02-loen-runtime-artifacts` | [[loen-runtime-artifacts]] | `docs/loen/<topic>/` artifacts, `loop.yaml`, per-topic `audit.html`, and TODO row rules |
```

- [ ] **Step 5: Run iwiki lint**

Run the MCP tool:

```text
wiki_lint(domain="icodex")
```

Expected: no broken refs for `[[loen-runtime-artifacts]]`.

- [ ] **Step 6: Commit local docs**

```bash
git add plugins/loen/docs/README.md plugins/loen/docs/architecture.md
git commit -m "docs(loen): document runtime artifacts"
```

Expected: commit succeeds with only the two plugin docs staged. iwiki writes auto-commit in the iwiki base; do not run `wiki_index` after successful iwiki write.

---

### Task 7: Verify Full Runtime Artifact Layer

**Files:**
- Test: `tests/test_loen_runtime_artifacts.sh`
- Test: `tests/test_loen_plugin_core.sh`
- Test: `tests/test_loen_enforcement_hooks.sh`

- [ ] **Step 1: Run focused runtime test**

Run:

```bash
bash tests/test_loen_runtime_artifacts.sh
```

Expected final line:

```text
PASS=45 FAIL=0
```

- [ ] **Step 2: Run focused LoEn regression tests**

Run:

```bash
bash tests/test_loen_plugin_core.sh
bash tests/test_loen_enforcement_hooks.sh
```

Expected: both commands exit `0`.

- [ ] **Step 3: Run Python syntax checks**

Run:

```bash
python3 -m py_compile plugins/loen/hooks/loen_artifacts.py plugins/loen/hooks/loen_common.py plugins/loen/hooks/audit-writer.py
```

Expected: exit code `0`.

- [ ] **Step 4: Run full Bash suite**

Run:

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: exit code `0`.

- [ ] **Step 5: Validate chain stage**

Run:

```bash
/check-chain result 02-loen-runtime-artifacts
```

Expected: verdict `OK`. This closes the matching row in `docs/TODO.md` as `done` with `Result: OK`.

- [ ] **Step 6: Commit chain-result updates if `docs/TODO.md` changed**

```bash
git add docs/TODO.md
git commit -m "docs(loen): close runtime artifacts task"
```

Expected: commit succeeds if `docs/TODO.md` changed. If `/check-chain result` made no local file changes, skip this commit.

---

## Self-Review Notes

- Spec coverage: scaffold files, slug validation, `loop.yaml` required fields, audit regeneration, and duplicate-free `docs/TODO.md` updates are covered by Task 1 and implemented in Tasks 2-5.
- Scope boundary: no `.agent-loop/`, no global audit index, no launcher wiring, and no installed-cache mutation are introduced.
- Type consistency: tests and implementation use `validate_topic_slug`, `scaffold_topic`, `render_audit`, `upsert_todo_row`, `parse_loop_yaml`, `current_stage`, `quality_gates`, `verifier`, and `budget` consistently.

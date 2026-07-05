#!/usr/bin/env python3
"""LoEn runtime artifact helpers."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date
import html
import json
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
  stop_conditions: list[str]
  handoff_conditions: list[str]
  protected_scope: list[str]


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


def validate_topic_slug(topic: str) -> str:
  if not topic or topic != topic.strip() or "/" in topic or "\\" in topic or ".." in topic:
    raise ValueError("LoEn topic must be a safe kebab-case slug")
  if not SLUG_RE.match(topic):
    raise ValueError("LoEn topic must use lowercase letters, numbers, and single dashes")
  if "--" in topic:
    raise ValueError("LoEn topic must not contain repeated dashes")
  return topic


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
    "governance:",
    "  automation_type: manual",
    '  schedule: ""',
    '  owner: ""',
    "  first_runs_require_human_review: 3",
    "  reviewed_runs: 0",
    "  auto_fix: false",
    "  auto_merge: false",
    "  report_only_on_no_findings: true",
    "  alert_on:",
    "    - protected_scope_attempt",
    "    - verifier_failure",
    "    - budget_exhausted",
    "    - metric_regression",
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

  loop_file = base / "loop.yaml"
  if not loop_file.exists():
    loop_file.write_text(
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


def _has_exact_markdown_value(text: str, expected: str) -> bool:
  for raw_line in text.splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#"):
      continue
    if line == expected:
      return True
  return False


def _yaml_section_list(loop_text: str, section: str) -> list[str]:
  values: list[str] = []
  in_section = False
  for raw in loop_text.splitlines():
    if raw == f"{section}:":
      in_section = True
      continue
    if in_section and raw and not raw.startswith(" ") and not raw.startswith("-"):
      break
    if in_section:
      stripped = raw.strip()
      if stripped.startswith("- "):
        values.append(stripped[2:].strip().strip('"'))
  return values


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
  alert_on = policy["alert_on"]
  return GovernanceSummary(
    automation_type=str(policy["automation_type"]),
    schedule=str(policy["schedule"]),
    owner=str(policy["owner"]),
    first_runs_require_human_review=int(policy["first_runs_require_human_review"]),
    reviewed_runs=int(policy["reviewed_runs"]),
    auto_fix=bool(policy["auto_fix"]),
    auto_merge=bool(policy["auto_merge"]),
    report_only_on_no_findings=bool(policy["report_only_on_no_findings"]),
    alert_on=list(alert_on) if isinstance(alert_on, list) else [],
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
    stop_conditions=_yaml_section_list(loop_text, "stop_conditions"),
    handoff_conditions=_yaml_section_list(loop_text, "handoff_conditions"),
    protected_scope=_yaml_section_list(loop_text, "protected_scope"),
  )


def render_audit(base: Path, topic: str) -> str:
  loop_text = _read(base / "loop.yaml")
  summary = _summary_from_loop(loop_text, topic)
  governance = _governance_summary(base, loop_text)
  evidence_files = _evidence_files(base)
  has_result = _has_exact_markdown_value(_read(base / "7_result.md"), "Done")
  has_check = _has_exact_markdown_value(_read(base / "5_check.md"), "PASS")
  verdict = "Done" if has_result and has_check and evidence_files else "Not done"
  verifier_result = "Verifier result: Done" if verdict == "Done" else "No verifier result recorded."
  stop_conditions = ", ".join(summary.stop_conditions) if summary.stop_conditions else "None recorded."
  handoff_conditions = ", ".join(summary.handoff_conditions) if summary.handoff_conditions else "None recorded."
  protected_scope = ", ".join(summary.protected_scope) if summary.protected_scope else "None recorded."
  evidence_html = "\n".join(f"<li>{html.escape(path)}</li>" for path in evidence_files) or "<li>No evidence files.</li>"
  review_required = (
    len(governance.automated_attempts) < governance.first_runs_require_human_review
    or any(item.get("review_required") is True and item.get("reviewed") is not True for item in governance.automated_attempts)
  )
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
    "    <section>",
    "      <h2>Verifier Result</h2>",
    f"      <p>{html.escape(verifier_result)}</p>",
    "    </section>",
    "    <section>",
    "      <h2>Budget and Stop/Handoff State</h2>",
    f"      <p><strong>Budget:</strong> {html.escape(summary.max_iterations)} iteration(s)</p>",
    f"      <p><strong>Stop conditions:</strong> {html.escape(stop_conditions)}</p>",
    f"      <p><strong>Handoff conditions:</strong> {html.escape(handoff_conditions)}</p>",
    "    </section>",
    "    <section>",
    "      <h2>Governance</h2>",
    f"      <p><strong>Automation type:</strong> {html.escape(governance.automation_type or 'manual')}</p>",
    f"      <p><strong>Schedule:</strong> {html.escape(governance.schedule or 'none')}</p>",
    f"      <p><strong>Owner:</strong> {html.escape(governance.owner or 'none')}</p>",
    f"      <p><strong>Review:</strong> {html.escape(review_text)}</p>",
    f"      <p>auto_fix: {str(governance.auto_fix).lower()}</p>",
    f"      <p>auto_merge: {str(governance.auto_merge).lower()}</p>",
    f"      <p>report_only_on_no_findings: {str(governance.report_only_on_no_findings).lower()}</p>",
    f"      <ul>{alert_html}</ul>",
    "    </section>",
    "    <section>",
    "      <h2>Automated Attempts</h2>",
    f"      <ul>{attempt_html}</ul>",
    "    </section>",
    "    <section>",
    "      <h2>Protected Scope Findings</h2>",
    "      <p>No protected-scope findings recorded.</p>",
    f"      <p><strong>Protected scope:</strong> {html.escape(protected_scope)}</p>",
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


def upsert_todo_row(todo_path: Path, topic: str, opened: str | None = None) -> None:
  topic_name = validate_topic_slug(topic)
  opened_date = opened or date.today().isoformat()
  header = "| Topic | Status | Intent | Spec | Plan | Result | Opened | Closed | Notes |\n"
  separator = "|-------|--------|--------|------|------|--------|--------|--------|-------|\n"
  row = f"| {topic_name} | in-progress | n/a | n/a | n/a | - | {opened_date} |  | LoEn loop |\n"
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
          cells[6] = opened_date
        lines[index] = "| " + " | ".join(cells) + " |\n"
      else:
        lines[index] = row
      break
  else:
    lines.append(row)
  todo_path.write_text("".join(lines), encoding="utf-8")

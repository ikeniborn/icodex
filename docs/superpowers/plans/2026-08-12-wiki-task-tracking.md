---
chain:
  intent: docs/superpowers/intents/2026-08-12-wiki-task-tracking-intent.md
  spec: docs/superpowers/specs/2026-08-12-wiki-task-tracking-design.md
review:
  plan_hash: cf41163d63573da3
  last_run: 2026-08-12
  phases:
    structure: { status: passed }
    coverage: { status: passed }
    dependencies: { status: passed }
    verifiability: { status: passed }
    consistency: { status: passed }
  findings: []
result_check:
  verdict: OK
  source: plan
  plan_hash: cf41163d63573da3
  last_run: 2026-08-13
  reviewed: true
  docs_checked: true
---

# Wiki Task Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace repository task rows with one authoritative iwiki page per direct, chain, or LoEn topic, including parent-owned subagent history, offline delivery, and a verified legacy archive.

**Architecture:** Add a local `task-ledger` skill as the shared agent contract and a dependency-free Python helper that owns only redacted offline spool state. Parent agents perform all MCP reads and writes; subagents and LoEn hooks return evidence without writing wiki state. Existing `docs/TODO.md` is archived once in iwiki, verified by exact topic set, then removed.

**Tech Stack:** Markdown Codex skills and policy, Python 3 standard library, Bash fixture tests, existing iwiki MCP tools, existing LoEn Python hooks.

---

## Requirement Coverage

| Requirement | Plan tasks |
|---|---|
| R1 canonical topic | 1, 2 |
| R2 task page | 1, 2, 5 |
| R3 lifecycle/changelog | 1, 3, 4 |
| R4 parent/subagent ownership | 1, 2, 3 |
| R5 offline spool | 1, 2 |
| R6 direct/chain/LoEn integration | 2, 3, 4 |
| R7 status reporting | 2, 6 |
| R8 legacy archive | 5 |
| R9 secret-safe evidence | 1, 7 |
| R10 shared devops standard | 6 |

## File Map

- Create `.codex-isolated/skills/task-ledger/SKILL.md`: mandatory per-task MCP workflow, page template, lifecycle, parent/subagent ownership, replay, completion gate.
- Create `.codex-isolated/skills/task-ledger/scripts/task_spool.py`: validate, atomically queue, list, and acknowledge redacted delivery events; never call MCP.
- Create `tests/test_task_ledger.sh`: executable spool and skill contract tests.
- Modify `.codex-isolated/AGENTS.md`: replace `docs/TODO.md`, direct exemption, LoEn row, topic, and status-report rules.
- Modify `.codex-isolated/skills/context-awareness/SKILL.md`: resolve exact task page and pending spool state during Phase 0.
- Modify `tests/test_workflow_boundaries.sh`: enforce mandatory direct/chain/LoEn pages and wiki-only status.
- Modify `.codex-isolated/skills/check-chain/SKILL.md`: replace task-row/cell writes with parent-owned task-page events.
- Modify `.codex-isolated/agents/chain-auditor.toml`: review task-page readiness, never write it.
- Modify `.codex-isolated/skills/html-report/references/chain-report.md`: use task-page state in result reports.
- Modify `tests/test_idd_skills.sh`, `tests/test_skill_routing.sh`, `tests/test_chain_result_report_contract.sh`, and `tests/test_chain_report_quality.sh`: update chain task-ledger assertions.
- Modify `plugins/loen/hooks/audit-writer.py` and `plugins/loen/hooks/loen_artifacts.py`: remove repository TODO writes while preserving audit generation.
- Modify `plugins/loen/skills/loop-start/SKILL.md`, `plugins/loen/README.md`, `plugins/loen/README.ru.md`, and `plugins/loen/docs/architecture.md`: define parent-owned wiki mirroring at LoEn boundaries.
- Modify `tests/test_loen_runtime_artifacts.sh`, `tests/test_loen_enforcement_hooks.sh`, and `tests/test_loen_overview_docs.sh`: prove LoEn no longer creates task rows.
- Delete `docs/TODO.md` only after verified MCP archive migration.
- Modify `README.md` and `docs/README.ru.md`: document mandatory wiki task pages and outage semantics.
- Update via MCP `icodex:reference/tasks/wiki-task-tracking`, `icodex:testing-and-project-state`, and `devops:concept/wiki-task-ledger`.

### Task 1: Add the Task Ledger Skill and Offline Spool

**Closes:** R1, R2, R3, R4, R5, R9.

**Files:**
- Create: `.codex-isolated/skills/task-ledger/SKILL.md`
- Create: `.codex-isolated/skills/task-ledger/scripts/task_spool.py`
- Create: `tests/test_task_ledger.sh`

**Required implementation skills:** Use `skill-creator` to preserve Codex skill
structure and `superpowers:writing-skills` to test the new skill contract before
deployment. These skills do not broaden the accepted task-ledger scope.

- [ ] **Step 1: Write failing spool schema and skill contract tests**

Create `tests/test_task_ledger.sh` with focused assertions equivalent to:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

skill="$ROOT/.codex-isolated/skills/task-ledger/SKILL.md"
helper="$ROOT/.codex-isolated/skills/task-ledger/scripts/task_spool.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

assert_exit "task-ledger skill exists" 0 test -f "$skill"
assert_exit "task spool helper exists" 0 test -f "$helper"
body="$(cat "$skill" 2>/dev/null || true)"
assert_contains "all tasks tracked" "$body" "direct, chain, and LoEn"
assert_contains "read-only tasks tracked" "$body" "read-only"
assert_contains "parent sole writer" "$body" "parent agent is the sole writer"
assert_contains "canonical slug" "$body" 'reference/tasks/<topic>'
assert_contains "completion waits" "$body" 'completion-pending'
assert_contains "server stays external" "$body" "never modify iwiki-mcp"

event='{"kind":"verification","occurred_at":"2026-08-12T12:00:00Z","actor":"root","summary":"focused suite passed","evidence":{"paths":["tests/test_task_ledger.sh"],"checks":[{"name":"task-ledger","status":"passed","exit_code":0}],"hashes":{"fixture":"0123456789abcdef"}}}'
assert_exit "enqueue valid event" 0 bash -c 'printf "%s" "$1" | python3 "$2" enqueue --codex-home "$3" --project icodex --topic wiki-task-tracking' _ "$event" "$helper" "$tmp/home"
assert_eq "spool mode is private" "600" "$(stat -c '%a' "$tmp/home/state/iwiki-task-spool/icodex/wiki-task-tracking.json")"
first="$(python3 "$helper" list --codex-home "$tmp/home" --project icodex --topic wiki-task-tracking)"
assert_contains "queued event has id" "$first" '"event_id"'
assert_exit "duplicate enqueue is idempotent" 0 bash -c 'printf "%s" "$1" | python3 "$2" enqueue --codex-home "$3" --project icodex --topic wiki-task-tracking' _ "$event" "$helper" "$tmp/home"
after_retry="$(python3 "$helper" list --codex-home "$tmp/home" --project icodex --topic wiki-task-tracking)"
assert_eq "one event after retry" "1" "$(python3 -c 'import json,sys; print(len(json.load(sys.stdin)["events"]))' <<<"$after_retry")"

same_evidence='{"kind":"verification","occurred_at":"2026-08-12T12:01:00Z","actor":"root","summary":"same evidence retried later","evidence":{"paths":["tests/test_task_ledger.sh"],"checks":[{"name":"task-ledger","status":"passed","exit_code":0}],"hashes":{"fixture":"0123456789abcdef"}}}'
assert_exit "timestamp and summary do not change idempotency" 0 bash -c 'printf "%s" "$1" | python3 "$2" enqueue --codex-home "$3" --project icodex --topic wiki-task-tracking' _ "$same_evidence" "$helper" "$tmp/home"
after_semantic_retry="$(python3 "$helper" list --codex-home "$tmp/home" --project icodex --topic wiki-task-tracking)"
assert_eq "semantic retry remains one event" "1" "$(python3 -c 'import json,sys; print(len(json.load(sys.stdin)["events"]))' <<<"$after_semantic_retry")"

second='{"kind":"close","occurred_at":"2026-08-12T12:02:00Z","actor":"root","summary":"task verified","evidence":{"paths":["docs/superpowers/plans/2026-08-12-wiki-task-tracking.md"],"checks":[{"name":"result","status":"passed","exit_code":0}],"hashes":{"fixture":"fedcba9876543210"}}}'
assert_exit "enqueue second ordered event" 0 bash -c 'printf "%s" "$1" | python3 "$2" enqueue --codex-home "$3" --project icodex --topic wiki-task-tracking' _ "$second" "$helper" "$tmp/home"
ordered="$(python3 "$helper" list --codex-home "$tmp/home" --project icodex --topic wiki-task-tracking)"
assert_eq "events preserve enqueue order" "verification,close" "$(python3 -c 'import json,sys; print(",".join(e["kind"] for e in json.load(sys.stdin)["events"]))' <<<"$ordered")"
first_id="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["events"][0]["event_id"])' <<<"$ordered")"
assert_exit "acknowledge confirmed event" 0 python3 "$helper" ack --codex-home "$tmp/home" --project icodex --topic wiki-task-tracking --event-id "$first_id"
after_ack="$(python3 "$helper" list --codex-home "$tmp/home" --project icodex --topic wiki-task-tracking)"
assert_eq "ack removes exactly one event" "close" "$(python3 -c 'import json,sys; print(",".join(e["kind"] for e in json.load(sys.stdin)["events"]))' <<<"$after_ack")"

secret='{"kind":"verification","occurred_at":"2026-08-12T12:00:00Z","actor":"root","summary":"token=abc123","evidence":{"paths":[],"checks":[],"hashes":{}}}'
assert_exit "secret payload rejected" 2 bash -c 'printf "%s" "$1" | python3 "$2" enqueue --codex-home "$3" --project icodex --topic wiki-task-tracking' _ "$secret" "$helper" "$tmp/home"
for leaked in 'password=hunter2' 'secret: value' 'api_key=abc' 'authorization: Basic abc' 'Bearer abc.def'; do
  payload="$(printf '%s' "$event" | sed "s/focused suite passed/$leaked/")"
  assert_exit "sensitive summary rejected: $leaked" 2 bash -c 'printf "%s" "$1" | python3 "$2" enqueue --codex-home "$3" --project icodex --topic wiki-task-tracking' _ "$payload" "$helper" "$tmp/home"
done
finish
```

The `fixture` hash values above are schema-test constants, not spec/plan gate hashes.
Result reconciliation always reads canonical hashes from current artifact frontmatter.

Insert this inline Python test before the final `finish` call for interrupted-write
evidence:

```bash
assert_eq "replace failure preserves valid queue" "OK" "$(python3 - "$helper" "$tmp/home" <<'PY'
import importlib.util
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("task_spool", sys.argv[1])
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)
codex_home = Path(sys.argv[2])
queue = codex_home / "state/iwiki-task-spool/icodex/wiki-task-tracking.json"
before = queue.read_bytes()
event = {
    "kind": "blocker",
    "occurred_at": "2026-08-12T12:03:00Z",
    "actor": "root",
    "summary": "simulated delivery failure",
    "evidence": {"paths": [], "checks": [], "hashes": {}},
}
original_replace = module.os.replace
def fail_replace(source, target):
    raise OSError("simulated replace failure")
module.os.replace = fail_replace
try:
    try:
        module.enqueue(codex_home, "icodex", "wiki-task-tracking", event)
    except OSError:
        pass
    else:
        raise SystemExit("enqueue unexpectedly succeeded")
finally:
    module.os.replace = original_replace
print("OK" if queue.read_bytes() == before else "CHANGED")
PY
)"
```

Then, still before `finish`, acknowledge the remaining event and prove empty queues are
removed:

```bash
remaining_id="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["events"][0]["event_id"])' <<<"$after_ack")"
assert_exit "acknowledge final event" 0 python3 "$helper" ack --codex-home "$tmp/home" --project icodex --topic wiki-task-tracking --event-id "$remaining_id"
assert_exit "empty queue file removed" 1 test -e "$tmp/home/state/iwiki-task-spool/icodex/wiki-task-tracking.json"
```

- [ ] **Step 2: Run the new test and confirm the expected failure**

```bash
bash tests/test_task_ledger.sh
```

Expected: failures name missing task-ledger skill/helper.

- [ ] **Step 3: Implement the minimal dependency-free spool helper**

Implement `task_spool.py` with this public contract:

```python
VALID_KINDS = {
    "open", "route", "dispatch", "return", "decision",
    "blocker", "verification", "close",
}

def validate_event(value: object, topic: str) -> dict[str, object]:
    """Require exact event/evidence keys, RFC3339-Z time, safe summaries,
    repository-relative paths, passed|failed checks, integer exit codes,
    and 16-64 character lowercase hexadecimal hashes."""

def event_id(topic: str, event: dict[str, object]) -> str:
    """Hash canonical redacted evidence, then return SHA-256(topic, kind,
    evidence_hash)[:16]; exclude timestamp, actor, and summary."""

def enqueue(codex_home: Path, project: str, topic: str,
            event: dict[str, object]) -> str:
    """Append once and replace the 0600 queue file atomically with os.replace."""

def list_events(codex_home: Path, project: str, topic: str) -> dict[str, object]:
    """Return schema_version/project/topic/events without changing state."""

def acknowledge(codex_home: Path, project: str, topic: str,
                acknowledged_id: str) -> None:
    """Remove exactly one confirmed event; unlink an empty queue file."""
```

CLI commands MUST be `enqueue`, `list`, and `ack`. `enqueue` reads one JSON event from
stdin. Reject summaries matching assignment forms for `token`, `password`, `secret`,
`api_key`, `authorization`, or a Bearer value. Reject unknown keys instead of preserving
raw data. Use `tempfile.mkstemp`, `os.fchmod(fd, 0o600)`, `flush`, `os.fsync`, and
`os.replace` in the target directory.

- [ ] **Step 4: Write the task-ledger skill contract**

The skill MUST include this ordered flow:

```text
1. wiki_status; bind the project domain for read/write when present.
2. Resolve one canonical lowercase-kebab-case topic.
3. Read or create reference/tasks/<topic> with type reference, status stable, tag task.
4. Load durable event keys, then replay and acknowledge pending events in order.
5. Require Current State, TODO, Subtasks, Evidence, Changelog; each starts with a <=250-character lead paragraph and uses no heading deeper than ##.
6. Parent records material events; subagents never write wiki.
7. On MCP failure enqueue redacted events and use completion-pending.
8. Allow done only after final evidence, empty spool, successful wiki write, and wiki_lint without a new task-page finding.
```

Include the exact lifecycle values and event kinds from the spec, the redacted evidence
schema, idempotency rule, status-report procedure, and prohibition on modifying
`iwiki-mcp` or calling `wiki_sync`.

- [ ] **Step 5: Run focused tests**

```bash
bash tests/test_task_ledger.sh
python3 -m py_compile .codex-isolated/skills/task-ledger/scripts/task_spool.py
```

Expected: `PASS` summary with `FAIL=0`; Python compile exits 0.

- [ ] **Step 6: Commit Task 1**

```bash
git add .codex-isolated/skills/task-ledger tests/test_task_ledger.sh
git commit -m "feat(iwiki): add task ledger lifecycle"
```

### Task 2: Make Task Pages Mandatory in Global and Direct Workflows

**Closes:** R1, R2, R4, R5, R6 direct, R7.

**Files:**
- Modify: `.codex-isolated/AGENTS.md`
- Modify: `.codex-isolated/skills/context-awareness/SKILL.md`
- Modify: `tests/test_workflow_boundaries.sh`
- Modify: `tests/test_task_ledger.sh`

- [ ] **Step 1: Add failing global-policy assertions**

Extend `tests/test_workflow_boundaries.sh` and `tests/test_task_ledger.sh` to require:

```bash
assert_contains "task page precedes every task" "$agents_body" "Every direct, chain, and LoEn task"
assert_contains "read-only work tracked" "$agents_body" "including read-only analysis"
assert_contains "wiki is sole durable status" "$agents_body" "sole durable task index"
assert_contains "outage is fail-open execution" "$agents_body" "execution may continue"
assert_contains "outage is fail-closed completion" "$agents_body" "must not report `done`"
assert_not_contains "no live repository task log" "$agents_body" "Task Log (docs/TODO.md)"
assert_contains "context includes task page" "$context_body" 'task_page_slug'
assert_contains "context includes pending delivery" "$context_body" 'task_delivery_pending'
```

Replace the old direct assertion about “no chain TODO artifacts” with an assertion that
direct work creates no chain artifact but always resolves a wiki task page.

- [ ] **Step 2: Run the policy tests and confirm they fail on old rules**

```bash
bash tests/test_workflow_boundaries.sh
bash tests/test_task_ledger.sh
```

Expected: failures cite old `docs/TODO.md` and direct exemptions.

- [ ] **Step 3: Replace task-log, topic, direct, LoEn, and status-report policy**

In `.codex-isolated/AGENTS.md`:

- Replace `Task Log (docs/TODO.md)` with `Wiki Task Ledger` matching the task-ledger skill.
- Permit only bounded discovery needed to derive domain/topic/route, then require page
  creation before durable implementation or task-specific read-only analysis.
- Keep workflow route selection independent from ledger creation.
- Replace chain and LoEn row/cell language with page `TODO` and `Changelog` updates.
- Make thread title best-effort while topic/page slug remains mandatory.
- Make project status read task-tagged pages only, report `completion-pending`, and list
  `in-progress` tasks older than 14 days.
- When MCP is unavailable, label durable status unavailable; local spool evidence is
  non-authoritative.
- Define subagent dispatch/return evidence and parent-only serialization.

Do not add a direct hook that writes wiki: MCP operations remain interactive parent
actions. Keep `@topic` only as optional profile bootstrap.

- [ ] **Step 4: Extend context-awareness output**

Add these fields to its output template and examples:

```json
{
  "task_topic": "<topic>",
  "task_page_slug": "reference/tasks/<topic>",
  "task_page_found": true,
  "task_lifecycle": "in-progress|blocked|completion-pending|done|null",
  "task_delivery_pending": false
}
```

Phase 0 MUST read exact task-page context after domain binding and surface spool
presence without treating the spool as durable status.

- [ ] **Step 5: Run focused tests**

```bash
bash tests/test_workflow_boundaries.sh
bash tests/test_task_ledger.sh
bash tests/test_idd_skills.sh
```

Expected: all exit 0 with `FAIL=0`.

- [ ] **Step 6: Commit Task 2**

```bash
git add .codex-isolated/AGENTS.md .codex-isolated/skills/context-awareness tests/test_workflow_boundaries.sh tests/test_task_ledger.sh
git commit -m "docs(policy): require wiki task pages"
```

### Task 3: Integrate check-chain and Review Reporting

**Closes:** R3, R4, R6 chain.

**Files:**
- Modify: `.codex-isolated/skills/check-chain/SKILL.md`
- Modify: `.codex-isolated/agents/chain-auditor.toml`
- Modify: `.codex-isolated/skills/html-report/references/chain-report.md`
- Modify: `tests/test_idd_skills.sh`
- Modify: `tests/test_skill_routing.sh`
- Modify: `tests/test_chain_result_report_contract.sh`
- Modify: `tests/test_chain_report_quality.sh`

- [ ] **Step 1: Replace expected task-row strings with failing task-page assertions**

Tests MUST require these exact contract statements:

```text
Main context keeps task-page and changelog writes.
Cached intent/spec/plan checks do not append a duplicate gate event.
execute records Spec and Plan as n/a in the task page.
result writes final evidence before the close event.
completion-pending is used while spool events remain.
```

Tests MUST reject active `docs/TODO.md`, “TODO row”, and “TODO cell” ownership text in
`check-chain`, chain auditor, and chain report instructions.

- [ ] **Step 2: Run chain-focused tests and confirm they fail**

```bash
bash tests/test_idd_skills.sh
bash tests/test_skill_routing.sh
bash tests/test_chain_result_report_contract.sh
bash tests/test_chain_report_quality.sh
```

Expected: failures identify old row/cell state.

- [ ] **Step 3: Replace check-chain Step 6 with task-page persistence**

Define stage events as:

```text
intent: gate / intent / OK|needs_work / <body-hash>
spec: gate / spec / OK|needs_work / <body-hash>
plan: gate / plan / OK|needs_work / <body-hash>
result: verification then close only when result_check is OK
```

The parent MUST update `TODO` and append the idempotent gate event after frontmatter is
persisted. Cached hash matches MUST verify page state but append nothing. For `execute`,
record spec/plan `n/a`; for `full`, preserve all stages. If MCP fails, enqueue the event
and keep result `completion-pending` even when code verification passed.

Update result report inputs from “TODO row state” to task-page lifecycle, evidence,
subtasks, and changelog. Keep all validation hashes and report behavior unchanged.

- [ ] **Step 4: Update chain-auditor ownership**

The read-only agent checks page readiness, event/hash agreement, pending delivery, and
result close eligibility. Its result format remains `decision/evidence/risks/next_action`.
The main agent keeps every MCP write and spool acknowledgment.

- [ ] **Step 5: Run chain-focused tests**

```bash
bash tests/test_idd_skills.sh
bash tests/test_skill_routing.sh
bash tests/test_chain_result_report_contract.sh
bash tests/test_chain_report_quality.sh
bash tests/test_task_ledger.sh
```

Expected: all exit 0 with no old live task-row contract.

- [ ] **Step 6: Commit Task 3**

```bash
git add .codex-isolated/skills/check-chain .codex-isolated/skills/html-report/references/chain-report.md .codex-isolated/agents/chain-auditor.toml tests/test_idd_skills.sh tests/test_skill_routing.sh tests/test_chain_result_report_contract.sh tests/test_chain_report_quality.sh
git commit -m "feat(chain): persist task state in iwiki"
```

### Task 4: Remove LoEn Repository TODO Coupling

**Closes:** R3, R4, R6 LoEn.

**Files:**
- Modify: `plugins/loen/hooks/audit-writer.py`
- Modify: `plugins/loen/hooks/loen_artifacts.py`
- Modify: `plugins/loen/skills/loop-start/SKILL.md`
- Modify: `plugins/loen/README.md`
- Modify: `plugins/loen/README.ru.md`
- Modify: `plugins/loen/docs/architecture.md`
- Modify: `tests/test_loen_runtime_artifacts.sh`
- Modify: `tests/test_loen_enforcement_hooks.sh`
- Modify: `tests/test_loen_overview_docs.sh`

- [ ] **Step 1: Change LoEn tests to require no repository task write**

Replace TODO-row assertions with:

```bash
assert_exit "audit writer regenerates audit" 0 env LOEN_MODE=advisory LOEN_TOPIC="$topic" LOEN_ARTIFACT_ROOT="$artifact_root" python3 "$audit_writer"
assert_eq "audit writer does not create repository TODO" "" "$(find "$workdir" -path '*/docs/TODO.md' -print -quit)"
assert_not_contains "artifact module has no TODO writer" "$(cat "$artifact_module")" "upsert_todo_row"
assert_not_contains "audit writer has no TODO env" "$(cat "$audit_writer")" "LOEN_TODO_PATH"
```

Require LoEn docs to say loop artifacts stay authoritative for loop execution while the
parent mirrors material lifecycle evidence to the shared task page.

- [ ] **Step 2: Run LoEn tests and confirm old behavior fails**

```bash
bash tests/test_loen_runtime_artifacts.sh
bash tests/test_loen_enforcement_hooks.sh
bash tests/test_loen_overview_docs.sh
```

Expected: failures show `upsert_todo_row` and `LOEN_TODO_PATH` still present.

- [ ] **Step 3: Remove only the TODO writer path**

In `audit-writer.py`, keep topic validation, directory creation, and `audit.html`
regeneration. Remove `os`, `Path`, `upsert_todo_row`, and the `LOEN_TODO_PATH` call when
they become unused. Delete `upsert_todo_row` from `loen_artifacts.py`; do not alter loop
state parsing, attempt history, evidence, or final verdict rendering.

- [ ] **Step 4: Update LoEn skills and architecture**

`loop-start` MUST require the parent to resolve/create the shared task page before the
loop starts. Each loop stage records material status via the parent. Hooks remain MCP-
free and `docs/loen/<topic>/` remains authoritative for loop execution. Remove diagrams
and prose that name `docs/TODO.md` as a global index.

- [ ] **Step 5: Run LoEn focused tests**

```bash
bash tests/test_loen_runtime_artifacts.sh
bash tests/test_loen_enforcement_hooks.sh
bash tests/test_loen_overview_docs.sh
bash tests/test_loen_plugin_core.sh
```

Expected: all exit 0 with `FAIL=0`; audit HTML behavior remains covered.

- [ ] **Step 6: Commit Task 4**

```bash
git add plugins/loen tests/test_loen_runtime_artifacts.sh tests/test_loen_enforcement_hooks.sh tests/test_loen_overview_docs.sh
git commit -m "refactor(loen): remove repository task index"
```

### Task 5: Migrate the Active Task and Legacy Archive

**Closes:** R2, R8.

**Files:**
- Delete after verification: `docs/TODO.md`
- Update via MCP: `icodex:reference/tasks/wiki-task-tracking`
- Update via MCP: `icodex:reference/tasks-legacy-archive`
- Update via MCP: `icodex:testing-and-project-state`
- Modify: `tests/test_task_ledger.sh`

- [ ] **Step 1: Add a failing repository migration assertion**

Add:

```bash
assert_exit "legacy repository TODO removed" 1 test -e "$ROOT/docs/TODO.md"
active_refs="$(rg -n 'docs/TODO\.md|LOEN_TODO_PATH|upsert_todo_row' "$ROOT/.codex-isolated" "$ROOT/plugins" "$ROOT/lib" "$ROOT/tests" "$ROOT/README.md" "$ROOT/docs/README.ru.md" 2>/dev/null || true)"
assert_eq "no active repository TODO dependency" "" "$active_refs"
```

The final assertion may exclude the legacy archive migration test description itself,
but MUST NOT exclude runtime, skill, hook, policy, or user documentation paths.

- [ ] **Step 2: Capture the exact legacy topic set before deletion**

```bash
migration_dir="$CODEX_HOME/state/iwiki-task-migration/wiki-task-tracking"
mkdir -p "$migration_dir"
awk -F'|' '/^\| [^ -]/ { topic=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", topic); if (topic != "Topic") print topic }' docs/TODO.md | sort > "$migration_dir/source-topics.txt"
wc -l "$migration_dir/source-topics.txt"
sha256sum docs/TODO.md
```

Expected: a non-zero count and one source SHA-256 recorded in task evidence.

For the checked-plan snapshot, expected evidence is 29 topics and source SHA-256
`44ebe8a8001d4197ad0092be416b6b55aebade03239dbec48dacb89fcfcdd718`. A mismatch before
migration means the source changed after review: stop, re-audit the new rows, and refresh
the archive input instead of silently using the old expectation.

- [ ] **Step 3: Write the immutable archive through MCP**

Call:

```text
wiki_write_page(
  domain="icodex",
  slug="reference/tasks-legacy-archive",
  type="reference",
  status="deprecated",
  tags=["task", "archive"],
  description="Immutable archive of the retired repository task table.",
  markdown=<H1 plus ## Migration lead and ## Archived Table containing the exact docs/TODO.md table>
)
```

Do not set `source`, because the repository file is intentionally removed. Link the
archive from `testing-and-project-state` so it is not orphaned.

- [ ] **Step 4: Create the canonical active task page**

Write `reference/tasks/wiki-task-tracking` with supported reference metadata and the
full current state/history copied from `reference/wiki-task-tracking`. Verify required
sections and event keys. Update `testing-and-project-state` to link the canonical page.

Run `wiki_lint(domain="icodex")` and verify neither new page is broken, orphaned, stale,
missing-source, tag-drifted, or structurally invalid.

- [ ] **Step 5: Verify archive equality**

Read `reference/tasks-legacy-archive` through MCP. Use `apply_patch` to write the exact
returned table topic column, one sorted topic per line, to the same task-specific
migration state directory as `archive-topics.txt`, then run:

```bash
migration_dir="$CODEX_HOME/state/iwiki-task-migration/wiki-task-tracking"
diff -u "$migration_dir/source-topics.txt" "$migration_dir/archive-topics.txt"
```

Expected: no output, exit 0; counts match exactly.

- [ ] **Step 6: HUMAN CHECKPOINT — retire the transitional task page**

Present evidence that `reference/tasks/wiki-task-tracking` contains the full state and
history and that backlinks point to it. Ask the user before calling
`wiki_delete_page(domain="icodex", slug="reference/wiki-task-tracking")`, because wiki
page deletion is proposal-first. After approval, delete it and rerun wiki lint.

- [ ] **Step 7: Remove the verified repository table and run migration tests**

Delete `docs/TODO.md` with `apply_patch`, then run:

```bash
bash tests/test_task_ledger.sh
git diff --check
```

Expected: migration assertions pass; no active repository dependency remains.

After evidence is recorded, remove only
`$CODEX_HOME/state/iwiki-task-migration/wiki-task-tracking/source-topics.txt` and
`archive-topics.txt` with `apply_patch`, then remove the now-empty task-specific
directory. Do not remove any broader state directory.

- [ ] **Step 8: Commit Task 5**

```bash
git add docs/TODO.md tests/test_task_ledger.sh
git commit -m "docs(tasks): archive repository task history"
```

### Task 6: Align User Documentation and Shared Standards

**Closes:** R7, R10.

**Files:**
- Modify: `README.md`
- Modify: `docs/README.ru.md`
- Modify: `tests/test_workflow_boundaries.sh`
- Update via MCP: `icodex:testing-and-project-state`
- Verify via MCP: `devops:concept/wiki-task-ledger`

- [ ] **Step 1: Add failing documentation assertions**

Require both READMEs to document per-topic task pages, direct/read-only coverage,
parent-only writes, offline `completion-pending`, and legacy archive. Reject text that
names `docs/TODO.md` as the current index.

- [ ] **Step 2: Run the documentation contract test**

```bash
bash tests/test_workflow_boundaries.sh
```

Expected: old README task-index wording fails.

- [ ] **Step 3: Update English and Russian user documentation**

Document:

```text
one canonical topic -> reference/tasks/<topic>
all direct, chain, and LoEn tasks -> mandatory page
parent -> sole writer; subagents -> structured evidence only
MCP outage -> local delivery spool + completion-pending
status -> task-tagged wiki pages only
legacy history -> reference/tasks-legacy-archive
```

Keep workflow routing, profile, and model-switch behavior unchanged.

- [ ] **Step 4: Reconcile icodex and devops wiki documentation**

Update `icodex:testing-and-project-state` from final source behavior and verify
`devops:concept/wiki-task-ledger` still matches R10 without claiming other repositories
are migrated. Run:

```text
wiki_lint(domain="icodex")
wiki_lint(domain="devops")
```

Expected: no new finding on changed pages. Record unrelated pre-existing domain
findings separately by page.

- [ ] **Step 5: Run focused documentation tests**

```bash
bash tests/test_workflow_boundaries.sh
bash tests/test_task_ledger.sh
bash tests/test_loen_overview_docs.sh
```

Expected: all exit 0 with `FAIL=0`.

- [ ] **Step 6: Commit Task 6**

```bash
git add README.md docs/README.ru.md tests/test_workflow_boundaries.sh
git commit -m "docs(iwiki): document wiki task ledger"
```

### Task 7: Verify the Complete Migration

**Closes:** all acceptance criteria and result evidence.

**Files:**
- Verify: every path above
- Update via MCP: `icodex:reference/tasks/wiki-task-tracking`
- Update through `$check-chain result`: plan frontmatter and canonical task page

- [ ] **Step 1: Run syntax and focused suites**

```bash
python3 -m py_compile .codex-isolated/skills/task-ledger/scripts/task_spool.py plugins/loen/hooks/audit-writer.py plugins/loen/hooks/loen_artifacts.py
bash tests/test_task_ledger.sh
bash tests/test_workflow_boundaries.sh
bash tests/test_idd_skills.sh
bash tests/test_skill_routing.sh
bash tests/test_chain_result_report_contract.sh
bash tests/test_chain_report_quality.sh
bash tests/test_loen_runtime_artifacts.sh
bash tests/test_loen_enforcement_hooks.sh
bash tests/test_loen_overview_docs.sh
bash tests/test_loen_plugin_core.sh
```

Expected: every command exits 0; Bash summaries report `FAIL=0`.

- [ ] **Step 2: Run the full Bash suite**

```bash
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Expected: exit 0 with no failed test file.

- [ ] **Step 3: Audit scope, secrets, and retired dependencies**

```bash
git diff --check
git status --short
rg -n 'docs/TODO\.md|LOEN_TODO_PATH|upsert_todo_row' .codex-isolated plugins lib README.md docs/README.ru.md tests || true
rg -n -i 'token[=:]|password[=:]|secret[=:]|api[_-]?key[=:]|authorization[=:]|bearer [a-z0-9._-]+' .codex-isolated/skills/task-ledger docs/superpowers README.md docs/README.ru.md || true
```

Expected: first search has only explicit historical migration-test prose; second has
only intentional rejection patterns in tests/helper, never a credential value.

- [ ] **Step 4: Verify durable task outcome**

Read `reference/tasks/wiki-task-tracking` and verify every Desired Outcome and Health
Metric from the intent. Confirm no pending spool file exists for this topic. Run
`wiki_lint` for `icodex` and `devops`; changed pages have no new findings.

- [ ] **Step 5: Run result reconciliation**

Run `$check-chain result docs/superpowers/plans/2026-08-12-wiki-task-tracking.md`.
Expected: `OK` only after plan coverage, focused review, tests, archive equality,
documentation, wiki state, and empty spool are evidenced. The updated check-chain MUST
close the canonical wiki task page and MUST NOT recreate `docs/TODO.md`.

- [ ] **Step 6: Commit final verification metadata if changed**

```bash
git add docs/superpowers/plans/2026-08-12-wiki-task-tracking.md
git commit -m "chore(tasks): verify wiki task migration"
```

Skip this commit when result reconciliation changes only external wiki state and leaves
the plan bytes unchanged.

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
assert_contains "canonical slug" "$body" "reference/tasks/<topic>"
assert_contains "completion waits" "$body" "completion-pending"
assert_contains "server stays external" "$body" "never modify iwiki-mcp"
assert_contains "page metadata type" "$body" "type: reference"
assert_contains "page metadata status" "$body" "status: stable"
assert_contains "page metadata tag" "$body" 'tag `task`'
for section in "Current State" "TODO" "Subtasks" "Evidence" "Changelog"; do
  assert_contains "required page section: $section" "$body" "## $section"
done
for field in topic route lifecycle opened closed parent pending-delivery; do
  assert_contains "current state field: $field" "$body" "$field"
done
assert_contains "TODO stays workflow-specific" "$body" "workflow-specific"
assert_contains "TODO does not impose chain stages" "$body" "direct or LoEn"
assert_contains "page read before replay" "$body" "Read or create"
assert_contains "helper never calls MCP" "$body" "never call MCP"
assert_contains "helper never syncs" "$body" "wiki_sync"
for lifecycle in in-progress blocked completion-pending done; do
  assert_contains "lifecycle: $lifecycle" "$body" "\`$lifecycle\`"
done
for kind in open route dispatch return decision blocker verification close; do
  assert_contains "event kind: $kind" "$body" "\`$kind\`"
done

event='{"kind":"verification","occurred_at":"2026-08-12T12:00:00Z","actor":"root","summary":"focused suite passed","evidence":{"paths":["tests/test_task_ledger.sh"],"checks":[{"name":"task-ledger","status":"passed","exit_code":0}],"hashes":{"fixture":"0123456789abcdef"}}}'
assert_exit "enqueue valid event" 0 bash -c 'printf "%s" "$1" | python3 "$2" enqueue --codex-home "$3" --project icodex --topic wiki-task-tracking' _ "$event" "$helper" "$tmp/home"
assert_eq "spool mode is private" "600" "$(stat -c '%a' "$tmp/home/state/iwiki-task-spool/icodex/wiki-task-tracking.json")"
first="$(python3 "$helper" list --codex-home "$tmp/home" --project icodex --topic wiki-task-tracking)"
assert_contains "queued event has id" "$first" '"event_id"'
assert_contains "queued event has evidence hash" "$first" '"evidence_hash"'
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

assert_eq "schema rejects malformed inputs" "OK" "$(python3 - "$helper" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("task_spool", sys.argv[1])
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)
base = {
    "kind": "verification",
    "occurred_at": "2026-08-12T12:00:00Z",
    "actor": "root",
    "summary": "safe summary",
    "evidence": {"paths": ["tests/test_task_ledger.sh"], "checks": [{"name": "suite", "status": "passed", "exit_code": 0}], "hashes": {"fixture": "0123456789abcdef"}},
}
cases = []
unknown = dict(base); unknown["raw_output"] = "no"; cases.append(unknown)
bad_time = dict(base); bad_time["occurred_at"] = "2026-08-12T12:00:00+00:00"; cases.append(bad_time)
unsafe = dict(base); unsafe["evidence"] = dict(base["evidence"], paths=["../secret"]); cases.append(unsafe)
bad_check = dict(base); bad_check["evidence"] = dict(base["evidence"], checks=[{"name": "suite", "status": "unknown", "exit_code": 0}]); cases.append(bad_check)
bad_hash = dict(base); bad_hash["evidence"] = dict(base["evidence"], hashes={"fixture": "UPPERCASE"}); cases.append(bad_hash)
for value in cases:
    try:
        module.validate_event(value, "wiki-task-tracking")
    except ValueError:
        continue
    raise SystemExit("invalid event accepted")
print("OK")
PY
)"

assert_eq "schema rejects controls and sensitive paths" "OK" "$(python3 - "$helper" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("task_spool", sys.argv[1])
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)
base = {
    "kind": "verification",
    "occurred_at": "2026-08-12T12:00:00Z",
    "actor": "root",
    "summary": "safe summary",
    "evidence": {"paths": ["tests/test_task_ledger.sh"], "checks": [{"name": "suite", "status": "passed", "exit_code": 0}], "hashes": {"fixture": "0123456789abcdef"}},
}
for field, value in (("actor", "root\r"), ("summary", "bad\u2028text")):
    candidate = dict(base); candidate[field] = value
    try: module.validate_event(candidate, "wiki-task-tracking")
    except ValueError: continue
    raise SystemExit("control character accepted")
for path in (".env", "config/.env.local", "auth/token.txt", "credentials/file", "private-key.pem", "a" * 1025):
    candidate = dict(base); candidate["evidence"] = dict(base["evidence"], paths=[path])
    try: module.validate_event(candidate, "wiki-task-tracking")
    except ValueError: continue
    raise SystemExit("unsafe path accepted")
for summary in ("SERVICE_API_KEY=abc", "CLIENT_TOKEN: abc", "access_key=abc", "private_key=abc", "x-api-key=abc", "api-key: abc", "access-token=abc", "client-secret: abc"):
    candidate = dict(base); candidate["summary"] = summary
    try: module.validate_event(candidate, "wiki-task-tracking")
    except ValueError: continue
    raise SystemExit("secret assignment accepted")
for path in ("src/auth.py", "lib/tokenizer.py", "docs/credential-format.md"):
    candidate = dict(base); candidate["evidence"] = dict(base["evidence"], paths=[path])
    module.validate_event(candidate, "wiki-task-tracking")
print("OK")
PY
)"

assert_eq "CLI invalid inputs are controlled" "OK" "$(python3 - "$helper" "$tmp/home" <<'PY'
import json
import subprocess
import sys

helper, home = sys.argv[1:]
base = {"kind": "verification", "occurred_at": "2026-08-12T12:00:00Z", "actor": "root", "summary": "safe", "evidence": {"paths": [], "checks": [], "hashes": {}}}
for value in ({**base, "kind": None}, {**base, "kind": ["verification"]}, ["not", "an", "event"]):
    result = subprocess.run([sys.executable, helper, "enqueue", "--codex-home", home, "--project", "icodex", "--topic", "wiki-task-tracking"], input=json.dumps(value), text=True, capture_output=True)
    if result.returncode != 2 or "task_spool:" not in result.stderr or "Traceback" in result.stderr:
        raise SystemExit("CLI validation leaked traceback")
print("OK")
PY
)"

assert_eq "queue boundary rejects symlinks and bad schema type" "OK" "$(python3 - "$helper" "$tmp/home" <<'PY'
import importlib.util
import json
import os
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("task_spool", sys.argv[1])
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)
home = Path(sys.argv[2])
queue = home / "state/iwiki-task-spool/icodex/boundary-test.json"
queue.parent.mkdir(parents=True, exist_ok=True)
queue.write_text(json.dumps({"schema_version": True, "project": "icodex", "topic": "boundary-test", "events": []}))
try: module.list_events(home, "icodex", "boundary-test")
except ValueError: pass
else: raise SystemExit("boolean schema version accepted")
queue.unlink()
target = home / "outside.json"; target.write_text("outside")
queue.symlink_to(target)
event = {"kind": "verification", "occurred_at": "2026-08-12T12:00:00Z", "actor": "root", "summary": "safe", "evidence": {"paths": [], "checks": [], "hashes": {}}}
try: module.enqueue(home, "icodex", "boundary-test", event)
except ValueError: pass
else: raise SystemExit("symlink queue accepted")
if target.read_text() != "outside": raise SystemExit("symlink target changed")
queue.unlink()
print("OK")
PY
)"

assert_eq "schema version CLI error is controlled" "OK" "$(python3 - "$helper" "$tmp/home" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

helper, home = sys.argv[1:]
queue = Path(home) / "state/iwiki-task-spool/icodex/schema-version-test.json"
queue.parent.mkdir(parents=True, exist_ok=True)
queue.write_text(json.dumps({"schema_version": True, "project": "icodex", "topic": "schema-version-test", "events": []}))
result = subprocess.run([sys.executable, helper, "list", "--codex-home", home, "--project", "icodex", "--topic", "schema-version-test"], text=True, capture_output=True)
if result.returncode != 2 or "schema_version" not in result.stderr or "Traceback" in result.stderr:
    raise SystemExit("schema version error was not controlled")
queue.unlink()
print("OK")
PY
)"

assert_eq "unsafe preexisting spool directory rejected" "OK" "$(python3 - "$helper" "$tmp" <<'PY'
import importlib.util
import os
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("task_spool", sys.argv[1])
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)
home = Path(sys.argv[2]) / "unsafe-home"
unsafe = home / "state" / "iwiki-task-spool"
unsafe.mkdir(parents=True)
unsafe.chmod(0o755)
event = {"kind": "verification", "occurred_at": "2026-08-12T12:00:00Z", "actor": "root", "summary": "safe", "evidence": {"paths": [], "checks": [], "hashes": {}}}
try: module.enqueue(home, "icodex", "unsafe-dir", event)
except ValueError: print("OK")
else: raise SystemExit("unsafe directory accepted")
PY
)"

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

remaining_id="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["events"][0]["event_id"])' <<<"$after_ack")"
assert_exit "acknowledge final event" 0 python3 "$helper" ack --codex-home "$tmp/home" --project icodex --topic wiki-task-tracking --event-id "$remaining_id"
assert_exit "empty queue file removed" 1 test -e "$tmp/home/state/iwiki-task-spool/icodex/wiki-task-tracking.json"

finish

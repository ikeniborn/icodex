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

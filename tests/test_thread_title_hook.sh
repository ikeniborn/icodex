#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

HOOK="$ROOT/.codex-isolated/hooks/thread-title.py"
assert_exit "lifecycle title hook exists" 0 test -f "$HOOK"
if [[ ! -f "$HOOK" ]]; then
  finish
  exit $?
fi

python3 - "$ROOT" <<'PY'
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("thread_title", root / ".codex-isolated/hooks/thread-title.py")
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)


class TitleHookTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name) / "project"
        self.project.mkdir()
        subprocess.run(["git", "init", "-q", str(self.project)], check=True)
        (self.project / ".iwiki.toml").write_text('read=["other", "test"]\nwrite=["test"]\nprimary="test"\n')
        self.home = Path(self.temp.name) / "home"
        self.home.mkdir()
        self.env = {"CODEX_HOME": str(self.home), "ICODEX_ROOT": str(root)}
        self.event = {
            "hook_event_name": "PostToolUse", "session_id": "session-1", "cwd": str(self.project),
            "tool_name": "mcp__iwiki_remote__wiki_update_page",
            "tool_input": {"domain": "test", "slug": "reference/tasks/fix-launch", "heading": "Current State",
                           "new_body": "Topic: fix-launch. Route: direct. Lifecycle: in-progress."},
            "tool_response": {"content": [{"type": "text", "text": json.dumps({
                "page": "test/reference/tasks/fix-launch.md", "heading": "Current State", "revision": 2})}]},
        }

    def titles(self, event=None):
        with patch.object(hook, "rename_thread") as rename:
            hook.handle(event if event is not None else self.event, self.env)
        return [call.args[-1] for call in rename.call_args_list]

    def test_active_completed_and_resumed_titles(self):
        self.assertEqual(self.titles(), ["fix-launch-inprogress"])
        self.event["tool_input"]["new_body"] = "- Lifecycle: done\n"
        self.assertEqual(self.titles(), ["fix-launch-done"])
        self.event["tool_input"]["new_body"] = "Lifecycle: in-progress"
        self.assertEqual(self.titles(), ["fix-launch-inprogress"])

    def test_new_task_page_uses_current_state_only(self):
        self.event["tool_name"] = "mcp__iwiki_remote__wiki_write_page"
        self.event["tool_input"] = {"domain": "test", "slug": "reference/tasks/fix-launch", "tags": ["task"],
            "markdown": "# Task\n\n## Current State\n\nLifecycle: in-progress\n\n## Evidence\n\nLifecycle: done\n"}
        self.event["tool_response"] = {"page": "test/reference/tasks/fix-launch.md", "indexed_chunks": 2}
        self.assertEqual(self.titles(), ["fix-launch-inprogress"])

    def test_unrelated_writes_and_nonterminal_states_do_not_rename(self):
        for field, value in [("domain", "other"), ("slug", "reference/task-history/fix-launch-001"),
                             ("heading", "Evidence"), ("new_body", "Lifecycle: blocked"),
                             ("new_body", "Lifecycle: completion-pending"),
                             ("new_body", "Lifecycle: done\nLifecycle: in-progress"),
                             ("new_body", "```\nLifecycle: done\n```"),
                             ("slug", "reference/tasks/../../escape")]:
            event = copy.deepcopy(self.event)
            event["tool_input"][field] = value
            with self.subTest(field=field, value=value):
                self.assertEqual(self.titles(event), [])

    def test_failed_or_mismatched_results_do_not_rename(self):
        for response in [{"isError": True}, {"error": "conflict"}, {},
                         {"page": "test/reference/tasks/someone-else.md"},
                         {"content": [{"type": "text", "text": '{"error":"conflict"}'}]},
                         {"content": [{"type": "text", "text": "not JSON"}]}]:
            event = copy.deepcopy(self.event)
            event["tool_response"] = response
            self.assertEqual(self.titles(event), [])

    def test_only_successful_iwiki_mutations_for_current_session(self):
        for field, value in [("tool_name", "mcp__unrelated__wiki_update_page"),
                             ("tool_name", "wiki_read_page"), ("session_id", "../session"),
                             ("hook_event_name", "PreToolUse")]:
            event = copy.deepcopy(self.event)
            event[field] = value
            self.assertEqual(self.titles(event), [])
        (self.project / ".iwiki.toml").unlink()
        self.assertEqual(self.titles(), [])

    def test_nested_cwd_and_local_transport_keep_project_scope(self):
        nested = self.project / "src"
        nested.mkdir()
        self.event["cwd"] = str(nested)
        self.event["tool_name"] = "mcp__iwiki_local__wiki_update_page"
        self.assertEqual(self.titles(), ["fix-launch-inprogress"])

    def test_rename_failure_is_visible_without_blocking(self):
        with patch.object(hook, "rename_thread", side_effect=RuntimeError("unavailable")):
            result = hook.handle(self.event, self.env)
        self.assertEqual(result["hookSpecificOutput"]["hookEventName"], "PostToolUse")
        self.assertIn("Thread title", result["hookSpecificOutput"]["additionalContext"])
        self.assertNotIn("decision", result)

    def test_launcher_installs_title_hook_once_and_preserves_other_entries(self):
        hooks_file = self.home / "hooks.json"
        existing = {"matcher": "unrelated", "hooks": [{"type": "command", "command": "true"}]}
        hooks_file.write_text(json.dumps({"hooks": {"PostToolUse": [existing]}}))
        command = ["bash", "-c", 'source "$1/lib/profile/wiring.sh"; ensure_profile_wiring', "_", str(root)]
        env = {**os.environ, "ICODEX_HOME_DIR": str(self.home)}
        subprocess.run(command, env=env, check=True)
        first = hooks_file.read_bytes()
        subprocess.run(command, env=env, check=True)
        self.assertEqual(hooks_file.read_bytes(), first)
        entries = json.loads(first)["hooks"]["PostToolUse"]
        self.assertEqual(entries[0], existing)
        title_entries = [entry for entry in entries if any("thread-title.py" in h["command"] for h in entry["hooks"])]
        self.assertEqual(len(title_entries), 1)
        self.assertRegex("mcp__iwiki_remote__wiki_write_page", title_entries[0]["matcher"])
        self.assertRegex("mcp__iwiki_remote__wiki_update_page", title_entries[0]["matcher"])
        self.assertNotRegex("mcp__iwiki_remote__wiki_read_page", title_entries[0]["matcher"])

    def test_protocol_updates_exact_session_without_starting_a_turn(self):
        binary = self.home / "codex-fixture"
        binary.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
home = Path(os.environ["CODEX_HOME"])
for line in sys.stdin:
    message = json.loads(line)
    with (home / "requests.jsonl").open("a") as out:
        out.write(json.dumps(message) + "\\n")
    if "id" not in message:
        continue
    if message["method"] == "thread/name/set":
        (home / "title.json").write_text(json.dumps(message["params"]))
    print(json.dumps({"id": message["id"], "result": {}}), flush=True)
''')
        binary.chmod(0o700)
        hook.rename_thread(binary, self.home, self.project, "session-1", "fix-launch-done")
        self.assertEqual(json.loads((self.home / "title.json").read_text()),
                         {"threadId": "session-1", "name": "fix-launch-done"})
        methods = [json.loads(line)["method"] for line in (self.home / "requests.jsonl").read_text().splitlines()]
        self.assertEqual(methods, ["initialize", "initialized", "thread/name/set"])

    def test_stalled_server_times_out_and_is_reaped(self):
        binary = self.home / "stalled-codex"
        binary.write_text('''#!/usr/bin/env python3
import os, time
from pathlib import Path
Path(os.environ["CODEX_HOME"], "server.pid").write_text(str(os.getpid()))
time.sleep(60)
''')
        binary.chmod(0o700)
        started = time.monotonic()
        with self.assertRaisesRegex(RuntimeError, "deadline exceeded"):
            hook.rename_thread(binary, self.home, self.project, "session-1", "fix-launch-done")
        self.assertLess(time.monotonic() - started, 13)
        with self.assertRaises(ProcessLookupError):
            os.kill(int((self.home / "server.pid").read_text()), 0)

    def test_successful_rename_reaps_a_server_that_delays_exit(self):
        binary = self.home / "slow-exit-codex"
        binary.write_text('''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
Path(os.environ["CODEX_HOME"], "server.pid").write_text(str(os.getpid()))
for line in sys.stdin:
    message = json.loads(line)
    if "id" in message:
        print(json.dumps({"id": message["id"], "result": {}}), flush=True)
    if message["method"] == "thread/name/set":
        time.sleep(3)
''')
        binary.chmod(0o700)
        alarm = hook.signal.alarm
        with patch.object(hook.signal, "alarm", side_effect=lambda seconds: alarm(1 if seconds == 8 else seconds)):
            hook.rename_thread(binary, self.home, self.project, "session-1", "fix-launch-done")
        with self.assertRaises(ProcessLookupError):
            os.kill(int((self.home / "server.pid").read_text()), 0)

    @unittest.skipUnless(os.environ.get("ICODEX_TITLE_INTEGRATION") == "1", "opt-in installed Codex integration")
    def test_installed_codex_reads_back_lifecycle_titles(self):
        binary = root / ".codex-isolated/bin/codex"
        env = {**os.environ, **self.env}
        with hook.AppServerClient([str(binary), "app-server"], self.project, env) as client:
            client.request("initialize", {"clientInfo": {"name": "icodex-title-test", "version": "1"}})
            client.notify("initialized", {})
            self.event["session_id"] = client.request("thread/start", {"cwd": str(self.project)})["thread"]["id"]
            # Persist the initial automatic title, as in a session that has started work.
            client.request("thread/name/set", {"threadId": self.event["session_id"], "name": "automatic-title"})
            for state, failed, expected in [
                ("in-progress", False, "fix-launch-inprogress"),
                ("done", True, "fix-launch-inprogress"),
                ("done", False, "fix-launch-done"),
                ("blocked", False, "fix-launch-done"),
                ("in-progress", False, "fix-launch-inprogress"),
            ]:
                self.event["tool_input"]["new_body"] = f"Lifecycle: {state}"
                event = copy.deepcopy(self.event)
                if failed:
                    event["tool_response"] = {"error": "conflict"}
                result = subprocess.run(
                    [sys.executable, str(root / ".codex-isolated/hooks/thread-title.py")],
                    input=json.dumps(event), text=True, capture_output=True, env=env, timeout=15, check=True,
                )
                self.assertEqual(result.stdout, "")
                thread = client.request("thread/read", {"threadId": self.event["session_id"]})["thread"]
                self.assertEqual(thread["name"], expected)
        client.stdout.close()
        client.process.stderr.close()


unittest.main(argv=["thread-title-tests"], verbosity=2)
PY
assert_eq "lifecycle title behavior checks" "0" "$?"
finish

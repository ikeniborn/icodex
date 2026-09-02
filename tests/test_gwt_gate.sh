#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

HOOK="$ROOT/.codex-isolated/hooks/gwt-gate.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home"

run_hook() { # <mode> <payload>
  local mode="$1" payload="$2"
  if [[ "$mode" == "post" ]]; then
    CODEX_HOME="$tmp/home" python3 "$HOOK" --post <<<"$payload"
  else
    CODEX_HOME="$tmp/home" python3 "$HOOK" <<<"$payload"
  fi
}

capture_code() { # <mode> <payload>
  local code=0
  run_hook "$1" "$2" >/dev/null 2>&1 || code=$?
  printf '%s' "$code"
}

concurrent_evidence_writers() { # <status|context>
  local evidence="$1"
  python3 - "$HOOK" "$tmp/concurrent-$evidence-home" "$evidence" <<'PY'
import fcntl
import json
import os
import subprocess
import sys
import time


hook, home, evidence = sys.argv[1:]
environment = os.environ.copy()
environment["CODEX_HOME"] = home


def status_payload(session_id, error=False):
    response = {
        "storage": "postgres",
        "transport": "streamable-http",
        "binding_source": "session",
        "specifications": {
            "domains": [{"domain": "demo", "mode": "optional", "source": "project"}]
        },
    }
    if error:
        response["error"] = {}
    return {
        "session_id": session_id,
        "hook_event_name": "PostToolUse",
        "tool_name": "wiki_status",
        "tool_response": response,
    }


def context_payload(session_id):
    return {
        "session_id": session_id,
        "hook_event_name": "PostToolUse",
        "tool_name": "wiki_spec_context",
        "tool_input": {"domain": "demo", "scenario_id": "checkout.submit"},
        "tool_response": {"isError": False},
    }


def mutation_payload(session_id, post=False):
    payload = {
        "session_id": session_id,
        "hook_event_name": "PostToolUse" if post else "PreToolUse",
        "tool_name": "wiki_update_page",
        "tool_input": {
            "domain": "demo",
            "new_body": '```iwiki-gwt\nid = "checkout.submit"\n```',
        },
    }
    if post:
        payload["tool_response"] = {"isError": False}
    return payload


def run(payload, post=False):
    command = [sys.executable, hook]
    if post:
        command.append("--post")
    return subprocess.run(
        command,
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        env=environment,
        check=False,
    )


def spawn(payload):
    process = subprocess.Popen(
        [sys.executable, hook, "--post"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=environment,
    )
    process.stdin.write(json.dumps(payload))
    process.stdin.close()
    process.stdin = None
    return process


def run_locked_writers(lock_path, payloads):
    processes = []
    with open(lock_path, "a+", encoding="utf-8") as lock_stream:
        fcntl.flock(lock_stream, fcntl.LOCK_EX)
        try:
            processes = [spawn(payload) for payload in payloads]
            deadline = time.monotonic() + 5
            while True:
                assert all(process.poll() is None for process in processes), (
                    "%s writer bypassed the transaction lock" % evidence
                )
                with open("/proc/locks", encoding="utf-8") as stream:
                    lock_rows = [line.split() for line in stream]
                waiting_pids = {
                    int(row[5]) for row in lock_rows
                    if len(row) > 5 and row[1:3] == ["->", "FLOCK"]
                }
                if all(process.pid in waiting_pids for process in processes):
                    break
                assert time.monotonic() < deadline, (
                    "%s writer did not wait on the transaction lock" % evidence
                )
                time.sleep(0.01)
        finally:
            fcntl.flock(lock_stream, fcntl.LOCK_UN)
    try:
        for process in processes:
            stdout, stderr = process.communicate(timeout=5)
            assert process.returncode == 0, stdout + stderr
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)


state_directory = os.path.join(home, "state")
os.makedirs(state_directory, exist_ok=True)
if evidence == "status":
    initial = run(status_payload("victim"), post=True)
    assert initial.returncode == 0, initial.stderr
    run_locked_writers(
        os.path.join(state_directory, "gwt-status.lock"),
        [status_payload("victim", error=True), status_payload("survivor")],
    )
    with open(os.path.join(state_directory, "gwt-status.json"), encoding="utf-8") as stream:
        state = json.load(stream)
    assert "victim" not in state, state
    assert state.get("survivor", {}).get("demo", {}).get("mode") == "optional", state
    assert run(mutation_payload("victim")).returncode == 2
    assert run(mutation_payload("survivor")).returncode == 0
elif evidence == "context":
    for session_id in ("victim", "survivor"):
        result = run(status_payload(session_id), post=True)
        assert result.returncode == 0, result.stderr
    initial = run(context_payload("victim"), post=True)
    assert initial.returncode == 0, initial.stderr
    run_locked_writers(
        os.path.join(state_directory, "gwt-contexts.lock"),
        [mutation_payload("victim", post=True), context_payload("survivor")],
    )
    with open(os.path.join(state_directory, "gwt-contexts.json"), encoding="utf-8") as stream:
        state = json.load(stream)
    key = "demo\0checkout.submit"
    assert key not in state.get("victim", {}), state
    assert key in state.get("survivor", {}), state
    victim = run(mutation_payload("victim"))
    assert victim.returncode == 0 and "wiki_spec_context" in victim.stdout, victim.stderr
    survivor = run(mutation_payload("survivor"))
    assert survivor.returncode == 0 and not survivor.stdout, survivor.stderr
else:
    raise AssertionError("unknown evidence kind: %s" % evidence)
PY
}

assert_exit "GWT gate exists" 0 test -f "$HOOK"

mutation='{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"mcp__iwiki__wiki_update_page","tool_input":{"domain":"demo","slug":"spec","heading":"Scenarios","new_body":"```iwiki-gwt\nid = \"checkout.submit\"\ngiven = \"cart\"\nwhen = \"submit\"\nthen = \"accepted\"\ncode = [{ role = \"implements\", selector = \"app.submit\" }, { role = \"verifies\", selector = \"tests.test_submit\" }]\n```"}}'
status_optional='{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"mcp__iwiki__wiki_status","tool_response":{"storage":"postgres","transport":"streamable-http","binding_source":"session","specifications":{"domains":[{"domain":"demo","mode":"optional","source":"project"}]}}}'
status_disabled='{"session_id":"disabled","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"storage":"postgres","transport":"stdio","specifications":{"domains":[{"domain":"demo","mode":"disabled","source":"project"}]}}}'
status_strict='{"session_id":"strict","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"storage":"postgres","transport":"streamable-http","binding_source":"session","specifications":{"domains":[{"domain":"demo","mode":"strict","source":"project"}]}}}'
status_default='{"session_id":"defaulted","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"storage":"postgres","transport":"streamable-http","binding_source":"token_default","specifications":{"domains":[{"domain":"demo","mode":"strict","source":"hosted_default"}]}}}'
status_substituted='{"session_id":"substituted","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"storage":"postgres","transport":"streamable-http","binding_source":"session","primary_substituted":true,"requested_primary":"demo","specifications":{"domains":[{"domain":"demo","mode":"strict","source":"project"}]}}}'
status_wrapped='{"session_id":"wrapped","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"content":[{"type":"text","text":"{\"storage\":\"postgres\",\"transport\":\"streamable-http\",\"binding_source\":\"session\",\"specifications\":{\"domains\":[{\"domain\":\"demo\",\"mode\":\"strict\",\"source\":\"project\"}]}}"}]}}'
status_malformed='{"session_id":"malformed-status","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"content":[{"type":"text","text":"not-json"}]}}'
status_malformed_then_valid='{"session_id":"malformed-then-valid","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"content":[{"type":"text","text":"not-json"},{"type":"text","text":"{\"storage\":\"postgres\",\"transport\":\"streamable-http\",\"binding_source\":\"session\",\"specifications\":{\"domains\":[{\"domain\":\"demo\",\"mode\":\"strict\",\"source\":\"project\"}]}}"}]}}'
status_direct_error='{"session_id":"direct-error","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"storage":"postgres","transport":"streamable-http","binding_source":"session","specifications":{"domains":[{"domain":"demo","mode":"strict","source":"project"}]},"error":{}}}'
status_wrapped_error_first='{"session_id":"wrapped-error-first","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"content":[{"type":"text","text":"{\"error\":{},\"storage\":\"postgres\",\"transport\":\"streamable-http\",\"binding_source\":\"session\",\"specifications\":{\"domains\":[{\"domain\":\"demo\",\"mode\":\"strict\",\"source\":\"project\"}]}}"},{"type":"text","text":"{\"storage\":\"postgres\",\"transport\":\"streamable-http\",\"binding_source\":\"session\",\"specifications\":{\"domains\":[{\"domain\":\"demo\",\"mode\":\"strict\",\"source\":\"project\"}]}}"}]}}'
status_wrapped_error_last='{"session_id":"wrapped-error-last","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"content":[{"type":"text","text":"{\"storage\":\"postgres\",\"transport\":\"streamable-http\",\"binding_source\":\"session\",\"specifications\":{\"domains\":[{\"domain\":\"demo\",\"mode\":\"strict\",\"source\":\"project\"}]}}"},{"type":"text","text":"{\"error\":{}}"}]}}'
status_wrapped_is_error_first='{"session_id":"wrapped-is-error-first","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"content":[{"type":"text","text":"{\"isError\":true}"},{"type":"text","text":"{\"storage\":\"postgres\",\"transport\":\"streamable-http\",\"binding_source\":\"session\",\"specifications\":{\"domains\":[{\"domain\":\"demo\",\"mode\":\"strict\",\"source\":\"project\"}]}}"}]}}'
status_wrapped_is_error_last='{"session_id":"wrapped-is-error-last","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"content":[{"type":"text","text":"{\"storage\":\"postgres\",\"transport\":\"streamable-http\",\"binding_source\":\"session\",\"specifications\":{\"domains\":[{\"domain\":\"demo\",\"mode\":\"strict\",\"source\":\"project\"}]}}"},{"type":"text","text":"{\"isError\":true}"}]}}'
status_missing_transport='{"session_id":"missing-transport","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"binding_source":"session","specifications":{"domains":[{"domain":"demo","mode":"strict","source":"project"}]}}}'
status_unknown_transport='{"session_id":"unknown-transport","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"transport":"unknown","binding_source":"session","specifications":{"domains":[{"domain":"demo","mode":"strict","source":"project"}]}}}'
status_other_domain='{"session_id":"other-domain","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"storage":"postgres","transport":"stdio","specifications":{"domains":[{"domain":"other","mode":"strict","source":"project"}]}}}'

assert_status_clears_trust() { # <label> <session> <rejected-status>
  local label="$1" session="$2" rejected_status="$3"
  local trusted_status target_mutation
  trusted_status="${status_optional/\"s1\"/\"$session\"}"
  target_mutation="${mutation/\"s1\"/\"$session\"}"
  assert_eq "$label baseline records trusted status" "0" "$(capture_code post "$trusted_status")"
  assert_eq "$label baseline authorizes GWT checks" "0" "$(capture_code pre "$target_mutation")"
  assert_eq "$label rejected status stays controlled" "0" "$(capture_code post "$rejected_status")"
  assert_eq "$label clears previous evidence" "2" "$(capture_code pre "$target_mutation")"
}

ordinary='{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"mcp__iwiki__wiki_update_page","tool_input":{"domain":"demo","slug":"notes","heading":"Text","new_body":"Ordinary Wiki text"}}'
assert_eq "ordinary Wiki mutation remains allowed" "0" "$(capture_code pre "$ordinary")"

assert_eq "GWT mutation without status fails closed" "2" "$(capture_code pre "${mutation//\"s1\"/\"missing\"}")"
assert_contains "missing status explains recovery" "$(run_hook pre "${mutation//\"s1\"/\"missing\"}" 2>&1)" 'wiki_status'
assert_eq "optional status records effective mode" "0" "$(capture_code post "$status_optional")"
assert_eq "optional unclassified scenario stays non-blocking" "0" "$(capture_code pre "$mutation")"
assert_contains "optional scenario nudges context" "$(run_hook pre "$mutation")" 'wiki_spec_context'
assert_eq "disabled status records mode" "0" "$(capture_code post "$status_disabled")"
assert_eq "disabled mode treats fence as ordinary" "0" "$(capture_code pre "${mutation//\"s1\"/\"disabled\"}")"
assert_eq "disabled mode emits no context nudge" "" "$(run_hook pre "${mutation//\"s1\"/\"disabled\"}" 2>&1)"
assert_eq "strict status records mode" "0" "$(capture_code post "$status_strict")"
assert_eq "strict unclassified scenario stays non-blocking" "0" "$(capture_code pre "${mutation//\"s1\"/\"strict\"}")"
assert_eq "token default status remains untrusted" "0" "$(capture_code post "$status_default")"
assert_eq "token default cannot authorize GWT update" "2" "$(capture_code pre "${mutation//\"s1\"/\"defaulted\"}")"
assert_eq "substituted primary status remains untrusted" "0" "$(capture_code post "$status_substituted")"
assert_eq "substituted primary cannot authorize GWT update" "2" "$(capture_code pre "${mutation//\"s1\"/\"substituted\"}")"
assert_eq "status is session isolated" "2" "$(capture_code pre "${mutation//\"s1\"/\"other-session\"}")"
assert_eq "wrapped status response records mode" "0" "$(capture_code post "$status_wrapped")"
assert_eq "wrapped status authorizes GWT checks" "0" "$(capture_code pre "${mutation//\"s1\"/\"wrapped\"}")"
assert_eq "malformed status response stays untrusted" "0" "$(capture_code post "$status_malformed")"
assert_eq "malformed status cannot authorize GWT update" "2" "$(capture_code pre "${mutation//\"s1\"/\"malformed-status\"}")"
assert_eq "malformed item followed by valid status records mode" "0" "$(capture_code post "$status_malformed_then_valid")"
assert_eq "malformed item followed by valid status authorizes checks" "0" "$(capture_code pre "${mutation//\"s1\"/\"malformed-then-valid\"}")"
assert_status_clears_trust "direct error" "direct-error" "$status_direct_error"
assert_status_clears_trust "wrapped error before valid" "wrapped-error-first" "$status_wrapped_error_first"
assert_status_clears_trust "wrapped error after valid" "wrapped-error-last" "$status_wrapped_error_last"
assert_status_clears_trust "wrapped isError before valid" "wrapped-is-error-first" "$status_wrapped_is_error_first"
assert_status_clears_trust "wrapped isError after valid" "wrapped-is-error-last" "$status_wrapped_is_error_last"
assert_status_clears_trust "missing transport" "missing-transport" "$status_missing_transport"
assert_status_clears_trust "unknown transport" "unknown-transport" "$status_unknown_transport"
assert_eq "other-domain status records trusted mode" "0" "$(capture_code post "$status_other_domain")"
other_domain_mutation="${mutation//\"s1\"/\"other-domain\"}"
other_domain_mutation="${other_domain_mutation//\"demo\"/\"other\"}"
assert_eq "other-domain status authorizes its own domain" "0" "$(capture_code pre "$other_domain_mutation")"
assert_eq "other-domain status cannot authorize demo" "2" "$(capture_code pre "${mutation//\"s1\"/\"other-domain\"}")"
assert_exit "concurrent status writers do not resurrect cleared evidence" 0 concurrent_evidence_writers status
assert_exit "concurrent context writers preserve one-use evidence" 0 concurrent_evidence_writers context

context='{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"mcp__iwiki__wiki_spec_context","tool_input":{"domain":"demo","scenario_id":"checkout.submit"},"tool_response":{"isError":false}}'
assert_eq "successful context records ordering evidence" "0" "$(capture_code post "$context")"
assert_eq "matching context allows scenario mutation" "0" "$(capture_code pre "$mutation")"
successful_mutation='{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"mcp__iwiki__wiki_update_page","tool_input":{"domain":"demo","slug":"spec","heading":"Scenarios","new_body":"```iwiki-gwt\nid = \"checkout.submit\"\ngiven = \"cart\"\nwhen = \"submit\"\nthen = \"accepted\"\ncode = [{ role = \"implements\", selector = \"app.submit\" }, { role = \"verifies\", selector = \"tests.test_submit\" }]\n```"},"tool_response":{"isError":false}}'
assert_eq "successful mutation consumes context" "0" "$(capture_code post "$successful_mutation")"
assert_eq "second unclassified mutation avoids false block" "0" "$(capture_code pre "$mutation")"
assert_contains "second mutation nudges fresh context" "$(run_hook pre "$mutation")" 'wiki_spec_context'

wrong_context='{"session_id":"s2","hook_event_name":"PostToolUse","tool_name":"wiki_spec_context","tool_input":{"domain":"demo","scenario_id":"checkout.cancel"},"tool_response":{"isError":false}}'
assert_eq "s2 optional status records mode" "0" "$(capture_code post "${status_optional//\"s1\"/\"s2\"}")"
assert_eq "alternate tool name records context" "0" "$(capture_code post "$wrong_context")"
wrong_mutation="${mutation//\"s1\"/\"s2\"}"
assert_eq "context-bound mutation cannot switch scenario ID" "2" "$(capture_code pre "$wrong_mutation")"

failed_context='{"session_id":"s3","hook_event_name":"PostToolUse","tool_name":"mcp__iwiki__wiki_spec_context","tool_input":{"domain":"demo","scenario_id":"checkout.submit"},"tool_response":{"isError":true}}'
assert_eq "s3 optional status records mode" "0" "$(capture_code post "${status_optional//\"s1\"/\"s3\"}")"
assert_eq "failed context call stays non-blocking" "0" "$(capture_code post "$failed_context")"
failed_mutation="${mutation//\"s1\"/\"s3\"}"
assert_eq "failed context avoids false mutation block" "0" "$(capture_code pre "$failed_mutation")"
assert_contains "failed context leaves mutation nudge" "$(run_hook pre "$failed_mutation")" 'wiki_spec_context'

wrapped_context_error='{"session_id":"wrapped-context-error","hook_event_name":"PostToolUse","tool_name":"wiki_spec_context","tool_input":{"domain":"demo","scenario_id":"checkout.submit"},"tool_response":{"content":[{"type":"text","text":"{}"},{"type":"text","text":"{\"error\":{}}"}]}}'
wrapped_context_error_mutation="${mutation//\"s1\"/\"wrapped-context-error\"}"
assert_eq "wrapped-context-error status records mode" "0" "$(capture_code post "${status_optional//\"s1\"/\"wrapped-context-error\"}")"
assert_eq "wrapped error context stays controlled" "0" "$(capture_code post "$wrapped_context_error")"
assert_eq "wrapped error context leaves mutation non-blocking" "0" "$(capture_code pre "$wrapped_context_error_mutation")"
assert_contains "wrapped error context leaves context nudge" "$(run_hook pre "$wrapped_context_error_mutation")" 'wiki_spec_context'

wrapped_context_is_error='{"session_id":"wrapped-context-is-error","hook_event_name":"PostToolUse","tool_name":"wiki_spec_context","tool_input":{"domain":"demo","scenario_id":"checkout.submit"},"tool_response":{"content":[{"type":"text","text":"{\"isError\":true}"},{"type":"text","text":"{}"}]}}'
wrapped_context_is_error_mutation="${mutation//\"s1\"/\"wrapped-context-is-error\"}"
assert_eq "wrapped-context-is-error status records mode" "0" "$(capture_code post "${status_optional//\"s1\"/\"wrapped-context-is-error\"}")"
assert_eq "wrapped isError context stays controlled" "0" "$(capture_code post "$wrapped_context_is_error")"
assert_eq "wrapped isError context leaves mutation non-blocking" "0" "$(capture_code pre "$wrapped_context_is_error_mutation")"
assert_contains "wrapped isError context leaves context nudge" "$(run_hook pre "$wrapped_context_is_error_mutation")" 'wiki_spec_context'

consume_session="consume-wrapped-failure"
consume_mutation="${mutation//\"s1\"/\"$consume_session\"}"
consume_context="${context//\"s1\"/\"$consume_session\"}"
wrapped_failed_mutation='{"session_id":"consume-wrapped-failure","hook_event_name":"PostToolUse","tool_name":"wiki_update_page","tool_input":{"domain":"demo","slug":"spec","heading":"Scenarios","new_body":"```iwiki-gwt\nid = \"checkout.submit\"\n```"},"tool_response":{"content":[{"type":"text","text":"{}"},{"type":"text","text":"{\"error\":{}}"}]}}'
assert_eq "wrapped-failed-mutation status records mode" "0" "$(capture_code post "${status_optional//\"s1\"/\"$consume_session\"}")"
assert_eq "wrapped-failed-mutation records context" "0" "$(capture_code post "$consume_context")"
assert_eq "wrapped failed mutation stays controlled" "0" "$(capture_code post "$wrapped_failed_mutation")"
assert_eq "wrapped failed mutation preserves context authorization" "0" "$(capture_code pre "$consume_mutation")"
assert_eq "wrapped failed mutation does not consume context" "" "$(run_hook pre "$consume_mutation" 2>&1)"

malformed='not-json'
assert_eq "malformed payload fails open" "0" "$(capture_code pre "$malformed")"
assert_eq "non-object payload fails open" "0" "$(capture_code pre '[]')"
state_before="$(find "$tmp/home/state" -type f -exec sha256sum {} + | sort)"
assert_eq "non-string tool name fails open" "0" "$(capture_code pre '{"tool_name":7}')"
assert_eq "non-string tool name emits no diagnostic" "" "$(run_hook pre '{"tool_name":7}' 2>&1)"
state_after="$(find "$tmp/home/state" -type f -exec sha256sum {} + | sort)"
assert_eq "non-string tool name leaves state unchanged" "$state_before" "$state_after"

printf '{"expired":{"demo":{"mode":"strict","timestamp":0}}}\n' > "$tmp/home/state/gwt-status.json"
assert_eq "expired status cannot authorize GWT update" "2" "$(capture_code pre "${mutation//\"s1\"/\"expired\"}")"

finish

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

assert_exit "GWT gate exists" 0 test -f "$HOOK"

mutation='{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"mcp__iwiki__wiki_update_page","tool_input":{"domain":"demo","slug":"spec","heading":"Scenarios","new_body":"```iwiki-gwt\nid = \"checkout.submit\"\ngiven = \"cart\"\nwhen = \"submit\"\nthen = \"accepted\"\ncode = [{ role = \"implements\", selector = \"app.submit\" }, { role = \"verifies\", selector = \"tests.test_submit\" }]\n```"}}'
status_optional='{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"mcp__iwiki__wiki_status","tool_response":{"storage":"postgres","transport":"streamable-http","binding_source":"session","specifications":{"domains":[{"domain":"demo","mode":"optional","source":"project"}]}}}'
status_disabled='{"session_id":"disabled","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"storage":"postgres","transport":"stdio","specifications":{"domains":[{"domain":"demo","mode":"disabled","source":"project"}]}}}'
status_strict='{"session_id":"strict","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"storage":"postgres","transport":"streamable-http","binding_source":"session","specifications":{"domains":[{"domain":"demo","mode":"strict","source":"project"}]}}}'
status_default='{"session_id":"defaulted","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"storage":"postgres","transport":"streamable-http","binding_source":"token_default","specifications":{"domains":[{"domain":"demo","mode":"strict","source":"hosted_default"}]}}}'
status_substituted='{"session_id":"substituted","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"storage":"postgres","transport":"streamable-http","binding_source":"session","primary_substituted":true,"requested_primary":"demo","specifications":{"domains":[{"domain":"demo","mode":"strict","source":"project"}]}}}'
status_wrapped='{"session_id":"wrapped","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"content":[{"type":"text","text":"{\"storage\":\"postgres\",\"transport\":\"streamable-http\",\"binding_source\":\"session\",\"specifications\":{\"domains\":[{\"domain\":\"demo\",\"mode\":\"strict\",\"source\":\"project\"}]}}"}]}}'
status_malformed='{"session_id":"malformed-status","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"content":[{"type":"text","text":"not-json"}]}}'
status_direct_error='{"session_id":"direct-error","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"storage":"postgres","transport":"streamable-http","binding_source":"session","specifications":{"domains":[{"domain":"demo","mode":"strict","source":"project"}]},"error":{}}}'
status_wrapped_error='{"session_id":"wrapped-error","hook_event_name":"PostToolUse","tool_name":"wiki_status","tool_response":{"content":[{"type":"text","text":"{\"error\":{},\"storage\":\"postgres\",\"transport\":\"streamable-http\",\"binding_source\":\"session\",\"specifications\":{\"domains\":[{\"domain\":\"demo\",\"mode\":\"strict\",\"source\":\"project\"}]}}"},{"type":"text","text":"{\"storage\":\"postgres\",\"transport\":\"streamable-http\",\"binding_source\":\"session\",\"specifications\":{\"domains\":[{\"domain\":\"demo\",\"mode\":\"strict\",\"source\":\"project\"}]}}"}]}}'

ordinary='{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"mcp__iwiki__wiki_update_page","tool_input":{"domain":"demo","slug":"notes","heading":"Text","new_body":"Ordinary Wiki text"}}'
assert_eq "ordinary Wiki mutation remains allowed" "0" "$(capture_code pre "$ordinary")"

assert_eq "GWT mutation without status fails closed" "2" "$(capture_code pre "${mutation//\"s1\"/\"missing\"}")"
assert_contains "missing status explains recovery" "$(run_hook pre "${mutation//\"s1\"/\"missing\"}" 2>&1)" 'wiki_status'
assert_eq "optional status records effective mode" "0" "$(capture_code post "$status_optional")"
assert_eq "optional unclassified scenario stays non-blocking" "0" "$(capture_code pre "$mutation")"
assert_contains "optional scenario nudges context" "$(run_hook pre "$mutation")" 'wiki_spec_context'
assert_eq "disabled status records mode" "0" "$(capture_code post "$status_disabled")"
assert_eq "disabled mode treats fence as ordinary" "0" "$(capture_code pre "${mutation//\"s1\"/\"disabled\"}")"
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
assert_eq "direct-error session records trusted status" "0" "$(capture_code post "${status_optional//\"s1\"/\"direct-error\"}")"
assert_eq "direct-error session starts authorized" "0" "$(capture_code pre "${mutation//\"s1\"/\"direct-error\"}")"
assert_eq "direct error-bearing status stays controlled" "0" "$(capture_code post "$status_direct_error")"
assert_eq "direct error-bearing status clears previous evidence" "2" "$(capture_code pre "${mutation//\"s1\"/\"direct-error\"}")"
assert_eq "wrapped-error session records trusted status" "0" "$(capture_code post "${status_optional//\"s1\"/\"wrapped-error\"}")"
assert_eq "wrapped-error session starts authorized" "0" "$(capture_code pre "${mutation//\"s1\"/\"wrapped-error\"}")"
assert_eq "wrapped error-bearing status stays controlled" "0" "$(capture_code post "$status_wrapped_error")"
assert_eq "wrapped error-bearing status clears previous evidence" "2" "$(capture_code pre "${mutation//\"s1\"/\"wrapped-error\"}")"

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

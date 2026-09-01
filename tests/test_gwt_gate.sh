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
assert_eq "unclassified scenario mutation avoids false block" "0" "$(capture_code pre "$mutation")"
assert_contains "unclassified scenario mutation nudges context" "$(run_hook pre "$mutation")" 'wiki_spec_context'

context='{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"mcp__iwiki__wiki_spec_context","tool_input":{"domain":"demo","scenario_id":"checkout.submit"},"tool_response":{"isError":false}}'
assert_eq "successful context records ordering evidence" "0" "$(capture_code post "$context")"
assert_eq "matching context allows scenario mutation" "0" "$(capture_code pre "$mutation")"
successful_mutation='{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"mcp__iwiki__wiki_update_page","tool_input":{"domain":"demo","slug":"spec","heading":"Scenarios","new_body":"```iwiki-gwt\nid = \"checkout.submit\"\ngiven = \"cart\"\nwhen = \"submit\"\nthen = \"accepted\"\ncode = [{ role = \"implements\", selector = \"app.submit\" }, { role = \"verifies\", selector = \"tests.test_submit\" }]\n```"},"tool_response":{"isError":false}}'
assert_eq "successful mutation consumes context" "0" "$(capture_code post "$successful_mutation")"
assert_eq "second unclassified mutation avoids false block" "0" "$(capture_code pre "$mutation")"
assert_contains "second mutation nudges fresh context" "$(run_hook pre "$mutation")" 'wiki_spec_context'

wrong_context='{"session_id":"s2","hook_event_name":"PostToolUse","tool_name":"wiki_spec_context","tool_input":{"domain":"demo","scenario_id":"checkout.cancel"},"tool_response":{"isError":false}}'
assert_eq "alternate tool name records context" "0" "$(capture_code post "$wrong_context")"
wrong_mutation="${mutation//\"s1\"/\"s2\"}"
assert_eq "context-bound mutation cannot switch scenario ID" "2" "$(capture_code pre "$wrong_mutation")"

failed_context='{"session_id":"s3","hook_event_name":"PostToolUse","tool_name":"mcp__iwiki__wiki_spec_context","tool_input":{"domain":"demo","scenario_id":"checkout.submit"},"tool_response":{"isError":true}}'
assert_eq "failed context call stays non-blocking" "0" "$(capture_code post "$failed_context")"
failed_mutation="${mutation//\"s1\"/\"s3\"}"
assert_eq "failed context avoids false mutation block" "0" "$(capture_code pre "$failed_mutation")"
assert_contains "failed context leaves mutation nudge" "$(run_hook pre "$failed_mutation")" 'wiki_spec_context'

ordinary='{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"mcp__iwiki__wiki_update_page","tool_input":{"domain":"demo","slug":"notes","heading":"Text","new_body":"Ordinary Wiki text"}}'
assert_eq "ordinary Wiki mutation remains allowed" "0" "$(capture_code pre "$ordinary")"

mkdir -p "$tmp/disabled"
printf '[specifications]\nmode = "disabled"\n' > "$tmp/disabled/.iwiki.toml"
disabled_mutation="${mutation/\"session_id\"/\"cwd\":\"$tmp\/disabled\",\"session_id\"}"
assert_eq "disabled mode leaves GWT fences ordinary" "0" "$(capture_code pre "$disabled_mutation")"

malformed='not-json'
assert_eq "malformed payload fails open" "0" "$(capture_code pre "$malformed")"
assert_eq "non-object payload fails open" "0" "$(capture_code pre '[]')"

finish

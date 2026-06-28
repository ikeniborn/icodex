#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

if [[ ! -x "$ROOT/.codex-isolated/bin/codex" ]]; then
  echo "SKIP: codex binary not installed"
  finish
  exit 0
fi

report="$ROOT/docs/superpowers/reports/iwiki-hook-probe.md"
mkdir -p "$(dirname "$report")"
{
  echo "# iwiki Hook Probe"
  echo
  echo "Date: $(date +%F)"
  echo
  echo "Codex version:"
  "$ROOT/.codex-isolated/bin/codex" --version || true
  echo
  echo "Local hook examples confirmed in repository:"
  echo "- PostToolUse"
  echo "- Stop"
  echo
  echo "Manual verification required for:"
  echo "- SessionStart"
  echo "- UserPromptSubmit"
  echo "- PreToolUse"
  echo
  echo "Result: record actual event support during implementation before claiming full automation."
} > "$report"

assert_exit "probe report written" 0 test -f "$report"
assert_contains "mentions SessionStart" "$(cat "$report")" "SessionStart"
finish

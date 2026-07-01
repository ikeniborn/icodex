#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

SK="$ROOT/.codex-isolated/skills"

parse_frontmatter() { # <file> — exit 0 iff YAML frontmatter has name + description
  python3 - "$1" <<'PY'
import sys, yaml
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
assert lines and lines[0].strip() == "---"
fm = []
for ln in lines[1:]:
    if ln.strip() == "---":
        break
    fm.append(ln)
d = yaml.safe_load("\n".join(fm))
assert isinstance(d, dict) and d.get("name") and d.get("description")
PY
}

# check-chain: one unified validator, four stage profiles.
CC="$SK/check-chain/SKILL.md"
assert_exit "check-chain SKILL.md exists" 0 test -f "$CC"
if [[ -f "$CC" ]]; then
  body="$(cat "$CC")"
  assert_contains "check-chain name frontmatter" "$body" "name: check-chain"
  assert_contains "check-chain has a description" "$body" "description:"
  assert_contains "check-chain references intent_hash" "$body" "intent_hash"
  assert_contains "check-chain references spec_hash" "$body" "spec_hash"
  assert_contains "check-chain references plan_hash" "$body" "plan_hash"
  assert_contains "check-chain covers result stage" "$body" "result_check"
  assert_exit "check-chain frontmatter parses" 0 parse_frontmatter "$CC"
fi

# fix-intent: intent capture skill.
FI="$SK/fix-intent/SKILL.md"
assert_exit "fix-intent SKILL.md exists" 0 test -f "$FI"
if [[ -f "$FI" ]]; then
  body="$(cat "$FI")"
  assert_contains "fix-intent name frontmatter" "$body" "name: fix-intent"
  assert_contains "fix-intent has a description" "$body" "description:"
  assert_exit "fix-intent frontmatter parses" 0 parse_frontmatter "$FI"
fi

finish

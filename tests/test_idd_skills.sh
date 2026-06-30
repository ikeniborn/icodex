#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

SK="$ROOT/.codex-isolated/skills"

check_skill() { # <name> <expected hash-key token> <expected tab token>
  local name="$1" key="$2" tab="$3" f="$SK/$1/SKILL.md"
  assert_exit "$name SKILL.md exists" 0 test -f "$f"
  [[ -f "$f" ]] || return 0
  local body; body="$(cat "$f")"
  assert_contains "$name has name frontmatter" "$body" "name: $name"
  assert_contains "$name has a description" "$body" "description:"
  assert_contains "$name references $key" "$body" "$key"
  assert_contains "$name targets tab: $tab" "$body" "tab: $tab"
  # frontmatter parses as YAML
  assert_exit "$name frontmatter parses" 0 python3 - "$f" <<'PY'
import sys, yaml
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
assert lines[0].strip() == "---"
fm = []
for ln in lines[1:]:
    if ln.strip() == "---": break
    fm.append(ln)
d = yaml.safe_load("\n".join(fm))
assert isinstance(d, dict) and d.get("name") and d.get("description")
PY
}

check_skill check-intent intent_hash intent
check_skill check-spec   spec_hash   spec
check_skill check-plan   plan_hash   plan
check_skill check-result plan_hash   result

finish

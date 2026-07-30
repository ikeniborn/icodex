#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

HOOK="$ROOT/.codex-isolated/hooks/profile-transition.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export CODEX_HOME="$tmp/home"
mkdir -p "$CODEX_HOME"

assert_exit "profile hook exists" 0 test -f "$HOOK"
if [[ ! -f "$HOOK" ]]; then
  finish
  exit $?
fi

hash_a="$(printf a | sha256sum | awk '{print $1}')"
hash_b="$(printf b | sha256sum | awk '{print $1}')"

create_handoff() { # <run> <sequence> <request> <task> <registry-hash> [model]
  python3 - "$ROOT" "$CODEX_HOME" "$1" "$2" "$3" "$4" "$5" "${6:-gpt-5.6-terra}" <<'PY'
import importlib.util
import sys
from pathlib import Path

root, home, run_id, sequence, request_id, task_id, registry_hash, model = sys.argv[1:]
spec = importlib.util.spec_from_file_location("profile_state_fixture", Path(root) / "lib/profile/state.py")
assert spec is not None and spec.loader is not None
state = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = state
spec.loader.exec_module(state)
request = {
    "run_id": run_id,
    "sequence": int(sequence),
    "target_root": "/repo",
    "topic": "demo-topic",
    "task_id": task_id,
    "registry_commit": "a" * 40,
    "registry_version": 1,
    "registry_hash": registry_hash,
    "manifest_commit": "b" * 40,
    "manifest_hash": "b" * 64,
    "profile": "engineering",
    "model": model,
    "effort": "medium",
    "request_id": request_id,
    "request_hash": "c" * 64,
}
state.create_handoff(state.routing_root(Path(home)), request)
PY
}

hook_result() { # <payload> <run> <sequence> <request>
  local payload="$1" run_id="$2" sequence="$3" request_id="$4" code=0 output
  output="$(env ICODEX_PROFILE_RUN_ID="$run_id" \
    ICODEX_PROFILE_SEQUENCE="$sequence" \
    ICODEX_PROFILE_REQUEST_ID="$request_id" \
    ICODEX_ROOT="$ROOT" CODEX_HOME="$CODEX_HOME" \
    python3 "$HOOK" <<<"$payload" 2>&1)" || code=$?
  printf '%s\n%s\n' "$code" "$output"
}

hook_code() { sed -n '1p'; }
hook_output() { sed -n '2,$p'; }

protected_payload='{"session_id":"s1","cwd":"/repo","hook_event_name":"PreToolUse","model":"gpt-5.6-terra","tool_name":"Write","tool_input":{"file_path":"x"}}'
create_handoff run-main 0 req-main demo-task "$hash_a"
result="$(hook_result "$protected_payload" run-main 0 req-main)"
assert_eq "matching handoff authorizes protected action" "0" "$(hook_code <<<"$result")"
assert_exit "matching handoff consumed once" 0 test -f "$CODEX_HOME/state/profile-routing/consumed/run-main.0.json"
assert_exit "matching handoff leaves no pending copy" 1 test -e "$CODEX_HOME/state/profile-routing/pending/run-main.0.json"
assert_exit "matching handoff persists session decision" 0 test -f "$CODEX_HOME/state/profile-routing/decisions/s1.json"
assert_contains "matching result uses standard allow JSON" "$(hook_output <<<"$result")" '"permissionDecision": "allow"'

result="$(hook_result "$protected_payload" run-main 0 req-main)"
assert_eq "later protected action reuses matching decision" "0" "$(hook_code <<<"$result")"

replay_payload="${protected_payload/\"s1\"/\"s2\"}"
result="$(hook_result "$replay_payload" run-main 0 req-main)"
assert_eq "handoff replay from another session denies" "2" "$(hook_code <<<"$result")"
assert_eq "denial has one remediation" "1" "$(grep -o -- '--run-task' <<<"$(hook_output <<<"$result")" | wc -l)"
assert_contains "denial uses safe task evidence" "$(hook_output <<<"$result")" 'icodex --run-task demo-topic demo-task'

missing_payload="${protected_payload/\"s1\"/\"missing-session\"}"
result="$(hook_result "$missing_payload" missing-run 0 missing-request)"
assert_eq "missing handoff denies" "2" "$(hook_code <<<"$result")"
assert_contains "missing evidence remediation is concrete template" "$(hook_output <<<"$result")" 'icodex --run-task <topic> <task-id>'

create_handoff correct-run 0 req-wrong-run demo-task "$hash_a"
result="$(hook_result "${protected_payload/\"s1\"/\"wrong-run-session\"}" wrong-run 0 req-wrong-run)"
assert_eq "wrong run denies" "2" "$(hook_code <<<"$result")"

create_handoff sequence-run 1 req-sequence demo-task "$hash_a"
result="$(hook_result "${protected_payload/\"s1\"/\"wrong-sequence-session\"}" sequence-run 2 req-sequence)"
assert_eq "wrong sequence denies" "2" "$(hook_code <<<"$result")"

create_handoff request-run 0 correct-request demo-task "$hash_a"
result="$(hook_result "${protected_payload/\"s1\"/\"wrong-request-session\"}" request-run 0 wrong-request)"
assert_eq "wrong request denies" "2" "$(hook_code <<<"$result")"

tamper_decision() { # <session> <field> <value>
  python3 - "$CODEX_HOME/state/profile-routing/decisions/$1.json" "$2" "$3" <<'PY'
import json
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
value[sys.argv[2]] = sys.argv[3]
path.write_text(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
os.chmod(path, 0o600)
PY
}

tamper_decision s1 task_id other-task
result="$(hook_result "$protected_payload" run-main 0 req-main)"
assert_eq "persisted task mismatch denies" "2" "$(hook_code <<<"$result")"
tamper_decision s1 task_id demo-task
tamper_decision s1 registry_hash "$hash_b"
result="$(hook_result "$protected_payload" run-main 0 req-main)"
assert_eq "persisted hash mismatch denies" "2" "$(hook_code <<<"$result")"
tamper_decision s1 registry_hash "$hash_a"

changed_model_payload="${protected_payload/gpt-5.6-terra/gpt-5.6-sol}"
result="$(hook_result "$changed_model_payload" run-main 0 req-main)"
assert_eq "changed payload model denies" "2" "$(hook_code <<<"$result")"

read_payload='{"session_id":"reader","model":"gpt-5.6-terra","tool_name":"Read","tool_input":{"file_path":"README.md"}}'
result="$(hook_result "$read_payload" discovery-run 0 discovery-request)"
assert_eq "direct unrelated Read allows before authorization" "0" "$(hook_code <<<"$result")"

rg_payload='{"session_id":"reader","model":"gpt-5.6-terra","tool_name":"Bash","tool_input":{"command":"rg --files"}}'
result="$(hook_result "$rg_payload" discovery-run 0 discovery-request)"
assert_eq "rg --files allows before authorization" "0" "$(hook_code <<<"$result")"

unknown_shell='{"session_id":"shell","model":"gpt-5.6-terra","tool_name":"Bash","tool_input":{"command":"python3 tests/run.py"}}'
result="$(hook_result "$unknown_shell" discovery-run 0 discovery-request)"
assert_eq "unknown shell command denies" "2" "$(hook_code <<<"$result")"

assert_shell_denied() { # <description> <command>
  local description="$1" command="$2" payload result
  payload="$(python3 - "$command" <<'PY'
import json
import sys
print(json.dumps({
    "session_id": "unsafe-shell",
    "model": "gpt-5.6-terra",
    "tool_name": "Bash",
    "tool_input": {"command": sys.argv[1]},
}))
PY
)"
  result="$(hook_result "$payload" unsafe-shell-run 0 unsafe-shell-request)"
  assert_eq "$description" "2" "$(hook_code <<<"$result")"
  assert_contains "$description returns standard deny" "$(hook_output <<<"$result")" '"permissionDecision": "deny"'
}

assert_shell_denied "tree attached short output denies" "tree -oFILE docs"
assert_shell_denied "tree equals short output denies" "tree -o=FILE docs"
assert_shell_denied "tree split short output denies" "tree -o FILE docs"
assert_shell_denied "tree split long output denies" "tree --output FILE docs"
assert_shell_denied "tree equals long output denies" "tree --output=FILE docs"
assert_shell_denied "sed attached lowercase write denies" "sed -n 'wFILE' README.md"
assert_shell_denied "sed attached uppercase write denies" "sed -n 'WFILE' README.md"
assert_shell_denied "sed separated lowercase write denies" "sed -n 'w FILE' README.md"
assert_shell_denied "sed separated uppercase write denies" "sed -n 'W FILE' README.md"
assert_shell_denied "sed execute command denies" "sed -n 'e id' README.md"
assert_shell_denied "sed substitution execute flag denies" "sed -n 's/x/y/e' README.md"
assert_shell_denied "git external diff denies" "git diff --ext-diff"
assert_shell_denied "git textconv helper denies" "git diff --textconv"
assert_shell_denied "git show textconv helper denies" "git show --textconv HEAD"
assert_shell_denied "git output file denies" "git log --output=FILE"

skill_read='{"session_id":"skill","model":"gpt-5.6-terra","tool_name":"Read","tool_input":{"file_path":"/repo/.codex/skills/executing-plans/SKILL.md"}}'
result="$(hook_result "$skill_read" discovery-run 0 discovery-request)"
assert_eq "execution skill SKILL.md read is protected" "2" "$(hook_code <<<"$result")"

partial_code=0
env ICODEX_PROFILE_RUN_ID=partial-run ICODEX_ROOT="$ROOT" CODEX_HOME="$CODEX_HOME" \
  python3 "$HOOK" <<<"$read_payload" >/dev/null 2>&1 || partial_code=$?
assert_eq "partial routed correlation denies read-only discovery" "2" "$partial_code"

interactive_output="$(env -u ICODEX_PROFILE_RUN_ID -u ICODEX_PROFILE_SEQUENCE -u ICODEX_PROFILE_REQUEST_ID \
  ICODEX_ROOT="$ROOT" CODEX_HOME="$CODEX_HOME" python3 "$HOOK" <<<"$protected_payload" 2>&1)"
interactive_code=$?
assert_eq "ordinary interactive work without routed env allows" "0" "$interactive_code"
assert_eq "ordinary interactive allow claims no routed authorization" "0" "$(grep -c 'permissionDecision\|authorized' <<<"$interactive_output")"

for malformed_tool in '[]' '{}' '7' 'null'; do
  malformed_payload="$(printf '{"session_id":"malformed","model":"gpt-5.6-terra","tool_name":%s,"tool_input":{}}' "$malformed_tool")"
  result="$(hook_result "$malformed_payload" malformed-run 0 malformed-request)"
  assert_eq "non-string routed tool $malformed_tool denies" "2" "$(hook_code <<<"$result")"
  assert_contains "non-string routed tool $malformed_tool standard deny" "$(hook_output <<<"$result")" '"permissionDecision": "deny"'
  malformed_interactive="$(env -u ICODEX_PROFILE_RUN_ID -u ICODEX_PROFILE_SEQUENCE -u ICODEX_PROFILE_REQUEST_ID \
    ICODEX_ROOT="$ROOT" CODEX_HOME="$CODEX_HOME" python3 "$HOOK" <<<"$malformed_payload" 2>&1)"
  malformed_interactive_code=$?
  assert_eq "non-string interactive tool $malformed_tool allows" "0" "$malformed_interactive_code"
  assert_eq "non-string interactive tool $malformed_tool claims nothing" "" "$malformed_interactive"
done

python3 - "$HOOK" <<'PY' >/dev/null 2>&1
import importlib.util
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("profile_transition_test", Path(sys.argv[1]))
assert spec is not None and spec.loader is not None
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)

def bash(command):
    return {"tool_name": "Bash", "tool_input": {"command": command}}

for command in (
    "rg --files | head", "rg --files > out", "x=$(rg --files)", "X=1 rg --files",
    "rg --files; pwd", "rg `printf x`", "(rg --files)", "find . -delete",
    "find . -exec printf x ;", "sed README.md", "git branch --delete old",
    "rg --pre formatter --files", "sed -n '1w out' README.md", "tree -o out docs",
    "git diff --output=out", "git show --output out HEAD", "git log --output=out",
    "tree -oFILE docs", "tree -o=FILE docs", "tree --output FILE docs", "tree --output=FILE docs",
    "sed -n 'wFILE' README.md", "sed -n 'WFILE' README.md",
    "sed -n 'w FILE' README.md", "sed -n 'W FILE' README.md",
    "sed -n 'e id' README.md", "sed -n 's/x/y/e' README.md",
    "git diff --ext-diff", "git diff --textconv", "git show --textconv HEAD",
):
    assert hook.is_protected(bash(command)), command
for command in (
    "rg --files", "sed -n 1,10p README.md", "git status --short", "git diff --stat",
    "git show HEAD", "git log -1", "git branch --show-current", "git rev-parse --show-toplevel",
    "tree -L 2 docs", "tree -a --dirsfirst docs", "find docs -maxdepth 2 -type f",
    "sed -n '/needle/p' README.md", "sed -n -e 1p README.md",
    "git diff --no-ext-diff --no-textconv", "git show --no-textconv HEAD",
):
    assert not hook.is_protected(bash(command)), command
assert hook.READ_ONLY_TOOLS == {"Read", "Glob", "Grep"}
assert hook.MUTATING_TOOLS == {"Write", "Edit", "apply_patch"}
for tool in ([], {}, 7, None):
    assert hook.is_protected({"tool_name": tool, "tool_input": {}})
PY
assert_eq "closed shell discovery classification" "0" "$?"

assert_eq "hook never references transcript path" "0" "$(grep -c 'transcript_path' "$HOOK")"
assert_eq "hook never imports network or subprocess clients" "0" "$(grep -Ec '(^|[[:space:]])(import|from)[[:space:]]+(socket|urllib|http|requests|subprocess)|curl|wget' "$HOOK")"
assert_eq "hook never invokes model switch" "0" "$(grep -c '/model' "$HOOK")"

finish

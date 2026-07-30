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
  local payload="$1" run_id="$2" sequence="$3" request_id="$4" code=0 stdout_file stderr_file
  stdout_file="$(mktemp "$tmp/hook-stdout.XXXXXX")"
  stderr_file="$(mktemp "$tmp/hook-stderr.XXXXXX")"
  env -i PATH=/usr/bin:/bin LC_ALL=C \
    ICODEX_PROFILE_RUN_ID="$run_id" \
    ICODEX_PROFILE_SEQUENCE="$sequence" \
    ICODEX_PROFILE_REQUEST_ID="$request_id" \
    ICODEX_ROOT="$ROOT" CODEX_HOME="$CODEX_HOME" \
    python3 "$HOOK" <<<"$payload" >"$stdout_file" 2>"$stderr_file" || code=$?
  printf '%s\n' "$code"
  base64 -w0 < "$stdout_file"; printf '\n'
  base64 -w0 < "$stderr_file"; printf '\n'
}

hook_result_with_env() { # <payload> <run> <sequence> <request> <name> <value>
  local payload="$1" run_id="$2" sequence="$3" request_id="$4" name="$5" value="$6" code=0
  local stdout_file stderr_file
  stdout_file="$(mktemp "$tmp/hook-env-stdout.XXXXXX")"
  stderr_file="$(mktemp "$tmp/hook-env-stderr.XXXXXX")"
  env -i PATH=/usr/bin:/bin LC_ALL=C "$name=$value" \
    ICODEX_PROFILE_RUN_ID="$run_id" \
    ICODEX_PROFILE_SEQUENCE="$sequence" \
    ICODEX_PROFILE_REQUEST_ID="$request_id" \
    ICODEX_ROOT="$ROOT" CODEX_HOME="$CODEX_HOME" \
    python3 "$HOOK" <<<"$payload" >"$stdout_file" 2>"$stderr_file" || code=$?
  printf '%s\n' "$code"
  base64 -w0 < "$stdout_file"; printf '\n'
  base64 -w0 < "$stderr_file"; printf '\n'
}

hook_code() { sed -n '1p'; }
hook_stdout() { sed -n '2p' | base64 -d; }
hook_stderr() { sed -n '3p' | base64 -d; }
hook_output() { hook_stdout; }

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
assert_eq "handoff replay returns structured decision" "0" "$(hook_code <<<"$result")"
assert_eq "handoff replay denial keeps stderr empty" "" "$(hook_stderr <<<"$result")"
assert_eq "denial has one remediation" "1" "$(grep -o -- '--run-task' <<<"$(hook_output <<<"$result")" | wc -l)"
assert_contains "denial uses safe task evidence" "$(hook_output <<<"$result")" 'icodex --run-task demo-topic demo-task'

missing_payload="${protected_payload/\"s1\"/\"missing-session\"}"
result="$(hook_result "$missing_payload" missing-run 0 missing-request)"
assert_eq "missing handoff returns structured decision" "0" "$(hook_code <<<"$result")"
assert_contains "missing handoff structured deny" "$(hook_output <<<"$result")" '"permissionDecision": "deny"'
assert_contains "missing evidence remediation is concrete template" "$(hook_output <<<"$result")" 'icodex --run-task <topic> <task-id>'

create_handoff correct-run 0 req-wrong-run demo-task "$hash_a"
result="$(hook_result "${protected_payload/\"s1\"/\"wrong-run-session\"}" wrong-run 0 req-wrong-run)"
assert_eq "wrong run returns structured deny" "0" "$(hook_code <<<"$result")"

create_handoff sequence-run 1 req-sequence demo-task "$hash_a"
result="$(hook_result "${protected_payload/\"s1\"/\"wrong-sequence-session\"}" sequence-run 2 req-sequence)"
assert_eq "wrong sequence returns structured deny" "0" "$(hook_code <<<"$result")"

create_handoff request-run 0 correct-request demo-task "$hash_a"
result="$(hook_result "${protected_payload/\"s1\"/\"wrong-request-session\"}" request-run 0 wrong-request)"
assert_eq "wrong request returns structured deny" "0" "$(hook_code <<<"$result")"

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
assert_eq "persisted task mismatch returns structured deny" "0" "$(hook_code <<<"$result")"
tamper_decision s1 task_id demo-task
tamper_decision s1 registry_hash "$hash_b"
result="$(hook_result "$protected_payload" run-main 0 req-main)"
assert_eq "persisted hash mismatch returns structured deny" "0" "$(hook_code <<<"$result")"
tamper_decision s1 registry_hash "$hash_a"

changed_model_payload="${protected_payload/gpt-5.6-terra/gpt-5.6-sol}"
result="$(hook_result "$changed_model_payload" run-main 0 req-main)"
assert_eq "changed payload model returns structured deny" "0" "$(hook_code <<<"$result")"

read_payload='{"session_id":"reader","model":"gpt-5.6-terra","tool_name":"Read","tool_input":{"file_path":"README.md"}}'
result="$(hook_result "$read_payload" discovery-run 0 discovery-request)"
assert_eq "direct unrelated Read allows before authorization" "0" "$(hook_code <<<"$result")"

rg_payload='{"session_id":"reader","model":"gpt-5.6-terra","tool_name":"Bash","tool_input":{"command":"rg --files"}}'
result="$(hook_result "$rg_payload" discovery-run 0 discovery-request)"
assert_eq "rg --files allows before authorization" "0" "$(hook_code <<<"$result")"
assert_contains "routed discovery returns rewritten input" "$(hook_output <<<"$result")" '"updatedInput"'
assert_eq "routed discovery rewrite keeps stderr empty" "" "$(hook_stderr <<<"$result")"

bash_payload() { # <command> [cwd]
  python3 - "$1" "${2:-$ROOT}" <<'PY'
import json
import sys
print(json.dumps({
    "session_id": "discovery-probe",
    "cwd": sys.argv[2],
    "model": "gpt-5.6-terra",
    "tool_name": "Bash",
    "tool_input": {"command": sys.argv[1]},
}))
PY
}

approved_command() { # <original-command> <hook-stdout-json>
  python3 - "$1" "$2" <<'PY'
import json
import sys
original = sys.argv[1]
raw = sys.argv[2]
if not raw.strip():
    print(original)
else:
    value = json.loads(raw)
    print(value.get("hookSpecificOutput", {}).get("updatedInput", {}).get("command", original))
PY
}

allowed_command() { # <original-command> <hook-stdout-json>
  python3 - "$1" "$2" <<'PY'
import json
import sys
original = sys.argv[1]
value = json.loads(sys.argv[2])
output = value.get("hookSpecificOutput", {})
if output.get("permissionDecision") == "allow":
    print(output.get("updatedInput", {}).get("command", original))
PY
}

approve_discovery() { # <command>
  local command="$1" cwd="${2:-$ROOT}" payload result stdout
  payload="$(bash_payload "$command" "$cwd")"
  result="$(hook_result "$payload" discovery-probe-run 0 discovery-probe-request)"
  stdout="$(hook_output <<<"$result")"
  approved_command "$command" "$stdout"
}

# Shell startup variables are interpreted before a sanitized rewritten command
# can run, so routed discovery must require authorization when they are visible.
startup_original='sed -n p README.md'
startup_payload="$(bash_payload "$startup_original" "$ROOT")"
for startup_name in BASH_ENV ENV; do
  startup_dir="$tmp/startup-$startup_name"
  mkdir -p "$startup_dir"
  startup_marker="$startup_dir/invoked"
  startup_file="$startup_dir/startup"
  printf 'printf invoked > %q\n' "$startup_marker" > "$startup_file"
  result="$(hook_result_with_env "$startup_payload" startup-run 0 startup-request "$startup_name" "$startup_file")"
  assert_eq "$startup_name preauth returns structured decision" "0" "$(hook_code <<<"$result")"
  assert_contains "$startup_name preauth is denied" "$(hook_output <<<"$result")" '"permissionDecision": "deny"'
  assert_eq "$startup_name preauth has no rewritten input" "0" "$(grep -c 'updatedInput' <<<"$(hook_output <<<"$result")")"
  startup_command="$(allowed_command "$startup_original" "$(hook_output <<<"$result")")"
  if [[ -n "$startup_command" && "$startup_name" == "BASH_ENV" ]]; then
    env -i PATH=/usr/bin:/bin BASH_ENV="$startup_file" /bin/bash -c "$startup_command" >/dev/null 2>&1 || true
  fi
  assert_exit "$startup_name preauth never starts injected shell" 1 test -e "$startup_marker"
done

function_marker="$tmp/imported-function-invoked"
function_value="() { printf invoked > '$function_marker'; }"
result="$(hook_result_with_env "$startup_payload" function-run 0 function-request 'BASH_FUNC_rg%%' "$function_value")"
assert_contains "imported shell function preauth is denied" "$(hook_output <<<"$result")" '"permissionDecision": "deny"'
assert_eq "imported shell function preauth has no rewritten input" "0" "$(grep -c 'updatedInput' <<<"$(hook_output <<<"$result")")"
assert_exit "imported shell function probe remains absent" 1 test -e "$function_marker"

# Exact authorization permits the original command and its inherited startup behavior.
authorized_startup_payload="${startup_payload/discovery-probe/authorized-startup}"
authorized_startup_file="$tmp/authorized-startup"
authorized_startup_marker="$tmp/authorized-startup-invoked"
printf 'printf invoked > %q\n' "$authorized_startup_marker" > "$authorized_startup_file"
create_handoff authorized-startup-run 0 authorized-startup-request demo-task "$hash_a"
result="$(hook_result_with_env "$authorized_startup_payload" authorized-startup-run 0 authorized-startup-request BASH_ENV "$authorized_startup_file")"
assert_contains "authorized startup command is allowed" "$(hook_output <<<"$result")" '"permissionDecision": "allow"'
assert_eq "authorized startup command keeps original input" "0" "$(grep -c 'updatedInput' <<<"$(hook_output <<<"$result")")"
startup_command="$(allowed_command "$startup_original" "$(hook_output <<<"$result")")"
if [[ -n "$startup_command" ]]; then
  env -i PATH=/usr/bin:/bin BASH_ENV="$authorized_startup_file" /bin/bash -c "$startup_command" >/dev/null 2>&1 || true
fi
assert_exit "authorized startup command may run original shell behavior" 0 test -e "$authorized_startup_marker"

approved="$(approve_discovery 'rg --files *')"
assert_contains "discovery rewrite uses fixed empty environment" "$approved" '/usr/bin/env -i PATH=/usr/bin:/bin LC_ALL=C'
assert_contains "discovery rewrite uses managed rg" "$approved" "$ROOT/.codex-isolated/bin/rg"
assert_contains "discovery rewrite disables ripgrep config" "$approved" '--no-config'
assert_contains "discovery rewrite quotes wildcard token" "$approved" "'*'"

# Actual pre-expansion exploit: raw `*` becomes `-i victim` after classification.
sed_probe="$tmp/sed-expansion"
mkdir -p "$sed_probe"
printf '' > "$sed_probe/-i"
printf 'original\n' > "$sed_probe/victim"
sed_before="$(stat -c '%i:%s' "$sed_probe/victim")"
approved="$(approve_discovery 'sed -n p *')"
(cd "$sed_probe" && PATH=/usr/bin:/bin /bin/bash -c "$approved" >/dev/null 2>&1) || true
sed_after="$(stat -c '%i:%s' "$sed_probe/victim")"
assert_eq "quoted discovery argv prevents sed wildcard in-place mutation" "$sed_before" "$sed_after"

# Option-shaped filenames stay literal for every representative discovery tool,
# and ambient PATH shadows never receive execution.
shadow_dir="$tmp/path-shadow"
option_probe="$tmp/option-files"
mkdir -p "$shadow_dir" "$option_probe"
git -C "$option_probe" init -q
for tool in rg find tree git; do
  printf '#!/usr/bin/env bash\nprintf invoked > %q\n' "$option_probe/$tool-shadowed" > "$shadow_dir/$tool"
  chmod +x "$shadow_dir/$tool"
done
printf '' > "$option_probe/--pre"
printf '' > "$option_probe/-delete"
printf '' > "$option_probe/-oPWNED"
printf '' > "$option_probe/--show-signature"
for command in 'rg --files *' 'find *' 'tree *' 'git status *'; do
  approved="$(approve_discovery "$command" "$option_probe")"
  assert_contains "$command rewrite keeps wildcard literal" "$approved" "'*'"
  (cd "$option_probe" && PATH="$shadow_dir:/usr/bin:/bin" /bin/bash -c "$approved" >/dev/null 2>&1) || true
done
for tool in rg find tree git; do
  assert_exit "$tool option-filename/PATH shadow not executed" 1 test -e "$option_probe/$tool-shadowed"
done

# A real ripgrep config with --pre must not launch its helper.
real_rg="$(command -v rg)"
rg_config_probe="$tmp/rg-config"
mkdir -p "$rg_config_probe"
printf 'needle\n' > "$rg_config_probe/victim.txt"
printf '#!/usr/bin/env bash\nprintf invoked > %q\ncat "$1"\n' "$rg_config_probe/pre-invoked" > "$rg_config_probe/pre-helper"
chmod +x "$rg_config_probe/pre-helper"
printf '%s\n%s\n' '--pre' "$rg_config_probe/pre-helper" > "$rg_config_probe/ripgreprc"
approved="$(approve_discovery 'rg needle victim.txt')"
(cd "$rg_config_probe" && PATH="$(dirname "$real_rg"):/usr/bin:/bin" \
  RIPGREP_CONFIG_PATH="$rg_config_probe/ripgreprc" /bin/bash -c "$approved" >/dev/null 2>&1) || true
assert_exit "ripgrep config pre-helper not executed" 1 test -e "$rg_config_probe/pre-invoked"

# Repo/global Git helpers are inert, and status cannot refresh/write the index.
git_probe="$tmp/git-helpers"
global_home="$tmp/git-global-home"
mkdir -p "$git_probe" "$global_home"
git -C "$git_probe" init -q
git -C "$git_probe" config user.email test@example.com
git -C "$git_probe" config user.name Test
printf 'base\n' > "$git_probe/tracked.txt"
git -C "$git_probe" add tracked.txt
git -C "$git_probe" commit -qm init
printf '#!/usr/bin/env bash\nprintf invoked >> %q\nexit 0\n' "$git_probe/helper-invoked" > "$git_probe/helper"
chmod +x "$git_probe/helper"
printf '#!/usr/bin/env bash\nprintf invoked > %q\ncat "$1"\n' "$git_probe/textconv-invoked" > "$git_probe/textconv-helper"
chmod +x "$git_probe/textconv-helper"
printf '#!/usr/bin/env bash\nprintf invoked > %q\nexit 0\n' "$git_probe/signature-invoked" > "$git_probe/signature-helper"
chmod +x "$git_probe/signature-helper"
printf '*.txt diff=probe\n' > "$git_probe/.gitattributes"
git -C "$git_probe" add .gitattributes
git -C "$git_probe" commit -qm attributes
git -C "$git_probe" config diff.external "$git_probe/helper"
git -C "$git_probe" config diff.probe.textconv "$git_probe/textconv-helper"
git -C "$git_probe" config core.fsmonitor "$git_probe/helper"
git -C "$git_probe" config gpg.program "$git_probe/signature-helper"
printf 'changed\n' >> "$git_probe/tracked.txt"
approved="$(approve_discovery 'git diff' "$git_probe")"
(cd "$git_probe" && PATH=/usr/bin:/bin /bin/bash -c "$approved" >/dev/null 2>&1) || true
assert_exit "repo Git external/fsmonitor helpers not executed" 1 test -e "$git_probe/helper-invoked"

git -C "$git_probe" config --unset diff.external
git -C "$git_probe" config --unset core.fsmonitor
approved="$(approve_discovery 'git diff' "$git_probe")"
(cd "$git_probe" && PATH=/usr/bin:/bin /bin/bash -c "$approved" >/dev/null 2>&1) || true
assert_exit "repo Git textconv helper not executed" 1 test -e "$git_probe/textconv-invoked"

approved="$(approve_discovery 'git log -1' "$git_probe")"
(cd "$git_probe" && PATH=/usr/bin:/bin /bin/bash -c "$approved" >/dev/null 2>&1) || true
assert_exit "repo Git signature helper not executed" 1 test -e "$git_probe/signature-invoked"

printf '#!/usr/bin/env bash\nprintf invoked > %q\nexit 0\n' "$git_probe/global-invoked" > "$git_probe/global-helper"
chmod +x "$git_probe/global-helper"
printf '[diff]\n\texternal = %s\n' "$git_probe/global-helper" > "$global_home/.gitconfig"
approved="$(approve_discovery 'git diff' "$git_probe")"
(cd "$git_probe" && HOME="$global_home" PATH=/usr/bin:/bin /bin/bash -c "$approved" >/dev/null 2>&1) || true
assert_exit "global Git external helper not executed" 1 test -e "$git_probe/global-invoked"

git -C "$git_probe" checkout -q -- tracked.txt
sleep 1
touch "$git_probe/tracked.txt"
index_before="$(sha256sum "$git_probe/.git/index" | awk '{print $1}')"
approved="$(approve_discovery 'git status --short' "$git_probe")"
(cd "$git_probe" && HOME="$global_home" PATH=/usr/bin:/bin /bin/bash -c "$approved" >/dev/null 2>&1) || true
index_after="$(sha256sum "$git_probe/.git/index" | awk '{print $1}')"
assert_eq "sanitized git status does not write index" "$index_before" "$index_after"

approved="$(approve_discovery 'git diff --stat' "$git_probe")"
assert_contains "git rewrite disables optional locks" "$approved" '--no-optional-locks'
assert_contains "git rewrite disables external diff" "$approved" '--no-ext-diff'
assert_contains "git rewrite disables textconv" "$approved" '--no-textconv'
assert_contains "git rewrite disables fsmonitor" "$approved" 'core.fsmonitor=false'
assert_contains "git rewrite disables global/system config" "$approved" 'GIT_CONFIG_NOSYSTEM=1'

# Local clean/process filters can execute helpers during working-tree diff/status.
filter_probe="$tmp/git-filter-helpers"
mkdir -p "$filter_probe"
git -C "$filter_probe" init -q
git -C "$filter_probe" config user.email test@example.com
git -C "$filter_probe" config user.name Test
printf '*.txt filter=probe\n' > "$filter_probe/.gitattributes"
printf 'base\n' > "$filter_probe/tracked.txt"
git -C "$filter_probe" add .gitattributes tracked.txt
git -C "$filter_probe" commit -qm init
filter_marker="$filter_probe/filter-invoked"
printf '#!/usr/bin/env bash\nprintf invoked > %q\ncat\n' "$filter_marker" > "$filter_probe/clean-helper"
printf '#!/usr/bin/env bash\nprintf invoked > %q\nexit 1\n' "$filter_marker" > "$filter_probe/process-helper"
chmod +x "$filter_probe/clean-helper" "$filter_probe/process-helper"
git -C "$filter_probe" config filter.probe.clean "$filter_probe/clean-helper"
git -C "$filter_probe" config filter.probe.process "$filter_probe/process-helper"
printf 'changed\n' >> "$filter_probe/tracked.txt"
for command in 'git diff' 'git status --short'; do
  rm -f "$filter_marker"
  payload="$(bash_payload "$command" "$filter_probe")"
  result="$(hook_result "$payload" filter-run 0 filter-request)"
  assert_eq "$command local filter returns structured decision" "0" "$(hook_code <<<"$result")"
  assert_contains "$command local filter is denied before authorization" "$(hook_output <<<"$result")" '"permissionDecision": "deny"'
  assert_eq "$command local filter has no rewritten input" "0" "$(grep -c 'updatedInput' <<<"$(hook_output <<<"$result")")"
  filter_command="$(allowed_command "$command" "$(hook_output <<<"$result")")"
  if [[ -n "$filter_command" ]]; then
    (cd "$filter_probe" && /bin/bash -c "$filter_command" >/dev/null 2>&1) || true
  fi
  assert_exit "$command denied path does not execute local filter" 1 test -e "$filter_marker"
done

linked_filter_probe="$tmp/git-filter-linked"
git -C "$filter_probe" worktree add -q --no-checkout "$linked_filter_probe" HEAD
payload="$(bash_payload 'git status --short' "$linked_filter_probe")"
result="$(hook_result "$payload" linked-filter-run 0 linked-filter-request)"
assert_contains "linked worktree inherits local filter denial" "$(hook_output <<<"$result")" '"permissionDecision": "deny"'
git -C "$filter_probe" worktree remove --force "$linked_filter_probe"

# Per-worktree filters live outside the common local config when worktreeConfig is enabled.
worktree_scope_root="$tmp/git-worktree-scope-root"
worktree_scope_linked="$tmp/git-worktree-scope-linked"
mkdir -p "$worktree_scope_root"
git -C "$worktree_scope_root" init -q
git -C "$worktree_scope_root" config user.email test@example.com
git -C "$worktree_scope_root" config user.name Test
git -C "$worktree_scope_root" config extensions.worktreeConfig true
printf '*.txt filter=probe\n' > "$worktree_scope_root/.gitattributes"
printf 'base\n' > "$worktree_scope_root/tracked.txt"
git -C "$worktree_scope_root" add .gitattributes tracked.txt
git -C "$worktree_scope_root" commit -qm init
git -C "$worktree_scope_root" worktree add -q "$worktree_scope_linked" HEAD
worktree_filter_marker="$tmp/worktree-filter-invoked"
printf '#!/usr/bin/env bash\nprintf invoked > %q\ncat\n' "$worktree_filter_marker" > "$tmp/worktree-clean-helper"
printf '#!/usr/bin/env bash\nprintf invoked > %q\nexit 1\n' "$worktree_filter_marker" > "$tmp/worktree-process-helper"
chmod +x "$tmp/worktree-clean-helper" "$tmp/worktree-process-helper"
git -C "$worktree_scope_linked" config --worktree filter.probe.clean "$tmp/worktree-clean-helper"
git -C "$worktree_scope_linked" config --worktree filter.probe.process "$tmp/worktree-process-helper"
printf 'changed\n' >> "$worktree_scope_linked/tracked.txt"
for command in 'git diff' 'git status --short'; do
  rm -f "$worktree_filter_marker"
  payload="$(bash_payload "$command" "$worktree_scope_linked")"
  result="$(hook_result "$payload" worktree-filter-run 0 worktree-filter-request)"
  assert_contains "$command worktree-scope filter is denied" "$(hook_output <<<"$result")" '"permissionDecision": "deny"'
  worktree_command="$(allowed_command "$command" "$(hook_output <<<"$result")")"
  if [[ -n "$worktree_command" ]]; then
    (cd "$worktree_scope_linked" && /bin/bash -c "$worktree_command" >/dev/null 2>&1) || true
  fi
  assert_exit "$command denied path skips worktree filter" 1 test -e "$worktree_filter_marker"
done
git -C "$worktree_scope_linked" config --worktree --unset filter.probe.clean
git -C "$worktree_scope_linked" config --worktree --unset filter.probe.process
payload="$(bash_payload 'git status --short' "$worktree_scope_linked")"
result="$(hook_result "$payload" clean-worktree-run 0 clean-worktree-request)"
assert_contains "clean linked worktree retains sanitized preauth" "$(hook_output <<<"$result")" '"updatedInput"'
git -C "$worktree_scope_root" worktree remove --force "$worktree_scope_linked"

include_filter_probe="$tmp/git-filter-include"
mkdir -p "$include_filter_probe"
git -C "$include_filter_probe" init -q
printf '[filter "probe"]\n\tclean = %s\n' "$filter_probe/clean-helper" > "$include_filter_probe/filter.inc"
git -C "$include_filter_probe" config include.path "$include_filter_probe/filter.inc"
payload="$(bash_payload 'git diff' "$include_filter_probe")"
result="$(hook_result "$payload" include-filter-run 0 include-filter-request)"
assert_contains "included local filter config is denied" "$(hook_output <<<"$result")" '"permissionDecision": "deny"'

payload="$(bash_payload 'git diff' "$tmp/missing-git-cwd")"
result="$(hook_result "$payload" bad-cwd-run 0 bad-cwd-request)"
assert_contains "untrusted Git cwd fails closed" "$(hook_output <<<"$result")" '"permissionDecision": "deny"'

no_filter_probe="$tmp/git-no-filter"
mkdir -p "$no_filter_probe"
git -C "$no_filter_probe" init -q
for command in 'git diff' 'git status --short'; do
  payload="$(bash_payload "$command" "$no_filter_probe")"
  result="$(hook_result "$payload" no-filter-run 0 no-filter-request)"
  assert_contains "$command without local filters remains sanitized preauth" "$(hook_output <<<"$result")" '"updatedInput"'
done

pattern_probe="$tmp/find-pattern"
mkdir -p "$pattern_probe"
printf '' > "$pattern_probe/keep.txt"
printf '' > "$pattern_probe/skip.md"
approved="$(approve_discovery "find . -name '*.txt'")"
pattern_output="$(cd "$pattern_probe" && /bin/bash -c "$approved" 2>/dev/null)"
assert_contains "quoted find pattern preserves tool-level matching" "$pattern_output" './keep.txt'
assert_eq "quoted find pattern excludes non-match" "0" "$(grep -c 'skip.md' <<<"$pattern_output")"

# Missing or symlinked managed tools never fall back to ambient PATH.
untrusted_root="$tmp/untrusted-root"
mkdir -p "$untrusted_root/.codex-isolated/bin"
ln -s "$ROOT/.codex-isolated/bin/rg" "$untrusted_root/.codex-isolated/bin/rg"
untrusted_stdout="$tmp/untrusted.stdout"
untrusted_stderr="$tmp/untrusted.stderr"
untrusted_code=0
env ICODEX_PROFILE_RUN_ID=untrusted-run ICODEX_PROFILE_SEQUENCE=0 \
  ICODEX_PROFILE_REQUEST_ID=untrusted-request ICODEX_ROOT="$untrusted_root" CODEX_HOME="$CODEX_HOME" \
  python3 "$HOOK" <<<"$rg_payload" >"$untrusted_stdout" 2>"$untrusted_stderr" || untrusted_code=$?
assert_eq "symlinked managed tool returns structured decision" "0" "$untrusted_code"
assert_contains "symlinked managed tool fails closed" "$(cat "$untrusted_stdout")" '"permissionDecision": "deny"'
assert_eq "symlinked managed tool keeps stderr empty" "" "$(cat "$untrusted_stderr")"

unknown_shell='{"session_id":"shell","model":"gpt-5.6-terra","tool_name":"Bash","tool_input":{"command":"python3 tests/run.py"}}'
result="$(hook_result "$unknown_shell" discovery-run 0 discovery-request)"
assert_eq "unknown shell command returns structured deny" "0" "$(hook_code <<<"$result")"
assert_contains "unknown shell command denial is JSON" "$(hook_output <<<"$result")" '"permissionDecision": "deny"'

create_handoff authorized-shell-run 0 authorized-shell-request demo-task "$hash_a"
authorized_shell='{"session_id":"authorized-shell","model":"gpt-5.6-terra","tool_name":"Bash","tool_input":{"command":"python3 tests/run.py"}}'
result="$(hook_result "$authorized_shell" authorized-shell-run 0 authorized-shell-request)"
assert_eq "protected authorized shell action allows" "0" "$(hook_code <<<"$result")"
assert_contains "protected authorized shell action has allow decision" "$(hook_output <<<"$result")" '"permissionDecision": "allow"'
assert_eq "protected authorized shell action keeps original input" "0" "$(grep -c 'updatedInput' <<<"$(hook_output <<<"$result")")"

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
  assert_eq "$description" "0" "$(hook_code <<<"$result")"
  assert_contains "$description returns standard deny" "$(hook_output <<<"$result")" '"permissionDecision": "deny"'
  assert_eq "$description keeps stderr empty" "" "$(hook_stderr <<<"$result")"
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
assert_shell_denied "git show signature helper denies" "git log --show-signature -1"

skill_read='{"session_id":"skill","model":"gpt-5.6-terra","tool_name":"Read","tool_input":{"file_path":"/repo/.codex/skills/executing-plans/SKILL.md"}}'
result="$(hook_result "$skill_read" discovery-run 0 discovery-request)"
assert_eq "execution skill SKILL.md read returns structured deny" "0" "$(hook_code <<<"$result")"
assert_contains "execution skill denial is JSON" "$(hook_output <<<"$result")" '"permissionDecision": "deny"'

partial_stdout="$tmp/partial.stdout"
partial_stderr="$tmp/partial.stderr"
partial_code=0
env ICODEX_PROFILE_RUN_ID=partial-run ICODEX_ROOT="$ROOT" CODEX_HOME="$CODEX_HOME" \
  python3 "$HOOK" <<<"$read_payload" >"$partial_stdout" 2>"$partial_stderr" || partial_code=$?
assert_eq "partial routed correlation returns structured decision" "0" "$partial_code"
assert_contains "partial routed correlation denies read-only discovery" "$(cat "$partial_stdout")" '"permissionDecision": "deny"'
assert_eq "partial routed correlation keeps stderr empty" "" "$(cat "$partial_stderr")"

interactive_output="$(env -u ICODEX_PROFILE_RUN_ID -u ICODEX_PROFILE_SEQUENCE -u ICODEX_PROFILE_REQUEST_ID \
  ICODEX_ROOT="$ROOT" CODEX_HOME="$CODEX_HOME" python3 "$HOOK" <<<"$protected_payload" 2>&1)"
interactive_code=$?
assert_eq "ordinary interactive work without routed env allows" "0" "$interactive_code"
assert_eq "ordinary interactive allow claims no routed authorization" "0" "$(grep -c 'permissionDecision\|authorized' <<<"$interactive_output")"

interactive_rg_output="$(env -u ICODEX_PROFILE_RUN_ID -u ICODEX_PROFILE_SEQUENCE -u ICODEX_PROFILE_REQUEST_ID \
  ICODEX_ROOT="$ROOT" CODEX_HOME="$CODEX_HOME" python3 "$HOOK" <<<"$rg_payload" 2>&1)"
interactive_rg_code=$?
assert_eq "ordinary interactive discovery allows" "0" "$interactive_rg_code"
assert_eq "ordinary interactive discovery is not rewritten" "" "$interactive_rg_output"

for malformed_tool in '[]' '{}' '7' 'null'; do
  malformed_payload="$(printf '{"session_id":"malformed","model":"gpt-5.6-terra","tool_name":%s,"tool_input":{}}' "$malformed_tool")"
  result="$(hook_result "$malformed_payload" malformed-run 0 malformed-request)"
  assert_eq "non-string routed tool $malformed_tool returns structured deny" "0" "$(hook_code <<<"$result")"
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
    "git log --show-signature -1", "git log --format=%G? -1",
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
assert_eq "hook never imports network clients" "0" "$(grep -Ec '(^|[[:space:]])(import|from)[[:space:]]+(socket|urllib|http|requests)|curl|wget' "$HOOK")"
assert_eq "hook subprocess probe never invokes a shell" "0" "$(grep -c 'shell=True' "$HOOK")"
assert_eq "hook never invokes model switch" "0" "$(grep -c '/model' "$HOOK")"

finish

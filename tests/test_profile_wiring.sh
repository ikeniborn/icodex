#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

MODULE="$ROOT/lib/profile/wiring.sh"
assert_exit "profile wiring module exists" 0 test -f "$MODULE"
if [[ ! -f "$MODULE" ]]; then
  finish
  exit $?
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export ICODEX_ROOT="$ROOT"
export ICODEX_SHARED_DIR="$ROOT/.codex-isolated"
export ICODEX_HOME_DIR="$tmp/home"
export ICODEX_PROJECT_ROOT="$tmp/project"
mkdir -p "$ICODEX_HOME_DIR" "$ICODEX_PROJECT_ROOT" "$tmp/bin" "$tmp/wiki-base"
ln -s "$ICODEX_SHARED_DIR/hooks.json" "$ICODEX_HOME_DIR/hooks.json"
printf 'model = "gpt-test"\n' > "$ICODEX_HOME_DIR/config.toml"

source "$ROOT/lib/core/logging.sh"
source "$ROOT/lib/caveman/caveman.sh"
source "$ROOT/lib/idd/idd.sh"
source "$ROOT/lib/plugin/loen.sh"
source "$ROOT/lib/iwiki/iwiki.sh"
source "$MODULE"

expected_python_launcher="$(command -p -v python3)"
expected_python="$(env -i PATH=/usr/bin:/bin LC_ALL=C "$expected_python_launcher" - <<'PY'
import os
import sys
from pathlib import Path

path = Path(sys.executable).resolve(strict=True)
assert path.is_absolute() and path.is_file() and os.access(path, os.X_OK) and not path.is_symlink()
print(path)
PY
)"
expected_command="$(python3 - "$expected_python" <<'PY'
import shlex
import sys
print(f'{shlex.quote(sys.argv[1])} "$CODEX_HOME/hooks/profile-transition.py"')
PY
)"

# Compose actual project wiring functions, then add profile wiring last.
export ICODEX_CAVEMAN_MODE=full
unset ICODEX_IDD || true
export ICODEX_LOEN_MODE=strict
export ICODEX_IWIKI_COMMAND="$tmp/bin/iwiki-mcp"
export ICODEX_IWIKI_BASE_DIR="$tmp/wiki-base"
export ICODEX_IWIKI_LLM_BASE_URL="http://test-llm.invalid/v1"
export ICODEX_IWIKI_LLM_KEY="test-key"
ensure_caveman_wiring
ensure_idd_wiring
ensure_loen_wiring
ensure_iwiki_wiring
ensure_iwiki_binding

assert_contains "actual LoEn wiring composed" "$(cat "$ICODEX_HOME_DIR/config.toml")" '[plugins."loen@ikeniborn"]'
assert_contains "actual iwiki wiring composed" "$(cat "$ICODEX_HOME_DIR/config.toml")" '[mcp_servers.iwiki]'
assert_exit "actual iwiki binding composed" 0 test -L "$ICODEX_HOME_DIR/.iwiki.toml"

before_entries="$(python3 - "$ICODEX_HOME_DIR/hooks.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
print(json.dumps(data["hooks"], separators=(",", ":")))
PY
)"
before_order="$(python3 - "$ICODEX_HOME_DIR/hooks.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
for event, entries in data["hooks"].items():
    for position, entry in enumerate(entries):
        commands = [hook.get("command", "") for hook in entry.get("hooks", [])]
        print(json.dumps([event, position, entry.get("matcher"), commands], separators=(",", ":")))
PY
)"
config_before="$(sha256sum "$ICODEX_HOME_DIR/config.toml" | awk '{print $1}')"
loen_hooks="$(_loen_cache_dir)/hooks/hooks.json"
loen_hooks_before="$(sha256sum "$loen_hooks" | awk '{print $1}')"

ensure_profile_wiring
hooks_file="$ICODEX_HOME_DIR/hooks.json"
assert_exit "profile-composed hooks are valid JSON" 0 python3 -c "import json; json.load(open('$hooks_file'))"
configured_command="$(python3 - "$hooks_file" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
for entry in data.get("hooks", {}).get("PreToolUse", []):
    for hook in entry.get("hooks", []):
        command = hook.get("command", "")
        if command.endswith('"$CODEX_HOME/hooks/profile-transition.py"'):
            print(command)
            raise SystemExit
PY
)"

profile_summary="$(python3 - "$hooks_file" "$expected_command" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
command = sys.argv[2]
matches = []
for position, entry in enumerate(data.get("hooks", {}).get("PreToolUse", [])):
    for hook in entry.get("hooks", []):
        if hook.get("command") == command:
            matches.append((position, entry, hook))
print(len(matches))
if matches:
    position, entry, hook = matches[0]
    print(position)
    print(len(data["hooks"]["PreToolUse"]) - 1)
    print(entry.get("matcher", ""))
    print(hook.get("type", ""))
    print(hook.get("timeout", ""))
    print(hook.get("statusMessage", ""))
PY
)"
assert_eq "exactly one profile hook" "1" "$(sed -n '1p' <<<"$profile_summary")"
assert_eq "profile hook appended last" "$(sed -n '3p' <<<"$profile_summary")" "$(sed -n '2p' <<<"$profile_summary")"
assert_eq "profile hook matcher is wildcard" "*" "$(sed -n '4p' <<<"$profile_summary")"
assert_eq "profile hook type" "command" "$(sed -n '5p' <<<"$profile_summary")"
assert_eq "profile hook timeout" "30" "$(sed -n '6p' <<<"$profile_summary")"
assert_eq "profile hook status" "Checking routed profile evidence" "$(sed -n '7p' <<<"$profile_summary")"

direct_hook_count="$(python3 - "$hooks_file" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
count = 0
for entry in data.get("hooks", {}).get("UserPromptSubmit", []):
    for hook in entry.get("hooks", []):
        if hook.get("command", "").endswith('"$CODEX_HOME/hooks/direct-topic.py"'):
            count += 1
print(count)
PY
)"
assert_eq "exactly one direct topic hook" "1" "$direct_hook_count"
assert_contains "direct topic hook status" "$(cat "$hooks_file")" "Checking direct topic profile"

after_without_profile="$(python3 - "$hooks_file" "$expected_command" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
command = sys.argv[2]
data["hooks"]["PreToolUse"] = [
    entry for entry in data["hooks"]["PreToolUse"]
    if not any(hook.get("command") == command for hook in entry.get("hooks", []))
]
data["hooks"]["UserPromptSubmit"] = [
    entry for entry in data["hooks"]["UserPromptSubmit"]
    if not any(hook.get("command", "").endswith('"$CODEX_HOME/hooks/direct-topic.py"') for hook in entry.get("hooks", []))
]
print(json.dumps(data["hooks"], separators=(",", ":")))
PY
)"
after_order_without_profile="$(python3 - "$hooks_file" "$expected_command" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
command = sys.argv[2]
for event, entries in data["hooks"].items():
    kept = [entry for entry in entries if not any(
        hook.get("command") == command
        or hook.get("command", "").endswith('"$CODEX_HOME/hooks/direct-topic.py"')
        for hook in entry.get("hooks", [])
    )]
    for position, entry in enumerate(kept):
        commands = [hook.get("command", "") for hook in entry.get("hooks", [])]
        print(json.dumps([event, position, entry.get("matcher"), commands], separators=(",", ":")))
PY
)"
assert_eq "every actual existing hook entry remains byte-equivalent" "$before_entries" "$after_without_profile"
assert_eq "every actual existing hook entry keeps order" "$before_order" "$after_order_without_profile"
assert_eq "profile wiring leaves LoEn and iwiki config bytes unchanged" "$config_before" "$(sha256sum "$ICODEX_HOME_DIR/config.toml" | awk '{print $1}')"
assert_eq "profile wiring leaves actual LoEn hook registry unchanged" "$loen_hooks_before" "$(sha256sum "$loen_hooks" | awk '{print $1}')"

assert_eq "profile hook uses canonical absolute interpreter" "$expected_command" "$configured_command"
assert_eq "profile hook command has no bare interpreter" "0" "$(grep -c 'python3 \\"\$CODEX_HOME/hooks/profile-transition.py\\"' "$hooks_file")"

# Existing bare profile hook entries are migrated, not duplicated.
python3 - "$hooks_file" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as stream:
    data = json.load(stream)
data["hooks"]["PreToolUse"].append({
    "matcher": "*",
    "hooks": [{"type": "command", "command": 'python3 "$CODEX_HOME/hooks/profile-transition.py"'}],
})
with open(path, "w", encoding="utf-8") as stream:
    json.dump(data, stream, indent=2)
    stream.write("\n")
PY
ensure_profile_wiring
assert_eq "legacy bare profile hook is removed" "0" "$(grep -c 'python3 \\"\$CODEX_HOME/hooks/profile-transition.py\\"' "$hooks_file")"

before_hash="$(sha256sum "$hooks_file" | awk '{print $1}')"
ensure_profile_wiring
after_hash="$(sha256sum "$hooks_file" | awk '{print $1}')"
assert_eq "profile wiring idempotent full bytes" "$before_hash" "$after_hash"
assert_eq "profile command remains unique" "1" "$(grep -c 'profile-transition.py' "$hooks_file")"
assert_contains "base secret hook preserved" "$(cat "$hooks_file")" "block-secrets.py"
assert_contains "base redaction hook preserved" "$(cat "$hooks_file")" "redact-secrets.py"
assert_contains "actual caveman hook preserved" "$(cat "$hooks_file")" "caveman-hook.py"
assert_contains "actual chain gate preserved" "$(cat "$hooks_file")" "chain-gate.py"

# Exercise the configured hook exactly through the shell boundary used by Codex.
export CODEX_HOME="$ICODEX_HOME_DIR"
hook_payload='{"session_id":"startup-shell","model":"gpt-5.6-terra","tool_name":"Read","tool_input":{"file_path":"README.md"}}'
launch_configured_profile_hook() {
  /bin/bash -lc "$configured_command" <<<"$hook_payload" >/dev/null 2>&1 || true
}

startup_bin="$tmp/startup-bin"
startup_env_marker="$tmp/startup-env-invoked"
startup_path_marker="$tmp/startup-path-invoked"
mkdir -p "$startup_bin"
printf '#!/usr/bin/env bash\nprintf invoked > %q\n' "$startup_path_marker" > "$startup_bin/python3"
chmod +x "$startup_bin/python3"
printf 'printf invoked > %q\nexport PATH=%q:$PATH\n' "$startup_env_marker" "$startup_bin" > "$tmp/startup-env"
export BASH_ENV="$tmp/startup-env"
if declare -F sanitize_profile_hook_environment >/dev/null; then
  sanitize_profile_hook_environment
fi
launch_configured_profile_hook
assert_exit "sanitized hook shell does not source BASH_ENV" 1 test -e "$startup_env_marker"
assert_exit "configured hook ignores malicious python PATH" 1 test -e "$startup_path_marker"
unset BASH_ENV

startup_function_marker="$tmp/startup-function-invoked"
export startup_function_marker
python3() { printf invoked > "$startup_function_marker"; }
export -f python3
if declare -F sanitize_profile_hook_environment >/dev/null; then
  sanitize_profile_hook_environment
fi
launch_configured_profile_hook
assert_exit "configured hook ignores exported python3 function" 1 test -e "$startup_function_marker"

# Launch stub observes the same environment inherited by Codex children.
normal_sourced_profile_fixture() { :; }
exported_profile_fixture() { :; }
export -f exported_profile_fixture
export BASH_ENV="$tmp/child-bash-env"
export ENV="$tmp/child-env"
child_environment="$tmp/child-environment"
launch_environment_stub() { /usr/bin/env > "$child_environment"; }
if declare -F sanitize_profile_hook_environment >/dev/null; then
  sanitize_profile_hook_environment
fi
launch_environment_stub
assert_eq "launch child has no shell startup variables" "0" "$(grep -Ec '^(BASH_ENV|ENV)=' "$child_environment")"
assert_eq "launch child has no exported shell functions" "0" "$(grep -c '^BASH_FUNC_' "$child_environment")"
assert_exit "sanitizer preserves normal sourced functions" 0 declare -F normal_sourced_profile_fixture
unset BASH_ENV ENV startup_function_marker
unset -f python3 exported_profile_fixture normal_sourced_profile_fixture launch_environment_stub launch_configured_profile_hook

# Readonly shell option variables can enable xtrace in a child before its command runs.
trace_marker="$tmp/child-xtrace-invoked"
trace_child_environment="$tmp/trace-child-environment"
trace_child_bashpid_file="$tmp/trace-child-bashpid"
trace_child_xtrace_file="$tmp/trace-child-xtrace"
trace_parent_bashpid="$BASHPID"
export TRACE_STAGE=parent
export TRACE_MARKER="$trace_marker"
export TRACE_CHILD_ENVIRONMENT="$trace_child_environment"
export TRACE_CHILD_BASHPID_FILE="$trace_child_bashpid_file"
export TRACE_CHILD_XTRACE_FILE="$trace_child_xtrace_file"
export ICODEX_SANITIZER_NORMAL=preserved
exec 9>/dev/null
{
  set -x
  builtin export SHELLOPTS BASHOPTS
  export PS4='$(if [[ "${TRACE_STAGE:-}" == child ]]; then printf invoked > "$TRACE_MARKER"; fi)'
  export PS0=control-ps0 PS1=control-ps1 PS2=control-ps2 PS3=control-ps3
  export PROMPT_COMMAND='printf prompt-control'
  export BASH_XTRACEFD=9
  sanitize_profile_hook_environment
  /bin/bash -lc 'TRACE_STAGE=child; printf "%s\n" "$BASHPID" > "$TRACE_CHILD_BASHPID_FILE"; /usr/bin/env > "$TRACE_CHILD_ENVIRONMENT"; [[ "$-" == *x* ]] && printf xtrace > "$TRACE_CHILD_XTRACE_FILE"; :'
  set +x
} 2>/dev/null
assert_exit "trace fixture records child BASHPID" 0 test -s "$trace_child_bashpid_file"
assert_eq "trace fixture distinguishes wrapper and child BASHPID" "1" "$([[ "$trace_parent_bashpid" != "$(cat "$trace_child_bashpid_file")" ]] && echo 1 || echo 0)"
assert_exit "sanitized child does not execute inherited PS4" 1 test -e "$trace_marker"
assert_exit "sanitized child does not inherit xtrace" 1 test -e "$trace_child_xtrace_file"
assert_eq "sanitized child has no shell trace or prompt control env" "0" "$(grep -Ec '^(SHELLOPTS|BASHOPTS|BASH_XTRACEFD|PS[0-4]|PROMPT_COMMAND)=' "$trace_child_environment")"
assert_contains "sanitized child preserves ordinary environment" "$(cat "$trace_child_environment")" 'ICODEX_SANITIZER_NORMAL=preserved'
builtin export -n SHELLOPTS BASHOPTS 2>/dev/null || true
unset PS0 PS1 PS2 PS3 PS4 PROMPT_COMMAND BASH_XTRACEFD
unset TRACE_STAGE TRACE_MARKER TRACE_CHILD_ENVIRONMENT TRACE_CHILD_BASHPID_FILE TRACE_CHILD_XTRACE_FILE ICODEX_SANITIZER_NORMAL

# Parser failure must preserve the input and remove its same-directory temp.
invalid_home="$tmp/invalid-home"
mkdir -p "$invalid_home"
printf '{invalid json\n' > "$invalid_home/hooks.json"
invalid_before="$(sha256sum "$invalid_home/hooks.json" | awk '{print $1}')"
export ICODEX_HOME_DIR="$invalid_home"
invalid_code=0
ensure_profile_wiring >/dev/null 2>&1 || invalid_code=$?
assert_eq "invalid hooks JSON returns failure" "1" "$([[ "$invalid_code" -ne 0 ]] && echo 1 || echo 0)"
assert_eq "invalid hooks JSON remains unchanged" "$invalid_before" "$(sha256sum "$invalid_home/hooks.json" | awk '{print $1}')"
assert_eq "parser failure removes profile temp" "0" "$(find "$invalid_home" -maxdepth 1 -name 'hooks.json.profile.*' | wc -l)"

# Profile temp cleanup must not replace a caller-owned RETURN trap.
return_home="$tmp/return-home"
return_marker="$tmp/caller-return-trap"
return_before="$tmp/caller-return-before"
return_after="$tmp/caller-return-after"
mkdir -p "$return_home"
printf '{"hooks":{}}\n' > "$return_home/hooks.json"
export ICODEX_HOME_DIR="$return_home"
trap 'printf preserved > "$return_marker"' RETURN
trap -p RETURN > "$return_before"
ensure_profile_wiring
trap -p RETURN > "$return_after"
trap - RETURN
assert_exit "profile wiring restores exact caller RETURN trap" 0 cmp -s "$return_before" "$return_after"

finish

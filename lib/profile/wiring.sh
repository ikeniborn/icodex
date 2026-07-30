#!/usr/bin/env bash
# Add the routed-profile PreToolUse guard without changing existing hook entries.

_profile_apply_hooks_json() {
  local home="$ICODEX_HOME_DIR/hooks.json" tmp python env_binary
  [[ -e "$home" || -L "$home" ]] || return 0
  python="$(command -p -v python3)" || return 1
  env_binary="$(command -p -v env)" || return 1
  [[ "$python" == /* && -x "$python" && "$env_binary" == /* && -x "$env_binary" ]] || return 1
  tmp="$(mktemp "${home}.profile.XXXXXX")"
  trap 'rm -f -- "$tmp"; trap - RETURN' RETURN
  if ! "$env_binary" -i PATH=/usr/bin:/bin LC_ALL=C "$python" - "$home" > "$tmp" <<'PY'
import json
import os
import shlex
import stat
import sys
from pathlib import Path

home = sys.argv[1]
with open(home, encoding="utf-8") as stream:
    config = json.load(stream)
hooks = config.setdefault("hooks", {})
interpreter = Path(sys.executable)
if not interpreter.is_absolute():
    raise RuntimeError("profile hook interpreter must be absolute")
interpreter = interpreter.resolve(strict=True)
metadata = interpreter.lstat()
if interpreter.is_symlink() or not stat.S_ISREG(metadata.st_mode) or not os.access(interpreter, os.X_OK):
    raise RuntimeError("profile hook interpreter must be a canonical executable")
script = "$CODEX_HOME/hooks/profile-transition.py"
command = f'{shlex.quote(str(interpreter))} "{script}"'

def is_profile_command(value):
    if not isinstance(value, str):
        return False
    try:
        arguments = shlex.split(value, posix=True)
    except ValueError:
        return False
    return (
        len(arguments) == 2
        and arguments[1] == script
        and (arguments[0] == "python3" or Path(arguments[0]).is_absolute())
    )

entries = []
for entry in hooks.get("PreToolUse", []):
    kept_hooks = [hook for hook in entry.get("hooks", []) if not is_profile_command(hook.get("command"))]
    if kept_hooks:
        if len(kept_hooks) == len(entry.get("hooks", [])):
            entries.append(entry)
        else:
            replacement = dict(entry)
            replacement["hooks"] = kept_hooks
            entries.append(replacement)
entries.append({
    "matcher": "*",
    "hooks": [{
        "type": "command",
        "command": command,
        "timeout": 30,
        "statusMessage": "Checking routed profile evidence",
    }],
})
hooks["PreToolUse"] = entries

json.dump(config, sys.stdout, indent=2)
sys.stdout.write("\n")
PY
  then
    return 1
  fi
  if [[ ! -L "$home" && -f "$home" ]] && cmp -s "$tmp" "$home"; then
    return 0
  fi
  mv -f "$tmp" "$home"
}

ensure_profile_wiring() {
  _profile_apply_hooks_json
}

sanitize_profile_hook_environment() {
  local declaration function_name
  builtin export -n SHELLOPTS BASHOPTS 2>/dev/null || true
  builtin unset \
    BASH_ENV ENV BASH_XTRACEFD \
    PS0 PS1 PS2 PS3 PS4 PROMPT_COMMAND
  while IFS= read -r declaration; do
    function_name="${declaration##* }"
    [[ -n "$function_name" ]] || continue
    builtin export -n -f "$function_name" 2>/dev/null || true
    builtin unset -f "$function_name" 2>/dev/null || true
  done < <(builtin declare -Fx)
}

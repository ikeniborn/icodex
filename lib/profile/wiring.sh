#!/usr/bin/env bash
# Add the routed-profile PreToolUse guard without changing existing hook entries.

_profile_apply_hooks_json() {
  local home="$ICODEX_HOME_DIR/hooks.json" tmp
  [[ -e "$home" || -L "$home" ]] || return 0
  tmp="$(mktemp "${home}.profile.XXXXXX")"
  trap 'rm -f -- "$tmp"; trap - RETURN' RETURN
  if ! python3 - "$home" > "$tmp" <<'PY'
import json
import sys

home = sys.argv[1]
with open(home, encoding="utf-8") as stream:
    config = json.load(stream)
hooks = config.setdefault("hooks", {})
command = 'python3 "$CODEX_HOME/hooks/profile-transition.py"'

entries = []
for entry in hooks.get("PreToolUse", []):
    kept_hooks = [hook for hook in entry.get("hooks", []) if hook.get("command") != command]
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

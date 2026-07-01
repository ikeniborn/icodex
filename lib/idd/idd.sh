#!/usr/bin/env bash
# Wire the IDD->SDD phase gate + nudge into the per-project Codex home at launch.
#
# IDD is ON BY DEFAULT and governed by ICODEX_IDD (opt-out: disabled only when
# ICODEX_IDD=off). When enabled, the idd-gate (PreToolUse) and idd-nudge
# (PostToolUse) entries are merged into $ICODEX_HOME_DIR/hooks.json; when opted
# out, they are stripped. Mirrors lib/caveman/caveman.sh and MUST run after
# ensure_caveman_wiring so it is the final authority on the IDD entries.

_idd_disabled() {
  [[ "$(printf '%s' "${ICODEX_IDD:-}" | tr '[:upper:]' '[:lower:]')" == "off" ]]
}

_idd_apply_hooks_json() { # <enable 0|1>
  local home="$ICODEX_HOME_DIR/hooks.json" shared="$ICODEX_SHARED_DIR/hooks.json" enable="$1" tmp
  [[ -e "$home" || -L "$home" ]] || return 0
  tmp="$(mktemp)"
  python3 - "$home" "$enable" > "$tmp" <<'PY'
import json, sys
home, enable = sys.argv[1], sys.argv[2] == "1"
with open(home, encoding="utf-8") as fh:
    cfg = json.load(fh)
hooks = cfg.setdefault("hooks", {})
GATE = 'python3 "$CODEX_HOME/hooks/chain-gate.py"'
NUDGE = 'python3 "$CODEX_HOME/hooks/chain-gate.py" --post'
# Legacy split-hook commands to strip on upgrade (self-healing migration).
LEGACY = [
    'python3 "$CODEX_HOME/hooks/idd-gate.py"',
    'python3 "$CODEX_HOME/hooks/idd-nudge.py"',
]

def strip(event, cmd):
    arr = hooks.get(event, [])
    kept = [e for e in arr
            if not any(h.get("command") == cmd for h in e.get("hooks", []))]
    if kept:
        hooks[event] = kept
    elif event in hooks:
        del hooks[event]

def present(event, cmd):
    return any(h.get("command") == cmd
               for e in hooks.get(event, []) for h in e.get("hooks", []))

def add(event, matcher, cmd, status):
    if present(event, cmd):
        return
    hooks.setdefault(event, []).append({
        "matcher": matcher,
        "hooks": [{"type": "command", "command": cmd,
                   "timeout": 30, "statusMessage": status}],
    })

strip("PreToolUse", GATE)
strip("PostToolUse", NUDGE)
for cmd in LEGACY:
    strip("PreToolUse", cmd)
    strip("PostToolUse", cmd)
if enable:
    add("PreToolUse", "Skill|apply_patch|Write|Edit", GATE, "IDD phase gate")
    add("PostToolUse", "apply_patch|Write", NUDGE, "IDD nudge")

json.dump(cfg, sys.stdout, indent=2)
sys.stdout.write("\n")
PY
  if [[ "$enable" == "0" && -f "$shared" ]] &&
     python3 - "$tmp" "$shared" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as a, open(sys.argv[2], encoding="utf-8") as b:
    sys.exit(0 if json.load(a) == json.load(b) else 1)
PY
  then
    rm -f "$home"
    ln -s "$shared" "$home"
    rm -f "$tmp"
    return 0
  fi
  if [[ -L "$home" || ! -f "$home" ]] || ! cmp -s "$tmp" "$home"; then
    rm -f "$home"
    cat "$tmp" > "$home"
  fi
  rm -f "$tmp"
}

ensure_idd_wiring() {
  if _idd_disabled; then
    _idd_apply_hooks_json 0
  else
    _idd_apply_hooks_json 1
  fi
}

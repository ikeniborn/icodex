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
export ICODEX_SHARED_DIR="$tmp/shared"
export ICODEX_HOME_DIR="$tmp/home"
mkdir -p "$ICODEX_SHARED_DIR/caveman" "$ICODEX_HOME_DIR"

cp "$ROOT/.codex-isolated/hooks.json" "$ICODEX_SHARED_DIR/hooks.json"
printf 'Active mode: **__CAVEMAN_MODE__**.\n' > "$ICODEX_SHARED_DIR/caveman/agents-block.md"
python3 - "$ICODEX_SHARED_DIR/hooks.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as stream:
    data = json.load(stream)
hooks = data.setdefault("hooks", {})
hooks.setdefault("PreToolUse", []).append({
    "matcher": "Bash|Read|Grep|Glob|apply_patch|Edit|Write",
    "hooks": [{"type": "command", "command": "python3 loen-tool-guard.py", "timeout": 30}],
})
hooks.setdefault("PostToolUse", []).append({
    "matcher": "Write|Edit", "hooks": [{"type": "command", "command": "python3 iwiki-update.py"}],
})
with open(path, "w", encoding="utf-8") as stream:
    json.dump(data, stream, indent=2)
    stream.write("\n")
PY
ln -s "$ICODEX_SHARED_DIR/hooks.json" "$ICODEX_HOME_DIR/hooks.json"

source "$ROOT/lib/caveman/caveman.sh"
source "$ROOT/lib/idd/idd.sh"
source "$MODULE"

export ICODEX_CAVEMAN_MODE=full
unset ICODEX_IDD || true
ensure_caveman_wiring
ensure_idd_wiring

before_entries="$(python3 - "$ICODEX_HOME_DIR/hooks.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
print(json.dumps(data["hooks"], separators=(",", ":")))
PY
)"
loen_before="$(python3 - "$ICODEX_HOME_DIR/hooks.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print(json.dumps(next(e for e in data["hooks"]["PreToolUse"] if "loen-tool-guard.py" in str(e)), separators=(",", ":")))
PY
)"
iwiki_before="$(python3 - "$ICODEX_HOME_DIR/hooks.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print(json.dumps(next(e for e in data["hooks"]["PostToolUse"] if "iwiki-update.py" in str(e)), separators=(",", ":")))
PY
)"

ensure_profile_wiring
hooks_file="$ICODEX_HOME_DIR/hooks.json"
assert_exit "profile-composed hooks are valid JSON" 0 python3 -c "import json; json.load(open('$hooks_file'))"

profile_summary="$(python3 - "$hooks_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
command = 'python3 "$CODEX_HOME/hooks/profile-transition.py"'
matches = []
for entry in data.get("hooks", {}).get("PreToolUse", []):
    for hook in entry.get("hooks", []):
        if hook.get("command") == command:
            matches.append((entry, hook))
print(len(matches))
if matches:
    entry, hook = matches[0]
    print(entry.get("matcher", ""))
    print(hook.get("type", ""))
    print(hook.get("timeout", ""))
    print(hook.get("statusMessage", ""))
PY
)"
assert_eq "exactly one profile hook" "1" "$(sed -n '1p' <<<"$profile_summary")"
assert_eq "profile hook matcher is wildcard" "*" "$(sed -n '2p' <<<"$profile_summary")"
assert_eq "profile hook type" "command" "$(sed -n '3p' <<<"$profile_summary")"
assert_eq "profile hook timeout" "30" "$(sed -n '4p' <<<"$profile_summary")"
assert_eq "profile hook status" "Checking routed profile evidence" "$(sed -n '5p' <<<"$profile_summary")"

after_without_profile="$(python3 - "$hooks_file" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
command = 'python3 "$CODEX_HOME/hooks/profile-transition.py"'
data["hooks"]["PreToolUse"] = [
    entry for entry in data["hooks"]["PreToolUse"]
    if not any(hook.get("command") == command for hook in entry.get("hooks", []))
]
print(json.dumps(data["hooks"], separators=(",", ":")))
PY
)"
assert_eq "every existing hook entry preserved" "$before_entries" "$after_without_profile"

loen_after="$(python3 - "$hooks_file" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print(json.dumps(next(e for e in data["hooks"]["PreToolUse"] if "loen-tool-guard.py" in str(e)), separators=(",", ":")))
PY
)"
iwiki_after="$(python3 - "$hooks_file" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print(json.dumps(next(e for e in data["hooks"]["PostToolUse"] if "iwiki-update.py" in str(e)), separators=(",", ":")))
PY
)"
assert_eq "LoEn hook entry byte-equivalent" "$loen_before" "$loen_after"
assert_eq "iwiki hook entry byte-equivalent" "$iwiki_before" "$iwiki_after"

before_hash="$(sha256sum "$hooks_file" | awk '{print $1}')"
ensure_profile_wiring
after_hash="$(sha256sum "$hooks_file" | awk '{print $1}')"
assert_eq "profile wiring idempotent bytes" "$before_hash" "$after_hash"
assert_eq "profile command remains unique" "1" "$(grep -c 'profile-transition.py' "$hooks_file")"
assert_contains "secret hook preserved" "$(cat "$hooks_file")" "block-secrets.py"
assert_contains "redaction hook preserved" "$(cat "$hooks_file")" "redact-secrets.py"
assert_contains "caveman hook preserved" "$(cat "$hooks_file")" "caveman-hook.py"
assert_contains "chain gate preserved" "$(cat "$hooks_file")" "chain-gate.py"

finish

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

profile_summary="$(python3 - "$hooks_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
command = 'python3 "$CODEX_HOME/hooks/profile-transition.py"'
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
after_order_without_profile="$(python3 - "$hooks_file" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
command = 'python3 "$CODEX_HOME/hooks/profile-transition.py"'
for event, entries in data["hooks"].items():
    kept = [entry for entry in entries if not any(
        hook.get("command") == command for hook in entry.get("hooks", [])
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

before_hash="$(sha256sum "$hooks_file" | awk '{print $1}')"
ensure_profile_wiring
after_hash="$(sha256sum "$hooks_file" | awk '{print $1}')"
assert_eq "profile wiring idempotent full bytes" "$before_hash" "$after_hash"
assert_eq "profile command remains unique" "1" "$(grep -c 'profile-transition.py' "$hooks_file")"
assert_contains "base secret hook preserved" "$(cat "$hooks_file")" "block-secrets.py"
assert_contains "base redaction hook preserved" "$(cat "$hooks_file")" "redact-secrets.py"
assert_contains "actual caveman hook preserved" "$(cat "$hooks_file")" "caveman-hook.py"
assert_contains "actual chain gate preserved" "$(cat "$hooks_file")" "chain-gate.py"

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

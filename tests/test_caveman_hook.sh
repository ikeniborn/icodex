#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

HOOK="$ROOT/.codex-isolated/hooks/caveman-hook.py"

# Each run gets a clean CODEX_HOME so the per-session mode file starts empty.
run() { # <launch_mode> <prompt> -> prints "<exit>\n<stdout>"
  local mode="$1" prompt="$2" home out code
  home="$(mktemp -d)"
  out="$(CODEX_HOME="$home" ICODEX_CAVEMAN_MODE="$mode" \
    python3 "$HOOK" <<EOF
{"prompt": $(printf '%s' "$prompt" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'), "session_id": "s1"}
EOF
)"
  code=$?
  printf '%s\n%s' "$code" "$out"
  rm -rf "$home"
}

assert_exit "hook file exists" 0 test -f "$HOOK"

# 1. Steady state: current mode == active launch mode -> zero output.
steady="$(run full "list the files")"
assert_eq  "steady exit 0"      "0" "$(sed -n '1p' <<<"$steady")"
assert_eq  "steady empty stdout" ""  "$(sed -n '2,$p' <<<"$steady")"

# 2. /caveman switch injects the new mode.
switch="$(run full "/caveman lite")"
assert_contains "switch injects additionalContext" "$switch" "additionalContext"
assert_contains "switch names lite"                 "$switch" "lite"

# 3. /caveman off injects a disable line.
off="$(run full "/caveman off")"
assert_contains "off disables" "$off" "DISABLED"

# 4. 'stop caveman' also disables.
stop="$(run full "stop caveman")"
assert_contains "stop caveman disables" "$stop" "DISABLED"

# 5. Persisted deviation: after switching to lite, a later plain turn still injects.
dev_home="$(mktemp -d)"
mkdir -p "$dev_home/.caveman"
printf 'lite' > "$dev_home/.caveman/mode-s1"
dev="$(CODEX_HOME="$dev_home" ICODEX_CAVEMAN_MODE="full" python3 "$HOOK" <<'EOF'
{"prompt": "do the thing", "session_id": "s1"}
EOF
)"
assert_contains "deviation re-injects active mode" "$dev" "lite"
rm -rf "$dev_home"

# 6. Non-dict JSON input (e.g. array) -> exit 0, empty stdout (no-op).
non_dict_home="$(mktemp -d)"
non_dict="$(CODEX_HOME="$non_dict_home" ICODEX_CAVEMAN_MODE="full" \
  python3 "$HOOK" <<< '[]')"
non_dict_code=$?
assert_eq  "non-dict exit 0"      "0" "$non_dict_code"
assert_eq  "non-dict empty stdout" ""  "$(sed -n '2,$p' <<<"$non_dict")"
rm -rf "$non_dict_home"

# 7. Non-string JSON values (e.g. number prompt, number session_id) -> exit 0, empty stdout.
nonstr_home="$(mktemp -d)"
nonstr="$(CODEX_HOME="$nonstr_home" ICODEX_CAVEMAN_MODE="full" python3 "$HOOK" <<'EOF'
{"prompt": 42, "session_id": 99}
EOF
)"
nonstr_code=$?
assert_eq "non-string values exit 0" "0" "$nonstr_code"
assert_eq "non-string values empty stdout" "" "$(sed -n '2,$p' <<<"$nonstr")"
rm -rf "$nonstr_home"

finish

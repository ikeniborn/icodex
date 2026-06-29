#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/core/logging.sh"

# Build a fake shared store + per-project home.
tmp="$(mktemp -d)"
export ICODEX_ROOT="$tmp"
export ICODEX_SHARED_DIR="$tmp/.codex-isolated"
export ICODEX_HOME_DIR="$tmp/.codex-homes/proj"
mkdir -p "$ICODEX_SHARED_DIR/caveman" "$ICODEX_HOME_DIR"

# Shared hooks.json with the existing secret-guard hook (the merge must preserve it).
cat > "$ICODEX_SHARED_DIR/hooks.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "python3 \"$CODEX_HOME/hooks/block-secrets.py\"" } ] }
    ]
  }
}
EOF
# Minimal template with the mode placeholder.
printf 'Active mode: **__CAVEMAN_MODE__**.\n' > "$ICODEX_SHARED_DIR/caveman/agents-block.md"
# Home hooks.json starts as a symlink, like setup_codex_home leaves it.
ln -s "$ICODEX_SHARED_DIR/hooks.json" "$ICODEX_HOME_DIR/hooks.json"

source "$ROOT/lib/caveman/caveman.sh"
agents="$ICODEX_HOME_DIR/AGENTS.md"
hooks="$ICODEX_HOME_DIR/hooks.json"

# 1. Enabled: region rendered, hooks.json merged into a real file.
export ICODEX_CAVEMAN_MODE=full
ensure_caveman_wiring
assert_contains "agents has region start" "$(cat "$agents")" "icodex:caveman:start"
assert_contains "agents substitutes mode" "$(cat "$agents")" "Active mode: **full**"
assert_exit "home hooks.json is a real file" 0 test -f "$hooks"
assert_eq  "home hooks.json is not a symlink" "1" "$([[ -L "$hooks" ]] && echo 0 || echo 1)"
assert_contains "merge keeps secret guard" "$(cat "$hooks")" "block-secrets.py"
assert_contains "merge adds caveman hook"  "$(cat "$hooks")" "caveman-hook.py"
assert_contains "merge wires UserPromptSubmit" "$(cat "$hooks")" "UserPromptSubmit"

# 2. Idempotent: second call leaves both files byte-identical.
a_before="$(cat "$agents")"; h_before="$(cat "$hooks")"
ensure_caveman_wiring
assert_eq "agents idempotent" "$a_before" "$(cat "$agents")"
assert_eq "hooks idempotent"  "$h_before" "$(cat "$hooks")"

# 3. Disabled: region removed, hooks.json restored to a symlink.
unset ICODEX_CAVEMAN_MODE
ensure_caveman_wiring
assert_eq "agents region removed" "0" "$(grep -c 'icodex:caveman:start' "$agents" 2>/dev/null || echo 0)"
assert_eq "home hooks.json back to symlink" "0" "$([[ -L "$hooks" ]] && echo 0 || echo 1)"

rm -rf "$tmp"
finish

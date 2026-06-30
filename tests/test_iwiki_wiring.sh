#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

assert_exit "iwiki module exists" 0 test -f "$ROOT/lib/iwiki/iwiki.sh"
if [[ ! -f "$ROOT/lib/iwiki/iwiki.sh" ]]; then
  finish; exit $?
fi
source "$ROOT/lib/iwiki/iwiki.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- inserts the region into an existing config.toml ---
export ICODEX_HOME_DIR="$tmp/home"
mkdir -p "$ICODEX_HOME_DIR"
printf 'model = "gpt-5.5"\n[features]\nmulti_agent = true\n' > "$ICODEX_HOME_DIR/config.toml"
ensure_iwiki_wiring
cfg="$(cat "$ICODEX_HOME_DIR/config.toml")"
assert_contains "block header present"  "$cfg" "[mcp_servers.iwiki]"
assert_contains "command present"       "$cfg" "/home/ikeniborn/.local/bin/iwiki-mcp"
assert_contains "env_vars present"      "$cfg" 'env_vars = ["IWIKI_LLM_KEY"]'
assert_contains "base dir present"      "$cfg" "IWIKI_BASE_DIR"
assert_contains "original key kept"     "$cfg" 'model = "gpt-5.5"'
assert_eq "exactly one start marker" "1" "$(grep -c '# icodex:iwiki:start' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "region is at end of file" "# icodex:iwiki:end" "$(tail -n1 "$ICODEX_HOME_DIR/config.toml")"

# --- idempotent: second run is byte-identical ---
before="$(cat "$ICODEX_HOME_DIR/config.toml")"
ensure_iwiki_wiring
after="$(cat "$ICODEX_HOME_DIR/config.toml")"
assert_eq "idempotent second run" "$before" "$after"
assert_eq "still one start marker" "1" "$(grep -c '# icodex:iwiki:start' "$ICODEX_HOME_DIR/config.toml")"

# --- stale region is replaced, not duplicated ---
cat > "$ICODEX_HOME_DIR/config.toml" <<'EOF'
model = "gpt-5.5"
# icodex:iwiki:start
[mcp_servers.iwiki]
command = "/old/path/iwiki-mcp"
# icodex:iwiki:end
EOF
ensure_iwiki_wiring
cfg="$(cat "$ICODEX_HOME_DIR/config.toml")"
assert_eq "stale: one start marker" "1" "$(grep -c '# icodex:iwiki:start' "$ICODEX_HOME_DIR/config.toml")"
assert_contains "stale: new command" "$cfg" "/home/ikeniborn/.local/bin/iwiki-mcp"
assert_eq "stale: old command gone" "0" "$(grep -c '/old/path/iwiki-mcp' "$ICODEX_HOME_DIR/config.toml")"

# --- no-op when home is unset ---
unset ICODEX_HOME_DIR
assert_exit "unset home -> noop 0" 0 ensure_iwiki_wiring

# --- no-op when config.toml is absent ---
export ICODEX_HOME_DIR="$tmp/empty"
mkdir -p "$ICODEX_HOME_DIR"
assert_exit "absent config -> noop 0" 0 ensure_iwiki_wiring
assert_eq "absent config not created" "1" "$([[ -f "$ICODEX_HOME_DIR/config.toml" ]] && echo 0 || echo 1)"

finish

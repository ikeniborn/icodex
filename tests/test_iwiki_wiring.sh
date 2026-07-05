#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

assert_exit "iwiki module exists" 0 test -f "$ROOT/lib/iwiki/iwiki.sh"
if [[ ! -f "$ROOT/lib/iwiki/iwiki.sh" ]]; then
  finish; exit $?
fi
source "$ROOT/lib/core/logging.sh"   # provides log_warn used by the guard
source "$ROOT/lib/iwiki/iwiki.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Required tier + command driven explicitly. Two optional passthrough vars are set;
# the other six are unset and must be OMITTED (server default applies).
export ICODEX_IWIKI_COMMAND="$tmp/bin/iwiki-mcp"
export ICODEX_IWIKI_BASE_DIR="$tmp/wiki-base"
export ICODEX_IWIKI_LLM_BASE_URL="http://test-llm:1234/v1"
export ICODEX_IWIKI_LLM_KEY="test-key"
export ICODEX_IWIKI_EMBED_MODEL="ollama-bge-m3"
export ICODEX_IWIKI_TOP_K="5"
unset ICODEX_IWIKI_EMBED_DIMENSIONS ICODEX_IWIKI_SCORE_THRESHOLD \
      ICODEX_IWIKI_GRAPH_DEPTH ICODEX_IWIKI_CHUNK_SIZE \
      ICODEX_IWIKI_CHUNK_OVERLAP ICODEX_IWIKI_SUMMARY_MAX_CHARS

export ICODEX_HOME_DIR="$tmp/home"
mkdir -p "$ICODEX_HOME_DIR"
printf 'model = "gpt-5.5"\n[features]\nmulti_agent = true\n' > "$ICODEX_HOME_DIR/config.toml"
ensure_iwiki_wiring
cfg="$(cat "$ICODEX_HOME_DIR/config.toml")"
assert_contains "block header present"     "$cfg" "[mcp_servers.iwiki]"
assert_contains "resolved command"         "$cfg" "command = \"$tmp/bin/iwiki-mcp\""
assert_contains "env_vars present"         "$cfg" 'env_vars = ["IWIKI_LLM_KEY"]'
assert_contains "resolved base dir"        "$cfg" "IWIKI_BASE_DIR = \"$tmp/wiki-base\""
assert_contains "resolved llm url"         "$cfg" 'IWIKI_LLM_BASE_URL = "http://test-llm:1234/v1"'
assert_contains "set optional embed model" "$cfg" 'IWIKI_EMBED_MODEL = "ollama-bge-m3"'
assert_contains "set optional top_k"       "$cfg" 'IWIKI_TOP_K = "5"'
assert_eq "unset optional dims absent"    "0" "$(grep -c 'IWIKI_EMBED_DIMENSIONS' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "unset optional chunk absent"   "0" "$(grep -c 'IWIKI_CHUNK_SIZE' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "unset optional summary absent" "0" "$(grep -c 'IWIKI_SUMMARY_MAX_CHARS' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "secret not written literally"  "0" "$(grep -c 'test-key' "$ICODEX_HOME_DIR/config.toml")"
assert_contains "original key kept"        "$cfg" 'model = "gpt-5.5"'
assert_eq "no hardcoded home path" "0" "$(grep -c '/home/ikeniborn' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "exactly one start marker" "1" "$(grep -c '# icodex:iwiki:start' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "region is at end of file" "# icodex:iwiki:end" "$(tail -n1 "$ICODEX_HOME_DIR/config.toml")"

# --- idempotent: second run is byte-identical ---
before="$(cat "$ICODEX_HOME_DIR/config.toml")"
ensure_iwiki_wiring
after="$(cat "$ICODEX_HOME_DIR/config.toml")"
assert_eq "idempotent second run" "$before" "$after"

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
assert_contains "stale: new command" "$cfg" "command = \"$tmp/bin/iwiki-mcp\""
assert_eq "stale: old command gone" "0" "$(grep -c '/old/path/iwiki-mcp' "$ICODEX_HOME_DIR/config.toml")"

# --- stale unmarked iwiki tables are removed before adding the managed region ---
cat > "$ICODEX_HOME_DIR/config.toml" <<'EOF'
model = "gpt-5.5"
[mcp_servers.iwiki]
command = "/old/unmarked/iwiki-mcp"
env_vars = ["IWIKI_LLM_KEY"]
[mcp_servers.iwiki.env]
IWIKI_BASE_DIR = "/old/wiki"
IWIKI_LLM_BASE_URL = "https://old.example/v1"

[mcp_servers.other]
command = "/bin/true"
EOF
ensure_iwiki_wiring
cfg="$(cat "$ICODEX_HOME_DIR/config.toml")"
assert_eq "unmarked stale: exactly one iwiki table" "1" "$(grep -cF '[mcp_servers.iwiki]' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "unmarked stale: exactly one iwiki env table" "1" "$(grep -cF '[mcp_servers.iwiki.env]' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "unmarked stale: old command gone" "0" "$(grep -c '/old/unmarked/iwiki-mcp' "$ICODEX_HOME_DIR/config.toml")"
assert_contains "unmarked stale: other mcp kept" "$cfg" "[mcp_servers.other]"
assert_contains "unmarked stale: managed marker present" "$cfg" "# icodex:iwiki:start"

# --- command auto-detected from PATH when ICODEX_IWIKI_COMMAND is unset ---
mkdir -p "$tmp/fakebin"
printf '#!/usr/bin/env bash\n' > "$tmp/fakebin/iwiki-mcp"
chmod +x "$tmp/fakebin/iwiki-mcp"
unset ICODEX_IWIKI_COMMAND
export ICODEX_HOME_DIR="$tmp/home-auto"
mkdir -p "$ICODEX_HOME_DIR"
printf 'model = "x"\n' > "$ICODEX_HOME_DIR/config.toml"
PATH="$tmp/fakebin:$PATH" ensure_iwiki_wiring
cfg="$(cat "$ICODEX_HOME_DIR/config.toml")"
assert_contains "auto-detected command from PATH" "$cfg" "command = \"$tmp/fakebin/iwiki-mcp\""
export ICODEX_IWIKI_COMMAND="$tmp/bin/iwiki-mcp"

# --- guard: missing required llm_base_url -> no region, returns 0 ---
unset ICODEX_IWIKI_LLM_BASE_URL
export ICODEX_HOME_DIR="$tmp/home-guard-url"
mkdir -p "$ICODEX_HOME_DIR"
printf 'model = "x"\n' > "$ICODEX_HOME_DIR/config.toml"
assert_exit "missing url -> noop 0" 0 ensure_iwiki_wiring
assert_eq "guard url: no region" "0" "$(grep -cF '[mcp_servers.iwiki]' "$ICODEX_HOME_DIR/config.toml")"
export ICODEX_IWIKI_LLM_BASE_URL="http://test-llm:1234/v1"

# --- guard: missing required llm_key -> no region, returns 0 ---
unset ICODEX_IWIKI_LLM_KEY IWIKI_LLM_KEY
export ICODEX_HOME_DIR="$tmp/home-guard-key"
mkdir -p "$ICODEX_HOME_DIR"
printf 'model = "x"\n' > "$ICODEX_HOME_DIR/config.toml"
assert_exit "missing key -> noop 0" 0 ensure_iwiki_wiring
assert_eq "guard key: no region" "0" "$(grep -cF '[mcp_servers.iwiki]' "$ICODEX_HOME_DIR/config.toml")"
export ICODEX_IWIKI_LLM_KEY="test-key"

# --- no-op when home is unset ---
unset ICODEX_HOME_DIR
assert_exit "unset home -> noop 0" 0 ensure_iwiki_wiring

# --- no-op when config.toml is absent ---
export ICODEX_HOME_DIR="$tmp/empty"
mkdir -p "$ICODEX_HOME_DIR"
assert_exit "absent config -> noop 0" 0 ensure_iwiki_wiring
assert_eq "absent config not created" "1" "$([[ -f "$ICODEX_HOME_DIR/config.toml" ]] && echo 0 || echo 1)"

# --- regression: under the launcher's `set -e`, wiring must not abort when the
# --- LAST optional var is unset (a `[[..]] && cmd` tail would return non-zero) ---
(
  set -euo pipefail
  export ICODEX_IWIKI_COMMAND="$tmp/bin/iwiki-mcp"
  export ICODEX_IWIKI_BASE_DIR="$tmp/wiki-base"
  export ICODEX_IWIKI_LLM_BASE_URL="http://test-llm:1234/v1"
  export ICODEX_IWIKI_LLM_KEY="test-key"
  unset ICODEX_IWIKI_EMBED_MODEL ICODEX_IWIKI_EMBED_DIMENSIONS ICODEX_IWIKI_TOP_K \
        ICODEX_IWIKI_SCORE_THRESHOLD ICODEX_IWIKI_GRAPH_DEPTH ICODEX_IWIKI_CHUNK_SIZE \
        ICODEX_IWIKI_CHUNK_OVERLAP ICODEX_IWIKI_SUMMARY_MAX_CHARS
  export ICODEX_HOME_DIR="$tmp/home-sete"
  mkdir -p "$ICODEX_HOME_DIR"
  printf 'model = "x"\n' > "$ICODEX_HOME_DIR/config.toml"
  ensure_iwiki_wiring
)
assert_eq "wiring survives set -e with all optionals unset" "0" "$?"

finish

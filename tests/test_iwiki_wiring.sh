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

# Local wiring cases must not inherit an operator's remote client configuration.
unset ICODEX_IWIKI_REMOTE_URL ICODEX_IWIKI_REMOTE_TOKEN IWIKI_REMOTE_TOKEN

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Required tier + command driven explicitly. Optional passthrough vars are set;
# the absent set below must be OMITTED (server default applies).
export ICODEX_IWIKI_COMMAND="$tmp/bin/iwiki-mcp"
export ICODEX_IWIKI_BASE_DIR="$tmp/wiki-base"
export ICODEX_IWIKI_LLM_BASE_URL="http://test-llm:1234/v1"
export ICODEX_IWIKI_LLM_KEY="test-key"
export ICODEX_PROJECT_ROOT="$tmp/project-root"
export ICODEX_IWIKI_PROJECT_DIR="$tmp/wrong-project"
mkdir -p "$ICODEX_PROJECT_ROOT"
export ICODEX_IWIKI_EMBED_MODEL="ollama-bge-m3"
export ICODEX_IWIKI_TOP_K="5"
export ICODEX_IWIKI_SEARCH_MODE="semantic"
export ICODEX_IWIKI_RERANK_MODEL="rerank-test-model"
export ICODEX_IWIKI_IDLE_TIMEOUT_SECONDS="0"
export ICODEX_IWIKI_SEED_TOP_K="7"
export ICODEX_IWIKI_BFS_TOP_K="11"
export ICODEX_IWIKI_SEED_THRESHOLD="0.17"
export ICODEX_IWIKI_WRITE_SEED_THRESHOLD="0.37"
export ICODEX_IWIKI_CHAT_MODEL="chat-test-model"
export ICODEX_IWIKI_CODE_GRAPH_ENABLED="false"
export ICODEX_IWIKI_CODE_GRAPH_MAX_FILE_BYTES="2000000"
export ICODEX_IWIKI_CODE_GRAPH_MAX_FILES="5000"
export ICODEX_IWIKI_CODE_GRAPH_AUTO_REBUILD="off"
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
assert_contains "secret env_vars present"  "$cfg" 'env_vars = ["IWIKI_LLM_KEY", "IWIKI_DB_PASSWORD"]'
assert_contains "resolved base dir"        "$cfg" "IWIKI_BASE_DIR = \"$tmp/wiki-base\""
assert_contains "resolved llm url"         "$cfg" 'IWIKI_LLM_BASE_URL = "http://test-llm:1234/v1"'
assert_contains "resolved project dir"     "$cfg" "IWIKI_PROJECT_DIR = \"$tmp/project-root\""
assert_contains "set optional embed model" "$cfg" 'IWIKI_EMBED_MODEL = "ollama-bge-m3"'
assert_contains "set optional top_k"       "$cfg" 'IWIKI_TOP_K = "5"'
assert_contains "set optional search mode" "$cfg" 'IWIKI_SEARCH_MODE = "semantic"'
assert_contains "set optional rerank model" "$cfg" 'IWIKI_RERANK_MODEL = "rerank-test-model"'
assert_contains "set optional idle timeout" "$cfg" 'IWIKI_IDLE_TIMEOUT_SECONDS = "0"'
assert_contains "set optional seed top k" "$cfg" 'IWIKI_SEED_TOP_K = "7"'
assert_contains "set optional bfs top k" "$cfg" 'IWIKI_BFS_TOP_K = "11"'
assert_contains "set optional seed threshold" "$cfg" 'IWIKI_SEED_THRESHOLD = "0.17"'
assert_contains "set optional write seed threshold" "$cfg" 'IWIKI_WRITE_SEED_THRESHOLD = "0.37"'
assert_contains "set optional chat model" "$cfg" 'IWIKI_CHAT_MODEL = "chat-test-model"'
assert_contains "set code graph enabled" "$cfg" 'IWIKI_CODE_GRAPH_ENABLED = "false"'
assert_contains "set code graph max file bytes" "$cfg" 'IWIKI_CODE_GRAPH_MAX_FILE_BYTES = "2000000"'
assert_contains "set code graph max files" "$cfg" 'IWIKI_CODE_GRAPH_MAX_FILES = "5000"'
assert_contains "set code graph auto rebuild" "$cfg" 'IWIKI_CODE_GRAPH_AUTO_REBUILD = "off"'
assert_eq "manual project dir ignored" "0" "$(grep -cF "$tmp/wrong-project" "$ICODEX_HOME_DIR/config.toml")"
assert_eq "unset optional dims absent"    "0" "$(grep -c 'IWIKI_EMBED_DIMENSIONS' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "unset optional chunk absent"   "0" "$(grep -c 'IWIKI_CHUNK_SIZE' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "unset optional summary absent" "0" "$(grep -c 'IWIKI_SUMMARY_MAX_CHARS' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "unset optional graph absent" "0" "$(grep -c 'IWIKI_GRAPH_DEPTH' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "unset optional score absent" "0" "$(grep -c 'IWIKI_SCORE_THRESHOLD' "$ICODEX_HOME_DIR/config.toml")"
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

# --- guard: missing project root -> no region, returns 0 ---
unset ICODEX_PROJECT_ROOT
export ICODEX_HOME_DIR="$tmp/home-guard-project"
mkdir -p "$ICODEX_HOME_DIR"
printf 'model = "x"\n' > "$ICODEX_HOME_DIR/config.toml"
assert_exit "missing project root -> noop 0" 0 ensure_iwiki_wiring
assert_eq "guard project: no region" "0" "$(grep -cF '[mcp_servers.iwiki]' "$ICODEX_HOME_DIR/config.toml")"
export ICODEX_PROJECT_ROOT="$tmp/project-root"
unset ICODEX_IWIKI_PROJECT_DIR

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
  export ICODEX_PROJECT_ROOT="$tmp/project-root"
  unset ICODEX_IWIKI_EMBED_MODEL ICODEX_IWIKI_EMBED_DIMENSIONS ICODEX_IWIKI_TOP_K \
        ICODEX_IWIKI_SEARCH_MODE ICODEX_IWIKI_RERANK_MODEL ICODEX_IWIKI_SEED_TOP_K \
        ICODEX_IWIKI_BFS_TOP_K ICODEX_IWIKI_SEED_THRESHOLD \
        ICODEX_IWIKI_WRITE_SEED_THRESHOLD ICODEX_IWIKI_CHAT_MODEL \
        ICODEX_IWIKI_SCORE_THRESHOLD ICODEX_IWIKI_GRAPH_DEPTH ICODEX_IWIKI_CHUNK_SIZE \
        ICODEX_IWIKI_CHUNK_OVERLAP ICODEX_IWIKI_SUMMARY_MAX_CHARS \
        ICODEX_IWIKI_CODE_GRAPH_ENABLED ICODEX_IWIKI_CODE_GRAPH_MAX_FILE_BYTES \
        ICODEX_IWIKI_CODE_GRAPH_MAX_FILES ICODEX_IWIKI_CODE_GRAPH_AUTO_REBUILD
  export ICODEX_HOME_DIR="$tmp/home-sete"
  mkdir -p "$ICODEX_HOME_DIR"
  printf 'model = "x"\n' > "$ICODEX_HOME_DIR/config.toml"
  ensure_iwiki_wiring
)
assert_eq "wiring survives set -e with all optionals unset" "0" "$?"

# --- PostgreSQL binding forwards DB password as a secret and does not require a Git base ---
export ICODEX_HOME_DIR="$tmp/home-postgres"
export ICODEX_PROJECT_ROOT="$tmp/project-postgres"
export ICODEX_IWIKI_DB_PASSWORD="db-test-secret"
unset ICODEX_IWIKI_BASE_DIR
mkdir -p "$ICODEX_HOME_DIR" "$ICODEX_PROJECT_ROOT"
printf 'model = "x"\n' > "$ICODEX_HOME_DIR/config.toml"
cat > "$ICODEX_PROJECT_ROOT/.iwiki.toml" <<'EOF'
read = ["postgres-domain"]
write = ["postgres-domain"]
primary = "postgres-domain"

[storage]
type = "postgres"
host = "db.invalid"
port = 5432
database = "iwiki"
user = "iwiki"
sslmode = "require"
iwiki_id = "test-wiki"
EOF
ensure_iwiki_wiring
cfg="$(cat "$ICODEX_HOME_DIR/config.toml")"
assert_contains "postgres block present" "$cfg" '[mcp_servers.iwiki]'
assert_contains "postgres forwards both secret names" "$cfg" 'env_vars = ["IWIKI_LLM_KEY", "IWIKI_DB_PASSWORD"]'
assert_eq "postgres has no Git base" "0" "$(grep -c 'IWIKI_BASE_DIR' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "postgres DB secret not written literally" "0" "$(grep -c 'db-test-secret' "$ICODEX_HOME_DIR/config.toml")"
unset ICODEX_IWIKI_DB_PASSWORD

# --- remote URL switches the managed iwiki server from local stdio to HTTPS MCP ---
export ICODEX_HOME_DIR="$tmp/home-remote"
export ICODEX_PROJECT_ROOT="$tmp/project-remote"
export ICODEX_IWIKI_REMOTE_URL="https://iwiki.example.com/mcp"
export ICODEX_IWIKI_REMOTE_TOKEN="remote-test-token"
unset ICODEX_IWIKI_BASE_DIR ICODEX_IWIKI_LLM_BASE_URL ICODEX_IWIKI_LLM_KEY
mkdir -p "$ICODEX_HOME_DIR" "$ICODEX_PROJECT_ROOT"
printf 'model = "x"\n' > "$ICODEX_HOME_DIR/config.toml"
ensure_iwiki_wiring
cfg="$(cat "$ICODEX_HOME_DIR/config.toml")"
assert_contains "remote URL configured" "$cfg" 'url = "https://iwiki.example.com/mcp"'
assert_contains "remote token env configured" "$cfg" 'bearer_token_env_var = "IWIKI_REMOTE_TOKEN"'
assert_eq "remote has no stdio command" "0" "$(grep -c '^command =' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "remote has no local env vars" "0" "$(grep -c '^env_vars =' "$ICODEX_HOME_DIR/config.toml")"
assert_eq "remote token not written literally" "0" "$(grep -c 'remote-test-token' "$ICODEX_HOME_DIR/config.toml")"
unset ICODEX_IWIKI_REMOTE_URL ICODEX_IWIKI_REMOTE_TOKEN

finish

#!/usr/bin/env bash
# Wire the iwiki MCP server into the per-project Codex home config.toml at launch.
# Always on: a delimited region registers [mcp_servers.iwiki]. The block is built
# from ICODEX_IWIKI_* config: command falls back to `command -v iwiki-mcp`;
# IWIKI_BASE_DIR / IWIKI_LLM_BASE_URL and the secret IWIKI_LLM_KEY are required
# (any unresolved -> warn + skip). Every other IWIKI_* server var is written only
# when its ICODEX_IWIKI_* is set, else the server default applies. The secret is
# forwarded via env_vars (mapped by apply_iwiki_env in lib/config/env.sh), never
# written literally. Mirrors the region mechanism in lib/config/isolated.sh
# (_sync_agents_base_region).

_IWIKI_REGION_START="# icodex:iwiki:start"
_IWIKI_REGION_END="# icodex:iwiki:end"

# Optional IWIKI_* server vars (each has a server-side default). Written only when
# the matching ICODEX_IWIKI_<NAME> is set. Extend this list to expose new vars.
_IWIKI_OPTIONAL_VARS="EMBED_MODEL EMBED_DIMENSIONS TOP_K SCORE_THRESHOLD GRAPH_DEPTH CHUNK_SIZE CHUNK_OVERLAP SUMMARY_MAX_CHARS"

# Emit the [mcp_servers.iwiki] block (without the region markers) from resolved
# values. command/env_vars precede the [.env] subtable header so they bind to the
# parent table, not the subtable. Optional vars are appended only when set.
_iwiki_region_body() { # <command> <base_dir> <llm_base_url>
  local cmd="$1" base="$2" url="$3" name cfg val
  printf '[mcp_servers.iwiki]\n'
  printf 'command = "%s"\n' "$cmd"
  printf 'env_vars = ["IWIKI_LLM_KEY"]\n'
  printf '[mcp_servers.iwiki.env]\n'
  printf 'IWIKI_BASE_DIR = "%s"\n' "$base"
  printf 'IWIKI_LLM_BASE_URL = "%s"\n' "$url"
  for name in $_IWIKI_OPTIONAL_VARS; do
    cfg="ICODEX_IWIKI_${name}"
    val="${!cfg:-}"
    [[ -n "$val" ]] && printf 'IWIKI_%s = "%s"\n' "$name" "$val"
  done
}

# Strip any existing iwiki region from the home config.toml, then append a fresh
# one at the end of the file. Idempotent: rewrites only when the content differs.
# No-op when ICODEX_HOME_DIR is unset or the config file does not exist.
ensure_iwiki_wiring() {
  [[ -n "${ICODEX_HOME_DIR:-}" ]] || return 0
  local file="$ICODEX_HOME_DIR/config.toml" body tmp cmd base url key
  [[ -f "$file" ]] || return 0
  cmd="${ICODEX_IWIKI_COMMAND:-$(command -v iwiki-mcp || true)}"
  base="${ICODEX_IWIKI_BASE_DIR:-}"
  url="${ICODEX_IWIKI_LLM_BASE_URL:-}"
  key="${ICODEX_IWIKI_LLM_KEY:-${IWIKI_LLM_KEY:-}}"
  if [[ -z "$cmd" || -z "$base" || -z "$url" || -z "$key" ]]; then
    log_warn "iwiki: required setting (command/base_dir/llm_base_url/llm_key) unresolved, skipping iwiki wiring"
    return 0
  fi
  body="$(_iwiki_region_body "$cmd" "$base" "$url")"
  tmp="$(mktemp)"
  awk -v s="$_IWIKI_REGION_START" -v e="$_IWIKI_REGION_END" '
    $0 == s { skip=1; next }
    $0 == e { skip=0; next }
    !skip { print }
  ' "$file" > "$tmp"
  printf '%s\n%s\n%s\n' "$_IWIKI_REGION_START" "$body" "$_IWIKI_REGION_END" >> "$tmp"
  if ! cmp -s "$tmp" "$file"; then
    cat "$tmp" > "$file"
  fi
  rm -f "$tmp"
}

# Seed a project-root .iwiki.toml (domain == project basename) when absent and
# symlink it into the Codex home so the iwiki MCP server (cwd == CODEX_HOME)
# resolves the per-project read/write binding. Never overwrites an existing
# project .iwiki.toml (it is the user's truth, e.g. a prior wiki_bind). No-op
# when the project root or home is unknown.
ensure_iwiki_binding() {
  [[ -n "${ICODEX_PROJECT_ROOT:-}" && -n "${ICODEX_HOME_DIR:-}" ]] || return 0
  local toml="$ICODEX_PROJECT_ROOT/.iwiki.toml" link="$ICODEX_HOME_DIR/.iwiki.toml" domain
  domain="$(basename "$ICODEX_PROJECT_ROOT")"
  if [[ ! -e "$toml" ]]; then
    printf 'read = ["%s"]\nwrite = "%s"\n' "$domain" "$domain" > "$toml"
  fi
  if [[ -L "$link" ]]; then
    [[ "$(readlink "$link")" == "$toml" ]] || { rm -f "$link"; ln -s "$toml" "$link"; }
  elif [[ ! -e "$link" ]]; then
    ln -s "$toml" "$link"
  fi
}

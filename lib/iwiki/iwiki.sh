#!/usr/bin/env bash
# Wire the iwiki MCP server into the per-project Codex home config.toml at launch.
# Always on: a delimited region registers [mcp_servers.iwiki]. Non-secret settings
# are literal; the secret IWIKI_LLM_KEY is forwarded from the environment via
# env_vars (mapped by apply_iwiki_env in lib/config/env.sh). Mirrors the region
# mechanism in lib/config/isolated.sh (_sync_agents_base_region).

_IWIKI_REGION_START="# icodex:iwiki:start"
_IWIKI_REGION_END="# icodex:iwiki:end"

# Emit the static [mcp_servers.iwiki] block (without the region markers).
# command/env_vars precede the [.env] subtable header so they bind to the
# parent table, not the subtable.
_iwiki_region_body() {
  cat <<'EOF'
[mcp_servers.iwiki]
command = "/home/ikeniborn/.local/bin/iwiki-mcp"
env_vars = ["IWIKI_LLM_KEY"]
[mcp_servers.iwiki.env]
IWIKI_BASE_DIR = "/home/ikeniborn/Documents/Project/iwiki-personal"
IWIKI_LLM_BASE_URL = "https://litellm.ikeniborn.ru/v1"
IWIKI_EMBED_MODEL = "ollama-bge-m3"
IWIKI_EMBED_DIMENSIONS = "1024"
EOF
}

# Strip any existing iwiki region from the home config.toml, then append a fresh
# one at the end of the file. Idempotent: rewrites only when the content differs.
# No-op when ICODEX_HOME_DIR is unset or the config file does not exist.
ensure_iwiki_wiring() {
  [[ -n "${ICODEX_HOME_DIR:-}" ]] || return 0
  local file="$ICODEX_HOME_DIR/config.toml" body tmp
  [[ -f "$file" ]] || return 0
  body="$(_iwiki_region_body)"
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

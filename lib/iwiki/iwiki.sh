#!/usr/bin/env bash
# Wire the iwiki MCP server into the per-project Codex home config.toml at launch.
# Always on: a delimited region registers [mcp_servers.iwiki]. The block is built
# from ICODEX_IWIKI_* config: command falls back to `command -v iwiki-mcp`;
# IWIKI_LLM_BASE_URL, generated IWIKI_PROJECT_DIR, and secret IWIKI_LLM_KEY are
# required. Git bindings also require IWIKI_BASE_DIR; PostgreSQL bindings require
# secret IWIKI_DB_PASSWORD instead. Every other IWIKI_* server var is written only
# when its ICODEX_IWIKI_* is set, else the
# server default applies. The secret is forwarded via env_vars (mapped by
# apply_iwiki_env in lib/config/env.sh), never written literally. IWIKI_PROJECT_DIR
# is generated from ICODEX_PROJECT_ROOT so Codex-spawned iwiki-mcp resolves the
# project .iwiki.toml even when its cwd is CODEX_HOME. Mirrors the region
# mechanism in lib/config/isolated.sh (_sync_agents_base_region).

_IWIKI_REGION_START="# icodex:iwiki:start"
_IWIKI_REGION_END="# icodex:iwiki:end"
_IWIKI_REMOTE_SCOPE_REGION_START="<!-- icodex:iwiki-remote-scope:start -->"
_IWIKI_REMOTE_SCOPE_REGION_END="<!-- icodex:iwiki-remote-scope:end -->"
_IWIKI_GWT_GATE='python3 "$CODEX_HOME/hooks/gwt-gate.py"'
_IWIKI_GWT_POST='python3 "$CODEX_HOME/hooks/gwt-gate.py" --post'

# Optional IWIKI_* server vars (each has a server-side default). Written only when
# the matching ICODEX_IWIKI_<NAME> is set. Extend this list to expose new vars.
_IWIKI_OPTIONAL_VARS="EMBED_MODEL EMBED_DIMENSIONS TOP_K SCORE_THRESHOLD SEARCH_MODE RERANK_MODEL IDLE_TIMEOUT_SECONDS GRAPH_DEPTH SEED_TOP_K BFS_TOP_K SEED_THRESHOLD WRITE_SEED_THRESHOLD CHAT_MODEL CHUNK_SIZE CHUNK_OVERLAP SUMMARY_MAX_CHARS CODE_GRAPH_ENABLED CODE_GRAPH_MAX_FILE_BYTES CODE_GRAPH_MAX_FILES CODE_GRAPH_AUTO_REBUILD"

# Emit the [mcp_servers.iwiki] block (without the region markers) from resolved
# values. command/env_vars precede the [.env] subtable header so they bind to the
# parent table, not the subtable. Optional vars are appended only when set.
_iwiki_region_body() { # <command> <base_dir> <llm_base_url> <project_dir>
  local cmd="$1" base="$2" url="$3" project="$4" name cfg val
  printf '[mcp_servers.iwiki]\n'
  printf 'command = "%s"\n' "$cmd"
  printf 'env_vars = ["IWIKI_LLM_KEY", "IWIKI_DB_PASSWORD"]\n'
  printf '[mcp_servers.iwiki.env]\n'
  if [[ -n "$base" ]]; then
    printf 'IWIKI_BASE_DIR = "%s"\n' "$base"
  fi
  printf 'IWIKI_LLM_BASE_URL = "%s"\n' "$url"
  printf 'IWIKI_PROJECT_DIR = "%s"\n' "$project"
  for name in $_IWIKI_OPTIONAL_VARS; do
    cfg="ICODEX_IWIKI_${name}"
    val="${!cfg:-}"
    # Use an if-block (not `[[ ... ]] && cmd`): a false test on the LAST iteration
    # would make the function exit non-zero, which under the launcher's `set -e`
    # aborts `body="$(_iwiki_region_body ...)"` and silently kills the launch.
    if [[ -n "$val" ]]; then
      printf 'IWIKI_%s = "%s"\n' "$name" "$val"
    fi
  done
}

_iwiki_remote_region_body() { # <remote-url>
  local remote_url="$1"
  printf '[mcp_servers.iwiki]\n'
  printf 'url = "%s"\n' "$remote_url"
  printf 'bearer_token_env_var = "IWIKI_REMOTE_TOKEN"\n'
}

_iwiki_strip_remote_scope_instructions() { # <agents-file>
  local file="$1"
  awk -v s="$_IWIKI_REMOTE_SCOPE_REGION_START" -v e="$_IWIKI_REMOTE_SCOPE_REGION_END" '
    $0 == s { in_region=1; next }
    $0 == e { in_region=0; next }
    !in_region { print }
  ' "$file"
}

# Remote HTTP servers authorize grants, but agents must select the complete project
# scope before their first wiki call. Keep this generated instruction out of
# config.toml so neither project metadata nor credentials can leak there.
ensure_iwiki_remote_scope_instructions() {
  [[ -n "${ICODEX_HOME_DIR:-}" ]] || return 0
  local file="$ICODEX_HOME_DIR/AGENTS.md" tmp
  [[ -f "$file" ]] || return 0
  tmp="$(mktemp)"
  _iwiki_strip_remote_scope_instructions "$file" > "$tmp"
  if [[ -n "${ICODEX_IWIKI_REMOTE_URL:-}" ]]; then
    cat >> "$tmp" <<'EOF'
<!-- icodex:iwiki-remote-scope:start -->

## Remote iwiki project scope

Before the first wiki call, load `read`, `write`, `primary`, and optional `[specifications].mode` from the project-root `.iwiki.toml`. Normalize domain names before passing them to `wiki_bind`; never pass TOML text, paths, `iwiki_id`, tokens, or other credentials. Call `wiki_bind` with the full normalized `read`, `write`, and `primary` values from `.iwiki.toml`, and pass `[specifications].mode` as `specification_mode` to hosted HTTP `wiki_bind`, before `wiki_status`, `wiki_search`, task-ledger, or any other wiki call.

Do not infer, broaden, or replace that scope with a project name, primary domain, or current session scope. On a missing or invalid TOML scope or a rejected bind (including 403), show a brief reason, do not make mutating wiki calls and retain task lifecycle `completion-pending`. If the `specification_mode` parameter is unavailable or `wiki_status` reports a mode mismatch, make no mutating specification call and retain task lifecycle `completion-pending`; ordinary Wiki work remains available. The remote server's token grants remain the absolute authorization limit.

Take the effective mode per domain from the `specifications` block of `wiki_status`, never from the project file. Hosted precedence is exact override, then the carried project mode, then hosted default, then the built-in `optional`; the server gates the carried mode with `allow_project_mode` and a tighten-only guard and reports a refused value as `project_mode_suppressed: true`. `source: project` confirms the carried mode answered; `source: hosted_override` is a legitimate server decision that outranks it, not a mismatch.

Hosted page mutations use PostgreSQL compare-and-swap. Read the current page immediately before `wiki_update_page`, `wiki_insert_section`, `wiki_move_section`, `wiki_delete_section`, or `wiki_delete_page`, and pass its current `revision` as `expected_revision`. When protecting one heading, also pass the `section_hash` returned by `wiki_read_page(..., heading=...)` as `expected_section_hash`; re-read after `conflict` or `section_conflict`.

`wiki_code_status`, `wiki_code_search`, and `wiki_code_context` read the published hosted snapshot. `wiki_code_index` returns `source_unavailable` because a hosted server has no client checkout; run indexing through a local MCP server instead. PostgreSQL writes are already durable, so do not call Git-only `wiki_sync` or OKF maintenance tools.

<!-- icodex:iwiki-remote-scope:end -->
EOF
  fi
  if ! cmp -s "$tmp" "$file"; then
    cat "$tmp" > "$file"
  fi
  rm -f "$tmp"
}

# Merge the GWT context-ordering gate into an existing per-project hooks file.
# The hook observes tool events only; it never performs MCP calls or Wiki writes.
ensure_iwiki_gwt_hook() {
  [[ -n "${ICODEX_HOME_DIR:-}" ]] || return 0
  local file="$ICODEX_HOME_DIR/hooks.json" tmp
  [[ -e "$file" || -L "$file" ]] || return 0
  tmp="$(mktemp)"
  python3 - "$file" "$_IWIKI_GWT_GATE" "$_IWIKI_GWT_POST" > "$tmp" <<'PY'
import json, sys

path, gate, post = sys.argv[1:]
with open(path, encoding="utf-8") as stream:
    config = json.load(stream)
hooks = config.setdefault("hooks", {})

def replace(event, command, matcher, status):
    entries = hooks.get(event, [])
    kept = [
        entry for entry in entries
        if not any(item.get("command") == command for item in entry.get("hooks", []))
    ]
    kept.append({
        "matcher": matcher,
        "hooks": [{
            "type": "command",
            "command": command,
            "timeout": 30,
            "statusMessage": status,
        }],
    })
    hooks[event] = kept

replace(
    "PreToolUse",
    gate,
    "mcp__iwiki__wiki_update_page|wiki_update_page",
    "Checking GWT context ordering",
)
replace(
    "PostToolUse",
    post,
    "mcp__iwiki__wiki_spec_context|wiki_spec_context|mcp__iwiki__wiki_update_page|wiki_update_page",
    "Recording GWT context ordering",
)
json.dump(config, sys.stdout, indent=2)
sys.stdout.write("\n")
PY
  if [[ -L "$file" || ! -f "$file" ]] || ! cmp -s "$tmp" "$file"; then
    rm -f "$file"
    cat "$tmp" > "$file"
  fi
  rm -f "$tmp"
}

_iwiki_project_uses_postgres() { # <project-root>
  local toml="$1"
  [[ -f "$toml/.iwiki.toml" ]] || return 1
  awk '
    /^[[:space:]]*\[storage\][[:space:]]*(#.*)?$/ { storage=1; next }
    /^[[:space:]]*\[/ { storage=0 }
    storage && /^[[:space:]]*type[[:space:]]*=[[:space:]]*"postgres"[[:space:]]*(#.*)?$/ { found=1 }
    END { exit !found }
  ' "$toml/.iwiki.toml"
}

_iwiki_strip_existing_wiring() { # <config>
  local file="$1"
  awk -v s="$_IWIKI_REGION_START" -v e="$_IWIKI_REGION_END" '
    $0 == s { in_region=1; next }
    $0 == e { in_region=0; next }
    in_region { next }
    /^\[mcp_servers\.iwiki(\]|\.)/ { in_stale=1; next }
    /^\[/ { in_stale=0 }
    !in_stale { print }
  ' "$file"
}

# Strip any existing iwiki region from the home config.toml, then append a fresh
# one at the end of the file. Idempotent: rewrites only when the content differs.
# No-op when ICODEX_HOME_DIR is unset or the config file does not exist.
ensure_iwiki_wiring() {
  [[ -n "${ICODEX_HOME_DIR:-}" ]] || return 0
  local file="$ICODEX_HOME_DIR/config.toml" body tmp cmd base url key db_password project remote_url remote_token postgres=0
  [[ -f "$file" ]] || return 0
  cmd="${ICODEX_IWIKI_COMMAND:-$(command -v iwiki-mcp || true)}"
  base="${ICODEX_IWIKI_BASE_DIR:-}"
  url="${ICODEX_IWIKI_LLM_BASE_URL:-}"
  key="${ICODEX_IWIKI_LLM_KEY:-${IWIKI_LLM_KEY:-}}"
  db_password="${ICODEX_IWIKI_DB_PASSWORD:-${IWIKI_DB_PASSWORD:-}}"
  project="${ICODEX_PROJECT_ROOT:-}"
  remote_url="${ICODEX_IWIKI_REMOTE_URL:-}"
  remote_token="${ICODEX_IWIKI_REMOTE_TOKEN:-${IWIKI_REMOTE_TOKEN:-}}"
  ensure_iwiki_remote_scope_instructions
  if [[ -n "$remote_url" ]]; then
    if [[ -z "$remote_token" ]]; then
      log_warn "iwiki: remote URL is set but remote token is unresolved, skipping iwiki wiring"
      return 0
    fi
    body="$(_iwiki_remote_region_body "$remote_url")"
  else
    if [[ -n "$project" ]] && _iwiki_project_uses_postgres "$project"; then
      postgres=1
    fi
    if [[ -z "$cmd" || -z "$url" || -z "$key" || -z "$project" || ( "$postgres" -eq 0 && -z "$base" ) || ( "$postgres" -eq 1 && -z "$db_password" ) ]]; then
      log_warn "iwiki: required setting unresolved, skipping iwiki wiring"
      return 0
    fi
    body="$(_iwiki_region_body "$cmd" "$base" "$url" "$project")"
  fi
  ensure_iwiki_gwt_hook
  tmp="$(mktemp)"
  _iwiki_strip_existing_wiring "$file" > "$tmp"
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

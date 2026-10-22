#!/usr/bin/env bash
# Per-project CODEX_HOME isolation. Expensive assets (binary, uv, plugin cache,
# auth) live in the shared store ($ICODEX_SHARED_DIR); per-project state lives in
# a home under $ICODEX_HOMES_DIR keyed by the target project root.

# Echo the target project root: the git toplevel of the CWD, else the real CWD.
resolve_project_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd -P
}

# Set ICODEX_PROJECT_ROOT and the per-project ICODEX_HOME_DIR.
resolve_codex_home() {
  local hash id
  ICODEX_PROJECT_ROOT="$(resolve_project_root)"
  hash="$(printf '%s' "$ICODEX_PROJECT_ROOT" | _sha256 | cut -c1-12)"
  id="$(basename "$ICODEX_PROJECT_ROOT")-$hash"
  ICODEX_HOME_DIR="$ICODEX_HOMES_DIR/$id"
}

# Keep a shared lock from before home creation until the wrapper and inherited
# vendor processes exit. ihar uses the adjacent file exclusively during migration.
acquire_codex_home_lifecycle_lock() { # <home>
  local home="$1" lockfile="${1}.ihar-lifecycle.lock" fd
  if [[ -n "${ICODEX_HOME_LIFECYCLE_FD:-}" ]]; then
    [[ "${ICODEX_HOME_LIFECYCLE_PATH:-}" == "$lockfile" ]] && return 0
    log_error "Codex lifecycle lock already protects another home"
    return 1
  fi
  command -v flock >/dev/null 2>&1 \
    || { log_error "flock is required for safe home migration"; return 1; }
  mkdir -p "$(dirname "$home")" || return 1
  if ! { exec {fd}>"$lockfile"; } 2>/dev/null; then
    log_error "cannot open lifecycle lock $lockfile"
    return 1
  fi
  if ! flock -s -w "${ICODEX_HOME_LOCK_TIMEOUT:-30}" "$fd"; then
    exec {fd}>&-
    log_error "home migration is active for $home; retry after it finishes"
    return 1
  fi
  ICODEX_HOME_LIFECYCLE_FD="$fd"
  ICODEX_HOME_LIFECYCLE_PATH="$lockfile"
}

# Symlink a shared-store entry into the per-project home (idempotent).
_link_shared() { # <name>
  local name="$1"
  local target="$ICODEX_HOME_DIR/$name" src="$ICODEX_SHARED_DIR/$name"
  if [[ -L "$target" && "$(readlink "$target")" == "$src" ]]; then
    return 0
  fi
  rm -rf "$target" 2>/dev/null || true
  ln -s "$src" "$target"
}

_AGENTS_BASE_REGION_START="<!-- icodex:base:start -->"
_AGENTS_BASE_REGION_END="<!-- icodex:base:end -->"

# Codex 0.156 removed the persistent bypass_hook_trust setting. Preserve the
# rest of each project-local config while dropping that obsolete root key.
_remove_obsolete_hook_trust_setting() { # <file>
  local file="$1" tmp
  [[ -f "$file" ]] || return 0
  tmp="$(mktemp)"
  awk '!/^[[:space:]]*bypass_hook_trust[[:space:]]*=/' "$file" > "$tmp"
  if ! cmp -s "$tmp" "$file"; then
    cat "$tmp" > "$file"
  fi
  rm -f "$tmp"
}

# Top-level keys owned by the template-managed region. When the region is
# installed into a home that still carries these keys outside the markers (a
# home predating the region), each such top-level line is removed so the
# region's value is the only one left; Codex rejects duplicate top-level keys.
_TEMPLATE_MANAGED_KEYS="model model_provider model_reasoning_effort web_search"

_TEMPLATE_REGION_START="# icodex:template-managed:start"
_TEMPLATE_REGION_END="# icodex:template-managed:end"

# Extract the managed region body (markers excluded) from the shared template;
# empty when the template has no region.
_template_region_body() { # <template>
  local template="$1"
  [[ -f "$template" ]] || return 0
  awk -v s="$_TEMPLATE_REGION_START" -v e="$_TEMPLATE_REGION_END" '
    $0 == s { in_region=1; next }
    $0 == e { in_region=0; next }
    in_region { print }
  ' "$template"
}

# Strip any existing managed region, then drop top-level lines for the managed
# keys and `[model_providers.*]` tables declared outside the region (pre-region
# homes): the re-inserted region must be the sole source of both, since Codex
# rejects a key or table declared twice. The region is inserted before the
# first TOML section header so its keys stay top-level even when the file ends
# inside a table (e.g. the appended iwiki region). Idempotent: writes only
# when the result differs.
_sync_template_managed_region() { # <home-config> <region-body>
  local config="$1" body="$2" tmp
  [[ -f "$config" ]] || return 0
  tmp="$(mktemp)"
  awk -v s="$_TEMPLATE_REGION_START" -v e="$_TEMPLATE_REGION_END" -v keys="$_TEMPLATE_MANAGED_KEYS" -v body="$body" '
    BEGIN {
      n = split(keys, k, " ")
      for (i = 1; i <= n; i++) managed[k[i]] = 1
    }
    function emit_region() {
      if (region_marker_printed) return
      region_marker_printed = 1
      if (body == "") return    # empty template region: remove, do not re-emit
      print s
      print body
      print e
      print ""
    }
    $0 == s { in_region=1; next }
    $0 == e { in_region=0; next }
    in_region { next }
    /^[[:space:]]*\[/ {
      if (!drop_provider_table) emit_region()
      drop_provider_table = ($0 ~ /^[[:space:]]*\[model_providers\./)
      if (drop_provider_table) next
      in_table = 1
      print
      next
    }
    drop_provider_table { next }         # body lines of a dropped provider table
    in_table { print; next }
    /^[[:space:]]*$/ { next }          # top-level blank lines never round-trip;
                                       # the emitted region supplies its own
    {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      for (key in managed) {
        if (line ~ ("^" key "[[:space:]]*=")) next
      }
      print
    }
    END { emit_region() }
  ' "$config" > "$tmp"
  if ! cmp -s "$tmp" "$config"; then
    cat "$tmp" > "$config"
  fi
  rm -f "$tmp"
}

# Maintain a delimited base region in <file>, re-synced from the shared AGENTS.md
# on every launch so edits to .codex-isolated/AGENTS.md propagate to every home.
# Strips any existing base region and re-appends the current shared content; any
# other region (e.g. caveman) or free text outside the markers is preserved.
# Idempotent: writes only when the result differs. Mirrors the region mechanism
# in lib/caveman/caveman.sh (_caveman_write_agents_region).
_sync_agents_base_region() { # <file>
  local file="$1" src="$ICODEX_SHARED_DIR/AGENTS.md" base tmp
  [[ -f "$src" ]] || return 0
  base="$(cat "$src")"
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    awk -v s="$_AGENTS_BASE_REGION_START" -v e="$_AGENTS_BASE_REGION_END" '
      $0 == s { skip=1; next }
      $0 == e { skip=0; next }
      !skip { print }
    ' "$file" > "$tmp"
  fi
  printf '%s\n%s\n%s\n' "$_AGENTS_BASE_REGION_START" "$base" "$_AGENTS_BASE_REGION_END" >> "$tmp"
  if [[ ! -f "$file" ]] || ! cmp -s "$tmp" "$file"; then
    cat "$tmp" > "$file"
  fi
  rm -f "$tmp"
}

# Create the shared bin dir (install/update path; no per-project home needed).
setup_shared_dirs() {
  mkdir -p "$ICODEX_SHARED_DIR/bin"
}

# Build the per-project home and export CODEX_HOME (run path).
setup_codex_home() {
  resolve_codex_home
  acquire_codex_home_lifecycle_lock "$ICODEX_HOME_DIR" || return 1
  mkdir -p "$ICODEX_HOME_DIR"
  _link_shared plugins
  _link_shared profiles
  _link_shared hooks
  _link_shared hooks.json
  _link_shared auth.json
  _link_shared skills      # user skills → runtime (variant A: whole-dir symlink)
  _link_shared rules       # codex execution-policy → runtime
  _link_shared agents      # custom subagents → runtime
  [[ -f "$ICODEX_HOME_DIR/config.toml" ]] \
    || cp "$ICODEX_SHARED_DIR/config.toml" "$ICODEX_HOME_DIR/config.toml"
  _remove_obsolete_hook_trust_setting "$ICODEX_HOME_DIR/config.toml"
  _sync_template_managed_region \
    "$ICODEX_HOME_DIR/config.toml" \
    "$(_template_region_body "$ICODEX_SHARED_DIR/config.toml")"
  _sync_agents_base_region "$ICODEX_HOME_DIR/AGENTS.md"
  export CODEX_HOME="$ICODEX_HOME_DIR"
}

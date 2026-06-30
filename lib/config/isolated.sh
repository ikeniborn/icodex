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

# Symlink a shared-store entry into the per-project home (idempotent).
_link_shared() { # <name>
  local name="$1"
  local target="$ICODEX_HOME_DIR/$name" src="$ICODEX_SHARED_DIR/$name"
  [[ -L "$target" ]] && return 0
  rm -rf "$target" 2>/dev/null || true
  ln -s "$src" "$target"
}

# Create the shared bin dir (install/update path; no per-project home needed).
setup_shared_dirs() {
  mkdir -p "$ICODEX_SHARED_DIR/bin"
}

# Build the per-project home and export CODEX_HOME (run path).
setup_codex_home() {
  resolve_codex_home
  mkdir -p "$ICODEX_HOME_DIR"
  _link_shared plugins
  _link_shared hooks
  _link_shared hooks.json
  _link_shared auth.json
  _link_shared skills      # user skills → runtime (variant A: whole-dir symlink)
  _link_shared rules       # codex execution-policy → runtime
  [[ -f "$ICODEX_HOME_DIR/config.toml" ]] \
    || cp "$ICODEX_SHARED_DIR/config.toml" "$ICODEX_HOME_DIR/config.toml"
  export CODEX_HOME="$ICODEX_HOME_DIR"
}

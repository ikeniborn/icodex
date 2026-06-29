#!/usr/bin/env bash
# Ensure the pinned codex binary is present & verified.
# Idempotency (resolves F-001): a stamp file holds the installed tag; if it
# matches the lockfile version and the binary is executable, skip the download.

# --- Seams (overridable in tests) ---

# Emit curl proxy args from .codex_config (ICODEX_PROXY), honoring --no-proxy.
# One arg per line so callers can read it into an array.
_curl_proxy_args() {
  [[ -n "${ICODEX_PROXY:-}" ]] || return 0
  (( ${ICODEX_DISABLE_PROXY:-0} )) && return 0
  printf '%s\n' "--proxy" "$ICODEX_PROXY"
}

_download() { # <url> <dest> [show_progress]
  local pargs=(); while IFS= read -r a; do pargs+=("$a"); done < <(_curl_proxy_args)
  if (( ${3:-0} )); then
    curl -fL --progress-bar ${pargs[@]+"${pargs[@]}"} "$1" -o "$2"
  else
    curl -fsSL ${pargs[@]+"${pargs[@]}"} "$1" -o "$2"
  fi
}

_resolve_latest() {
  local pargs=(); while IFS= read -r a; do pargs+=("$a"); done < <(_curl_proxy_args)
  curl -fsSL ${pargs[@]+"${pargs[@]}"} "https://api.github.com/repos/$ICODEX_REPO/releases/latest" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

_release_url() { # <tag> <asset>
  printf 'https://github.com/%s/releases/download/%s/%s\n' "$ICODEX_REPO" "$1" "$2"
}

_uv_source_bin() {
  command -v uv 2>/dev/null || true
}

_install_uv_from_network() { # <dest_dir>
  local dest_dir="$1" installer
  mkdir -p "$dest_dir"
  installer="$(mktemp)"
  if ! _download "https://astral.sh/uv/install.sh" "$installer" 0; then
    rm -f "$installer"
    return 1
  fi
  UV_INSTALL_DIR="$dest_dir" sh "$installer"
  rm -f "$installer"
  [[ -x "$dest_dir/uv" ]]
}

# Export UV_BIN for the launched codex/plugins. The path is deterministic
# ($ICODEX_SHARED_DIR/bin/uv), recomputed every run, so nothing is persisted to
# .codex_config — an absolute path there would only go stale if the project moves.
_export_uv_bin() { # <uv_bin>
  export UV_BIN="$1"
}

ensure_uv_dependency() {
  local target="$ICODEX_SHARED_DIR/bin/uv" source
  if [[ -x "$target" ]]; then
    _export_uv_bin "$target"
    return 0
  fi

  source="$(_uv_source_bin)"
  mkdir -p "$ICODEX_SHARED_DIR/bin"
  if [[ -n "$source" && -x "$source" ]]; then
    cp "$source" "$target" || return 1
    chmod +x "$target"
  else
    log_info "installing uv dependency..."
    if ! _install_uv_from_network "$ICODEX_SHARED_DIR/bin"; then
      log_error "uv dependency install failed"
      return 1
    fi
  fi

  _export_uv_bin "$target"
}

_extract_codex() { # <tarball> -> installs $ICODEX_BIN
  local tarball="$1" tmpd found install_tmp
  tmpd="$(mktemp -d)"
  if ! tar -xzf "$tarball" -C "$tmpd"; then
    log_error "failed to extract $tarball"; rm -rf "$tmpd"; return 1
  fi
  found="$(find "$tmpd" -type f -name 'codex*' ! -name '*.tar*' ! -name '*.sigstore' | head -1)"
  if [[ -z "$found" ]]; then
    log_error "codex binary not found inside archive"; rm -rf "$tmpd"; return 1
  fi
  mkdir -p "$ICODEX_SHARED_DIR/bin"
  install_tmp="$ICODEX_SHARED_DIR/bin/.codex.new.$$"
  if ! cp "$found" "$install_tmp"; then
    log_error "failed to stage codex binary at $install_tmp"
    rm -f "$install_tmp"; rm -rf "$tmpd"; return 1
  fi
  if ! chmod +x "$install_tmp"; then
    log_error "failed to mark codex binary executable: $install_tmp"
    rm -f "$install_tmp"; rm -rf "$tmpd"; return 1
  fi
  if ! mv -f "$install_tmp" "$ICODEX_BIN"; then
    log_error "failed to replace codex binary at $ICODEX_BIN"
    rm -f "$install_tmp"; rm -rf "$tmpd"; return 1
  fi
  rm -rf "$tmpd"
  return 0
}

# install_ensure [--update]
install_ensure() {
  local update=0
  [[ "${1:-}" == "--update" ]] && update=1

  local asset; asset="$(detect_asset)" || return 1
  local want_version want_sha
  want_version="$(lockfile_get "$ICODEX_LOCKFILE" version 2>/dev/null || true)"
  want_sha="$(lockfile_get "$ICODEX_LOCKFILE" sha256 2>/dev/null || true)"

  # Idempotency: stamp matches pinned tag and binary present -> done.
  if (( ! update )) && [[ -x "$ICODEX_BIN" && -f "$ICODEX_STAMP" && -n "$want_version" ]]; then
    if [[ "$(cat "$ICODEX_STAMP")" == "$want_version" ]]; then
      return 0
    fi
  fi

  local tag="$want_version"
  if (( update )) || [[ -z "$tag" ]]; then
    (( update )) && log_info "resolving latest codex release..."
    tag="$(_resolve_latest)" || { log_error "cannot resolve latest codex release"; return 1; }
  fi
  [[ -n "$tag" ]] || { log_error "no codex version pinned and latest unresolved"; return 1; }

  local url tarball sha
  url="$(_release_url "$tag" "$asset")"
  tarball="$(mktemp)"
  (( update )) && log_info "downloading $asset from $tag..."
  if ! _download "$url" "$tarball" "$update"; then
    log_error "download failed: $url"
    log_error "manual: fetch $asset from https://github.com/$ICODEX_REPO/releases/tag/$tag"
    rm -f "$tarball"; return 1
  fi
  (( update )) && log_info "verifying sha256..."
  sha="$(_sha256 < "$tarball")"

  if (( ! update )) && [[ -n "$want_sha" && "$want_sha" != "$sha" ]]; then
    log_error "sha256 mismatch (tamper guard): pinned '$want_sha' got '$sha'"
    rm -f "$tarball"; return 1
  fi

  (( update )) && log_info "extracting codex binary..."
  if ! _extract_codex "$tarball"; then
    rm -f "$tarball"; return 1
  fi
  printf '%s\n' "$tag" > "$ICODEX_STAMP"
  rm -f "$tarball"

  if (( update )); then
    log_info "writing lockfile..."
    lockfile_write "$ICODEX_LOCKFILE" "$tag" "$asset" "$sha"
    log_info "pinned codex $tag (sha256 $sha)"
  fi
  return 0
}

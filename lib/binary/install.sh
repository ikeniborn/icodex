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

_download() { # <url> <dest>
  local pargs=(); while IFS= read -r a; do pargs+=("$a"); done < <(_curl_proxy_args)
  curl -fsSL ${pargs[@]+"${pargs[@]}"} "$1" -o "$2"
}

_resolve_latest() {
  local pargs=(); while IFS= read -r a; do pargs+=("$a"); done < <(_curl_proxy_args)
  curl -fsSL ${pargs[@]+"${pargs[@]}"} "https://api.github.com/repos/$ICODEX_REPO/releases/latest" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

_release_url() { # <tag> <asset>
  printf 'https://github.com/%s/releases/download/%s/%s\n' "$ICODEX_REPO" "$1" "$2"
}

_extract_codex() { # <tarball> -> installs $ICODEX_BIN
  local tarball="$1" tmpd found
  tmpd="$(mktemp -d)"
  if ! tar -xzf "$tarball" -C "$tmpd"; then
    log_error "failed to extract $tarball"; rm -rf "$tmpd"; return 1
  fi
  found="$(find "$tmpd" -type f -name 'codex*' ! -name '*.tar*' ! -name '*.sigstore' | head -1)"
  if [[ -z "$found" ]]; then
    log_error "codex binary not found inside archive"; rm -rf "$tmpd"; return 1
  fi
  mkdir -p "$ICODEX_HOME_DIR/bin"
  cp "$found" "$ICODEX_BIN"
  chmod +x "$ICODEX_BIN"
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
    tag="$(_resolve_latest)" || { log_error "cannot resolve latest codex release"; return 1; }
  fi
  [[ -n "$tag" ]] || { log_error "no codex version pinned and latest unresolved"; return 1; }

  local url tarball sha
  url="$(_release_url "$tag" "$asset")"
  tarball="$(mktemp)"
  if ! _download "$url" "$tarball"; then
    log_error "download failed: $url"
    log_error "manual: fetch $asset from https://github.com/$ICODEX_REPO/releases/tag/$tag"
    rm -f "$tarball"; return 1
  fi
  sha="$(_sha256 < "$tarball")"

  if [[ -n "$want_sha" && "$want_sha" != "$sha" ]]; then
    log_error "sha256 mismatch (tamper guard): pinned '$want_sha' got '$sha'"
    rm -f "$tarball"; return 1
  fi

  if ! _extract_codex "$tarball"; then
    rm -f "$tarball"; return 1
  fi
  printf '%s\n' "$tag" > "$ICODEX_STAMP"
  rm -f "$tarball"

  if (( update )); then
    lockfile_write "$ICODEX_LOCKFILE" "$tag" "$asset" "$sha"
    log_info "pinned codex $tag (sha256 $sha)"
  fi
  return 0
}

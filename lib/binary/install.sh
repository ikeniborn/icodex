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

# Wget counterpart of _curl_proxy_args, used by the download fallback below.
# wget takes the proxy via -e directives rather than curl's single --proxy flag.
_wget_proxy_args() {
  [[ -n "${ICODEX_PROXY:-}" ]] || return 0
  (( ${ICODEX_DISABLE_PROXY:-0} )) && return 0
  printf '%s\n' "-e" "use_proxy=yes" "-e" "https_proxy=$ICODEX_PROXY" "-e" "http_proxy=$ICODEX_PROXY"
}

# Download <url> to <dest>. curl is the primary path; on any curl failure we
# retry with wget when it is present. The fallback matters on hosts whose curl
# is linked against an OpenSSL build that cannot decode a GOST (or otherwise
# unsupported) CA in the concatenated system trust bundle: curl aborts the whole
# TLS handshake (x509_pubkey_decode: unsupported algorithm), while wget reads the
# hashed CApath and only touches the issuer it needs, so it succeeds.
_download() { # <url> <dest> [show_progress]
  local cargs=(); while IFS= read -r a; do cargs+=("$a"); done < <(_curl_proxy_args)
  if (( ${3:-0} )); then
    curl -fL --progress-bar ${cargs[@]+"${cargs[@]}"} "$1" -o "$2" && return 0
  else
    curl -fsSL ${cargs[@]+"${cargs[@]}"} "$1" -o "$2" && return 0
  fi
  command -v wget >/dev/null 2>&1 || return 1
  local wargs=(); while IFS= read -r a; do wargs+=("$a"); done < <(_wget_proxy_args)
  if (( ${3:-0} )); then
    wget -q --show-progress ${wargs[@]+"${wargs[@]}"} -O "$2" "$1"
  else
    wget -q ${wargs[@]+"${wargs[@]}"} -O "$2" "$1"
  fi
}

_resolve_latest() {
  local api="https://api.github.com/repos/$ICODEX_REPO/releases/latest" body
  local cargs=(); while IFS= read -r a; do cargs+=("$a"); done < <(_curl_proxy_args)
  if ! body="$(curl -fsSL ${cargs[@]+"${cargs[@]}"} "$api")"; then
    command -v wget >/dev/null 2>&1 || return 1
    local wargs=(); while IFS= read -r a; do wargs+=("$a"); done < <(_wget_proxy_args)
    body="$(wget -qO- ${wargs[@]+"${wargs[@]}"} "$api")" || return 1
  fi
  printf '%s\n' "$body" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
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

_export_shared_bin_path() {
  local bin_dir="$ICODEX_SHARED_DIR/bin"
  case ":${PATH:-}:" in
    *":$bin_dir:"*) ;;
    *) export PATH="$bin_dir${PATH:+:$PATH}" ;;
  esac
}

_ensure_managed_tool() { # <name>
  local name="$1" source="$ICODEX_ROOT/lib/binary/shims/$1" target="$ICODEX_SHARED_DIR/bin/$1" tmp module_dir
  if [[ ! -f "$source" ]]; then
    module_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source="$module_dir/shims/$name"
  fi
  [[ -f "$source" ]] || { log_error "helper tool shim missing: $source"; return 1; }
  mkdir -p "$(dirname "$target")"
  if [[ -e "$target" ]] && ! grep -qF "managed by icodex helper-tools" "$target" 2>/dev/null; then
    return 0
  fi
  tmp="$(mktemp)"
  cp "$source" "$tmp" || { rm -f "$tmp"; return 1; }
  chmod +x "$tmp"
  if [[ -f "$target" ]] && cmp -s "$tmp" "$target"; then
    rm -f "$tmp"
  else
    mv -f "$tmp" "$target"
  fi
}

ensure_cli_tools() {
  _ensure_managed_tool tree || return 1
  _ensure_managed_tool rg || return 1
  _export_shared_bin_path
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

_extract_release_binary() { # <tarball> <archive-name-pattern> <name> <destination>
  local tarball="$1" pattern="$2" name="$3" destination="$4" tmpd found install_tmp
  tmpd="$(mktemp -d)"
  if ! tar -xzf "$tarball" -C "$tmpd"; then
    log_error "failed to extract $tarball"; rm -rf "$tmpd"; return 1
  fi
  found="$(find "$tmpd" -type f -name "$pattern" | head -1)"
  if [[ -z "$found" ]]; then
    log_error "$name binary not found inside archive"; rm -rf "$tmpd"; return 1
  fi
  mkdir -p "$(dirname "$destination")"
  install_tmp="$(dirname "$destination")/.${name}.new.$$"
  if ! cp "$found" "$install_tmp"; then
    log_error "failed to stage $name binary at $install_tmp"
    rm -f "$install_tmp"; rm -rf "$tmpd"; return 1
  fi
  if ! chmod +x "$install_tmp"; then
    log_error "failed to mark $name binary executable: $install_tmp"
    rm -f "$install_tmp"; rm -rf "$tmpd"; return 1
  fi
  if ! mv -f "$install_tmp" "$destination"; then
    log_error "failed to replace $name binary at $destination"
    rm -f "$install_tmp"; rm -rf "$tmpd"; return 1
  fi
  rm -rf "$tmpd"
  return 0
}

_extract_codex() {
  _extract_release_binary "$1" codex codex "$ICODEX_BIN"
}

_extract_code_mode_host() {
  _extract_release_binary "$1" 'codex-code-mode-host-*' code-mode-host "$ICODEX_SHARED_DIR/bin/codex-code-mode-host"
}

# install_ensure [--update]
install_ensure() {
  local update=0
  [[ "${1:-}" == "--update" ]] && update=1

  local asset host_asset host_bin
  asset="$(detect_asset)" || return 1
  host_asset="$(detect_code_mode_host_asset)" || return 1
  host_bin="$ICODEX_SHARED_DIR/bin/codex-code-mode-host"
  local want_version want_sha
  want_version="$(lockfile_get "$ICODEX_LOCKFILE" version 2>/dev/null || true)"
  want_sha="$(lockfile_get "$ICODEX_LOCKFILE" sha256 2>/dev/null || true)"

  # Idempotency: stamp matches pinned tag and binary present -> done.
  if (( ! update )) && [[ -x "$ICODEX_BIN" && -x "$host_bin" && -f "$ICODEX_STAMP" && -n "$want_version" ]]; then
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

  if (( update )) && [[ -x "$ICODEX_BIN" && -x "$host_bin" && -f "$ICODEX_STAMP" && -n "$want_version" ]]; then
    if [[ "$tag" == "$want_version" && "$(cat "$ICODEX_STAMP")" == "$tag" ]]; then
      log_info "codex already at latest $tag; skipping download"
      return 0
    fi
  fi

  local url host_url tarball host_tarball sha
  url="$(_release_url "$tag" "$asset")"
  host_url="$(_release_url "$tag" "$host_asset")"
  tarball="$(mktemp)"
  host_tarball="$(mktemp)"
  (( update )) && log_info "downloading $asset from $tag..."
  if ! _download "$url" "$tarball" "$update"; then
    log_error "download failed: $url"
    log_error "manual: fetch $asset from https://github.com/$ICODEX_REPO/releases/tag/$tag"
    rm -f "$tarball" "$host_tarball"; return 1
  fi
  (( update )) && log_info "downloading $host_asset from $tag..."
  if ! _download "$host_url" "$host_tarball" "$update"; then
    log_error "download failed: $host_url"
    log_error "manual: fetch $host_asset from https://github.com/$ICODEX_REPO/releases/tag/$tag"
    rm -f "$tarball" "$host_tarball"; return 1
  fi
  (( update )) && log_info "verifying sha256..."
  sha="$(_sha256 < "$tarball")"

  if (( ! update )) && [[ -n "$want_sha" && "$want_sha" != "$sha" ]]; then
    log_error "sha256 mismatch (tamper guard): pinned '$want_sha' got '$sha'"
    rm -f "$tarball" "$host_tarball"; return 1
  fi

  (( update )) && log_info "extracting codex binary..."
  if ! _extract_codex "$tarball"; then
    rm -f "$tarball" "$host_tarball"; return 1
  fi
  (( update )) && log_info "extracting code-mode host..."
  if ! _extract_code_mode_host "$host_tarball"; then
    rm -f "$tarball" "$host_tarball"; return 1
  fi
  printf '%s\n' "$tag" > "$ICODEX_STAMP"
  rm -f "$tarball" "$host_tarball"

  if (( update )); then
    log_info "writing lockfile..."
    lockfile_write "$ICODEX_LOCKFILE" "$tag" "$asset" "$sha"
    log_info "pinned codex $tag (sha256 $sha)"
  fi
  return 0
}

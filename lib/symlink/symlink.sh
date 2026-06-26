#!/usr/bin/env bash
# Create a user-space `icodex` symlink so the wrapper runs as plain `icodex`.
# Target dir: $ICODEX_LINK_DIR, default ~/.local/bin. An existing non-symlink
# file at the target is left untouched (never clobber a real file).
install_symlink() {
  local dir="${ICODEX_LINK_DIR:-$HOME/.local/bin}"
  dir="${dir/#\~\//$HOME/}"            # expand a leading ~/ (config values aren't sourced)
  local target="$ICODEX_ROOT/icodex.sh"
  local link="$dir/icodex"

  mkdir -p "$dir" || { log_error "cannot create $dir"; return 1; }

  if [[ -L "$link" ]]; then
    if [[ "$(readlink "$link")" == "$target" ]]; then
      log_info "icodex symlink already up to date: $link"
    else
      ln -sf "$target" "$link"
      log_info "repaired icodex symlink: $link -> $target"
    fi
  elif [[ -e "$link" ]]; then
    log_warn "$link exists and is not an icodex symlink — left untouched"
    return 0
  else
    ln -s "$target" "$link"
    log_info "created icodex symlink: $link -> $target"
  fi

  case ":$PATH:" in
    *":$dir:"*) ;;
    *) log_warn "$dir is not on your PATH — add it to run 'icodex' directly" ;;
  esac
  return 0
}

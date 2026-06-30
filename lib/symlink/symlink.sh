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

  return 0
}

# Ensure the launcher dir ($ICODEX_LINK_DIR, default ~/.local/bin) is on PATH by
# appending an export to the user's shell profile. Idempotent via a marker line:
# repeated install/update runs never duplicate the entry. The shell is detected
# from $SHELL; an unknown shell gets a manual hint instead of an edit, and the
# profile is only ever appended to (never clobbered). Called after
# install_symlink on both --install and --update.
ensure_path_entry() {
  local dir="${ICODEX_LINK_DIR:-$HOME/.local/bin}"
  dir="${dir/#\~\//$HOME/}"

  # Already reachable — nothing to do.
  case ":$PATH:" in
    *":$dir:"*) return 0 ;;
  esac

  local marker="# added by icodex (PATH for the icodex launcher)"
  local profile line
  case "$(basename "${SHELL:-}")" in
    fish)
      profile="${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"
      line="fish_add_path $dir"
      ;;
    zsh)
      profile="$HOME/.zshrc"
      line="export PATH=\"$dir:\$PATH\""
      ;;
    bash)
      profile="$HOME/.bashrc"
      line="export PATH=\"$dir:\$PATH\""
      ;;
    *)
      log_warn "$dir is not on your PATH — add it manually to run 'icodex' directly"
      return 0
      ;;
  esac

  # Idempotent: skip if the dir is already referenced in the profile — whether by
  # our marker, a prior run, or the user's own manual edit. This avoids stacking a
  # second export on top of a hand-added one.
  if [[ -f "$profile" ]] && grep -qF "$dir" "$profile" 2>/dev/null; then
    return 0
  fi

  mkdir -p "$(dirname "$profile")" \
    || { log_warn "cannot create $(dirname "$profile") — add $dir to PATH manually"; return 0; }
  printf '\n%s\n%s\n' "$marker" "$line" >> "$profile" \
    || { log_warn "cannot write $profile — add $dir to PATH manually"; return 0; }
  log_info "added $dir to PATH in $profile — run 'source $profile' or restart your shell"
  return 0
}

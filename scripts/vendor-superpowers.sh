#!/usr/bin/env bash
# Maintainer tool: regenerate the committed Superpowers plugin cache.
#
#   ./scripts/vendor-superpowers.sh <sha>
#
# Installs Superpowers into a scratch CODEX_HOME via the real `codex plugin`
# commands, then normalizes the produced cache into the repo at the canonical
# path named by vendor/superpowers/pin (git-tracked).
# "Install once on one machine -> deliver via git."
set -euo pipefail
VENDOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

_vendor_publish() { # <source-cache-root> <dest-cache-root> <pin> <patch-dir>
  local source_root="$1" dest_root="$2" pin="$3" patch_dir="$4"
  local -a sources overlays
  local source rel destination parent stage backup pin_stage overlay

  mapfile -t sources < <(find "$source_root" -mindepth 3 -maxdepth 3 -type d -path '*/superpowers/*' -exec test -f '{}/.codex-plugin/plugin.json' \; -print | sort)
  [[ "${#sources[@]}" -eq 1 ]] || { log_error "expected exactly one Superpowers source cache, found ${#sources[@]}"; return 1; }
  source="${sources[0]}"
  rel="${source#"$source_root"/}"
  [[ "$rel" =~ ^[A-Za-z0-9._-]+/superpowers/[A-Za-z0-9._-]+$ ]] || { log_error "invalid source cache identity: $rel"; return 1; }

  mapfile -t overlays < <(find "$patch_dir" -maxdepth 1 -type f -name '*.patch' -print | sort)
  [[ "${#overlays[@]}" -gt 0 ]] || { log_error "no Superpowers overlay patches found in $patch_dir"; return 1; }

  destination="$dest_root/$rel"
  parent="$(dirname "$destination")"
  mkdir -p "$parent" "$(dirname "$pin")"
  stage="$(mktemp -d "$parent/.stage.XXXXXX")"
  backup="$parent/.backup.$$"
  pin_stage="$(mktemp "$(dirname "$pin")/.pin.XXXXXX")"
  trap 'rm -rf "$stage" "$backup"; rm -f "$pin_stage"' RETURN

  rsync -a --delete "$source/" "$stage/"
  rm -rf "$stage/.git"
  find "$stage" -name .gitignore -delete
  for overlay in "${overlays[@]}"; do
    patch --batch --forward --fuzz=0 -d "$stage" -p1 < "$overlay" >/dev/null || {
      log_error "Superpowers overlay conflict: $(basename "$overlay")"
      return 1
    }
  done
  [[ -f "$stage/.codex-plugin/plugin.json" ]] || { log_error "plugin.json missing after staging"; return 1; }
  [[ -f "$stage/skills/brainstorming/SKILL.md" && -f "$stage/skills/writing-plans/SKILL.md" ]] || {
    log_error "required patched skills missing after staging"
    return 1
  }
  printf '%s\n' "$rel" > "$pin_stage"

  [[ ! -e "$backup" ]] || { log_error "publication backup already exists: $backup"; return 1; }
  if [[ -e "$destination" ]]; then mv "$destination" "$backup"; fi
  if ! mv "$stage" "$destination"; then
    [[ ! -e "$backup" ]] || mv "$backup" "$destination"
    return 1
  fi
  if ! mv "$pin_stage" "$pin"; then
    rm -rf "$destination"
    [[ ! -e "$backup" ]] || mv "$backup" "$destination"
    return 1
  fi
  rm -rf "$backup"
  trap - RETURN
}

# Network wrapper — only runs when executed directly, never when sourced by tests.
_vendor_main() {
  local sha="${1:?usage: vendor-superpowers.sh <immutable-sha>}"
  local bin="$VENDOR_ROOT/.codex-isolated/bin/codex"
  [[ -x "$bin" ]] || { log_error "codex binary missing — run ./icodex.sh --install"; return 1; }
  local scratch; scratch="$(mktemp -d)"
  CODEX_HOME="$scratch" "$bin" plugin marketplace add obra/superpowers --ref "$sha" >&2
  local mkt; mkt="$(grep -oE '\[marketplaces\.[^]]+\]' "$scratch/config.toml" | head -1 | sed -E 's/\[marketplaces\.(.+)\]/\1/')"
  [[ -n "$mkt" ]] || { log_error "could not determine marketplace name from $scratch/config.toml"; return 1; }
  CODEX_HOME="$scratch" "$bin" plugin add "superpowers@$mkt" >&2
  _vendor_publish "$scratch/plugins/cache" "$VENDOR_ROOT/.codex-isolated/plugins/cache" \
    "$VENDOR_ROOT/vendor/superpowers/pin" "$VENDOR_ROOT/vendor/superpowers/patches"
  rm -rf "$scratch"
  log_info "vendored pinned Superpowers cache with ordered zero-fuzz overlays"
}

# Run the wrapper only on direct execution (so tests can source the file safely).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # shellcheck source=/dev/null
  source "$VENDOR_ROOT/lib/core/logging.sh"
  _vendor_main "$@"
fi

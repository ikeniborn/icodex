#!/usr/bin/env bash
# Maintainer tool: regenerate the committed Superpowers plugin cache.
#
#   ./scripts/vendor-superpowers.sh <sha>
#
# Installs Superpowers into a scratch CODEX_HOME via the real `codex plugin`
# commands, then normalizes the produced cache into the repo at the canonical
# path .codex-isolated/plugins/cache/superpowers/superpowers/<ver>/ (git-tracked).
# "Install once on one machine -> deliver via git."
set -euo pipefail
VENDOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Pure: copy a scratch cache dir into the canonical repo location and de-lint it.
_vendor_normalize() { # <src_cache_dir> <dest_cache_root> <plugin> <ver>
  local src="$1" destroot="$2" plugin="$3" ver="$4"
  local dest="$destroot/superpowers/$plugin/$ver"
  rm -rf "$dest"; mkdir -p "$dest"
  rsync -a --delete "$src/" "$dest/"
  rm -rf "$dest/.git"
  find "$dest" -name .gitignore -delete
  [[ -z "$(find "$dest" -name .gitignore -print -quit)" ]] || { log_error "nested .gitignore remained in $dest"; return 1; }
  [[ -f "$dest/.codex-plugin/plugin.json" ]] || { log_error "plugin.json missing after vendoring $dest"; return 1; }
  return 0
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
  local srccache; srccache="$(find "$scratch/plugins/cache" -type d -path '*/superpowers/*' -name '[0-9]*' | head -1)"
  [[ -n "$srccache" ]] || { log_error "no vendored cache dir found under $scratch/plugins/cache"; return 1; }
  local ver; ver="$(basename "$srccache")"
  _vendor_normalize "$srccache" "$VENDOR_ROOT/.codex-isolated/plugins/cache" superpowers "$ver"
  rm -rf "$scratch"
  log_info "vendored superpowers $ver — update the <ver> note in config.toml and: git add .codex-isolated/plugins .codex-isolated/config.toml"
}

# Run the wrapper only on direct execution (so tests can source the file safely).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # shellcheck source=/dev/null
  source "$VENDOR_ROOT/lib/core/logging.sh"
  _vendor_main "$@"
fi

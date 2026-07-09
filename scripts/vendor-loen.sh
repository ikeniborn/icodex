#!/usr/bin/env bash
# Maintainer tool: regenerate the committed LoEn plugin cache from plugins/loen/.
#
#   ./scripts/vendor-loen.sh
#
# The source tree stays editable under plugins/loen/. This script creates the
# portable Codex cache used by icodex launch-time marketplace wiring.
set -euo pipefail
VENDOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOEN_VENDOR_MARKETPLACE="${LOEN_VENDOR_MARKETPLACE:-ikeniborn}"

_loen_manifest_version() { # <manifest>
  python3 - "$1" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
name = data.get("name")
version = data.get("version")
if name != "loen":
  raise SystemExit(f"manifest name must be loen, got {name!r}")
if not isinstance(version, str) or not version.strip():
  raise SystemExit("manifest version is missing")
print(version)
PY
}

_loen_validate_cache() { # <cache_dir>
  local cache="$1" manifest required
  manifest="$cache/.codex-plugin/plugin.json"
  [[ -f "$manifest" ]] || { log_error "plugin.json missing after vendoring $cache"; return 1; }
  for required in skills hooks agents assets docs; do
    [[ -e "$cache/$required" ]] || { log_error "required LoEn asset missing after vendoring: $required"; return 1; }
  done
  [[ -z "$(find "$cache" -name .git -type d -print -quit)" ]] || { log_error "nested .git remained in $cache"; return 1; }
  [[ -z "$(find "$cache" -name .gitignore -print -quit)" ]] || { log_error "nested .gitignore remained in $cache"; return 1; }
  [[ -z "$(find "$cache" -name '*.pyc' -print -quit)" ]] || { log_error "generated pyc remained in $cache"; return 1; }
  [[ -z "$(find "$cache" -type d -name __pycache__ -print -quit)" ]] || { log_error "generated __pycache__ remained in $cache"; return 1; }
}

_vendor_loen_remove_legacy_caches() { # <dest_cache_root> <canonical_marketplace>
  local destroot="$1" canonical="$2" legacy
  for legacy in iclaude icodex-local; do
    [[ "$legacy" == "$canonical" ]] && continue
    rm -rf "$destroot/$legacy/loen"
    rmdir "$destroot/$legacy" 2>/dev/null || true
  done
}

_vendor_loen_remove_stale_versions() { # <dest_cache_root> <marketplace> <current_version>
  local destroot="$1" marketplace="$2" current_version="$3" root existing
  root="$destroot/$marketplace/loen"
  [[ -d "$root" ]] || return 0
  for existing in "$root"/*; do
    [[ -d "$existing" ]] || continue
    [[ "$(basename "$existing")" == "$current_version" ]] && continue
    rm -rf "$existing"
  done
}

_vendor_loen_normalize() { # <src_plugin_dir> <dest_cache_root> [marketplace]
  local src="$1" destroot="$2" marketplace="${3:-$LOEN_VENDOR_MARKETPLACE}"
  local manifest version dest
  manifest="$src/.codex-plugin/plugin.json"
  [[ -f "$manifest" ]] || { log_error "LoEn source manifest missing: $manifest"; return 1; }
  version="$(_loen_manifest_version "$manifest")" || return 1
  dest="$destroot/$marketplace/loen/$version"

  rm -rf "$dest"
  mkdir -p "$dest"
  cp -R "$src/." "$dest/"

  find "$dest" -name .git -type d -prune -exec rm -rf {} +
  find "$dest" -type d -name __pycache__ -prune -exec rm -rf {} +
  find "$dest" \( -name .gitignore -o -name '*.pyc' -o -name '.DS_Store' \) -delete
  _loen_validate_cache "$dest"
  _vendor_loen_remove_stale_versions "$destroot" "$marketplace" "$version"
  _vendor_loen_remove_legacy_caches "$destroot" "$marketplace"
  printf '%s\n' "$dest"
}

_vendor_loen_main() {
  local dest
  dest="$(_vendor_loen_normalize "$VENDOR_ROOT/plugins/loen" "$VENDOR_ROOT/.codex-isolated/plugins/cache" "$LOEN_VENDOR_MARKETPLACE")" || return 1
  log_info "vendored LoEn to ${dest#$VENDOR_ROOT/}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # shellcheck source=/dev/null
  if [[ -f "$VENDOR_ROOT/lib/core/logging.sh" ]]; then
    source "$VENDOR_ROOT/lib/core/logging.sh"
  else
    log_info()  { printf '[icodex] %s\n' "$*" >&2; }
    log_error() { printf '[icodex] ERROR: %s\n' "$*" >&2; }
  fi
  _vendor_loen_main "$@"
fi

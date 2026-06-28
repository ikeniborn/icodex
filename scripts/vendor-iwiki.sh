#!/usr/bin/env bash
# Maintainer tool: normalize ai-wiki-plugin into the committed Codex plugin cache.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$ROOT/lib/core/logging.sh"

_json_value() { # <file> <key>
  local file="$1" key="$2"
  sed -nE 's/^[[:space:]]*"'$key'"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$file" | head -1
}

_validate_iwiki_version() { # <version>
  local version="$1"
  [[ "$version" != "." && "$version" != ".." ]] || return 1
  [[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

_write_codex_manifest() { # <src_manifest> <dest_manifest>
  local src_manifest="$1" dest_manifest="$2"
  local name version description homepage repository license
  name="$(_json_value "$src_manifest" name)"
  version="$(_json_value "$src_manifest" version)"
  description="$(_json_value "$src_manifest" description)"
  homepage="$(_json_value "$src_manifest" homepage)"
  repository="$(_json_value "$src_manifest" repository)"
  license="$(_json_value "$src_manifest" license)"

  mkdir -p "$(dirname "$dest_manifest")"
  cat > "$dest_manifest" <<JSON
{
  "name": "$name",
  "version": "$version",
  "description": "$description",
  "author": {
    "name": "ikeniborn",
    "url": "https://github.com/ikeniborn"
  },
  "homepage": "$homepage",
  "repository": "$repository",
  "license": "$license",
  "keywords": [
    "documentation",
    "embeddings",
    "wiki",
    "semantic-search",
    "knowledge-graph"
  ],
  "skills": "./skills/"
}
JSON
}

_strip_iwiki_generated_artifacts() { # <dest>
  local dest="$1"
  rm -rf "$dest/.git" "$dest/.venv" "$dest/.pytest_cache"
  find "$dest" -type d \( -name .git -o -name .venv -o -name .pytest_cache -o -name __pycache__ \) -prune -exec rm -rf {} +
  find "$dest" -type f \( -name '*.pyc' -o -name .gitignore \) -delete
}

_vendor_iwiki_normalize() { # <source_plugin_root> <dest_cache_root>
  local src="$1" destroot="$2"
  local src_manifest="$src/.claude-plugin/plugin.json"
  [[ -f "$src_manifest" ]] || { log_error "source manifest missing: $src_manifest"; return 1; }

  local version dest
  version="$(_json_value "$src_manifest" version)"
  [[ -n "$version" ]] || { log_error "version missing in $src_manifest"; return 1; }
  _validate_iwiki_version "$version" || { log_error "unsafe version in $src_manifest: $version"; return 1; }

  dest="$destroot/ai-wiki/iwiki/$version"
  rm -rf "$dest"
  mkdir -p "$dest"

  cp -R "$src/skills" "$dest/"
  cp -R "$src/engine" "$dest/"
  cp -R "$src/hooks" "$dest/"
  [[ ! -f "$src/README.md" ]] || cp "$src/README.md" "$dest/"
  [[ ! -f "$src/hooks/hooks.json" ]] || cp "$src/hooks/hooks.json" "$dest/hooks.json"

  _write_codex_manifest "$src_manifest" "$dest/.codex-plugin/plugin.json"
  _strip_iwiki_generated_artifacts "$dest"

  [[ -f "$dest/.codex-plugin/plugin.json" ]] || { log_error "plugin.json missing after vendoring $dest"; return 1; }
  [[ -d "$dest/skills" ]] || { log_error "skills dir missing after vendoring $dest"; return 1; }
  [[ -f "$dest/engine/pyproject.toml" ]] || { log_error "engine pyproject missing after vendoring $dest"; return 1; }
  [[ -d "$dest/hooks" ]] || { log_error "hooks dir missing after vendoring $dest"; return 1; }

  printf '%s\n' "$dest"
}

if [[ "${1:-}" == "--lib-only" ]]; then
  return 0 2>/dev/null || exit 0
fi

_vendor_iwiki_main() {
  local source_plugin_root="${1:-/home/ikeniborn/Documents/Project/ai-wiki-plugin}"
  local dest_cache_root="${2:-$ROOT/.codex-isolated/plugins/cache}"
  _vendor_iwiki_normalize "$source_plugin_root" "$dest_cache_root"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _vendor_iwiki_main "$@"
fi

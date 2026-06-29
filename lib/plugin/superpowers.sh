#!/usr/bin/env bash
# Wire the git-vendored Superpowers plugin into config.toml at launch.
#
# The committed artifact is path-portable: the marketplace `source` must resolve
# to a valid path on every host and is rewritten here from $ICODEX_ROOT. Codex
# validates the source on every launch, so this runs on the default (launch) path.

# Echo the absolute vendored cache dir, or nothing when the plugin is not vendored.
# Anchored at $ICODEX_SHARED_DIR so the glob is independent of the process CWD and the per-project home.
_superpowers_cache_dir() {
  local m
  for m in "$ICODEX_SHARED_DIR"/plugins/cache/*/superpowers/*/; do
    [[ -d "$m" ]] || continue
    printf '%s\n' "${m%/}"
    return 0
  done
  return 0
}

# Derive the marketplace name from the cache path: …/cache/<mkt>/superpowers/<ver>
_superpowers_marketplace_name() { # <cache_dir>
  basename "$(dirname "$(dirname "$1")")"
}

_superpowers_marketplace_root() { # <mkt>
  printf '%s/tmp/marketplaces/%s\n' "$ICODEX_HOME_DIR" "$1"
}

_write_superpowers_marketplace_manifest() { # <root> <mkt>
  local root="$1" mkt="$2"
  mkdir -p "$root/.agents/plugins"
  cat > "$root/.agents/plugins/marketplace.json" <<EOF
{
  "name": "$mkt",
  "interface": {
    "displayName": "icodex local"
  },
  "plugins": [
    {
      "name": "superpowers",
      "source": {
        "source": "local",
        "path": "./plugins/superpowers"
      },
      "policy": {
        "installation": "AVAILABLE",
        "authentication": "ON_INSTALL",
        "products": [
          "CODEX"
        ]
      },
      "category": "Developer Tools"
    }
  ]
}
EOF
  cp "$root/.agents/plugins/marketplace.json" "$root/.agents/plugins/api_marketplace.json"
}

_ensure_superpowers_marketplace_root() { # <cache_dir> <mkt>
  local cache="$1" mkt="$2" root plugin_link
  root="$(_superpowers_marketplace_root "$mkt")"
  plugin_link="$root/plugins/superpowers"

  mkdir -p "$root/plugins"
  if [[ -e "$plugin_link" || -L "$plugin_link" ]]; then
    rm -rf "$plugin_link"
  fi
  ln -s "$cache" "$plugin_link"
  _write_superpowers_marketplace_manifest "$root" "$mkt"
  printf '%s\n' "$root"
}

# Idempotently rewrite the `source` line inside [marketplaces.<mkt>] to <abs>.
_rewrite_marketplace_source() { # <config> <mkt> <abs>
  local config="$1" mkt="$2" abs="$3" tmp
  tmp="$(mktemp)"
  awk -v mkt="$mkt" -v abs="$abs" '
    /^\[/ { insec = ($0 == "[marketplaces." mkt "]") }
    insec && /^[[:space:]]*source[[:space:]]*=/ { print "source = \"" abs "\""; next }
    { print }
  ' "$config" > "$tmp"
  cmp -s "$tmp" "$config" || cat "$tmp" > "$config"  # overwrite in place (preserve inode/perms) only when changed
  rm -f "$tmp"
}

# Orchestrate: fix the source path in the committed base config.
ensure_superpowers_wiring() {
  local config="$ICODEX_HOME_DIR/config.toml"
  if [[ ! -f "$config" ]]; then
    log_error "missing $config — cannot configure superpowers"
    return 0
  fi
  local cache mkt marketplace
  cache="$(_superpowers_cache_dir)"
  if [[ -z "$cache" ]]; then
    log_warn "superpowers plugin not vendored under .codex-isolated/plugins/cache"
    return 0
  fi
  mkt="$(_superpowers_marketplace_name "$cache")"
  marketplace="$(_ensure_superpowers_marketplace_root "$cache" "$mkt")"
  _rewrite_marketplace_source "$config" "$mkt" "$marketplace"
}

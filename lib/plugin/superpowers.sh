#!/usr/bin/env bash
# Wire the git-vendored Superpowers plugin into the live config.toml at launch.
#
# The committed artifact is path-portable: the marketplace `source` must resolve
# to a valid path on every host and is rewritten here from $ICODEX_ROOT. Codex
# validates the source on every launch, so this runs on the default (launch) path.

# Echo the absolute vendored cache dir, or nothing when the plugin is not vendored.
# Anchored at $ICODEX_ROOT so the glob is independent of the process CWD.
_superpowers_cache_dir() {
  local m
  for m in "$ICODEX_HOME_DIR"/plugins/cache/*/superpowers/*/; do
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

# Orchestrate: materialize config.toml from the example, then fix the source path.
ensure_superpowers_wiring() {
  local example="$ICODEX_HOME_DIR/config.toml.example"
  local config="$ICODEX_HOME_DIR/config.toml"
  if [[ ! -f "$config" ]]; then
    if [[ -f "$example" ]]; then
      cp "$example" "$config"
    else
      log_error "missing $example — cannot configure superpowers"
      return 0
    fi
  fi
  local cache mkt
  cache="$(_superpowers_cache_dir)"
  if [[ -z "$cache" ]]; then
    log_warn "superpowers plugin not vendored under .codex-isolated/plugins/cache"
    return 0
  fi
  mkt="$(_superpowers_marketplace_name "$cache")"
  _rewrite_marketplace_source "$config" "$mkt" "$cache"
}

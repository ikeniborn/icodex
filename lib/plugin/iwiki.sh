#!/usr/bin/env bash
# Wire the git-vendored iwiki plugin into the live config.toml at launch.

_iwiki_cache_dir() {
  local m
  for m in "$ICODEX_HOME_DIR"/plugins/cache/ai-wiki/iwiki/*/; do
    [[ -d "$m" ]] || continue
    printf '%s\n' "${m%/}"
    return 0
  done
  return 0
}

_iwiki_rewrite_marketplace_source() { # <config> <mkt> <abs>
  local config="$1" mkt="$2" abs="$3" tmp status=0
  tmp="$(mktemp)"
  if awk -v mkt="$mkt" -v abs="$abs" '
    /^\[/ { insec = ($0 == "[marketplaces." mkt "]") }
    insec && /^[[:space:]]*source[[:space:]]*=/ { print "source = \"" abs "\""; next }
    { print }
  ' "$config" > "$tmp"; then
    if ! cmp -s "$tmp" "$config"; then
      cat "$tmp" > "$config" || status=$?
    fi
  else
    status=$?
  fi
  rm -f "$tmp"
  return "$status"
}

ensure_iwiki_wiring() {
  local example="$ICODEX_HOME_DIR/config.toml.example"
  local config="$ICODEX_HOME_DIR/config.toml"
  if [[ ! -f "$config" ]]; then
    if [[ -f "$example" ]]; then
      cp "$example" "$config"
    else
      log_error "missing $example - cannot configure iwiki"
      return 0
    fi
  fi

  local cache
  cache="$(_iwiki_cache_dir)"
  if [[ -z "$cache" ]]; then
    log_warn "iwiki plugin not vendored under .codex-isolated/plugins/cache"
    return 0
  fi

  _iwiki_rewrite_marketplace_source "$config" "ai-wiki" "$cache"
}

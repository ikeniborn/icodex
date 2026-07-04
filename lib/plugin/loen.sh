#!/usr/bin/env bash
# Wire the git-vendored LoEn plugin into each per-project Codex home.
#
# LoEn is vendored under .codex-isolated/plugins/cache/icodex-local/loen/<ver>/.
# The runtime marketplace root lives under the per-project CODEX_HOME so Codex
# sees a valid host-local marketplace source on every launch.

type log_warn >/dev/null 2>&1 || log_warn() { printf '[icodex] WARN: %s\n' "$*" >&2; }
type log_error >/dev/null 2>&1 || log_error() { printf '[icodex] ERROR: %s\n' "$*" >&2; }

_LOEN_MARKETPLACE="icodex-local"

_loen_mode() {
  local value="${ICODEX_LOEN_MODE:-advisory}"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    off|advisory|enforce|strict) printf '%s\n' "$value" ;;
    *)
      log_warn "invalid ICODEX_LOEN_MODE '$value'; using advisory"
      printf 'advisory\n'
      ;;
  esac
}

_loen_cache_dir() {
  local m
  for m in "$ICODEX_SHARED_DIR"/plugins/cache/"$_LOEN_MARKETPLACE"/loen/*/; do
    [[ -d "$m" ]] || continue
    [[ -f "$m/.codex-plugin/plugin.json" ]] || continue
    printf '%s\n' "${m%/}"
    return 0
  done
  return 0
}

_loen_marketplace_name() { # <cache_dir>
  basename "$(dirname "$(dirname "$1")")"
}

_loen_marketplace_root() { # <mkt>
  printf '%s/tmp/marketplaces/%s\n' "$ICODEX_HOME_DIR" "$1"
}

_write_loen_marketplace_manifest() { # <root> <mkt>
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
      "name": "loen",
      "source": {
        "source": "local",
        "path": "./plugins/loen"
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

_ensure_loen_marketplace_root() { # <cache_dir> <mkt>
  local cache="$1" mkt="$2" root plugin_link
  root="$(_loen_marketplace_root "$mkt")"
  plugin_link="$root/plugins/loen"

  mkdir -p "$root/plugins"
  if [[ -e "$plugin_link" || -L "$plugin_link" ]]; then
    rm -rf "$plugin_link"
  fi
  ln -s "$cache" "$plugin_link"
  _write_loen_marketplace_manifest "$root" "$mkt"
  printf '%s\n' "$root"
}

_loen_toml_escape() { # <value>
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

_loen_remove_section() { # <config> <header>
  local config="$1" header="$2" tmp
  tmp="$(mktemp)"
  awk -v header="$header" '
    /^\[/ { skip = ($0 == header) }
    !skip { print }
  ' "$config" > "$tmp"
  cmp -s "$tmp" "$config" || cat "$tmp" > "$config"
  rm -f "$tmp"
}

_loen_upsert_marketplace_section() { # <config> <mkt> <source>
  local config="$1" mkt="$2" source="$3" escaped
  escaped="$(_loen_toml_escape "$source")"
  _loen_remove_section "$config" "[marketplaces.$mkt]"
  {
    printf '\n[marketplaces.%s]\n' "$mkt"
    printf 'source_type = "local"\n'
    printf 'source = "%s"\n' "$escaped"
  } >> "$config"
}

_loen_upsert_plugin_section() { # <config> <mkt> <enabled>
  local config="$1" mkt="$2" enabled="$3"
  _loen_remove_section "$config" "[plugins.\"loen@$mkt\"]"
  {
    printf '\n[plugins."loen@%s"]\n' "$mkt"
    printf 'enabled = %s\n' "$enabled"
  } >> "$config"
}

_loen_disable_wiring() { # <config> <mkt>
  local config="$1" mkt="$2"
  _loen_remove_section "$config" "[marketplaces.$mkt]"
  _loen_upsert_plugin_section "$config" "$mkt" "false"
}

ensure_loen_wiring() {
  local config="$ICODEX_HOME_DIR/config.toml"
  if [[ ! -f "$config" ]]; then
    log_error "missing $config - cannot configure LoEn"
    return 0
  fi

  local mode cache mkt marketplace
  mode="$(_loen_mode)"
  export LOEN_MODE="$mode"

  if [[ "$mode" == "off" ]]; then
    _loen_disable_wiring "$config" "$_LOEN_MARKETPLACE"
    return 0
  fi

  cache="$(_loen_cache_dir)"
  if [[ -z "$cache" ]]; then
    log_warn "LoEn plugin not vendored under .codex-isolated/plugins/cache/$_LOEN_MARKETPLACE/loen"
    return 0
  fi

  mkt="$(_loen_marketplace_name "$cache")"
  marketplace="$(_ensure_loen_marketplace_root "$cache" "$mkt")"
  _loen_upsert_marketplace_section "$config" "$mkt" "$marketplace"
  _loen_upsert_plugin_section "$config" "$mkt" "true"
}

#!/usr/bin/env bash
# Wire the git-vendored Superpowers plugin into config.toml at launch.
#
# The committed artifact is path-portable: the marketplace `source` must resolve
# to a valid path on every host and is rewritten here from $ICODEX_ROOT. Codex
# validates the source on every launch, so this runs on the default (launch) path.

# Resolve only vendor/superpowers/pin; this function is shared by runtime and tests.
_superpowers_validate_generation() { # <cache> <generation>
  python3 - "$1/.codex-plugin/plugin.json" "$1/.icodex-vendor-provenance.json" "$2" <<'PY' 2>/dev/null
import json
import re
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        manifest = json.load(handle)
except (OSError, ValueError):
    raise SystemExit(2)
try:
    with open(sys.argv[2], encoding="utf-8") as handle:
        provenance = json.load(handle)
except (OSError, ValueError):
    raise SystemExit(1)

if not isinstance(manifest, dict) or manifest.get("name") != "superpowers":
    raise SystemExit(2)
if not isinstance(provenance, dict):
    raise SystemExit(1)
status = provenance.get("status")
if status == "legacy-unverified-cache-generation":
    valid = provenance.get("cache_generation") == sys.argv[3] and provenance.get("source_ref") is None
elif status == "verified-immutable-source-ref":
    valid = bool(re.fullmatch(r"[0-9a-f]{7,64}", provenance.get("source_ref", "")))
else:
    valid = False
if not valid:
    raise SystemExit(1)
PY
}

_superpowers_pinned_cache_dir() {
  local pin="$ICODEX_ROOT/vendor/superpowers/pin" rel cache
  [[ -f "$pin" ]] || { log_error "superpowers pin missing: $pin"; return 1; }
  [[ "$(wc -l < "$pin" | tr -d ' ')" == 1 ]] || { log_error "superpowers pin malformed: expected one line"; return 1; }
  IFS= read -r rel < "$pin"
  [[ "$rel" =~ ^[A-Za-z0-9._-]+/superpowers/[A-Za-z0-9._-]+$ ]] || { log_error "superpowers pin malformed: $rel"; return 1; }
  local marketplace _plugin generation
  IFS=/ read -r marketplace _plugin generation <<< "$rel"
  [[ "$marketplace" != "." && "$marketplace" != ".." && "$generation" != "." && "$generation" != ".." ]] || {
    log_error "superpowers pin malformed: traversal segment"
    return 1
  }
  cache="$ICODEX_SHARED_DIR/plugins/cache/$rel"
  [[ -d "$cache" && -f "$cache/.codex-plugin/plugin.json" ]] || { log_error "superpowers pinned cache missing: $cache"; return 1; }
  local validation_code=0
  _superpowers_validate_generation "$cache" "$generation" || validation_code=$?
  if [[ "$validation_code" -eq 2 ]]; then
    log_error "superpowers plugin manifest invalid"
    return 1
  elif [[ "$validation_code" -ne 0 ]]; then
    log_error "superpowers generation provenance invalid"
    return 1
  fi
  printf '%s\n' "$cache"
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

_ensure_symlink_target() { # <link> <target> <label>
  local link="$1" target="$2" label="$3"
  if [[ -L "$link" ]]; then
    if [[ "$(readlink "$link")" == "$target" ]]; then
      return 0
    fi
    rm -f "$link"
  elif [[ -e "$link" ]]; then
    log_warn "$label exists and is not a symlink; leaving it unchanged: $link"
    return 0
  fi
  ln -s "$target" "$link"
}

_ensure_superpowers_skills_root() {
  local root="$ICODEX_HOME_DIR/skills" shared="$ICODEX_SHARED_DIR/skills" entry name old_dotglob old_nullglob
  if [[ -L "$root" ]]; then
    rm -f "$root"
  fi
  mkdir -p "$root"

  [[ "$root" == "$shared" || ! -d "$shared" ]] && return 0

  old_dotglob="$(shopt -p dotglob || true)"
  old_nullglob="$(shopt -p nullglob || true)"
  shopt -s nullglob dotglob
  for entry in "$shared"/*; do
    name="$(basename "$entry")"
    _ensure_symlink_target "$root/$name" "$entry" "shared skill"
  done
  eval "$old_dotglob"
  eval "$old_nullglob"
}

_ensure_superpowers_skill_links() { # <cache_dir>
  local cache="$1" root skill name
  root="$ICODEX_HOME_DIR/skills"
  _ensure_superpowers_skills_root
  for skill in "$cache"/skills/*/; do
    [[ -f "$skill/SKILL.md" ]] || continue
    name="$(basename "${skill%/}")"
    _ensure_symlink_target "$root/$name" "${skill%/}" "superpowers skill"
  done
}

_superpowers_config_tool() { # <validate|rewrite> <config> <marketplace> [source]
  python3 - "$@" <<'PY' 2>/dev/null
import json
import re
import sys

mode, path, marketplace = sys.argv[1:4]
source = sys.argv[4] if mode == "rewrite" else None
with open(path, encoding="utf-8") as handle:
    lines = handle.readlines()


def parse_header(line):
    match = re.match(r"^\s*\[(.*)\]\s*(?:#.*)?$", line.rstrip("\r\n"))
    if not match:
        return None
    body = match.group(1)
    keys = []
    token = ""
    quote = None
    escaped = False
    for char in body:
        if quote:
            token += char
            if quote == '"' and escaped:
                escaped = False
            elif quote == '"' and char == "\\":
                escaped = True
            elif char == quote:
                quote = None
        elif char in "\"'":
            quote = char
            token += char
        elif char == ".":
            keys.append(token.strip())
            token = ""
        else:
            token += char
    if quote:
        return None
    keys.append(token.strip())
    decoded = []
    for key in keys:
        if re.match(r"^[A-Za-z0-9_-]+$", key):
            decoded.append(key)
        elif len(key) >= 2 and key[0] == key[-1] == '"':
            try:
                decoded.append(json.loads(key))
            except (TypeError, ValueError):
                return None
        elif len(key) >= 2 and key[0] == key[-1] == "'":
            decoded.append(key[1:-1])
        else:
            return None
    return tuple(decoded)

target_marketplace = ("marketplaces", marketplace)
target_plugin = ("plugins", "superpowers@" + marketplace)
marketplace_headers = []
plugin_headers = []
source_lines = []
current = None
for index, line in enumerate(lines):
    header = parse_header(line)
    if header is not None:
        current = header
        if header == target_marketplace:
            marketplace_headers.append(index)
        if len(header) == 2 and header[0] == "plugins" and header[1].startswith("superpowers@"):
            plugin_headers.append(header)
        continue
    if current == target_marketplace and re.match(r"^\s*source\s*=", line):
        source_lines.append(index)

if len(marketplace_headers) != 1 or plugin_headers != [target_plugin] or len(source_lines) != 1:
    raise SystemExit(1)

if mode == "validate":
    raise SystemExit(0)
if mode != "rewrite" or source is None:
    raise SystemExit(1)
ending = "\r\n" if lines[source_lines[0]].endswith("\r\n") else "\n"
lines[source_lines[0]] = "source = " + json.dumps(source) + ending
sys.stdout.write("".join(lines))
PY
}

# Idempotently rewrite source in the uniquely validated marketplace table.
_rewrite_marketplace_source() { # <config> <mkt> <abs>
  local config="$1" mkt="$2" abs="$3" tmp
  tmp="$(mktemp)"
  _superpowers_config_tool rewrite "$config" "$mkt" "$abs" > "$tmp" || { rm -f "$tmp"; return 1; }
  cmp -s "$tmp" "$config" || cat "$tmp" > "$config"
  rm -f "$tmp"
}

_superpowers_config_has_identity() { # <config> <marketplace>
  _superpowers_config_tool validate "$1" "$2"
}

# Orchestrate: fix the source path in the committed base config.
ensure_superpowers_wiring() {
  local config="$ICODEX_HOME_DIR/config.toml"
  if [[ ! -f "$config" ]]; then
    log_error "missing $config — cannot configure superpowers"
    return 1
  fi
  local cache mkt marketplace
  cache="$(_superpowers_pinned_cache_dir)" || return 1
  mkt="$(_superpowers_marketplace_name "$cache")"
  _superpowers_config_has_identity "$config" "$mkt" || {
    log_error "superpowers marketplace mismatch: expected $mkt in $config"
    return 1
  }
  marketplace="$(_ensure_superpowers_marketplace_root "$cache" "$mkt")"
  _ensure_superpowers_skill_links "$cache"
  _rewrite_marketplace_source "$config" "$mkt" "$marketplace"
}

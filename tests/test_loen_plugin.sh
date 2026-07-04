#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

assert_exit "vendor script exists" 0 test -f "$ROOT/scripts/vendor-loen.sh"
assert_exit "loen adapter exists" 0 test -f "$ROOT/lib/plugin/loen.sh"

version="$(python3 - "$ROOT/plugins/loen/.codex-plugin/plugin.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(data["version"])
PY
)"
assert_eq "source manifest version used by integration" "0.1.0" "$version"

repo="$tmp/repo"
mkdir -p "$repo/scripts" "$repo/plugins" "$repo/.codex-isolated/plugins/cache"
cp "$ROOT/scripts/vendor-loen.sh" "$repo/scripts/vendor-loen.sh" 2>/dev/null || true
cp -R "$ROOT/plugins/loen" "$repo/plugins/loen"

vendor_log="$tmp/vendor.log"
vendor_code=0
( cd "$repo" && bash scripts/vendor-loen.sh ) >"$vendor_log" 2>&1 || vendor_code=$?
assert_eq "vendor command exits zero" "0" "$vendor_code"

cache="$repo/.codex-isolated/plugins/cache/icodex-local/loen/$version"
manifest="$cache/.codex-plugin/plugin.json"
assert_exit "canonical loen cache created" 0 test -d "$cache"
assert_exit "vendored cache has codex manifest" 0 test -f "$manifest"
for required in skills hooks agents assets docs; do
  assert_exit "vendored cache preserves $required" 0 test -e "$cache/$required"
done
assert_exit "generated pycache stripped" 1 test -d "$cache/hooks/__pycache__"
assert_eq "generated pyc stripped" "0" "$(find "$cache" -name '*.pyc' | wc -l | tr -d ' ')"
assert_eq "nested git dirs stripped" "0" "$(find "$cache" -name .git -type d | wc -l | tr -d ' ')"
assert_eq "nested gitignore files stripped" "0" "$(find "$cache" -name .gitignore | wc -l | tr -d ' ')"
assert_contains "vendor log names canonical cache" "$(cat "$vendor_log")" ".codex-isolated/plugins/cache/icodex-local/loen/$version"

vendored_summary="$(python3 - "$manifest" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(data.get("name", ""))
print(data.get("version", ""))
print(data.get("skills", ""))
print(data.get("hooks", ""))
print(data.get("agents", ""))
print(data.get("assets", ""))
print(data.get("interface", {}).get("displayName", ""))
PY
)"
assert_eq "vendored manifest name" "loen" "$(sed -n '1p' <<<"$vendored_summary")"
assert_eq "vendored manifest version" "$version" "$(sed -n '2p' <<<"$vendored_summary")"
assert_eq "vendored manifest skills path" "./skills/" "$(sed -n '3p' <<<"$vendored_summary")"
assert_eq "vendored manifest hooks path" "./hooks/hooks.json" "$(sed -n '4p' <<<"$vendored_summary")"
assert_eq "vendored manifest agents path" "./agents/" "$(sed -n '5p' <<<"$vendored_summary")"
assert_eq "vendored manifest assets path" "./assets/" "$(sed -n '6p' <<<"$vendored_summary")"
assert_eq "vendored manifest display name" "LoEn" "$(sed -n '7p' <<<"$vendored_summary")"

export ICODEX_ROOT="$tmp/runtime"
export ICODEX_SHARED_DIR="$ICODEX_ROOT/.codex-isolated"
export ICODEX_HOME_DIR="$ICODEX_ROOT/.codex-homes/demo"
export ICODEX_BIN="$ICODEX_SHARED_DIR/bin/codex"
mkdir -p "$ICODEX_SHARED_DIR/plugins/cache/icodex-local/loen" "$ICODEX_SHARED_DIR/bin" "$ICODEX_HOME_DIR"
cp -R "$cache" "$ICODEX_SHARED_DIR/plugins/cache/icodex-local/loen/$version"
touch "$ICODEX_BIN"
chmod +x "$ICODEX_BIN"

cat > "$ICODEX_HOME_DIR/config.toml" <<'EOF_CONFIG'
bypass_hook_trust = true

[marketplaces.openai-curated]
source_type = "local"
source = "/keep/openai-curated"

[plugins."superpowers@openai-curated"]
enabled = true
EOF_CONFIG

if [[ -f "$ROOT/lib/plugin/loen.sh" ]]; then
  source "$ROOT/lib/plugin/loen.sh"
fi

unset ICODEX_LOEN_MODE LOEN_MODE
wire_code=0
ensure_loen_wiring >/dev/null 2>"$tmp/loen-warn.log" || wire_code=$?
cfg="$ICODEX_HOME_DIR/config.toml"
marketplace="$ICODEX_HOME_DIR/tmp/marketplaces/icodex-local"
assert_eq "loen wiring exits zero" "0" "$wire_code"
assert_eq "default mode exported" "advisory" "${LOEN_MODE:-}"
assert_exit "runtime marketplace manifest created" 0 test -f "$marketplace/.agents/plugins/marketplace.json"
assert_exit "runtime api marketplace manifest created" 0 test -f "$marketplace/.agents/plugins/api_marketplace.json"
assert_exit "runtime loen symlink resolves" 0 test -f "$marketplace/plugins/loen/.codex-plugin/plugin.json"
assert_contains "loen marketplace section written" "$(cat "$cfg")" "[marketplaces.icodex-local]"
assert_contains "loen marketplace source points to runtime root" "$(cat "$cfg")" "source = \"$marketplace\""
assert_contains "loen plugin enabled" "$(cat "$cfg")" "[plugins.\"loen@icodex-local\"]"
assert_contains "loen plugin enabled true" "$(cat "$cfg")" "enabled = true"
assert_contains "other marketplace preserved" "$(cat "$cfg")" "source = \"/keep/openai-curated\""
assert_contains "marketplace manifest names loen" "$(cat "$marketplace/.agents/plugins/marketplace.json")" '"name": "loen"'
assert_contains "marketplace manifest uses relative loen path" "$(cat "$marketplace/.agents/plugins/marketplace.json")" '"path": "./plugins/loen"'

before="$(cat "$cfg")"
ensure_loen_wiring >/dev/null 2>&1
assert_eq "loen wiring idempotent" "$before" "$(cat "$cfg")"

for mode in advisory enforce strict; do
  export ICODEX_LOEN_MODE="$mode"
  ensure_loen_wiring >/dev/null 2>&1
  assert_eq "mode exported: $mode" "$mode" "${LOEN_MODE:-}"
  enabled_count="$(awk '
    /^\[/ { insec = ($0 == "[plugins.\"loen@icodex-local\"]") }
    insec && $0 == "enabled = true" { count++ }
    END { print count + 0 }
  ' "$cfg")"
  assert_eq "plugin enabled in $mode" "1" "$enabled_count"
done

export ICODEX_LOEN_MODE="off"
ensure_loen_wiring >/dev/null 2>&1
assert_eq "off mode exported" "off" "${LOEN_MODE:-}"
off_enabled_count="$(awk '
  /^\[/ { insec = ($0 == "[plugins.\"loen@icodex-local\"]") }
  insec && $0 == "enabled = true" { count++ }
  END { print count + 0 }
' "$cfg")"
assert_eq "off mode leaves no enabled LoEn plugin" "0" "$off_enabled_count"
assert_exit "off mode keeps vendored cache" 0 test -f "$ICODEX_SHARED_DIR/plugins/cache/icodex-local/loen/$version/.codex-plugin/plugin.json"

export ICODEX_LOEN_MODE="bogus"
ensure_loen_wiring >/dev/null 2>"$tmp/invalid-mode.log"
assert_eq "invalid mode falls back to advisory" "advisory" "${LOEN_MODE:-}"
assert_contains "invalid mode warns" "$(cat "$tmp/invalid-mode.log")" "invalid ICODEX_LOEN_MODE"

legacy_refs="$(grep -R "lib/plugin/iwiki.sh" "$ROOT/lib/plugin/loen.sh" 2>/dev/null || true)"
assert_eq "loen adapter does not reference legacy iwiki plugin path" "" "$legacy_refs"

rm -rf "$ICODEX_SHARED_DIR/plugins/cache/icodex-local/loen"
missing_before="$(cat "$cfg")"
unset ICODEX_LOEN_MODE
missing_code=0
missing_warn="$(ensure_loen_wiring 2>&1 >/dev/null)" || missing_code=$?
assert_eq "missing loen cache does not fail" "0" "$missing_code"
assert_contains "missing cache warns" "$missing_warn" "LoEn plugin not vendored"
assert_eq "missing cache leaves config untouched" "$missing_before" "$(cat "$cfg")"

finish
